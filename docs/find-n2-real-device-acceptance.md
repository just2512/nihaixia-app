# OPPO Find N2 真机折叠屏验收方案

> 状态：待真机执行（MISSING）。本文是执行方案，不是设备通过报告。Widget 测试、模拟器截图和 CI 通过均不能替代 Find N2 实机验收。

## 1. 验收目标与边界

验证当前 `master` 的 Flutter 页面在 OPPO Find N2 上，面对真实外屏、展开内屏、半折叠姿态、系统窗口 Insets、输入法和 Android 平台 UI 时，是否保持可见、可操作、状态连续且无布局异常。

当前实现约束（以代码和自动化测试为准）：

- 外屏窄窗口使用单栏布局。
- 完全展开内屏（flat）使用完整可用内屏宽度；根导航可保留左侧 NavigationRail，Tab 内容应延伸至其余可用区域，不应被错误限制在右半屏。
- 半折叠/桌面姿态按真实铰链/折痕边界选择安全面板；页面、弹窗和来源控件应位于同一可用屏区。
- 零宽折痕与有物理宽度的铰链必须分别检查，不能把两种 DisplayFeature 当成同一情况。
- 相机、Android 文件选择器等平台系统 UI 的位置由 Android/厂商系统控制，Flutter 路由锚点不能保证它们落在哪一块屏；本方案只验收系统 UI 能否正常启动、完成、返回并正确回传结果。

## 2. 设备与构建前置条件

执行前记录：

| 项目 | 必须提供的值 |
|---|---|
| 设备 | OPPO Find N2，型号以 `getprop ro.product.model` 实测值为准 |
| Android | 系统版本、SDK、ColorOS 版本（设置页截图或设备信息） |
| 系统显示 | 屏幕分辨率、密度、系统字号、显示大小 |
| 应用 | 包名 `com.nihaisha.nihaisha_app`、Git commit、APK SHA-256 |
| 构建 | 本轮 master CI 的 arm64 Debug APK；不得用旧 APK 混测 |
| 连接 | USB 调试已授权；电脑有 Android platform-tools（adb）和 PowerShell |

安装本轮 APK 后先确认：

```powershell
adb devices
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.sdk
adb shell wm size
adb shell wm density
adb shell settings get system font_scale
adb shell pm path com.nihaisha.nihaisha_app
```

如设备型号、APK commit 或 SHA-256 不明，先标记 BLOCKED，不开始正式验收。

## 3. 采集工具与证据目录

仓库已有窗口诊断脚本：

```powershell
./tool/capture_find_n2_metrics.ps1
```

脚本自动检查 adb 设备、包名和已安装状态，记录设备元数据，并只保存 Flutter 日志中带 `[WINDOW_METRICS]` 的行。采集期间依次切换外屏、展开内屏、半折叠，并操作键盘、相机和文件选择器；按 Ctrl+C 结束。

每轮证据建议按以下结构整理：

```text
output/find-n2/<run-id>/
  device-metadata.json
  window-metrics.log
  capture-summary.json
  apk-info.txt
  screenshots/
    01-outer-home.png
    02-inner-flat-home.png
    03-half-fold-home.png
    04-ziwei-chart-outer.png
    05-ziwei-chart-inner.png
    06-palace-detail-half-fold.png
    07-dialog-source-panel.png
    08-keyboard-visible.png
    09-system-file-picker.png
    10-after-return.png
  test-results.md
```

截图需保留完整屏幕边界和系统状态栏/导航栏；截图中如含真实个人资料、出生信息、问诊内容或账号，应使用专门测试数据或先遮盖敏感内容。不要提交真实个人健康信息。

## 4. 真机测试矩阵

每个场景均需记录：步骤、预期、实际、结果状态、截图编号、对应 `[WINDOW_METRICS]` 时间戳。状态只能使用：

