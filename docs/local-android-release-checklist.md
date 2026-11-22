# 本地 Android 构建与升级检查清单

> 本文是本地构建、签名和设备验收清单，不是测试结果或 PASS 报告。正式 Release APK 只在维护者本地构建和签名，不进入 GitHub Actions artifact、GitHub Release 或仓库。

## 1. 当前源码版本基线

| 项目 | 当前值 | 核对要求 |
|---|---|---|
| App version | `2.0.0+8048` | `versionName=2.0.0`，`versionCode=8048` |
| Android applicationId | `com.nihaisha.nihaisha_app` | 必须与设备现有安装包一致 |
| 共享 applicationId 已知最高构建号 | `8047` | 已核验上游 `pubspec.yaml@92ef759` 为 `1.11.34+8047`；本版本 `8048` 仍须高于设备实际读取的 versionCode |
| 当前应用代码基线 | 本地构建时检出的最新 `master` HEAD | 执行构建前记录 `git rev-parse HEAD`；最终 merge SHA 以执行台账 §67 的交接记录为准 |
| 分发渠道 | 本地构建 / 原签名 / 本地交付 | 不创建发行 Tag，不发布 GitHub Release，不上传正式 APK |

## 2. 原签名密钥：硬门槛

- 必须使用旧版已安装 App 对应的原始签名私钥。不要新生成密钥代替旧密钥；证书不同会导致 Android 拒绝覆盖安装。
- `android/key.properties`、keystore、密码和证书材料均为本地私有文件，禁止提交 Git、Issue、PR、CI Variables 或聊天内容。
- `android/key.properties.template` 仅是字段示例。Gradle 的 `storeFile` 路径相对于 `android/app/` 解析；keystore 若放在 `android/` 根目录，示例为 `../nihaisha.jks`。文件名、alias、storeType 按原密钥的真实值填写。
- Release Gradle 任务现为 fail-closed：缺少配置、必需字段或 keystore 文件时立即失败；不再 fallback 到 Debug 签名。CI Debug 构建不要求本地密钥。

### 2.1 从设备提取已安装 APK 的证书

先连接 Find N2，读取已安装包路径：

```powershell
adb shell pm path com.nihaisha.nihaisha_app
```

从输出复制设备实际的 base.apk 路径，再提取旧 APK：

```powershell
adb pull /data/app/.../base.apk old-installed.apk
```

读取证书指纹：

```powershell
apksigner verify --print-certs .\\old-installed.apk
```

记录 `Signer #1 certificate SHA-256 digest`。若无法提取设备当前 APK，可使用明确来自该设备当前安装版本的旧 APK；不得用来源不明的网络 APK 代替证书基线。

> 历史文档中的缩写指纹只能作为线索，不能代替从当前安装包读取完整 SHA-256。

## 3. 本地构建

在仓库根目录执行：

```powershell
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
flutter build apk --release
```

Release 构建前必须确认 `android/key.properties` 与原 keystore 存在。缺失时 Gradle 应按设计失败，不要临时生成新密钥，也不要改用 Debug 签名包覆盖旧版。

ABI splits 已由项目 Gradle 配置管理；不要额外添加 `--split-per-abi` 改变 Flutter versionCode 映射。Find N2 使用包含 `arm64-v8a` 的 Release 包。

## 4. 安装前核验

```powershell
aapt2 dump badging .\\build\\app\\outputs\\flutter-apk\\app-arm64-v8a-release.apk
apksigner verify --print-certs .\\build\\app\\outputs\\flutter-apk\\app-arm64-v8a-release.apk
Get-FileHash .\\build\\app\\outputs\\flutter-apk\\app-arm64-v8a-release.apk -Algorithm SHA256
```

逐项核对：

- package / applicationId 精确为 `com.nihaisha.nihaisha_app`。
- `versionName=2.0.0`、`versionCode=8048`，且新版 versionCode 必须严格大于设备当前版本。
- 新 APK signer certificate SHA-256 与当前安装包证书完全一致；如果签名轮换，必须有 Android 平台认可的 signing lineage 证据。
- `apksigner verify` 成功，APK 非空，ABI 包含 `arm64-v8a`。
- 记录本地 Release APK SHA-256、versionName、versionCode、applicationId、ABI 和证书 SHA-256。

**任何一项不一致都停止，不安装、不卸载旧版、不清除数据。** 不得通过改包名、降低版本码或换密钥绕过系统检查。

## 5. 覆盖升级与数据保留

核验全部通过后，先通过 App 现有导出入口备份重要收藏/诊断历史；不要把真实患者资料放进 CI 或仓库。然后执行：

```powershell
adb install -r .\\build\\app\\outputs\\flutter-apk\\app-arm64-v8a-release.apk
```

不得先执行 `adb uninstall`，不得清除 App 数据或 SQLite 文件。安装后检查：

- App 正常启动，applicationId / versionName / versionCode 与构建记录一致。
- 原有收藏、诊断历史、命盘、历史会话、设置仍可读取。
- 原本地 AI 模型及配置仍可识别；附件按既有路径可读取。
- 强制停止并重启后，本地历史数据仍可恢复。

若安装器拒绝更新、证书不符、版本回退、数据库迁移失败或本地数据缺失，立即停止；保留旧版和数据，保存错误日志，不得清数据后改判通过。

## 6. OPPO Find N2 真机验收

云端 Widget 测试和 Android arm64 Debug CI 不能替代实机。按以下文档完成完整矩阵：

- `docs/find-n2-real-device-acceptance.md`：外屏、展开内屏、半折叠、Insets、键盘、选择菜单、来源面板、原位覆盖升级。
- `docs/find-n2-local-ai-acceptance-checklist.md`：GPU / CPU 分别至少 20 轮、多媒体、Native 状态、Activity/force-stop 恢复和清除。
- `docs/find-n2-ai-trace-acceptance-plan.md`：端到端 trace_id、实际 backend、跨轮及数据持久化证据。
- `docs/local-ai-e4b.md`：E4B 模型导入、SHA-256、运行时配置和已知边界。

每个场景记录设备型号、Android / ColorOS、App commit、Release APK SHA-256、模型 SHA-256、实际 backend、步骤、截图与状态。状态使用 PASS / FAIL / BLOCKED / MISSING；未执行项不得写 PASS。

## 7. 发布边界与完成定义

- 正式 APK 只在维护者本地生成、签名、计算 SHA-256；由维护者选择线下或约定的私下渠道交付。
- 不推送发行 Tag，不触发在线 Release workflow，不创建 GitHub Release，不把正式签名 APK 或 keystore 上传到 GitHub。
- GitHub Actions 仅保留 Flutter 回归、Android Debug ABI/Manifest/Native unit tests，以及“缺少本地签名材料时 Release 构建必须失败”的负向验证。
- 只有本地 Release 构建、旧新证书一致、包名/版本码正确、`adb install -r` 数据保留与 Find N2 关键场景均有证据，才能标记 `LOCAL RELEASE PASS`。此前统一保持 `PREPARATION / NOT RELEASED`。
