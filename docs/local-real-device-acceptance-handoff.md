# 研纪 OPPO Find N2 本地实机验收交接单

> **文档版本：** 1.8  
> **编制日期：** 2026-11-27  
> **执行地点：** 本地 Windows + OPPO Find N2（PUG110）  
> **当前状态：** **CLOUD AI CLOSEOUT CI: PASS / DEVICE: LOCAL ONLY / NOT RUN**  
> **目标：** 汇总远端交付后的唯一设备验收入口。本文件是本地执行交接，不是修复任务，也不是实机通过报告。

---

## 1. 当前交接基线

本文件编制时核对到的仓库状态如下：

| 项目 | 当前核对值 | 执行要求 |
|---|---|---|
| 仓库 | **just2512/nihaixia-app** | 只从最新 master 构建 |
| 构建基线 | **本轮运行时代码基线 04eb5bec9321b3d00eb85fdea7c0bd31b6fdc40f；五层运行时集成点 45144f6c3d140d259ac51f8cfbb886c19c10e0a3；Core-3 旧包装 API 退役合并点 11ac0c5918e5c25754b44e71f0ba48c82bea6669；Native 旧媒体 helper 清理合并点 04eb5bec9321b3d00eb85fdea7c0bd31b6fdc40f** | 运行时代码基线 04eb5bec9321b3d00eb85fdea7c0bd31b6fdc40f 的 Flutter tests run 45993861676、Flutter Quality Gate run 45993861611、Fork License run 45993861643 均 SUCCESS；Android arm64/JVM job 140491798547 与 140488210528 均 SUCCESS。Branch validation job 140488213234 为 SKIPPED，不计 PASS。执行前仍必须 git fetch origin 并重新读取届时最新 origin/master SHA、版本与 CI 终态；不得沿用本表历史 SHA 构建 |
| App 版本 | **2.0.0+8048** | versionName=2.0.0、versionCode=8048；必须严格大于设备现有 versionCode 才能覆盖升级 |
| Android applicationId | **com.nihaisha.nihaisha_app** | 不得修改 |
| 产品显示名称 | **研纪** | 桌面、应用信息、最近任务和 App 内关于页均应一致 |
| 本地模型 | Gemma 4 E4B IT | 不打包进 APK，单独下载、校验和导入 |
| 模型文件长度 | **3,659,530,240 bytes** | 必须完全一致 |
| 模型 SHA-256 | **0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0** | 必须逐字符一致 |
| LiteRT-LM | **0.18.0** | 以当前锁定依赖为准 |

**重要：** 本文件是唯一设备验收交接入口。旧的 `find-n2-e4b-local-handover.md` 与 PR #576 临时交接单已合并到本文件并撤销独立入口。执行时重新同步最新 `master`，记录 commit、CI、版本和 APK 元数据；不要沿用任何历史 SHA。

当前主线已经按专业版架构 v1.3 完成云端落地：App 运行时只有一个 ai_access 权益，Native Gate 统一控制所有 LiteRT 模型加载和推理；HeadlessToolDispatcher 保留执行计划/能力映射/结果校验，ContextResolutionGateway 保留来源引用/锚点完整性校验，两者均不承担独立收费判断。协议 v1 历史 AI Feature 兼容映射为同一 aiAccess，协议 v2 只使用 ai_access。App 永久 Token 不等同于 Fork 源代码商业许可。上述为代码与 CI 结论，不证明 Find N2 上的 Keystore、Token 正向激活、Native Gate 实际行为或 GPU/CPU 推理已经通过。

## 2. 执行前准备

### 2.1 必备条件

- OPPO Find N2 真机，USB 调试已授权；记录设备实际型号，不根据旧文档中的型号拼写推断。
- Windows PowerShell、Android SDK Platform Tools（adb）、apksigner、apkanalyzer、Flutter SDK。
- 当前仓库完整检出，能读取最新 master。
- 本机已有原始 Release 签名文件：android/key.properties 和对应 keystore。两者只保存在本机。
- 若执行 E4B：准备足够存储空间及正确的模型文件。
- 若执行正式授权正向场景：准备由当前生产发行者信任链签发、且绑定本设备的合法测试 Token。没有生产 Key Ring 或合法 Token 时，正向授权场景记 BLOCKED / MISSING，不得把测试发行者密钥塞入 Release 包。

### 2.2 只读采集设备信息

在仓库根目录执行：

~~~powershell
adb devices -l
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.sdk
adb shell getprop ro.build.display.id
adb shell wm size
adb shell wm density
adb shell settings get system font_scale
adb shell pm path com.nihaisha.nihaisha_app
~~~

另在 ColorOS「关于本机」记录 ColorOS 版本、显示大小、系统字号、桌面主题图标设置。保存不含个人账号信息的设备信息截图。

建立本轮独立证据目录：

~~~powershell
$runId = Get-Date -Format "yyyyMMdd-HHmmss"
$outDir = ".\output\find-n2\$runId"
New-Item -ItemType Directory -Force -Path "$outDir\screenshots" | Out-Null
New-Item -ItemType Directory -Force -Path "$outDir\logs" | Out-Null
~~~

不要覆盖上轮证据目录。

## 3. 旧包基线、签名与无损覆盖升级

### 3.1 提取旧安装信息

先确认设备原本安装的是本项目应用。保存设备上实际安装的 APK，并提取包名、版本和签名：

~~~powershell
$pkg = "com.nihaisha.nihaisha_app"
$oldPathLine = adb shell pm path $pkg | Select-Object -First 1
if (-not $oldPathLine) { throw "设备上未发现旧版安装；不要将清洁安装冒充覆盖升级验收。" }
$oldApkPath = ($oldPathLine -replace '^package:', '').Trim()
adb pull $oldApkPath "$outDir\installed-before.apk"
apksigner verify --verbose --print-certs "$outDir\installed-before.apk"
apkanalyzer manifest application-id "$outDir\installed-before.apk"
apkanalyzer manifest version-code "$outDir\installed-before.apk"
apkanalyzer manifest version-name "$outDir\installed-before.apk"
Get-FileHash "$outDir\installed-before.apk" -Algorithm SHA256
~~~

将旧包的 applicationId、versionCode、versionName、完整 signer certificate SHA-256 和 APK SHA-256 写入 build-metadata.json。同时记录升级前收藏、诊断历史、命盘、助手会话、设置和模型状态的数量或合成样本标识；不得写入真实病历或个人资料。

### 3.2 本地构建与安装前检查

先刷新仓库并锁定当前构建基线：

~~~powershell
git fetch origin
git checkout master
git pull --ff-only origin master
git rev-parse HEAD
git show -s --format=fuller HEAD
~~~

Release 必须使用原签名。缺少 android/key.properties 或原 keystore 时停止，不允许回退到 Debug 签名。

~~~powershell
$ErrorActionPreference = "Stop"
if (-not (Test-Path ".\android\key.properties")) {
  throw "缺少本地原签名配置；停止 Release 构建。"
}
flutter pub get --enforce-lockfile
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
flutter analyze --no-pub --no-fatal-infos
if ($LASTEXITCODE -ne 0) { throw "flutter analyze failed" }
flutter test --no-pub
if ($LASTEXITCODE -ne 0) { throw "flutter test failed" }
flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw "Release build failed" }

$apk = ".\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
if (-not (Test-Path $apk)) {
  throw "未找到预期 arm64 Release APK；先检查构建输出，不要猜测或安装其他 APK。"
}
apksigner verify --verbose --print-certs $apk
apkanalyzer manifest application-id $apk
apkanalyzer manifest version-code $apk
apkanalyzer manifest version-name $apk
Get-FileHash $apk -Algorithm SHA256
~~~

安装前必须同时满足：

1. 新旧 applicationId 完全一致，为 com.nihaisha.nihaisha_app。
2. 新 versionCode 严格大于设备当前版本；本轮源码声明版本为 2.0.0+8048。若设备已安装 8048 或更高版本，停止，先按版本策略提升构建号。
3. 新旧 signer certificate SHA-256 完全一致，或有 Android 平台认可的 signing lineage 证据。
4. apksigner verify 成功，APK 含 arm64-v8a。
5. 已记录本轮 git commit、APK SHA-256、证书 SHA-256、版本、包名和 ABI。