- **PASS**：实机行为满足本节全部通过条件，且证据齐全。
- **FAIL**：实际行为违反任一通过条件。
- **BLOCKED**：因设备、权限、构建或环境原因无法执行。
- **MISSING**：尚未执行或缺少足够证据。

不得把 BLOCKED/MISSING 写成 PASS；同一场景部分通过也不能整体 PASS。

### A. 外屏竖屏

1. 折叠设备，仅使用外屏冷启动应用。
2. 依次打开首页、统一助手、紫微排盘、命盘详情。
3. 在紫微页面检查命盘、十二宫位、宫位名称/星曜文本、底部操作入口和滚动区域。
4. 打开宫位详情、普通对话框、日期/时间选择器；逐个关闭并返回。
5. 滚动长内容至顶部和底部，执行返回、再次进入。

通过条件：
- 页面没有横向溢出、RenderFlex overflow、文字/按钮裁切或不可触达控件。
- 主要操作不被状态栏、导航栏、圆角/挖孔或键盘遮挡。
- 页面纵向滚动正常，底部内容可到达；弹层可完整查看并可关闭。
- 返回后页面状态与进入前一致，不出现空白页、重复页面或卡死。

### B. 内屏完全展开（flat）

1. 展开设备至完全平展，等待系统完成窗口尺寸变化。
2. 冷启动应用；记录根导航、Tab 内容和命盘布局。
3. 分别进入统一助手和紫微排盘，检查横向布局、命盘完整性、长文本和详情入口。
4. 从左侧/顶部导航切换多个 Tab，再返回原页面。

通过条件：
- `[WINDOW_METRICS]` 显示实际内屏尺寸和系统上报的 DisplayFeature；以设备真实报告为准。
- 当前代码定义的 flat 行为成立：内容使用可用内屏宽度，不因残留 DisplayFeature 被错误压缩成单侧窄屏；导航和内容均不被裁切。
- 命盘各宫位位置、连线、文字和交互区域完整；无异常缩放、重叠或横向滚动条。
- 切换 Tab 后状态恢复符合页面既有设计，无状态丢失或内容错位。

### C. 半折叠 / 桌面姿态

1. 将设备置于可稳定停留的半折叠姿态，分别测试上屏和下屏作为来源区域的场景。
2. 从可见屏区进入紫微排盘，滚动命盘和说明文档。
3. 点击宫位打开详情；再从该屏区打开普通弹窗、日期/时间选择器。
4. 分别从上侧与下侧触发可用弹层/导航入口，检查其显示位置。
5. 尝试在半折叠状态切换到助手并输入文本。

通过条件：
- 页面主内容被约束在安全物理屏区，不穿过实际铰链/遮挡区域；触控目标位于可见且可触摸区域。
- 弹窗/详情应锚定到触发控件所在屏区；不允许从下屏触发却显示在上屏不可见区域，反之亦然。
- 页面、AppBar、滚动区、底部操作区不互相覆盖；滚动到两端均无溢出。
- 如果设备或系统不支持稳定半折叠姿态，记录设备状态和系统信息并标记 BLOCKED，不以模拟器替代。

### D. 紫微排盘与宫位详情（核心业务）

分别在外屏、内屏 flat、半折叠可用屏区执行：

1. 打开排盘页，检查命盘整体布局及十二宫位。
2. 逐一点击至少四个不同位置的宫位（包含边缘宫位和中间区域），打开宫位详情。
3. 在详情内滚动到最底部，再返回顶部；关闭后再次打开另一个宫位。
4. 从详情页跳转关联文档（若入口存在），返回排盘页。
5. 旋转/折叠状态切换后复查当前命盘和详情状态。

通过条件：
- 命盘十二宫位均可辨识、点击区域与视觉位置一致；不得有宫位被铰链遮挡或点击错位。
- 详情弹层显示在正确屏区，长内容完整可滚动；底部按钮可见、可触达。
- 关闭/返回后命盘数据和当前页面恢复；不丢失出生参数，不产生重复路由。
- 任何真实布局异常、点击偏移或文本遮挡均判 FAIL，即使截图看起来大致正常。

