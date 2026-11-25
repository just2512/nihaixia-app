# 研纪 OPPO Find N2 本地实机验收交接单

> **文档版本：** 1.0  
> **编制日期：** 2026-11-24  
> **执行地点：** 用户本地 Windows + OPPO Find N2  
> **当前状态：** **PREPARE / LOCAL ONLY / MISSING**  
> **目标：** 将远程已交付代码转为可复核的真实设备验收证据。本文件是执行入口，不是实机通过报告。

---

## 1. 当前交接基线

本文件编制时核对到的仓库状态如下：

| 项目 | 当前核对值 | 执行要求 |
|---|---|---|
| 仓库 | **just2512/nihaixia-app** | 只从最新 master 构建 |
| 编制时 master HEAD | **57f62083590c5619f84da98ff7c5b5f430efeba8** | 这是文档编制时的快照；本地构建前必须重新读取 HEAD |
| 最近一笔应用运行时代码提交 | **57f62083590c5619f84da98ff7c5b5f430efeba8** | v1.3 单一 ai_access Native Gate + Dispatcher/Gateway 仅保留安全/来源完整性职责；PR #472/#478/#482 已合并 |
| App 版本 | **2.0.0+8048** | versionName=2.0.0、versionCode=8048；必须严格大于设备现有 versionCode 才能覆盖升级 |
| Android applicationId | **com.nihaisha.nihaisha_app** | 不得修改 |
| 产品显示名称 | **研纪** | 桌面、应用信息、最近任务和 App 内关于页均应一致 |
| 本地模型 | Gemma 4 E4B IT | 不打包进 APK，单独下载、校验和导入 |
| 模型文件长度 | **3,659,530,240 bytes** | 必须完全一致 |
| 模型 SHA-256 | **0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0** | 必须逐字符一致 |
| LiteRT-LM | **0.18.0** | 以当前锁定依赖为准 |

**重要：** 编制时 HEAD 不等于执行时 HEAD。取得交接后先同步最新 master，重新记录 commit、版本、CI 和 APK 元数据。不要使用旧交接文档中的 1717b36… 或 b884b0… 代替当前构建基线。

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

完整模型配置和操作细节以 docs/local-ai-e4b.md、docs/find-n2-local-ai-acceptance-checklist.md、docs/find-n2-ai-trace-acceptance-plan.md 为准。本节是本轮最低执行摘要。

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
- 记录首次加载时间、每轮耗时、空回复、崩溃、state:7、温度/降频和可观测内存情况。未知错误不得猜测根因。

### 5.3 图片、语音与恢复

- GPU、CPU 两个实际 backend 分别测试图片和语音输入；同时检查取消、权限拒绝、文件无效和尺寸/时长边界。
- 至少完成 5 轮后执行 Activity recreation，再执行 adb shell am force-stop com.nihaisha.nihaisha_app，重新启动并核对会话恢复。
- 对比 UI 时间线、SQLite transcript、Native completed-turn history；未完成轮次不能伪装成成功消息。
- 执行 App 内“清除全部 AI 数据”时，只验证该功能定义的 AI 数据范围：AI 会话、任务、附件/缓存和 TRACE 应按合同清除；收藏、诊断历史、命盘、设置和模型文件按既有合同保留。
- 不要通过 Android 系统“清除应用数据”代替 AI 数据清理验收。

### 5.4 TRACE

需要 Debug-only TRACE 时，只能按 docs/find-n2-e4b-local-handover.md §7 的本地签名流程执行：
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

### 6.5 云端 v1.3 集成证据（不是实机通过证明）