**任何一项不满足都判 BLOCKED，不得安装。**

### 3.3 覆盖安装

全部门槛通过后执行：

~~~powershell
adb install -r $apk
~~~

**严禁：**
- adb uninstall com.nihaisha.nihaisha_app；
- adb shell pm clear com.nihaisha.nihaisha_app；
- 在系统设置中清除应用数据/存储；
- 删除数据库、应用私有目录或模型文件来绕过升级失败；
- 使用 CI Debug APK 覆盖保留旧数据的安装。

安装失败时保留旧 App、数据和日志；根据证书、版本码或 ABI 原因排查。不得通过卸载重装把失败改成通过。

### 3.4 升级后数据核对

升级后依次检查旧有收藏、诊断历史、命盘、助手历史会话、主题/字号/默认设置及模型状态；每类至少核对一条可辨认的合成或非敏感样本。再新增一条测试记录，强制停止 App 后重启，确认旧记录和新记录都能读取。

通过条件：旧数据未重置、内容可打开、新数据能持久化、App 冷启动正常。任何缺失或迁移异常均为 FAIL，不得清库后重测并覆盖原失败记录。

## 4. 品牌、图标与 Find N2 折叠屏验收

### 4.1 品牌一致性

- 桌面名称、应用抽屉、Android 应用信息、最近任务、App 内关于页均显示 **研纪**。
- applicationId、Android namespace、Dart package、数据目录和模型路径保持兼容；更名不等于修改技术身份。
- Launcher 图标在主屏、应用抽屉和最近任务中一致；圆形/圆角方形遮罩下主体不裁切；浅色、深色桌面背景下均清晰。
- 当前颜色唯一规范为 docs/yanji-visual-design-system.md v1.5（2026-11-24）：品牌浅色主色 #D71019，深色主色 #FF5B62；图标资源以 lib/theme/yanji_palette.dart 与 test/yanji_android_icon_resource_test.dart 的一致性约束为准。
- **不得采用旧专项文档中已过时的松墨绿 #43594D / 灰绿 #E7E9E4 作为现行品牌验收基准。** 旧文档现已加注规范更新说明。
- 浅色/深色 App 主题分别查看主要页面、导航、输入框、链接、状态徽标和风险提示。颜色之外还必须保留文本/图标/结构区分，不能仅凭颜色判断状态。

### 4.2 姿态与字号矩阵

以下姿态必须分别留证，不得以某一姿态的 PASS 代替其他姿态：

| 场景 | 设备状态 | 重点检查 |
|---|---|---|
| 外屏 | 折叠、竖屏 | 底部导航、单列内容、输入区、键盘和底部安全区 |
| 内屏 flat | 完全展开 | NavigationRail、主内容可用宽度、排盘/图表、列表/详情和弹窗 |
| 半折叠 | 桌面/半开姿态 | 内容是否避开物理铰链，路由/弹窗是否锚定来源屏区 |
| 横屏/分屏 | 系统支持时 | 内容可滚动、控件可触达、无异常裁切 |

每种适用姿态分别测试系统字号 100% / 150% / 200%。同时覆盖：键盘弹出/收起、日期/时间选择器、普通对话框、底部弹层、系统返回、相机、系统文件选择器、外屏与内屏切换、锁屏/解锁和 App 前后台切换。

**必须使用真实窗口指标：**

~~~powershell
.\tool\capture_find_n2_metrics.ps1
~~~

按工具提示依次切换外屏、内屏 flat、半折叠，弹出键盘并打开相机/文件选择器；按 Ctrl+C 结束。保存 [WINDOW_METRICS] 日志，并将每张截图与 sizeDp、DPR、displayFeatures、viewInsets 对应。

通过条件：无黑边/白屏、横向溢出、控件跨越铰链、文字裁切、输入区被键盘遮挡、折叠切换导致草稿/当前 Tab 无故丢失、系统选择器无法返回或结果无法回传。

## 5. E4B 本地 AI 实机验收

完整模型配置和操作细节以 docs/local-ai-e4b.md、docs/find-n2-local-ai-acceptance-checklist.md、docs/find-n2-ai-trace-acceptance-plan.md 为准。本节是本轮最低执行摘要。当前 Native `LocalAiModelStatus` 已提供 `conversationKvCacheTokens` / `conversationKvCacheObservationStatus` 与 `modelMaxContextTokens` / `modelMaxContextTokensObservationStatus`；这些是运行态只读观测，不是 App 可用输入预算。当前 `conversationKvCacheBudgetStatus` 为 `NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`，设备测试不得将观测值自行解释为剩余 Token 数或可用上下文预算。

### 5.1 模型完整性与离线

- 文件名：gemma-4-E4B-it.litertlm。
- 文件长度：3,659,530,240 bytes。
- SHA-256：0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0。
- 模型下载到本地后先校验哈希，再从 App 文件选择器导入；不得将模型二进制提交仓库或放入 APK。
- 开启飞行模式并确认 Wi-Fi、移动数据均关闭；本地加载和文字推理不得依赖模型服务器。

### 5.2 GPU / CPU 多轮

GPU、CPU 必须分开建立会话与记录。每组要求：

- 由 App 设置中分别选择 GPU / CPU；每次加载后记录 Native 返回的**实际 backend**。
- 每个实际 backend 至少连续完成 20 轮文字问答；覆盖上下文追问、实体回指、无检索命中、澄清、工具结果解释。
- 中间重置会话后再完成至少 3 轮，确认旧上下文不串入。
- GPU 若实际回退 CPU，该组按 CPU 记录，不计入 GPU 轮数。
- 记录首次加载时间、每轮耗时、空回复、崩溃、state:7、温度/降频和可观测内存情况；同时记录 Native 返回的 `conversationKvCacheTokens`、`conversationKvCacheObservationStatus`、`modelMaxContextTokens`、`modelMaxContextTokensObservationStatus` 与 `conversationKvCacheBudgetStatus`。若观测状态为 UNKNOWN，保留 UNKNOWN 并附错误码/脱敏日志，不猜测根因；即使两项观测均有值，也不得把它们当成 App 可用输入预算。

### 5.3 图片、语音与恢复

- GPU、CPU 两个实际 backend 分别测试图片和语音输入；同时检查取消、权限拒绝、文件无效和尺寸/时长边界。
- 至少完成 5 轮后执行 Activity recreation，再执行 adb shell am force-stop com.nihaisha.nihaisha_app，重新启动并核对会话恢复。
- 对比 UI 时间线、SQLite transcript、Native completed-turn history；未完成轮次不能伪装成成功消息。
- 执行 App 内“清除全部 AI 数据”时，只验证该功能定义的 AI 数据范围：AI 会话、任务、附件/缓存和 TRACE 应按合同清除；收藏、诊断历史、命盘、设置和模型文件按既有合同保留。
- 不要通过 Android 系统“清除应用数据”代替 AI 数据清理验收。

### 5.4 TRACE

需要 Debug-only TRACE 时，按本文件 §14.3 的本地签名流程执行：
- 本机使用原 Release 签名，显式设置 localDebugUsesReleaseSigning=true；该属性不得进入 CI。
- 安装前再次核对 Debug APK 的包名、版本码和证书 SHA-256 与已安装包一致。
- TRACE 只记录 allowlist 元数据：trace_id、阶段、状态、实际 backend、必要的稳定 ID、耗时和错误码。
- 不导出 prompt/response 原文、病历/症状正文、出生资料、图片/音频内容、附件绝对路径、Token、密钥或密码。
- TRACE 完成后重新构建正常 Release APK，用相同原签名执行 adb install -r 恢复，并确认历史、模型和设置仍在。

原签名材料不可用时 TRACE 记 BLOCKED；不得改装 CI Debug APK。

## 6. 专业版离线授权与 Native Gate 验收

**本轮需额外关注：** 当前 master 已有协议修订 2 的单一 ai_access 权益实现，并保留修订 1 旧 Token 兼容。权威架构要求见 docs/pro-edition-architecture-constraints.md v1.3。代码提交和单测通过不等于 Find N2 的 Keystore / Gate / 正式发行者链路通过。

### 6.1 授权状态与密钥行为

