# 研纪 Android 真实设备安装与图标显示验收

**文档版本：** 1.0  
**编制日期：** 2026-11-22  
**目标设备：** OPPO Find N2（PUG110）  
**执行方式：** 本地执行；由设备操作者安装、截图、填写结果并回传  
**验收原则：** 未在真实设备执行的项目一律记为 `MISSING`，不得用 CI 构建成功或 Widget 测试通过替代真机结论。

> **配色规范校正（2026-11-24）：** 本文早期版本中的松墨绿/灰绿配色已被 `docs/yanji-visual-design-system.md` v1.5 取代；当前设备验收必须以 v1.5 和代码 Token 为准。

---

## 1. 验收目的与范围

本次验收确认“研纪”品牌图标和名称在 Android 实际安装后是否正确显示，并验证本轮更新没有破坏旧版本覆盖升级与现有本地数据。

验收范围：

1. 安装包身份与升级兼容：包名、签名、版本号、覆盖安装。
2. Launcher 图标：主屏、应用抽屉、圆角/圆形遮罩、浅色/深色桌面背景。
3. 对外名称：桌面名称、应用信息页、最近任务、应用内 About。
4. Find N2 外屏、展开内屏和半折叠状态下的显示。
5. 更新后原有收藏、问诊历史、设置和本地模型状态是否保留。

**本次不验收：** 中医规则正确性、AI 回答质量、全功能性能回归、网络服务可用性。这些不属于本次品牌图标及安装显示验收范围。

## 2. 当前代码基线与必须保持的身份

截至编制日期，当前主线版本为 `2.0.0+8048`；执行时仍须以实际检出的 master 和 APK 元数据为准。

| 项目 | 预期值 / 规则 |
|---|---|
| 对外应用名称 | 研纪 |
| Android applicationId | `com.nihaisha.nihaisha_app`，不得修改 |
| Android namespace | `com.nihaisha.nihaisha_app`，不得修改 |
| Dart package | `nihaisha_app`，不得修改 |
| 桌面显示名称 | 研纪 |
| Launcher 颜色规范 | 以 `docs/yanji-visual-design-system.md` v1.5（2026-11-24）为唯一权威；不在本专项文档固化第二套颜色值 |
| Launcher 资源校验 | `lib/theme/yanji_palette.dart` 是颜色 Token 唯一来源；Launcher 资源须通过 `test/yanji_android_icon_resource_test.dart` |
| 数据目录、数据库和模型路径 | 保持原位，不迁移、不清理 |
| 签名 | 必须与当前设备已安装版本相同，才能验证覆盖升级 |

本次改动不得修改 `applicationId`、`namespace`、签名密钥、数据库文件名/目录、本地模型目录或 Android 备份规则。

## 3. 图标视觉验收标准

图标采用用户提供的开卷抽象图形：左侧较宽的圆弧书页、中央上扬页片、右侧竖向书页边和下方连续弧形书底。保留原图的不对称结构，不加文字、拼音、印章、小字或副标题。

**颜色以 `docs/yanji-visual-design-system.md` v1.5（2026-11-24）为唯一权威：**

- 本文早期版本中的松墨绿 `#43594D` / 灰绿 `#E7E9E4` 已过期，不再作为当前 Launcher 颜色验收标准。
- 基础色值以 `lib/theme/yanji_palette.dart` 为唯一代码来源；图标资源必须通过 `test/yanji_android_icon_resource_test.dart` 的 Token 一致性校验，不得在本文件另立固定颜色。
- 当前浅色品牌主色为 `#D71019`，深色主题主色为 `#FF5B62`；Launcher 图标是静态系统资源，应在浅色、深色桌面背景下分别验证清晰度。
- 如品牌 Token 后续变更，以更新后的视觉系统、资源和测试为准，不以此历史专项文档中的旧色值为准。

**视觉通过条件：**

- 主体轮廓完整，中心页片与左右书页不粘连、不缺边。
- 主体在圆形、圆角方形等 Launcher 遮罩下没有关键部分被裁切。
- 图标在浅色桌面、深色桌面背景下均可辨认，不与背景融为一体。
- 图标没有白边、黑边、透明缺块、锯齿异常、拉伸、模糊或旧图标残影。
- 主屏与应用抽屉显示一致；应用名称均为“研纪”。
- ColorOS 若启用主题图标/单色图标，需分别记录主题图标关闭和开启时的实际效果；设备不提供此功能时记 `NOT_APPLICABLE`。

## 4. 执行前准备：不得跳过