- **当前构建基线：** `master @ 82b2474202a33d802722e79560f6ae17670aab9a`；`pubspec.yaml = 2.0.0+8048`；Android `applicationId = com.nihaisha.nihaisha_app`。本地执行前仍须重新读取最新 master HEAD、APK 元数据、签名证书及设备当前安装版本。
- **v1.3 授权链路：** PR #472（冻结单一授权架构）、#478（Native LiteRT `ai_access` 总门禁）、#482（撤销 Dispatcher/Gateway 的独立收费判断）、#491（云端收尾台账及本地交接）均已合并。协议修订 1 的历史 AI 权益兼容映射为同一 `aiAccess`；协议修订 2 只使用 `ai_access`。App 永久 Token 不等于 Fork 源代码商业许可。
- **PR #491 精确 HEAD：** `feb63195967a5fcca62ffc9c9945cb6b1ad2d28e`。Fork license job `138912318822` SUCCESS；Flutter regression job `138912319129` SUCCESS；Android arm64/JVM job `138915366727` SUCCESS；Branch validation job `138912320094` SKIPPED，不计 PASS。PR #491 只更新执行台账和本交接单。
- **PR #493：** 已合并（`fd2c0da989a9d748088b9ef0bbad3f697c6d327d`），把瞬时 RAG 正文与 Native 恢复 transcript 分离。Fork job `138939441644`、Flutter job `138939441699`、Android arm64/JVM job `138942270425` 均 SUCCESS；Branch validation `138939443409` SKIPPED。该改动不证明跨进程持久化或完整 session 隔离。
- **PR #495：** 已合并（`9c7a4c6761a467bb13b0b5381992df2e96cfc3ba`），只冻结 Core-0 五层 DTO 字段合同和源码/测试映射，不代表 DTO 已接入运行时。PR Fork job `138948246934`、Flutter job `138948369724` SUCCESS；Branch validation `138948371713` SKIPPED。
- **PR #496：** 已合并（`b62bc101865612c02503bedce8d05cf11390d56d`），Native 恢复 transcript 限制为最多 12 个完整成功轮次、user/model 文本合计最多 10,000 UTF-16 code units，仅淘汰最旧完整轮次。精确 PR HEAD `a403a71a4fcddb65d3929f306b4c2c927b9cabed` 的 Fork job `138946470635`、Flutter job `138946470476`、Android arm64/JVM job `138949605374` 均 SUCCESS；Branch validation `138946472646` SKIPPED。该字符上限不等于 LiteRT-LM token 预算，不限制活动 Conversation KV Cache，也不证明完整 session 隔离。
- **PR #498：** 已合并（`82b2474202a33d802722e79560f6ae17670aab9a`），新增候选证据批次与经典候选收集边界；保留既有查询顺序、去重与上下文前四条投影，不等于证据排序层已完成。精确 PR HEAD `f004427f24a686e80cf9a85eefb8b0ca6c734c94` 的 Fork job `138955502743`、Flutter job `138955626207`、Android arm64/JVM job `138958765875` 均 SUCCESS；Branch validation `138955627515` SKIPPED。
- **当前 master 合并后回归快照：** Fork license run `45541268760` / job `138960091324` SUCCESS；Flutter regression run `45541268723` / job `138960091330` 在本节更新时仍为 IN_PROGRESS；Flutter Quality Gate run `45541268958` / job `138960091985` 仍为 IN_PROGRESS；Branch validation job `138960093668` SKIPPED。Android arm64/JVM 依赖 Flutter 回归完成后启动，故本快照不将其记为 PASS。执行本地构建前应重新读取这些 workflow 的最终结论。
- CI Android Debug APK 只证明 CI 构建、ABI、Manifest 和 JVM 自动化；它不是产品正式签名 Release APK，不能用于旧版覆盖升级，也不能证明 Find N2 的 Keystore、StrongBox/TEE、GPU/CPU LiteRT、多媒体或进程恢复行为。
- Release 源码 fail-closed 规则已有代码/CI 覆盖：缺失或格式错误的 Key Ring 不得验证发行者；Release Gradle 门禁要求合法非空 Key Ring，并独立要求本地原签名材料。**正式发行仍 BLOCKED：** 正式发行者公钥来源、GitHub Secret `YANJI_LICENSE_KEY_RING` 实际值、生产私钥离线托管/恢复演练、真实客户签发与密钥轮换均缺少可核验证据。
- 当前 Fork inventory：changed 980 / added 816 / modified 164 / deleted 15；分类为 FORK_COMMERCIAL 457、APACHE_2_0_AND_FORK_COMMERCIAL 158、KNOWLEDGE_BASE_EXCLUDED 364、THIRD_PARTY_EXCLUDED 1。JSON 中 980 条路径唯一。自动 license boundary 只证明 inventory/DEP5/SPDX 结构一致，不证明 Fork 自有代码权属；`OWNERSHIP_EVIDENCE_REQUIRED` 仍须真实权利人材料补证。
- `LICENSE-FORK-COMMERCIAL.md` 当前 blob SHA 与 PR #491 合并时完全相同；其源代码商业许可授予范围未因 `ai_access` Token 或本轮 AI 运行时改动而缩小。
- **其他远程工作分支不属于当前构建基线：** #416 保持 OPEN / DRAFT / UNTOUCHED；#499（Core-1 session isolation）、#500（执行台账）、#501（显式证据选择）仍为独立 OPEN 分支，不在本轮交接 PR 中修改或合并。#500 负责执行台账更新，本交接单只维护本文件。
- **设备状态仍为 `LOCAL ONLY / MISSING / UNKNOWN`。** Keystore / StrongBox / TEE、AtomicFile 故障恢复、原签名覆盖升级及数据保留、GPU/CPU 各 20 轮、多媒体、Activity/进程恢复、端到端 TRACE 与 AI 数据清除均须在 OPPO Find N2 本地执行并附证据。云端源码/CI 收尾不以设备验收为前置条件。

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