1. 无 Token 冷启动：状态为未授权；不得自动创建设备密钥；免费确定性功能仍可使用。
2. 日常启动、状态刷新、Token 导入：只能 get-only 读取已有 Keystore alias；不得自动新建或替换密钥。
3. 只有用户明确进入激活申请并主动确认创建时，才允许创建 P-256 设备密钥。
4. 记录设备实际安全级别：STRONGBOX / TRUSTED_ENVIRONMENT / SOFTWARE / UNKNOWN；只在明确 StrongBox 不可用时允许回退 TEE，并记录真实原因。
5. 退出并冷启动 App，重新验证 Token；不得依赖持久化 is_pro 或未经验证的本地缓存授予权限。

### 6.2 Token 协议兼容与替换

使用发行端提供的合法、与本设备绑定的签名测试凭证：

| Token | 预期 |
|---|---|
| 修订 1，包含 ai_advanced | 签名/设备/App/产品均有效时映射为单一 aiAccess=true |
| 修订 1，包含 contextual_assistant | 同样映射为 aiAccess=true |
| 修订 1，不含上述任一旧 AI Feature | aiAccess=false |
| 修订 2，仅包含 ai_access | 合法时 aiAccess=true |
| 修订 2 只有旧 Feature ID | 不得映射为 AI 访问 |
| 错误签名、未知发行者、错误 App、错误设备、损坏字段/重复 ID | 拒绝，不授予权限 |

Token 替换必须先完整验证，再原子写入并重读验证。新 Token 无效、用户取消或原子写入失败时，旧 Token 必须保留；旧、新权益不能静默合并。授权文件和 Keystore 行为按架构文件核验，不能用数据库字段或 UI 文案代替。

### 6.3 Native 模型访问门禁

在无 Token、无权益、checking、暂时不可用、签名错误、设备不匹配或发行者不可信时：

- Native LiteRT Engine 不得加载；
- 文本、图片、语音及其他推理入口均不得执行；
- UI 禁用按钮不是通过证据，必须确认 Native Gate 拒绝；
- 免费的确定性问诊、排盘、历法、剂量换算、纯本地查询和数据管理不应被误锁。

在合法 ai_access Token 有效时，允许全部受支持的 Native LiteRT 推理入口；不得按页面、AI 模式或媒体类型拆成不同付费权益。授权失效后应拒绝新推理并安全释放运行中的模型会话。

### 6.4 破坏性场景隔离

Android 系统清除 App 数据、卸载重装、删除 Token、模拟 KeyStore alias 丢失等测试会改变本地状态。**不得在保存个人历史/模型的主设备安装实例上直接执行。** 只有完成独立备份、使用专门测试实例并获得明确执行许可后，才执行这些破坏性场景；否则标记 BLOCKED / NOT RUN，不影响对非破坏性项目的验收记录。

若生产 Key Ring、发行端或设备绑定 Token 尚未准备好：
- 无 Token 负向 Gate、免费功能和“不自动建 key”场景仍可执行；
- 合法 Token 正向授权、旧 Token 兼容、Token 替换和完整推理场景标记 BLOCKED / MISSING；
- 不得把测试 issuer 加入生产 Release，不得伪造 Token，不得用本地开关绕过 Gate。

### 6.5 云端 v1.3 / Core 集成证据（不是实机通过证明）
- **AI 五层运行时集成点：** 45144f6c3d140d259ac51f8cfbb886c19c10e0a3（PR #585 merge commit，包含 #583 媒体结构化协议）。本轮运行时代码复核基线：master@04eb5bec9321b3d00eb85fdea7c0bd31b6fdc40f；当前 app version 2.0.0+8048，Android applicationId = com.nihaisha.nihaisha_app。本地执行前始终重新读取最新 origin/master 并记录实际构建 SHA、APK 元数据、签名证书及设备当前安装版本。
- **v1.3 单一授权链路：** PR #472（冻结单一授权架构）、#478（Native LiteRT `ai_access` 总门禁）、#482（撤销 Dispatcher/Gateway 独立收费判断）、#491（云端收尾台账/交接）均已合并。协议修订 1 的历史 AI 权益兼容映射为同一 `aiAccess`；协议修订 2 只使用 `ai_access`。App 永久 Token 不等于 Fork 源代码商业许可。
- **Core 云端实现记录：**
  - PR #493 已合并（`fd2c0da989a9d748088b9ef0bbad3f697c6d327d`），分离瞬时 RAG 正文与 Native 恢复 transcript；Fork、Flutter、Android arm64/JVM 检查均 SUCCESS（run `45541268760` / `45541268723` / Android job `138942270425`）。
  - PR #495 已合并（`9c7a4c6761a467bb13b0b5381992df2e96cfc3ba`），冻结 Core-0 五层 DTO 字段合同和源码/测试映射；Fork 与 Flutter 检查 SUCCESS（`138948246934`、`138948369724`）。
  - PR #496 已合并（`b62bc101865612c02503bedce8d05cf11390d56d`），Native transcript 只恢复完整成功轮次并限制为最多 12 轮/10,000 UTF-16 code units；精确 HEAD 的 Fork、Flutter、Android arm64/JVM 检查 SUCCESS（`138946470635`、`138946470476`、`138949605374`）。该字符上限不等于 LiteRT-LM token 预算。
  - PR #498 已合并（`82b2474202a33d802722e79560f6ae17670aab9a`），新增候选证据批次与经典候选收集边界；精确 HEAD 的 Fork、Flutter、Android arm64/JVM 检查 SUCCESS（`138955502743`、`138955626207`、`138958765875`）。
 - **PR #576 产品范围纠偏（历史记录）：** PR #576 的精确 HEAD 及 CI 结果仍作为该次变更的历史证据；其 merge commit `5dcf91f...` 已被后续主线推进取代，不再是当前应用代码基线。
 - **Core-3 媒体协议 / PR #583：** 图片、音频附件已接入 ReasoningRequest/Response v1 和 Native 双阶段提交；精确 HEAD 的 Flutter regression、Android arm64/JVM、Fork license 与 push Branch validation 均 SUCCESS。旧 sendImage/sendAudio Native 入口 fail-closed；音频转写仍是待用户确认草稿。
- **Core-3 旧兼容接口退役 / PR #594：** 精确 HEAD `85e77de947d144fd52902690094ba84de4d248c8` 已合并为 master `11ac0c5918e5c25754b44e71f0ba48c82bea6669`。LocalAiService 旧 sendMessage*/sendImage*/sendAudio* 包装方法已移除；Native 旧 sendMessage 保留为返回 `STRUCTURED_REASONING_PROTOCOL_REQUIRED` 的 fail-closed 兼容入口。Flutter regression run `45968674159`、Android arm64 APK/JVM job `140406700872`（22/22 steps）与 Fork License run `45968674271` 均 SUCCESS；PR Branch validation 为 SKIPPED，不计 PASS。
- **Core-3 Native 旧媒体 helper 清理 / PR #598：** merge commit `04eb5bec9321b3d00eb85fdea7c0bd31b6fdc40f` 删除已无调用点的 `sendLocalImage()` / `sendLocalAudio()` 自由文本推理 helper；旧 `sendImage` / `sendAudio` MethodChannel 仍 fail-closed，结构化附件主路径不变。静态回归扩展至核对 8 个真实模型调用入口均声明 `requiresAiAccess=true`，并确认 `runAiTask` 经过唯一 `AiModelAccessGate`。该变更并入既有媒体/Native 场景，不单独建立本地交接单。精确运行时代码 HEAD 的 Flutter tests、Flutter Quality Gate、Fork License 均 SUCCESS；Android arm64/JVM 对应 job SUCCESS。
- **Core-5 跨层 E2E / PR #585：** 已合并 20 轮知识追问和一次工具动作确认/执行/结果解释 widget 测试。精确 HEAD 的 Flutter regression、Android arm64/JVM、Fork license 和同 SHA push Branch validation 均 SUCCESS。fake executor 不代表真实 E4B/设备已通过。
- **当前主线 CI：** 本地执行前再次读取最新 master SHA 和对应 CI 终态。任何未完成、SKIPPED 或其他 SHA 的检查不得计 PASS；本交接文档更新不改变运行时代码。
- 上述 CI Debug APK/arm64 artifact 只证明 CI 构建、ABI、Manifest 和对应 JVM/Flutter 自动化，不是产品正式签名 Release APK，也不代表 Find N2 真机安装或覆盖升级通过。Branch validation 为 SKIPPED 时不计 PASS。
- **Fork inventory：** 当前清单记录新增/修改路径共 1,011 个（新增 847、修改 164），删除路径 15 个；分类为 Apache 2.0 + Fork 双层许可 158、Fork 商业授权候选 489、知识库排除 363、第三方排除 1。以 `docs/fork-license-file-inventory.md` 和 JSON 的当前 master 版本为准；自动 license boundary 只证明 inventory/DEP5/SPDX 结构一致，不证明 Fork 自有代码权属。
- **正式发行仍 BLOCKED：** 正式发行者公钥来源、GitHub Secret `YANJI_LICENSE_KEY_RING` 实际值、生产私钥离线托管/恢复演练、真实客户签发与密钥轮换均缺少可核验证据。不得使用测试公钥或临时公钥替代。
- **设备状态仍为 `LOCAL ONLY / MISSING / UNKNOWN`。** Keystore / StrongBox / TEE、AtomicFile 故障恢复、原签名覆盖升级及数据保留、GPU/CPU 多轮、多媒体、Activity/进程恢复、知识条目一键解读、键盘避让、端到端 TRACE 与 AI 数据清除均须在 OPPO Find N2 本地执行并附证据。设备验收放在云端工作之后，不作为云端代码/CI 的阻塞项。