### 4.1 设备信息记录

安装前记录以下信息，并保存一张设备“关于本机”截图：

```powershell
adb devices
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.sdk
adb shell getprop ro.build.display.id
adb shell wm size
adb shell wm density
```

同时记录 ColorOS 版本、系统字体大小、显示大小/缩放、当前 Launcher 主题图标设置。

### 4.2 记录旧版安装基线

确认设备当前已经安装旧版“研纪”，记录：

- 应用信息页显示名称、版本号。
- 应用内“设置 → 关于”显示的版本号和构建号。
- 旧版 APK 的来源、文件名和 SHA-256（能够取得时）。
- 已有收藏数量及 1–2 条可辨认的样本标题。
- 已有问诊历史数量及 1 条可辨认的样本（无历史时明确记“原本为空”）。
- 当前主题、字体缩放、默认性别、诊断详细度等已设置项目。
- 本地 AI 模型状态：未安装 / 已安装 / 已安装且可加载；如果已安装，记录模型文件名和应用显示的状态即可，不要复制、移动或删除模型文件。

保存安装前主屏图标、应用抽屉图标和应用信息页截图。不得在验收前清除应用数据、清理缓存、重置设置或删除已有模型。

### 4.3 准备当前主线 APK

正式 Release APK 只在维护者本地使用既有 Release keystore 构建和签名，不通过 GitHub Actions artifact、GitHub Release 或仓库分发。必须在当前主线 `2.0.0+8048` 上构建，并按 `docs/local-android-release-checklist.md` 核对原签名、版本码和 ABI。

在仓库根目录执行：

```powershell
flutter pub get --enforce-lockfile
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub
flutter build apk --release
```

构建前必须确认 `android/key.properties` 和原始 Release keystore 存在。缺少签名材料时应停止并让 Gradle fail closed；不得生成新密钥、改用 Debug 签名包或通过 GitHub Actions 获取正式 Release APK。

Find N2 使用包含 `arm64-v8a` 的 Release 包，通常为：