### 7.1 禁止进入证据包的资料

不得提交 keystore、key.properties、密码、完整 Token、私钥、公钥原始材料、真实病历/症状、个人出生资料、梦境隐私、prompt/response 原文、图片/音频正文、模型二进制、附件绝对路径或账号身份信息。截图和日志先脱敏。

### 7.2 整体验收完成定义

只有本轮约定范围内所有必测场景均为 PASS，且 APK 身份/签名/升级、数据保留、外屏/内屏/半折叠、品牌、E4B 实际 backend、授权门禁与恢复证据齐全，才能记录 **LOCAL DEVICE ACCEPTANCE = PASS**。

出现任何必测 FAIL，整体不得 PASS；仍有必测 BLOCKED / MISSING，整体只能记录 PARTIAL 或 BLOCKED。不得把计划、源码存在、Widget、模拟器或 CI 成功当作 Find N2 实机通过。

---

## 8. 专项文档入口

本交接单负责执行顺序和交付证据；具体步骤及完整场景矩阵仍以以下文件为准：

1. [Find N2 / E4B 本地验收交接总清单](find-n2-e4b-local-handover.md)
2. [本地 Android 构建与升级检查清单](local-android-release-checklist.md)
3. [Find N2 真机折叠屏验收方案](find-n2-real-device-acceptance.md)
4. [Gemma 4 E4B 本地配置与边界](local-ai-e4b.md)
5. [Find N2 本地 AI 后端验收清单](find-n2-local-ai-acceptance-checklist.md)
6. [Find N2 AI TRACE 验收方案](find-n2-ai-trace-acceptance-plan.md)
7. [研纪 UI 视觉设计系统](yanji-visual-design-system.md)
8. [研纪品牌与应用身份规范](brand-identity.md)
9. [研纪专业版架构约束 v1.3](pro-edition-architecture-constraints.md)

---

**交接结论：** 当前仅完成远程仓库与规范基线核对，未连接或操作用户的 OPPO Find N2。所有本地设备结果在真实执行并提供证据前均保持 MISSING / LOCAL ONLY。