## 7. 证据包、结果记录与回传

每轮目录至少包含：

~~~text
output/find-n2/<run-id>/
  device-metadata.json
  build-metadata.json
  model-metadata.json
  authorization-results.md
  window-metrics.log
  screenshots/
  logs/
  test-results.md
~~~

test-results.md 每一行按以下格式填写：

| ID | 场景/设备姿态 | 前置条件 | 操作步骤 | 预期 | 实际 | 状态 | 证据 |
|---|---|---|---|---|---|---|---|
| INST-01 | 原签名覆盖升级 | 旧包存在、证书已核对 | adb install -r | 数据保留 | 待填写 | MISSING | 文件名/日志 |
| BRAND-01 | 名称与图标 | 升级安装成功 | 检查桌面/抽屉/关于页 | 名称研纪、图标符合当前规范 | 待填写 | MISSING | 截图 |
| FOLD-01 | 外屏 | 设备折叠 | 启动、切 Tab、弹键盘 | 无溢出/遮挡 | 待填写 | MISSING | 截图+metrics |
| FOLD-02 | 内屏 flat | 完全展开 | 导航、内容、弹窗 | 可用宽度正确 | 待填写 | MISSING | 截图+metrics |
| FOLD-03 | 半折叠 | 半开姿态 | 打开页面/弹层/输入 | 避开铰链 | 待填写 | MISSING | 截图+metrics |
| AI-GPU-01 | GPU 多轮 | Native 实际 backend=GPU | 至少 20 轮 | 无状态错乱/空回复 | 待填写 | MISSING | trace/log |
| AI-CPU-01 | CPU 多轮 | Native 实际 backend=CPU | 至少 20 轮 | 无状态错乱/空回复 | 待填写 | MISSING | trace/log |
| LIC-01 | 无 Token Gate | 无合法 Token | 尝试模型加载/推理 | Native 拒绝、免费功能可用 | 待填写 | MISSING | 脱敏日志 |
| LIC-02 | 合法 ai_access | 合法绑定 Token | 加载并推理 | Gate 允许、后端可核对 | 待填写 | MISSING | 脱敏 TRACE |

状态只能使用：
- **PASS**：真机执行完成，满足全部通过条件，证据可复核；
- **FAIL**：真机执行完成，违反通过条件；保留失败日志和最小复现；
- **BLOCKED**：有明确外部前置依赖/权限/设备条件缺失，写清阻断原因；
- **MISSING**：未执行或证据不足；
- **NOT_APPLICABLE / NOT_ENABLED**：当前设备/系统/产品范围不适用，必须注明理由。

#### 7.0 Find N2 本地验收总览（统一状态矩阵）

下表把已合并的远端改动归并为本地执行包。它是同一交接单的总索引，不按 PR 或功能另建文档。云端 CI 通过只代表代码/自动化门禁通过；本表中的设备项当前全部尚未实测。

| 工作包 | 云端代码/自动化状态 | Find N2 当前状态 | 本地必须留存的关键证据 |
|---|---|---|---|
| 安装身份、原签名覆盖升级与数据保留 | Manifest、ABI、签名构建保护等自动化门禁通过；正式 Release 仍由本地原签名构建 | MISSING | 旧/新 APK 元数据、签名证书 SHA-256、版本码、覆盖安装结果、升级前后数据哨兵 |
| 品牌名称、Launcher 图标与外屏/内屏/半折叠布局 | 品牌资源/几何约束有自动化检查；PR #564 尚未合并，不属于本轮运行时代码基线 | MISSING | 当前 master 图标截图、ColorOS 遮罩、外屏/内屏/半折叠截图与窗口 metrics |
| Core-1 Native 会话记忆与多轮恢复 | Transcript、SessionState owner/provenance、临时上下文隔离、请求终态 Ledger、UNKNOWN 不重放已有代码/测试 | MISSING / DEVICE UNKNOWN | GPU 与 CPU 各至少 20 轮、实际 backend、state:7、Activity/process restart、SQLite/UI/Native transcript 对照 |
| Core-2 检索证据与知识条目解读 | CandidateEvidence、RankedEvidenceSet、黄金检索回归及来源回填约束已有云端覆盖 | MISSING | 本地知识命中/无命中/跨轮回指、知识条目情境入口、来源锚点和消息 metadata |
| Core-3 五模式文本与图片/音频附件 | 五模式结构化 Request/Response、媒体双阶段提交、旧自由文本入口 fail-closed；PR #598 清理不可达旧 helper | MISSING / DEVICE UNKNOWN | E4B 文字/图片/音频场景、实际 backend、每轮 TRACE、取消/失败不伪成功 |
| Core-4 四项受限工具执行闭环 | 仅 dosage、solar_terms、yuxiaji_omen、sanshan_lingqian；显式确认、one-shot claim、结果读回与 UNKNOWN 不重放有自动化覆盖 | MISSING | 真实工具调用 TRACE、参数确认、实际结果、重复请求/中断不重放 |
| Core-5 跨层应用流程 | 20 轮知识追问与一次工具提案/确认/执行/解释的 widget E2E 已通过；使用 fake Native/executor | MISSING / DEVICE UNKNOWN | 真机 E4B 真实模型输出、引用回填、工具结果解释与持久化链路 |
| AI 数据清理与重启恢复 | 代码及自动化覆盖已合并；不扩大删除范围 | MISSING | 清理前后 AI 数据与非 AI 数据哨兵、强停/重启后复核、失败域报告 |
| ai_access / Token / Keystore | 云端单一授权 Gate 与协议回归已覆盖；正式发行者材料/合法绑定 Token 不由 CI 伪造 | MISSING；合法生产 Token 未准备时正向授权场景记 BLOCKED | Keystore/设备密钥状态、合法设备绑定 Token 的验签/替换/重启复验；不使用测试密钥绕过 |

记忆层边界：当前已接入的 `Conversation.getTokenCount()` 与 `ModelInfo.maxContextTokens()` 只是 Native 运行时只读观测；`conversationKvCacheBudgetStatus=NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`。本地不得把观测值解释为剩余输入预算，不得自行补出 Token 阈值、输出预留或自动压缩结论。所有未执行项维持 MISSING / UNKNOWN / BLOCKED。

#### 7.1 本地执行进度汇报要求

本文件是唯一设备交接单。本地执行者必须直接更新本文件，不得为每个 PR、每个设备场景或每次修复另建交接文档。每次开始、阶段完成、遇到阻塞和结束时，均在本节追加一条进度记录，并同步更新 §7 的 `test-results.md` 对应场景状态。

