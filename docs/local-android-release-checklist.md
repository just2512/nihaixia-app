# 本地 Android 构建与升级检查清单

> 本文只定义本地构建、签名和设备验收。正式 APK 不在 GitHub Actions、GitHub Release 或仓库附件中构建/发布。

## 1. 当前源码版本基线

| 项目 | 当前值 | 核对要求 |
|---|---|---|
| App version | `1.11.30+8039` | `versionName=1.11.30`，`versionCode=8039` |
| Android applicationId | `com.nihaisha.nihaisha_app` | 必须与设备现有安装包一致 |
| 当前 master 基线 | `7681d6584d3a3667a5f54a19fac0f675774fd749` | 本清单对应本版本源码；构建前以仓库最新 master 为准 |
| 分发渠道 | 本地构建 / 本地签名 / 线下或私下交付 | 不创建发行 Tag，不发布 GitHub Release，不上传正式 APK |

当前 `pubspec.yaml` 已从上一版 `1.11.29+8038` 递进到 `1.11.30+8039`。不要再次手动递增，也不要为了构建而修改 `applicationId`。

## 2. 签名密钥：硬门槛

- 必须使用旧版已安装 App 对应的原始 HanTang 签名私钥。不要新生成一套密钥代替旧密钥；新密钥会导致 Android 拒绝覆盖安装。
- `android/key.properties`、keystore、密码和证书材料均为本地私有文件，禁止提交到 Git、Issue、PR、CI Variables 或聊天内容。
- `android/key.properties.template` 仅作字段示例。`storeFile` 路径按 `android/app/` 目录解析；若 keystore 放在 `android/` 根目录，示例路径为 `../nihaisha.jks`。文件名、alias、storeType 必须按真实原密钥填写，不能照抄猜测。
- 当前 Gradle Release 构建已经改为 fail-closed：缺少配置、必需字段或 keystore 文件时，Release 任务会报错退出，不再回退 Debug 签名。Debug CI 构建不要求本地密钥。

### 2.1 从设备提取当前安装包证书

连接 OPPO Find N2，先读取当前安装包路径：

```powershell
adb shell pm path com.nihaisha.nihaisha_app
```

将输出中的 `base.apk` 路径复制出来，再提取旧 APK（示例路径需替换为设备实际输出）：

```powershell
adb pull /data/app/.../base.apk old-installed.apk
```

使用 Android SDK Build Tools 中的 `apksigner` 输出旧包证书指纹：

```powershell
apksigner verify --print-certs .\old-installed.apk
```

记录 `Signer #1 certificate SHA-256 digest`。若设备无法提取旧 APK，可使用确认来自该设备当前安装版本的旧安装包；不要用未经确认的网络 APK 作为证书基线。

## 3. 本地构建

在仓库根目录运行：

```powershell
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
flutter build apk --release
```

项目已配置 ABI splits 和 universal APK；不要额外添加 `--split-per-abi`，以免改变 Flutter 对分架构 APK `versionCode` 的处理。Find N2 使用 `arm64-v8a` 安装包。

构建输出目录：`build/app/outputs/flutter-apk/`。常见文件包括 `app-arm64-v8a-release.apk` 与 `app-release.apk`；实际文件名以构建目录为准。

## 4. 安装前核验 APK

```powershell
aapt2 dump badging .\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
apksigner verify --print-certs .\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
Get-FileHash .\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk -Algorithm SHA256
```

逐项核对：

- `package: name='com.nihaisha.nihaisha_app'`。
- `versionName='1.11.30'`，`versionCode='8039'`；版本码必须高于设备当前安装版本。
- 新 APK 的 signer certificate SHA-256 与第 2.1 节记录的旧版指纹完全一致。
- `apksigner verify` 成功，APK 文件非空。

**任何一项不一致都停止，不安装、不卸载旧版、不清除数据。** 不能通过改包名、降低版本码或重新生成密钥来绕过检查。

## 5. 覆盖升级与数据检查

证书、包标识和版本核验全部通过后，先通过 App 内已有导出功能备份重要诊断历史/收藏；模型文件等外置资源另行确认其本地位置。然后才执行：

```powershell
adb install -r .\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

不得先执行 `adb uninstall`，不得清除 App 数据或恢复出厂。安装后检查：

- App 能正常启动，包名仍为 `com.nihaisha.nihaisha_app`，版本显示为 `1.11.30`。
- 原诊断历史、收藏、命盘、设置仍可读取；既有数据库没有被重置。
- 原本地 AI 模型及其配置仍可识别；音频/图片附件和相关记录按原有路径可读取。
- 若安装器拒绝更新或出现签名错误，立即停止；保留设备旧版和数据，回查证书，不做卸载重装。

## 6. OPPO Find N2 真机验收

云端 Widget 和 Android arm64 Debug CI 不能代替实机。至少记录设备系统版本、屏幕/折叠姿态、截图和结果：

- 外屏：启动、根导航、工具入口和详情页无横向溢出。
- 展开内屏：紫微命盘整屏查看完整；宫位详情背景不透明、星曜文本可换行。
- 半折叠：工具页内容不跨越物理 hinge；右侧面板触发的页面边界仍限制在当前物理面板。
- 易经：上卦、下卦、动爻三个下拉控件可见、可展开、可选择。
- 剂量换算：数值与单位控件不溢出，单位下拉可完整展开。
- 阅读：本草讲稿、伤寒金匮、内经和详情页能正常打开、检索和返回；检查常用字号及 200% 字号。

真机验收记录必须区分 `PASS`、`FAIL`、`MISSING`；未实际操作的项目保持 `MISSING`。

## 7. 发布边界与完成定义

- 正式 APK 只在维护者本地生成、签名和计算 SHA-256；由维护者选择线下或私下分发渠道。
- 不推送 `v1.11.30` Tag，不触发 `workflow_dispatch` 发布，不创建 GitHub Release，不把正式签名 APK 或 keystore 上传到 GitHub。
- GitHub Actions 中保留的 Flutter regression、Android Debug 验证 APK 和 Release 签名 fail-closed dry-run 仅属于代码验收；不会生成或发布正式 Release APK。

只有本地 Release 构建、旧新证书一致、包名/版本码正确、`adb install -r` 数据保留、Find N2 实机验收均有证据，才可把该版本标记为 `LOCAL RELEASE PASS`。否则保持 `PREPARATION / NOT RELEASED`。
