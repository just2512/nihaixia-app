#!/usr/bin/env bash
# nihaixia-app 一键构建 APK 脚本
# 在 Windows Git Bash 里运行: cd /d/app && ./build-apk.sh
# 原理: 拷代码到 WSL ext4 原生文件系统构建（避免 /mnt/d 的 AAPT2 崩溃 + 提速）
# 产出: D:\app\apk-output\app-release.apk (正式签名，可覆盖升级)
set -euo pipefail

WIN_REPO="/d/app"
APK_OUTPUT="$WIN_REPO/apk-output"
WSL_REPO="/home/actions/app"
KEYSTORE="/mnt/d/release-key.jks"
KSPASS="nihaisha2026"
KALIAS="nihaisha"

echo "=== 1/6 拉最新代码 ==="
cd "$WIN_REPO"
git fetch origin master 2>/dev/null
git checkout master 2>/dev/null
git pull origin master 2>/dev/null || true

echo "=== 1.5/6 设计 token 回归检查（拒绝裸 Color/fontSize）==="
wsl -e bash -lc 'export PATH="/home/actions/flutter/bin:$PATH"; cd /mnt/d/app && dart run tool/check_design_tokens.dart'

echo "=== 2/6 首次创建签名钥匙（已存在则跳过）==="
wsl -e bash -lc "test -f $KEYSTORE || keytool -genkeypair -v \
  -keystore $KEYSTORE -storetype PKCS12 -keyalg RSA -keysize 2048 \
  -validity 36500 -alias $KALIAS -storepass $KSPASS -keypass $KSPASS \
  -dname 'CN=nihaisha, O=nihaisha, L=Shanghai, C=CN'" 2>/dev/null
echo "Keystore OK"

echo "=== 3/6 同步代码到 WSL ext4（排除 .git/build 缓存）==="
wsl -e bash -lc "rsync -a --delete \
  --exclude='.git' --exclude='build' --exclude='.gradle' \
  --exclude='.dart_tool' --exclude='apk-output' \
  /mnt/d/app/ $WSL_REPO/" 2>&1 | tail -1
# 强制更新源码 mtime：DrvFs 时间戳会让 gradle/flutter 增量编译误判"未改动"跳过重编译
wsl -e bash -lc "find $WSL_REPO/lib $WSL_REPO/android/app/src/main/kotlin -type f \( -name '*.dart' -o -name '*.kt' \) -exec touch {} + 2>/dev/null"
echo "Sync done"

echo "=== 4/6 配置签名 + SQLite + 提速堆 ==="
wsl -e bash -lc "
# 签名
cat > $WSL_REPO/android/key.properties << EOF
storeFile=$KEYSTORE
storePassword=$KSPASS
keyAlias=$KALIAS
keyPassword=$KSPASS
EOF
# SQLite 用系统库（绕 GFW 下载）
mkdir -p $WSL_REPO/hook
cat > $WSL_REPO/hook/user_defines.json << 'EOF'
{\"sqlite3\":{\"source\":\"system\",\"name_linux\":\"/usr/lib/x86_64-linux-gnu/libsqlite3.so.0\"}}
EOF
# 修复 ic_launcher.png（RGB 无 alpha 会让本机 AAPT2 9.0.1 崩溃；CI 不受影响）
python3 $WSL_REPO/tool/fix_launcher_png.py $WSL_REPO/android/app/src/main/res
echo "PNG fix OK"
# 堆从 1GB 提到 4GB（R8 提速 10-30 倍）
sed -i 's|^org.gradle.jvmargs=.*|org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g -XX:+UseG1GC|' $WSL_REPO/android/gradle.properties
echo 'Config done'
"

echo "=== 5/6 构建 Release APK ==="
wsl -e bash -lc '
export FLUTTER_SUPPRESS_ANALYTICS=true
export PATH="/home/actions/flutter/bin:$PATH"
export ANDROID_HOME="/home/actions/android-sdk"
export ANDROID_SDK_ROOT="/home/actions/android-sdk"
cd '"$WSL_REPO"'
flutter pub get --enforce-lockfile 2>&1 | tail -2
flutter build apk --release -PciArm64Only=true 2>&1 | tail -10
'

echo "=== 6/6 复制 APK 到 Windows ==="
mkdir -p "$APK_OUTPUT"
wsl -e bash -lc "cp $WSL_REPO/build/app/outputs/flutter-apk/app-release.apk /mnt/d/app/apk-output/ 2>/dev/null && echo OK || echo FAIL"

APK="$APK_OUTPUT/app-release.apk"
if [ -f "$APK" ]; then
    echo ""
    echo "========================================"
    echo "构建成功！"
    echo "========================================"
    ls -la "$APK"
    echo ""
    sha256sum "$APK"
    echo ""
    echo "安装到手机 (USB调试已连接):"
    echo "  adb install -r $APK"
    echo "  -r = 覆盖升级，保留数据"
else
    echo "=== 构建失败 ==="
    exit 1
fi