| 日期/时间 | 本地执行者 | 设备型号 / Android / ColorOS | 实际构建 SHA / APK version+versionCode | 已完成场景（ID） | 当前状态（PASS/FAIL/BLOCKED/MISSING/UNKNOWN） | 证据目录/文件 | 缺口或阻塞原因 | 下一步 |
|---|---|---|---|---|---|---|---|
| 待本地首次执行填写 | 本地执行者填写 | 实测值 | 必须填写实际值，不沿用文档历史 SHA | 待填写 | MISSING | `output/find-n2/<run-id>/` | 尚未开始本地实机验收 | 从 §1、§3 开始，先核对设备旧包、签名和最新 master |

**更新规则：**
- 不覆盖旧记录；每次进度更新追加新行，保留时间顺序。
- 只填写真实执行结果；未执行写 MISSING，缺少依赖写 BLOCKED，证据不完整写 UNKNOWN，不得预填 PASS。
- 每次更新必须包含实际 master SHA、APK version/versionCode、设备型号、证据目录和明确缺口；失败场景同时记录最小复现与脱敏日志。
- 若本地发现需要远端修复的问题，在本表记录缺陷 ID/复现与证据，并在同一仓库的执行台账登记；远端修复完成后仍回到本文件更新原场景，不新建第二份交接单。
- 远端每次合并影响设备验收的改动，只更新本文件对应章节和当前基线，不新增 PR 专属交接文件。

### 7.2 禁止进入证据包的资料

不得提交 keystore、key.properties、密码、完整 Token、私钥、公钥原始材料、真实病历/症状、个人出生资料、梦境隐私、prompt/response 原文、图片/音频正文、模型二进制、附件绝对路径或账号身份信息。截图和日志先脱敏。

### 7.3 整体验收完成定义

只有本轮约定范围内所有必测场景均为 PASS，且 APK 身份/签名/升级、数据保留、外屏/内屏/半折叠、品牌、E4B 实际 backend、授权门禁与恢复证据齐全，才能记录 **LOCAL DEVICE ACCEPTANCE = PASS**。

出现任何必测 FAIL，整体不得 PASS；仍有必测 BLOCKED / MISSING，整体只能记录 PARTIAL 或 BLOCKED。不得把计划、源码存在、Widget、模拟器或 CI 成功当作 Find N2 实机通过。

---

## 8. 配套专项操作规范

本文件是唯一设备验收交接入口；以下文件只提供对应专项的详细操作步骤，不再各自作为独立交接单：

1. [本地 Android 构建与升级检查清单](local-android-release-checklist.md)
2. [Find N2 真机折叠屏验收方案](find-n2-real-device-acceptance.md)
3. [Gemma 4 E4B 本地配置与边界](local-ai-e4b.md)
4. [Find N2 本地 AI 后端验收清单](find-n2-local-ai-acceptance-checklist.md)
5. [Find N2 AI TRACE 验收方案](find-n2-ai-trace-acceptance-plan.md)
6. [研纪 UI 视觉设计系统](yanji-visual-design-system.md)
7. [研纪品牌与应用身份规范](brand-identity.md)
8. [研纪专业版架构约束 v1.3](pro-edition-architecture-constraints.md)
 
---
 
## 14. 2026-11-27 Core-5 合并后的统一验收补充
 
> 本节和本文件其他部分共同构成唯一设备交接；不再新增 PR 专属交接单。所有场景目前均为 **NOT RUN / LOCAL ONLY**，须以真实 Find N2 证据更新。
 
### 14.1 云端合并与构建前置条件
 
  1. PR #583 与 #585 已合并到 `master`；AI 五层运行时集成点为 `45144f6c3d140d259ac51f8cfbb886c19c10e0a3`。当前文档复核基线为 `1d79bc2f628fde789c5b5602cee889f844972c23`，对应 Flutter tests、Flutter Quality Gate、Fork License 三项主线 CI 均 SUCCESS；本次仅同步文档。#583 已通过媒体结构化协议精确 HEAD 验收，#585 已通过 20 轮跨层 E2E 精确 HEAD 验收。实际设备安装前仍须读取最终 `origin/master` SHA 与对应云端 CI 终态；不得沿用旧 PR SHA 或旧 APK。