`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

ABI splits 已由项目 Gradle 配置管理；不要额外添加 `--split-per-abi` 改变 Flutter versionCode 映射。

安装前检查新 APK 的包名、版本和签名：

```powershell
aapt2 dump badging .\\build\\app\\outputs\\flutter-apk\\app-arm64-v8a-release.apk
apksigner verify --print-certs .\\build\\app\\outputs\\flutter-apk\\app-arm64-v8a-release.apk
Get-FileHash .\\build\\app\\outputs\\flutter-apk\\app-arm64-v8a-release.apk -Algorithm SHA256
```

逐项核对 `applicationId=com.nihaisha.nihaisha_app`、`versionName=2.0.0`、`versionCode=8048`，并确认新旧签名证书 SHA-256 一致、versionCode 严格大于设备当前版本。任一条件不满足都停止，不卸载旧版、不清数据。

## 5. 覆盖安装验收

### 5.1 安装命令

先连接手机并确认设备只有一个目标设备：

```powershell
adb devices
```

使用 `-r` 保留现有应用数据进行覆盖安装：

```powershell
adb install -r .\app-arm64-v8a-release.apk
```

安装后读取包信息：

```powershell
adb shell dumpsys package com.nihaisha.nihaisha_app | findstr /i "versionName versionCode"
```

### 5.2 禁止操作

以下命令/操作在本轮验收中禁止：

```powershell
adb uninstall com.nihaisha.nihaisha_app
adb shell pm clear com.nihaisha.nihaisha_app
```

也不要在系统设置中点击“清除数据/清除存储”，不要删除应用私有目录，不要清除 Launcher 数据。

### 5.3 安装失败时的处理

- `INSTALL_FAILED_UPDATE_INCOMPATIBLE`：通常说明新旧签名不一致。立即停止，不卸载旧版；重新核对 Release keystore 和证书指纹。
- `INSTALL_FAILED_VERSION_DOWNGRADE`：说明新包 `versionCode` 低于设备当前版本。停止并构建更高版本，不使用 `-d` 强制降级。
- `INSTALL_FAILED_NO_MATCHING_ABIS`：检查是否选错 APK；Find N2 应优先使用 arm64-v8a 包。
- 其他安装失败：保留旧应用和数据，记录完整错误文本，暂不尝试卸载重装。

**覆盖安装通过条件：** 安装命令成功，包名仍是 `com.nihaisha.nihaisha_app`，版本信息符合本次 APK 元数据，应用数据没有被重置。

## 6. 安装后的显示验收

| 编号 | 检查位置 | 执行步骤 | 通过条件 | 结果 |
|---|---|---|---|---|
| I-01 | Android 主屏 | 查看现有快捷图标 | 图标已更新为符合当前视觉系统 Token 的开卷图形，名称为“研纪” | MISSING |
| I-02 | 应用抽屉 | 打开全部应用列表 | 图标和名称与主屏一致 | MISSING |
| I-03 | Launcher 遮罩 | 检查圆形/圆角方形显示 | 主体完整，无裁切、黑边或白边 | MISSING |
| I-04 | 浅色桌面 | 在浅色/明亮壁纸上查看 | 主体与背景对比清楚 | MISSING |
| I-05 | 深色桌面 | 在深色壁纸或深色桌面下查看 | 图标前景与背景边界清晰，主体结构可辨 | MISSING |
| I-06 | 应用信息 | 设置 → 应用管理 → 研纪 | 系统显示名称为“研纪”，不是旧产品名称 | MISSING |
| I-07 | 最近任务 | 打开 App 后进入最近任务 | 任务卡片名称/图标无旧名称和旧图标 | MISSING |
| I-08 | 应用内 About | 设置 → 关于 | 标题显示“研纪”，版本/构建号真实对应当前 APK | MISSING |
| I-09 | 强制停止后重开 | 强制停止 App，再从桌面打开 | 新图标仍正确，应用正常启动 | MISSING |
| I-10 | Launcher 缓存 | 若首次安装后仍显示旧图标，重启设备后复查 | 重启后图标更新；不得通过清除 Launcher 数据解决 | MISSING |

若安装后暂时显示旧图标，先记录截图，再重启设备复查。不要清除桌面/Launcher 的应用数据，也不要通过卸载 App 刷新图标。

## 7. Find N2 内外屏真实显示验收

Find N2 的系统窗口实际尺寸受 ColorOS 显示缩放、系统栏、折叠状态影响。以下 dp 数值是设计参考，不是硬编码验收目标；最终以设备实际显示和窗口为准。

| 姿态 | 预期表现 | 必查内容 | 结果 |
|---|---|---|---|
| 折叠外屏 | 紧凑单栏、底部导航 | 首页、知识、工具、问诊、收藏切换；文字不溢出；底部导航和输入栏不被手势区遮挡 | MISSING |
| 完全展开内屏 | 左侧 NavigationRail，当前页面使用导航栏以外的可用内容区域 | 内容不被无故限制在半屏；没有右半屏黑区；主要页面可滚动、控件可点击 | MISSING |
| 半折叠/桌面姿态 | 内容落在安全显示区域 | 关键文字、输入光标、按钮不跨过物理铰链；没有黑屏/错位 | MISSING |
| 内外屏切换 | 根据当前窗口重新布局 | 当前 Tab、正在编辑的草稿和滚动状态不应无故丢失 | MISSING |
| 键盘弹出 | 输入区域随键盘调整 | 输入框、发送按钮可见；关闭键盘后布局恢复 | MISSING |
| 弹窗/日期选择 | 出现在合理的可视区域 | 弹窗不被铰链遮挡、不出屏、不被裁切 | MISSING |
| 横屏/分屏（系统允许时） | 按实际窗口宽度自适应 | 无横向溢出、黑色空白或固定宽度错位 | MISSING / NOT_APPLICABLE |
| 字体缩放 | 100%、150%、200% 分别检查 | 名称、按钮、表格和输入区域不被截断；允许换行和增加高度 | MISSING |

**布局背景：** 当前适配设计约定为外屏紧凑单栏；完全展开时由 NavigationRail 占据左侧导航区域，当前 Tab 使用剩余可用窗口宽度；半折叠/物理铰链状态需要避开真实遮挡区域。不得简单地把完全展开的内容强行限制在右半屏。

## 8. 原有数据与模型保留验收

覆盖安装后，按第 4.2 节记录的基线逐项对比：

| 编号 | 验收对象 | 检查方法 | 通过条件 | 结果 |
|---|---|---|---|---|
| D-01 | 收藏 | 打开收藏列表，核对数量和样本标题 | 数量与内容不减少、不变成空列表 | MISSING |
| D-02 | 问诊历史 | 打开历史列表，核对数量和样本记录 | 原有记录仍能打开 | MISSING |
| D-03 | 应用设置 | 检查主题、字号、默认性别、诊断详细度 | 原值保留 | MISSING |
| D-04 | 本地 AI 模型状态 | 进入本地 AI 模型区域 | 如果安装前已安装，更新后仍显示已安装；若原本未安装，仍记录未安装，不将其视为失败 | MISSING |
| D-05 | 本地模型加载 | 仅当安装前模型已安装且设备允许时执行加载 | 可加载并完成至少一次本地对话；模型不要求重新下载 | MISSING / NOT_APPLICABLE |
| D-06 | 进程重启持久性 | 关闭/强制停止 App 后重新打开 | 收藏、历史、设置和模型状态仍在 | MISSING |

本地模型路径当前由应用使用 `files/ai_models/gemma-4-E4B-it.litertlm`。Android 备份规则明确排除模型目录；本次验收是**同一设备、同一 applicationId 的覆盖升级**，不涉及卸载重装或跨设备迁移。

**数据保护失败处置：** 只要发现收藏、历史、设置或模型状态异常消失，立即停止后续清理/重装操作，保留当前 APK、设备状态和截图；不得清除数据、卸载 App 或重新导入模型来掩盖问题。先回报具体缺失对象和发生步骤。

## 9. 截图与证据要求

至少保存以下截图，统一放入一个按日期命名的目录，例如 `find-n2-acceptance-2026-11-21/`：

1. `01-device-info.png`：设备型号、Android/ColorOS 版本。
2. `02-before-home-icon.png`：安装前主屏旧版图标及名称。
3. `03-before-app-info.png`：旧版应用信息/版本。
4. `04-after-home-icon.png`：更新后主屏图标及名称。
5. `05-after-app-drawer.png`：更新后应用抽屉。
6. `06-after-app-info.png`：更新后系统应用信息。
7. `07-about-outer.png`：外屏 About 页面。
8. `08-home-inner.png`：展开内屏首页。
9. `09-knowledge-inner.png`：展开内屏知识页面。
10. `10-tools-inner.png`：展开内屏工具页面。
11. `11-interview-inner.png`：展开内屏问诊/AI 页面。
12. `12-half-fold.png`：半折叠姿态（系统支持时）。
13. `13-data-before-after.png`：可证明收藏、历史和模型状态前后对应的界面截图；隐去真实姓名、病历等个人信息。

截图不应包含真实患者个人信息、身份证号码、电话号码、账号或其他隐私内容。必要时使用无敏感信息的测试记录。

## 10. 结果判定与回传模板

每个项目只允许填写以下状态：

- `PASS`：按文档步骤在 OPPO Find N2 真机执行，预期表现符合，并有截图或记录。
- `FAIL`：真实设备执行后出现不符合项，须写明复现步骤和证据。
- `MISSING`：没有执行、没有设备或没有证据。不能当作通过。
- `NOT_APPLICABLE`：该项确实不适用于当前设备/系统，必须说明原因。

### 验收记录

| 字段 | 本地填写 |
|---|---|
| 执行日期/时间 |  |
| 执行人 |  |
| 设备型号 |  |
| Android / ColorOS 版本 |  |
| 屏幕分辨率 / 密度 |  |
| 安装前版本 / versionCode |  |
| 安装后版本 / versionCode |  |
| 新 APK 文件名 / SHA-256 |  |
| 新旧签名证书 SHA-256 是否一致 |  |
| 覆盖安装命令结果 |  |
| 主屏与抽屉图标 |  |
| 应用名称 / About |  |
| 外屏 / 内屏 / 半折叠 |  |
| 收藏 / 历史 / 设置保留 |  |
| 本地模型状态 |  |
| 失败项和复现步骤 |  |
| 截图证据目录 |  |

**最终结论：** `PASS / FAIL / MISSING`（有任何关键项 FAIL 或 MISSING 时，不得签署“全部通过”）。

**本地交接要求：** 完成后将本文件填写版、截图目录、APK SHA-256、签名证书指纹以及失败复现步骤交回项目维护方。不要提交签名私钥、keystore 密码、模型文件或含用户隐私的数据库副本。

---

## 11. 本次自动化与真机验收边界

自动化可验证：Android 资源可编译、Manifest 名称、applicationId/namespace 兼容边界、品牌资源颜色和文档约定、Flutter 回归测试。

只有 OPPO Find N2 真机可验证：桌面/应用抽屉实际图标、ColorOS Launcher 遮罩效果、图标缓存刷新、真实外屏/内屏/半折叠窗口表现、真实签名覆盖升级和旧数据留存。

**本文件创建时，真实设备安装与显示验收状态为 `MISSING`。** 完成本地执行并提交证据后，才可更新为 `PASS`。