### E. 系统字号与显示大小

至少执行系统字号 100%、150%、200% 三档（以 Android 设置可选档位为准），每档重复外屏、内屏 flat、半折叠的关键页面检查。记录实际 font_scale，不只记录设置档位。

通过条件：
- 不裁切关键文本、命盘宫位名称、按钮标签和表单输入内容。
- 文本增大后允许页面变高并滚动，不允许通过缩小字体、固定高度裁切或隐藏内容规避问题。
- 交互控件仍可触达，弹层内容可滚动到底部。

恢复设备原字号和显示大小后再继续下一组测试。

### F. 键盘、输入区与 Insets

分别在外屏、内屏 flat、半折叠执行：

1. 进入统一助手，聚焦输入框并输入多行测试文本。
2. 弹出键盘，滚动历史消息，发送消息；再聚焦输入框。
3. 使用系统返回键收起键盘，再次打开键盘；切换屏幕姿态时保持键盘打开一次。
4. 在有底部操作区的页面重复检查。

通过条件：
- 输入框、发送按钮和正在编辑的文本不被键盘遮挡；键盘出现后内容区域正确缩小/滚动。
- `viewInsets` 随键盘变化，键盘收起后恢复；无底部空白残留、跳屏或布局抖动。
- 折叠/展开期间不丢失输入草稿，不出现重复发送。
- 软键盘关闭后页面能恢复到原滚动位置附近。

### G. 弹窗、底部弹层和全屏路由

1. 从左右/上下不同物理屏区触发普通对话框、宫位详情、日期/时间选择器。
2. 从来源屏区打开全屏详情页，再返回。
3. 在半折叠姿态重复从两个屏区触发弹层。
4. 在 flat 状态检查弹窗是否错误地被限制在半屏。

通过条件：
- 弹窗/路由的位置与调用来源一致，且完整处于可用物理屏区。
- flat 状态按当前设计使用完整可用内屏；half-opened 状态遵循安全屏区。
- 背景遮罩、关闭按钮、返回键和点击外部关闭行为符合组件原有设计。
- 不出现 DialogRoute 默认锚点导致的跨屏、弹窗超界或无法关闭。

### H. 相机、系统文件选择器和权限

1. 从真实业务入口启动相机拍照。
2. 从真实业务入口启动 Android 系统文件选择器，选取一个非敏感测试文件。
3. 分别在外屏、内屏 flat、半折叠姿态执行；如系统不允许某姿态，记录原因。
4. 完成选择后返回应用，检查预览、文件名/类型、后续流程。
5. 拒绝权限、首次授权、再次进入分别检查；如支持“仅本次允许”，也需覆盖。

通过条件：
- 系统 UI 可启动、可取消、可完成；系统返回后应用仍可操作。
- 成功选择时 URI/文件结果正确回传，预览内容与选择文件一致；取消时不残留错误附件。
- 权限拒绝后应用给出可理解反馈，不崩溃、不假装成功；重新授权后可恢复。
- 不要求系统文件选择器/相机窗口必须由 Flutter 锚定到指定屏区；但必须记录系统实际显示位置和返回行为。

### I. 折叠/展开/旋转连续性与稳定性

1. 应用前台时执行外屏 → 内屏 flat → 半折叠 → 外屏，至少完整循环 3 次。
2. 在循环中分别停留在首页、紫微排盘、宫位详情、统一助手。
3. 执行一次锁屏/解锁和一次应用切后台/前台。
4. 结束前冷启动一次，检查页面可正常恢复。

通过条件：
- 每次尺寸/姿态变化均完成重新布局，无黑屏、白屏、内容停留在旧屏区、崩溃或 ANR。
- 当前业务数据、对话草稿和可恢复的页面状态符合原有持久化设计。
- 不出现重复导航栈、失效点击区域、明显触摸偏移或持续高频重绘。
- 3 次循环全部完成；任何一次出现可复现故障均判 FAIL。