2. 在本地执行 \`git fetch origin\`、\`git checkout master\`、\`git pull --ff-only origin master\`，记录 \`git rev-parse HEAD\` 与 \`git show -s --format=fuller HEAD\`。
3. 本地构建只使用该最新 master。任何 PR head、旧分支或旧 APK 均不能作为设备验收构建基线。
4. 构建前重新核对 \`pubspec.yaml\`、applicationId、设备旧版 versionCode、原签名证书和模型 SHA；与 §3 的无损覆盖安装门槛一致。
5. 若上述 CI 或签名/版本门槛未满足，设备安装记为 BLOCKED，不得用卸载、清除数据或 Debug 签名绕过。
 
### 14.2 普通学习助手链路补充场景
 
使用合成、非敏感的学习问题与测试文件，不输入真实患者资料或其他个人敏感信息。
 
| ID | 场景 | 操作 | 验收重点 | 状态 |
|---|---|---|---|---|
| P576-01 | 普通学习对话 | 发送一个普通中医基础知识问题 | 可以调用模型、返回并展示非空回答 | NOT_RUN |
| P576-02A | 自动模式 | 发送普通知识问题 | 正常路由，不依赖临床检测状态 | NOT_RUN |
| P576-02B | 问诊模式 | 发送学习性、非诊断执行的中医概念问题 | 模式入口和普通学习解释可用；App 确定性问诊规则不被模型替代 | NOT_RUN |
| P576-02C | 学习模式 | 发送普通经典条文或本草学习问题 | 正常检索、解释与来源回链 | NOT_RUN |
| P576-02D | 工具模式 | 请求一个无破坏性的已有工具 | 参数校验、用户确认（如适用）、真实工具执行和结果回流可关联 | NOT_RUN |
| P576-02E | 玄学模式 | 发送传统术数文化性问题 | 模式隔离和普通解释可用，不将文化问题当成临床问题 | NOT_RUN |
| P576-03 | initialPrompt / 情境入口 | 从知识条目或结果页点击“问 AI” | 初始上下文、source/anchor/snapshot 正确，不串项 | NOT_RUN |
| P576-04 | 历史续聊 | 打开既有助手会话并追问上一轮内容 | 历史恢复、指代正确，不重复提交旧轮次 | NOT_RUN |
| P576-05 | 图片附件 | 使用无个人信息的普通知识图片 | 选择、权限、读取、模型处理、展示与消息关联正常；取消/失败不伪装成功 | NOT_RUN |
| P576-06 | 语音附件 | 使用普通短语音样本 | 录音/选择、转写或模型处理、结果展示与持久化正常；失败状态清楚 | NOT_RUN |
| P576-07 | 工具结果回流 | 执行一个已有确定性工具 | 只有 App 实际执行并校验的结果进入解释；模型不得伪造结果 | NOT_RUN |
| P585-01 | 20 轮记忆隔离与单次工具闭环 | 同一会话连续 20 轮知识追问，再发起一次 tools-mode ACTION_PROPOSAL；由用户显式确认 | requestId 唯一；会话记忆携带用户知识上下文但排除隐藏 reasoning/tool Ledger；确认前执行次数为 0；确认后真实执行恰好 1 次；claim/terminal 可回读；解释回合 allowlist 为空且只消费已验证结果 | NOT_RUN |
| P576-08 | 会话切换 | 在两个会话间分别追问 | 消息、附件和上下文锚点不跨会话污染 | NOT_RUN |
| P576-09 | 应用重启恢复 | 完成一轮后强制停止并重启 App | 已完成轮次可恢复；未完成轮次不冒充成功；无重复消息 | NOT_RUN |
| P576-10 | TRACE（可选 Debug） | 显式启用本地 Debug TRACE 并执行代表场景 | trace_id、阶段、实际 backend、消息和持久化记录可关联；仅导出脱敏 allowlist 元数据 | NOT_RUN |
 
本项目不执行临床红旗 detector、临床风险分类、医学审核、本人/他人/否定/历史/假设/引用等临床语义测试。此类事项不属于设备验收，不得重新列为 MISSING、BLOCKED 或发布前置条件。
 
### 14.3 Debug-only TRACE 的原签名切换流程
 
TRACE 只用于本机诊断；不得安装 CI Debug APK，不得上传或分发带调试能力的 APK。
 
\`\`\`powershell
$env:ORG_GRADLE_PROJECT_localDebugUsesReleaseSigning = 'true'
$env:ORG_GRADLE_PROJECT_ciArm64Only = 'true'
try {
  flutter build apk --debug --no-pub --target-platform android-arm64
  if ($LASTEXITCODE -ne 0) { throw "Local TRACE Debug build failed." }
}
finally {
  Remove-Item Env:ORG_GRADLE_PROJECT_localDebugUsesReleaseSigning -ErrorAction SilentlyContinue
  Remove-Item Env:ORG_GRADLE_PROJECT_ciArm64Only -ErrorAction SilentlyContinue
}
$debugApk = ".\\build\\app\\outputs\\flutter-apk\\app-debug.apk"
apksigner verify --verbose --print-certs $debugApk
Get-FileHash $debugApk -Algorithm SHA256
apkanalyzer manifest application-id $debugApk
apkanalyzer manifest version-code $debugApk
\`\`\`
 
仅当 Debug APK 的 applicationId 一致、versionCode 不低于设备当前包、签名证书 SHA-256 与设备当前包完全相同，才允许 \`adb install -r $debugApk\`。TRACE 完成后清除本地构建属性，按 §3 重建正常 Release APK，并用原签名覆盖安装恢复。原签名材料缺失时标记 BLOCKED，不安装、不卸载、不清数据。
 
### 14.4 本地回传内容
 
在独立的 \`output/find-n2/<run-id>/\` 目录回传：
 
- 实际 master commit、App version/versionCode、applicationId、APK SHA-256、签名证书 SHA-256、ABI；
- 设备型号、Android/ColorOS、屏幕姿态和系统字号；
- P576-01 至 P576-10 逐项结果，及本文件第 3–7 节其他适用项目结果；
- GPU/CPU 实际 backend、轮次结果、耗时、空回复/异常和脱敏 TRACE；
- 升级前后用户数据保留核对；
- 可复现缺陷的预期/实际、最小复现、脱敏日志和截图编号。
 
状态按实际证据记为 PASS / FAIL / BLOCKED / UNKNOWN / NOT_RUN。未执行不得记 PASS；只提交脱敏摘要，不提交数据库原件、模型文件、密钥、真实个人资料或对话原文。
 

**交接结论：** 当前仅完成远程仓库与规范基线核对，未连接或操作用户的 OPPO Find N2。所有本地设备结果在真实执行并提供证据前均保持 MISSING / LOCAL ONLY。


## 15. 2026-11-27 合并 PR #560 的知识解读与键盘避让实机验收

> 本节将原 PR #560 的独立交接内容纳入本文件。**本文件仍是唯一设备验收交接入口**；不再保留第二份知识解读交接单。源码、APK、模型和设备基线统一使用本文件 §1–§5 的现行值；PR #560 原文中的旧 master SHA 不再作为构建基线。

### 15.1 本节验收范围

| ID | 验收对象 | 必须确认的结果 |
|---|---|---|
| P1-IME | 外屏/内屏情境 AI 面板键盘避让 | composer 与 App 发送按钮始终可见；文字不丢；收起后布局恢复；折叠/展开不破坏会话 |
| P0-AUTO | 七类知识详情一键解读 | 点击后自动提交一次短意图；不要求用户编辑长提示；不把完整资料放进用户消息 |
| P0-CONTEXT | 后台知识上下文与跨轮追问 | 每轮绑定当前详情条目；source/anchor/version 不串线；上下文失效时明确失败，不使用旧缓存 |
| P0-QUALITY | E4B 知识理解质量 | 不复述详情页；分析关系与内在逻辑；区分原文记载、归纳、MISSING/UNKNOWN；不补造内容 |

本节只补充上述 P0/P1 细项。GPU/CPU 通用稳定性 20 轮、多媒体、Activity/进程恢复、AI 数据清理、授权和 TRACE 仍按本文件 §3–§8 执行；这些专项不因本节通过而自动关闭。经典阅读页选中文段自由提问，以及易经、八字、紫微、子午流注、节气、运气、剂量换算等确定性 `toolResult/fieldValue` 结果解释不属于本节七类知识条目 adapter 验收。

### 15.2 P1：键盘避让实机验收

**外屏 bottom-sheet（IME-OUT）**

1. 合拢 Find N2，打开任一已迁移的知识详情，点击“问 AI 解读”。
2. 等待情境 AI bottom-sheet 出现；初始打开不得因自动解读抢焦点或主动弹出键盘。
3. 点击 composer，弹出系统键盘，输入 `外屏键盘可见性测试 123`。
4. 检查 composer、光标和输入文字完整位于 IME 顶边之上；App 自己的发送按钮完整可见且可点击。不得把系统键盘 Enter 键当作 App 发送按钮。
5. 检查底部安全区、手势导航区和面板边界没有重叠或裁切。
6. 使用 App 发送按钮发送，确认无丢字、重复发送；记录发送后键盘实际状态，不擅自规定未定义行为。
7. 使用系统返回键收起键盘，确认面板恢复、无残留空白/错误位移；再次聚焦并重复输入/收起一次。

**内屏 side-panel（IME-IN）**

1. 展开 Find N2，进入知识详情并点击“问 AI 解读”，确认助手以内屏 side-panel 显示。
2. 点击 composer，弹出系统键盘，输入 `内屏键盘可见性测试 456`。
3. 检查 composer、文字、光标和 App 发送按钮完整位于键盘上方；面板没有因 Dialog inset 与内部布局重复避让而过度缩小。
4. 使用 App 发送按钮发送，再用系统返回键收起键盘；确认 side-panel 高度、宽度、位置恢复。
5. 关闭并重新打开面板，再测试一次，排除 route 残留旧 inset。

**折叠切换（IME-FOLD）**

- 内屏打开助手并弹出键盘时合拢设备，检查切到外屏后的会话、输入文本和输入框状态。
- 外屏打开助手并弹出键盘时展开设备，检查切到内屏后的 side-panel/route 位置和输入状态。
- 对设备实际支持的半折叠姿态重复检查并记录。
- 若 ColorOS 在折叠切换时主动关闭键盘，可记录为系统行为，不单独判代码失败；但输入内容、会话和重新聚焦能力仍须验证。

**PASS 条件：** 无崩溃、黑屏、错位、裁切、丢字、重复发送或发送按钮遮挡；键盘收起后布局恢复；会话和未提交文本按路由生命周期保持。真实窗口尺寸、姿态与截图按 §4.2 / §7 记录。

### 15.3 P0：七类知识详情一键解读（AUTO）

必须逐个执行，不用一个入口代表全部入口：

| 场景 ID | 入口 | 操作 |
|---|---|---|
| AUTO-FORMULA | 方剂 | 打开具体方剂详情，点击 AI 解读 |
| AUTO-HERB | 本草 | 打开具体本草详情，点击 AI 解读 |
| AUTO-ACUPOINT | 穴位 | 打开具体穴位详情，点击 AI 解读 |
| AUTO-ACUPUNCTURE | 针灸处方 | 打开具体处方条目，点击 AI 解读 |
| AUTO-CASE | 医案 | 打开具体医案详情，点击 AI 解读 |
| AUTO-MERIDIAN | 六经 | 打开具体六经详情，点击 AI 解读 |
| AUTO-NEIJING | 内经 | 打开具体条文详情，点击 AI 解读 |

每个入口检查：

1. 点击后无需编辑长提示或再次点击发送；模型就绪且情境会话初始化完成后自动启动一次分析。
2. 用户消息/对话记录只包含短意图，不出现完整 JSON、sourceId、anchorId、版本号、本地路径或内部约束文本。
3. 不自动弹出键盘或抢输入焦点。
4. 输出对应当前打开条目，不串到上一个页面或上一次会话。
5. 不重复启动；用消息时间线和脱敏 TRACE 的 request/turn 元数据核对。

另测模型尚未加载时的等待场景（AUTO-WAIT-READY）：从知识详情点击解读后，应等待模型可用，不提前发送、不丢失 pending 意图；模型加载且会话初始化完成后自动提交一次。多次状态刷新、页面重建不得重复提交。初始化失败或 contextRef 无效时显示明确失败/UNKNOWN，不得使用旧缓存条目继续回答。

### 15.4 P0：当前条目上下文和连续追问（CONTEXT-FOLLOWUP）

选择本地真实存在、字段较完整的方剂条目作为主场景，优先桂枝汤；若当前数据集中不存在，则选一个实际可打开且组成字段完整的条目，记录真实名称，不造测试数据。

1. 在详情页点击 AI 解读，等待第一轮回复并记录当前详情标题。
2. 追问：`你刚才分析的整体结构，分别依据当前条目中的哪些信息？请区分条目明确记载和你的归纳，不要重列完整组成。`
3. 再追问：`当前条目没有直接说明的配伍作用有哪些？请明确标记无法确认的部分，不要用常见说法补齐。`
4. 确认两轮追问仍围绕原条目，前文指代有效，不要求重新粘贴资料或再次编辑长提示。
5. 返回详情页，打开另一条目并启动新解读；确认上下文切换到新条目，没有跨条目污染。
6. 若 App 提供本地来源/引用入口，点击并确认回到当前条目；无法打开或定位到错误条目记 FAIL。

**PASS 条件：** 首次点击只启动一次；连续追问保持当前条目；切换条目后同步切换；内部 source/evidence ID 不作为普通回答文本暴露；锚点、版本或来源解析失败时明确失败，不使用缓存旧条目回答。

### 15.5 P0：E4B 知识理解质量（QUALITY）

GPU 与 CPU 必须分开建会话、分别记录。每次记录用户选择 backend 与 Native 实际 backend；GPU 选择后若实际回退 CPU，该轮不得计入 GPU 结果。每种 backend 各执行以下三个代表场景，均从详情页一键解读入口启动，不手工粘贴完整资料。

**A. 方剂组方关系（FORMULA-QUALITY）**

- 使用桂枝汤或本地资料中另一个组成字段完整的方剂。
- 初始分析说明整体结构、条目实际标注的药物角色及配伍关系，不重新完整罗列药物/剂量清单。
- 追问：`请把你提出的关系逐项对应到当前条目的依据；哪些是明确记载，哪些是根据条目内容归纳？`
- 追问：`哪些问题当前条目无法确认？请保留 UNKNOWN，不要补充条目未提供的禁忌、剂量或临床证据。`

**B. 本草信息关系（HERB-QUALITY）**

- 选择本地存在、性味/归经/功用字段较完整的本草条目。
- 初始分析解释这些字段之间能建立的关系，而不是逐项释义后结束。
- 追问：`你刚才的归纳分别由哪些条目字段支持？原文没有直接建立的关系请明确标出。`
- 追问：`当前条目没有提供哪些信息？不要根据模型记忆补齐。`

**C. 医案证据链（CASE-QUALITY）**

- 选择 App 内已有医案详情，只使用合成、非敏感学习资料，不输入真实个人病例。
- 初始分析梳理该记录包含的症状、病机、治法、方药之间的对应关系。
- 追问：`把记录明载的内容和你根据记录作出的推断分开说明；每个推断指出依据。`
- 追问：`这份记录不能支持哪些结论？请明确列出未知，不要自行补齐。`

若真实条目缺少上述字段，记录实际缺项并检查模型是否正确说明不足，不得为了通过验收而造数据或替换为虚构资料。

**逐条输出断言：**

| 断言 | PASS 条件 | FAIL 条件 |
|---|---|---|
| 不复述 | 不重抄详情页完整资料，只引用解释关系所必需的少量内容 | 主要内容仍是逐字段改写或完整列表复述 |
| 有分析 | 至少说明当前条目两个或多个信息之间的关系/结构，且有当前资料依据 | 只有概述、释义或换词，没有关系分析 |
| 原文与归纳分开 | 标出条目明确记载与基于条目的归纳，并说明归纳依据 | 把模型推断伪装成原文事实 |
| 未知处理 | 对未提供信息明确说明 MISSING/UNKNOWN 或“当前资料无法确认” | 用常识或模型记忆擅自填空 |
| 不编造 | 不新增条目未提供的组成、剂量、禁忌、出处、证据或规则 | 出现无法由当前条目支持的具体事实 |
| 连续追问 | 两次追问保持当前条目和前文指代 | 丢失条目、串到旧条目或要求重新粘贴资料 |
| 输出可用 | 回复非空、结构连贯、回答实际问题 | 空回复、重复循环、乱码、无关输出或协议拒绝 |

一次回答出现编造内容或把归纳伪装成原文，整条场景记 FAIL，并保存最小复现与 trace_id。只在全部适用断言通过时记 PASS。

### 15.6 场景记录与隐私边界

将以下场景纳入 §7 的本轮 `test-results.md`，每项填写 backend（适用时）、结果、trace_id/证据文件和失败说明：

| 场景 ID | 验收内容 | 初始状态 |
|---|---|---|
| IME-OUT / IME-IN / IME-FOLD | 外屏、内屏、折叠切换键盘避让 | NOT RUN |
| AUTO-FORMULA / AUTO-HERB / AUTO-ACUPOINT | 方剂、本草、穴位自动解读 | NOT RUN |
| AUTO-ACUPUNCTURE / AUTO-CASE / AUTO-MERIDIAN / AUTO-NEIJING | 针灸处方、医案、六经、内经自动解读 | NOT RUN |
| AUTO-WAIT-READY | 模型未就绪时等待并单次提交 | NOT RUN |
| CONTEXT-FOLLOWUP | 当前条目绑定与连续追问 | NOT RUN |
| FORMULA-QUALITY-GPU / HERB-QUALITY-GPU / CASE-QUALITY-GPU | GPU 实际 backend 下三类知识解读 | NOT RUN |
| FORMULA-QUALITY-CPU / HERB-QUALITY-CPU / CASE-QUALITY-CPU | CPU 实际 backend 下三类知识解读 | NOT RUN |

每个 FAIL 至少记录最小复现、预期/实际、实际 backend、模型状态、trace_id、时间范围、截图/录屏文件名、脱敏错误码和复测结果。状态只能使用 PASS / FAIL / BLOCKED / UNKNOWN / NOT RUN，不使用百分制或主观评分。

截图和录屏只包含 App 合成知识资料与 UI，不得包含真实患者资料、个人病历、身份资料或私密信息。不得把原始数据库、模型文件、签名密钥、`key.properties`、prompt/response 正文或附件复制进仓库、PR、Issue 或 CI artifact；TRACE 只保留项目允许的脱敏元数据。完整交接回报按 §7.1–§7.2 与本文件 §14.4 执行。

**合并说明：** 原 PR #560 的独立文件 `docs/find-n2-ai-knowledge-interpretation-local-handoff.md` 不作为第二交接入口；其 P0/P1 设备场景已并入本节，实际执行只更新本文件定义的统一证据目录和记录表。


---

## 16. 当前统一交接入口与文档归并核对（2026-11-27）

### 16.1 唯一交接入口

- 唯一设备执行与进度汇报入口：`docs/local-real-device-acceptance-handoff.md`（即本文件）。
- 本地所有实机任务、修复回归和阶段进度均在本文件 §7.1 追加记录；场景逐项状态仍写入本文件定义的 `output/find-n2/<run-id>/test-results.md`。
- 不再新增 PR 专属交接单、GPU/CPU 专属交接单、媒体专属交接单、知识解读专属交接单或授权专属交接单。新场景并入本文件相应章节。

### 16.2 已核对的历史交接路径

| 历史路径 | 当前 master 核对结果 | 处理口径 |
|---|---|---|
| `docs/find-n2-e4b-local-handover.md` | 不存在（404） | 旧内容已并入本文件；不恢复独立入口 |
| `docs/find-n2-ai-knowledge-interpretation-local-handoff.md` | 不存在（404） | P0/P1 场景已并入 §15；不恢复独立入口 |
| `docs/local-device-acceptance-handoff-2026-11-24.md` | 不存在（404） | 不作为当前交接文件 |
| PR #576 临时交接内容 | 已在本文件中保留对应场景与执行约束 | 只更新本文件，不另建临时文件 |

### 16.3 配套规范、历史验收记录与唯一交接单的区别

本次按文件名包含 `handoff` / `handover` / `acceptance` 的路径复核，并将历史记录、专项 runbook 与当前活动交接入口区分如下。它们不是多份平行进度交接单，不需要复制内容或删除有用的操作步骤：

| 文件 | 分类 | 处理口径 |
|---|---|---|
| `docs/2026-11-04-unified-assistant-acceptance-audit.md` | 历史助手验收审计 | 保留为历史审计记录，不作为当前实机进度表 |
| `docs/find-n2-acceptance-2026-11-02.md` | 历史设备验收记录 | 保留当时结果，不替代当前 master 的验收 |
| `docs/find-n2-real-device-acceptance.md` | Find N2 实机验收操作规范 | 保留操作步骤，进度统一回填本文件 §7.1 |
| `docs/find-n2-real-device-brand-acceptance.md` | 品牌/安装/更新专项验收操作规范 | 保留操作步骤，结果回填本文件 §7.1 |
| `docs/find-n2-local-ai-acceptance-checklist.md` | E4B 本地 AI 验收清单 | 保留操作步骤，不单独建立进度交接单 |
| `docs/find-n2-ai-trace-acceptance-plan.md` | TRACE 专项验收计划 | 保留采集与核对规范，结果回填本文件 §7.1 |
| `docs/local-real-device-acceptance-handoff.md` | 当前唯一活动设备交接单 | 唯一记录当前基线、场景状态、证据、缺口和本地进度 |
| `docs/local-android-release-checklist.md` | Android 本地发行操作规范 | 保留，不作为并行交接单 |
| `docs/local-ai-e4b.md` | E4B 模型导入与运行操作规范 | 保留，不作为并行交接单 |
| `docs/yanji-visual-design-system.md`、`docs/brand-identity.md`、`docs/pro-edition-architecture-constraints.md` | 设计/品牌/授权架构规范 | 保留为约束依据，不复制为设备进度表 |

以上 7 份名称直接匹配 handoff/handover/acceptance 的文件中，只有本文件是当前活动交接单；其余 6 份是历史审计、历史结果或专项验收 runbook。不得把历史/操作规范当成重复交接文档删除。

### 16.4 历史复核状态（master 1d79bc2f628fde789c5b5602cee889f844972c23）

- **远端代码：** PR #594 已合并至 `master@11ac0c5918e5c25754b44e71f0ba48c82bea6669`；LocalAiService 旧非结构化包装方法已删除，Native 旧文本入口 fail-closed。当前主线 HEAD 已继续推进至 `1d79bc2f628fde789c5b5602cee889f844972c23`。
- **当前 master 合并后 CI：** 在 `1d79bc2f628fde789c5b5602cee889f844972c23` 上，Flutter tests run `45976217087`、Flutter Quality Gate run `45976217173`、Fork License run `45976217114` 均 SUCCESS；三项均对应当前表内同一 SHA。
- **Core-1 / Core-4 / Core-5 云端边界：** Native transcript/KV 隔离与请求状态有自动化覆盖；当前 Native KV Cache token 数、模型声明 maxContextTokens 有只读观测，但 App 可用输入预算状态仍为 `NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`，不代表自动预算治理已完成；四项 ACTION_PROPOSAL capability 的能力级输入、副作用、幂等及结果回读审计已记录；20 轮知识追问与一次工具动作的 Flutter 回归已合入。fake service/executor 不代表真实 E4B 或真机 TRACE。
- **本地：** `LOCAL ONLY / NOT RUN`；本文件 §7.1 首行仍待本地执行者填写，所有未实测场景继续保持 MISSING / UNKNOWN。Debug APK/ABI/JVM/Widget 结果不等于 Find N2 正式 Release 安装或真实设备验证。
- **文档归并：** 当前唯一设备进度入口仍为本文件；历史验收记录和专项 runbook 已分类保留，不另建 PR/GPU/CPU/媒体/知识解读/授权专属交接单。

### 16.5 2026-11-27 当前运行时代码基线与云端收尾复核（PR #598）

- **运行时代码基线：** `master@04eb5bec9321b3d00eb85fdea7c0bd31b6fdc40f`，PR #598 merge commit。该提交删除 Native 中已无调用点的 `sendLocalImage()` / `sendLocalAudio()` 旧自由文本媒体推理 helper；保留旧 `sendImage` / `sendAudio` MethodChannel 的 fail-closed 响应，结构化 `sendReasoningAttachmentMessage` 图片/音频路径未改。
- **精确 SHA CI：** Flutter tests run `45993861676` SUCCESS；Flutter Quality Gate run `45993861611` SUCCESS；Fork License run `45993861643` SUCCESS。Flutter tests 的 Android arm64/JVM job `140491798547` SUCCESS；Flutter Quality Gate 的 Android native/JVM/arm64 debug build job `140488210528` SUCCESS。Branch validation job `140488213234` 为 SKIPPED，不计 PASS。
- **Native 模型入口门禁：** 新增静态防回归检查覆盖 8 个真实模型调用入口，均要求 `requiresAiAccess=true`；共享 `runAiTask` 强制经过唯一 `AiModelAccessGate`。旧拒绝路由不进入模型推理。此项是源码/自动化证据，不是设备授权 Gate 实测。
- **Core-0：** 五层契约、DTO、数据所有权、失败语义和当前源码/测试映射已冻结；不为形式拆层新增服务、Agent、数据库或权限门禁。
- **Core-1：** Native 多轮云端确定性治理包括有界成功 transcript、临时 RAG/SessionState/reasoning/media 上下文隔离、SessionState 会话归属与 provenance、请求 PENDING/FINALIZED/REJECTED/UNKNOWN/SUPERSEDED Ledger、UNKNOWN 不重放，以及 KV Cache token 数/模型 maxContextTokens 只读观测。App 可用 Token/input budget 仍为 `NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`，自动预算治理/压缩不得在缺少设备校准时猜测实现；GPU/CPU 多轮、state:7、Activity/process restart 与真实 token 数均为 DEVICE UNKNOWN。
- **Core-2：** 约定范围的 CandidateEvidence、多源聚合、独立 RankedEvidenceSet/KEEP-DROP 决策及黄金检索回归已落地；保留既有查询、匹配、顺序与来源限额，不新增无证据评分、Embedding 或 Reranker。
- **Core-3：** 五种主文本模式和图片/音频附件使用 ReasoningRequest/Response v1 与 Native 双阶段提交；旧 Dart 包装接口和 Native 不可达媒体 helper 已退役，旧路由 fail-closed；辅助 intent、八字槽位、症状整理、问项理解继续使用各自窄 DTO。
- **Core-4：** 生产 ACTION_PROPOSAL 白名单仅四项：`dosage`、`solar_terms`、`yuxiaji_omen`、`sanshan_lingqian`。显式确认、one-shot claim、结果安全读回及 UNKNOWN 不重放有自动化覆盖，不扩展其他 Headless 工具权限。
- **Core-5：** 20 轮知识追问与一次工具提案/确认/执行/结果解释的应用层 E2E 已合入；使用 fake Native service/executor，不能证明真实 E4B 或 Find N2 已通过。
- **工作流 H：** 本轮可由云端完成的代码、自动化、架构映射、执行台账和 CI 收尾已达到当前约定范围；整体仍标 PARTIAL，只因 Find N2 本地证据尚未执行，不得把设备状态写为 PASS，也不得反过来以设备未测阻塞云端既定工作。
- **工作流 I：** 用户 Markdown 书架继续 `DEFERRED / NOT AUTHORIZED`，不作为当前五层收尾门槛。
- **唯一设备交接：** 仍只有 `docs/local-real-device-acceptance-handoff.md` 一份活动交接单。专项折叠屏、品牌图标、AI TRACE、GPU/CPU 清单均为操作规范；所有本地进度、场景状态、证据目录、缺口和下一步统一回填该文件 §7.1。未实测仍为 MISSING / UNKNOWN / BLOCKED。
- **执行要求：** 本文件和专项 runbook 均不预填设备结果。执行前必须同步最新 `origin/master`；本节 SHA 是本次运行时代码复核快照，不替代本地构建时的实时 HEAD。