## 5. 结果记录模板

复制下表到本轮 `test-results.md`，逐项填写，不要只写“正常”：

| ID | 场景 | 设备姿态/字号 | 操作步骤 | 预期结果 | 实际结果 | 状态 | 截图/日志时间戳 |
|---|---|---|---|---|---|---|---|
| A1 | 外屏首页/紫微 | 外屏 / 100% |  |  |  | MISSING |  |
| B1 | 内屏 flat | 展开 / 100% |  |  |  | MISSING |  |
| C1 | 半折叠上屏 | 半折叠 / 100% |  |  |  | MISSING |  |
| C2 | 半折叠下屏 | 半折叠 / 100% |  |  |  | MISSING |  |
| D1 | 十二宫位/详情 | 各姿态 |  |  |  | MISSING |  |
| E1 | 系统字号 | 150% / 200% |  |  |  | MISSING |  |
| F1 | 键盘与 Insets | 各姿态 |  |  |  | MISSING |  |
| G1 | 对话框/底部弹层 | 各姿态 |  |  |  | MISSING |  |
| H1 | 相机/文件选择器 | 各姿态 |  |  |  | MISSING |  |
| I1 | 姿态切换循环 | 3 次 |  |  |  | MISSING |  |

本轮结论只能是：
- **PASS**：所有适用场景 PASS，证据齐全。
- **FAIL**：至少一项 FAIL；附最小复现步骤和证据。
- **BLOCKED**：关键场景因设备/系统限制不能执行；明确列出阻塞项。
- **INCOMPLETE**：仍有 MISSING 项。

## 6. 失败后的定位与修复流程

先保留失败现场，不先改代码。每个问题按以下顺序处理：

1. **复现与分类**：记录姿态、方向、字号、操作路径、发生频率；确认只在真机出现还是 Widget 也可复现。
2. **窗口事实核对**：对照同一时间的 `[WINDOW_METRICS]`：`sizeDp`、`dpr`、`displayFeatures`（type/state/bounds）、`viewInsets`、`viewPadding`、文字缩放。先确认系统上报事实，禁止猜测设备姿态。
3. **坐标系核对**：检查页面是否嵌套在单侧面板；核对 RenderBox 窗口坐标与局部坐标转换、铰链 bounds 是否与当前宿主视口相交。错误地把全窗口坐标当局部坐标是常见根因。
4. **布局约束核对**：沿父子 Widget 追踪 Constraints、SafeArea、Scaffold resize、滚动容器、固定高度/宽度、命盘绘制区域和点击 hit-test 区域。不要先加裁切或隐藏溢出。
5. **路由核对**：弹窗是否走 `showFoldAwareDialog`，全屏页面是否走 `FoldAwareMaterialPageRoute`；来源 BuildContext 是否属于真正触发控件；平台系统 UI 是否被误认为 Flutter 路由。
6. **修复与回归**：先补能稳定复现的 Widget 回归（真实 DisplayFeature bounds/state、窗口尺寸、DPR、Insets），再做最小生产代码修复；运行对应专项、静态分析、全量 Flutter 回归和 Android arm64 构建。
7. **真机复测**：使用新 commit 对应的新 APK，重跑失败场景及相关相邻场景；记录修复前后证据。原失败记录保留，不覆盖、不删除。

### 失败现象 → 优先检查方向

| 现象 | 优先检查 | 不允许的“修复” |
|---|---|---|
| 页面/命盘跨铰链 | DisplayFeature bounds、宿主视口坐标、AdaptiveSinglePane | 直接隐藏溢出或把内容裁掉 |
| flat 内屏只显示半边 | posture state、根导航是否屏蔽已消费的 feature、父级宽度约束 | 固定写死 Find N2 像素宽度 |
| 半折叠弹窗跑到另一屏 | 来源 RenderBox anchor、DialogRoute anchorPoint、SafeArea | 把所有弹窗强制放在固定一侧 |
| 宫位点击位置与图形错位 | Canvas 坐标、缩放变换、命中测试坐标 | 放大点击热区掩盖坐标错误 |
| 键盘遮挡输入框 | viewInsets、Scaffold resizeToAvoidBottomInset、滚动/焦点处理 | 固定底部留白或关闭键盘适配 |
| 字号放大后内容被裁切 | 固定高度、Text overflow、滚动容器和约束 | 强制缩小系统字号/应用字体 |
| 系统选择器返回后无附件 | Android Activity result、URI 权限/生命周期、插件回调 | 用假 URI 或模拟结果判通过 |
| 折叠切换后黑屏/旧布局 | MediaQuery 更新、状态订阅、缓存的尺寸/锚点 | 只在进入页面时读取一次窗口尺寸 |

修复完成的必要证据：失败复现记录、根因说明、代码差异、回归测试、修复后真机日志/截图。缺少任一项，实机缺陷仍保持未关闭。

## 7. 需要提交给维护者的材料

每轮真机测试请提供：

1. `device-metadata.json`、`window-metrics.log`、`capture-summary.json`。
2. `test-results.md`（逐项 PASS/FAIL/BLOCKED/MISSING）。
3. 对应截图原图；失败时另附 10–20 秒屏幕录制（若能复现）。
4. 本轮 APK 文件名、SHA-256、Git commit、安装方式；不要只发“最新 APK”。
5. 失败项的最小复现步骤、发生频率、预期/实际差异。
6. 如涉及系统权限，说明首次授权/拒绝/再次授权的操作路径。

如日志过大，可先打包 `output/find-n2/<run-id>/`。提交前检查并清理个人信息、真实出生资料、问诊文本、账号和文件内容。

## 8. 当前验收状态

- CI/Widget 自动化：按对应 GitHub Actions run 记录判定。
- OPPO Find N2 外屏、内屏 flat、半折叠、键盘、系统弹窗/选择器：**MISSING，等待实机材料**。
- 本文不预先宣称任何真机项目通过。

## 9. 新版 APK 安装、旧版卸载与数据清理验收

### 9.1 当前构建身份（每轮 CI 重新核对）

- Android applicationId：com.nihaisha.nihaisha_app
- 当前 pubspec 配置：version 1.11.29+8038，即 versionName 1.11.29、versionCode 8038。
- CI 目标：单一 arm64-v8a APK。
- 以上仅为当前仓库配置快照，不证明手机旧 APK 的包名、签名或版本；旧 APK 元数据必须实测。

每轮交付必须记录 Git commit、workflow run、artifact 名称、SHA-256、applicationId、versionName、versionCode、ABI 列表和签名证书 SHA-256。缺少任一项，APK 安装验收标记 BLOCKED。

### 9.2 本轮执行干净安装，不宣称原位覆盖升级

用户已明确要求先卸载手机旧版并删除原有使用数据，再安装新版。因此本轮路径为：卸载旧包 → 确认旧包数据已删除 → 安装新包。这不验证数据迁移，也不等同于 Android 原位覆盖升级（adb install -r）。

同包名不保证能够覆盖安装。原位升级还要求签名证书兼容，且新版 versionCode 不低于已安装版本。证书不一致可能出现 INSTALL_FAILED_UPDATE_INCOMPATIBLE；versionCode 回退可能出现 INSTALL_FAILED_VERSION_DOWNGRADE。不得通过改包名、降低门槛或伪造签名绕过。

先确认设备和包名：

```powershell
adb devices
adb shell pm path com.nihaisha.nihaisha_app
adb shell dumpsys package com.nihaisha.nihaisha_app
```

确认用户需要保留的资料已另行备份后，卸载旧版（卸载会删除应用沙盒数据）：

```powershell
adb uninstall com.nihaisha.nihaisha_app
adb shell pm path com.nihaisha.nihaisha_app
```

第二条命令应不再返回 APK 路径；若仍返回，先核对设备、Android 用户 profile 和包名，不得假定卸载成功。

安装本轮 CI 下载的 APK：

```powershell
adb install .\app-arm64-v8a.apk
adb shell pm path com.nihaisha.nihaisha_app
adb shell dumpsys package com.nihaisha.nihaisha_app
```

必须返回 Success；包路径存在；实测 applicationId、versionName、versionCode 与本轮 CI 产物元数据一致；启动后无安装器报错、闪退或初始化异常。

如果设备上存在工作资料/多用户副本，逐一确认安装用户；不得误删其他用户的数据。不得在未确认备份需求前执行共享存储或整机数据清理。

### 9.3 APK 离线核验

在电脑安装 Android SDK Build Tools 后，对本轮下载的确切 APK 执行：

```powershell
Get-FileHash .\app-arm64-v8a.apk -Algorithm SHA256
apkanalyzer manifest application-id .\app-arm64-v8a.apk
apkanalyzer manifest version-code .\app-arm64-v8a.apk
apkanalyzer manifest version-name .\app-arm64-v8a.apk
apkanalyzer files list .\app-arm64-v8a.apk
apksigner verify --print-certs .\app-arm64-v8a.apk
```

通过条件：
- SHA-256 与交付记录一致。
- applicationId 精确为 com.nihaisha.nihaisha_app。
- versionName/versionCode 与本轮构建配置及 CI 记录一致；versionCode 不得意外回退。
- 原生库 ABI 清单只包含 arm64-v8a，不得把 universal 或其他 ABI APK 当成本轮 arm64 产物。
- APK 签名验证成功，并记录 signer certificate SHA-256。Debug 签名仅用于本轮测试，不得冒充正式发布签名。

### 9.4 干净安装后的应用冒烟测试

安装后依次执行并记录：

1. 首次启动、数据库初始化、首页加载、退出后再次启动。
2. 统一助手：新建会话、发送一条非敏感测试消息、返回会话列表、重新打开并确认消息恢复。
3. 知识检索：执行一项本地知识查询，确认来源引用可展开/回链；无结果时应如实提示，不得显示伪造来源。
4. 工具调用：触发一项可用工具，检查参数、执行状态、结果和错误路径。
5. 收藏、分享、复制处方、诊断历史入口：逐项验证可操作；系统分享面板能正常拉起并返回；复制内容可粘贴核对；收藏和历史在重启后仍符合设计。
6. 紫微：打开排盘、进入宫位详情、滚动长内容、返回；随后按第 4 节折叠屏矩阵执行。
7. Android 权限与系统文件选择器/相机：按 H 项执行；拒绝权限后应可恢复。
8. 强制停止后重启、切后台再返回、卸载后重新安装的行为分别记录。重新安装后旧沙盒数据不应残留；不得将此结果误写成数据迁移成功。

通过条件：每项均有真实设备操作记录和证据；启动、数据库初始化、路由和系统交互无崩溃、ANR、卡死。失败项保留为 FAIL，不以 Widget 测试替代真机结果。

### 9.5 将来如需真正的原位覆盖升级

这属于独立验收，不包含在本轮卸载清数据路径内。必须另外使用旧版 APK 与新版 APK 验证：

- 两者 applicationId 完全相同。
- 新版 versionCode 大于旧版。
- 新版签名证书与旧版兼容（通常要求同一签名证书）。
- adb install -r new.apk 安装成功。
- 旧版已有数据库、收藏、会话、设置等数据按迁移设计保留且可读取。
- 数据库 schema migration、失败回滚和重复升级测试通过。

任一条件不满足，不能宣称可覆盖升级。若旧 APK 使用不同签名且无法取得相同发布密钥，只能卸载后干净安装，用户数据将丢失；这与当前指定的验收路径一致。
