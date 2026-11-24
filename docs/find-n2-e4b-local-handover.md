# Find N2 / E4B 本地验收交接总清单

> **状态：LOCAL ONLY / MISSING。** 本文件是 E4B 专项总清单，不是测试结果。所有设备、模型、安装升级、GPU/CPU 推理、TRACE 和恢复项目必须在真实 OPPO Find N2 上记录证据；云端 CI 不会替代实机验收。
>
> 本地操作顺序、覆盖升级、品牌/折叠屏与授权总体验收入口见 [本地实机验收交接单](local-real-device-acceptance-handoff.md)。

## 0. 当前代码与模型基线

| 项目 | 当前基线 | 核验要求 |
|---|---|---|
| 仓库 | `just2512/nihaixia-app` | 只从最终合并后的 `master` 构建 |
| 当前应用代码基线 | `master @ d6db3c9e7093bbe0619abf431199a18f2d6d6593` | 截至 2026-11-24 当前代码快照；最近应用代码提交为协议 v2 单一 `ai_access` 权益及协议 v1 历史 Token 兼容。此 SHA 是本次文档编制快照，执行前必须刷新 |
| 当前主线整体基线 | `master @ d6db3c9e7093bbe0619abf431199a18f2d6d6593` | 2026-11-24 实际读取到的 master HEAD；设备构建前再次读取 master HEAD、版本和对应 CI |
| 本轮应用版本 | `2.0.0+8048` | versionName `2.0.0`，versionCode `8048`；升级时仍须严格大于设备旧版本 |
| 应用包名 | `com.nihaisha.nihaisha_app` | 必须与设备已安装包一致 |
| 原签名配置 | 本地 `android/key.properties` + 原 keystore | 仅本地保管；不得提交、上传、粘贴到聊天或放入 CI secret |
| E4B 文件 | `gemma-4-E4B-it.litertlm` | 固定修订 `28299f30ee4d43294517a4ac93abd6163412f07f` |
| 模型大小 | `3,659,530,240` bytes | 大小不一致拒绝导入 |
| 模型 SHA-256 | `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0` | 必须逐字符一致 |
| Android LiteRT-LM | `0.18.0` | 以仓库锁定依赖为准 |

**本轮云端代码验收已完成不等于 Find N2 已通过。** 设备状态在实际采集前均为 `MISSING / UNKNOWN / LOCAL ONLY`。如果后续 master 出现新的应用代码提交，应先更新本文件中的 commit SHA / App version 并重新核对相关 CI，再开始设备验收。

## 1. 必须使用的操作文档

按以下顺序执行，不要把单份专项清单当成完整验收：

1. [本地 Android 构建、签名和升级](local-android-release-checklist.md)：原签名核对、Release APK 构建与 Debug-only TRACE 安全切换。
2. [Find N2 真机折叠屏验收](find-n2-real-device-acceptance.md)：外屏、内屏、半折叠、键盘/Insets、弹层、文件选择器和无损升级；按 §M 验收内经/本草讲稿段落级情境入口，并按 §N 验收 Dream、Guansha、确定性工具结果/字段快照及跨结果多轮 TRACE。
3. [Gemma 4 E4B 本地配置与边界](local-ai-e4b.md)：模型下载、SHA 校验、导入、Native backend 和已知行为。
4. [Find N2 本地 AI 后端验收](find-n2-local-ai-acceptance-checklist.md)：GPU/CPU、多轮、多媒体、进程恢复、清除和针灸情境条目；本地结果与字段快照入口按真机验收方案 §N 执行。
5. [Find N2 AI TRACE 验收方案](find-n2-ai-trace-acceptance-plan.md)：各阶段、trace_id、消息 metadata、Native backend 和持久化核对。

## 2. 第一阶段：旧包检查与本地 Release 构建

连接 Find N2，先执行只读检查：

```powershell
adb devices
adb shell pm path com.nihaisha.nihaisha_app
$remoteApk = (adb shell pm path com.nihaisha.nihaisha_app | Select-Object -First 1) -replace '^package:', ''
adb pull $remoteApk .\\installed-old.apk
apksigner verify --print-certs .\\installed-old.apk
apkanalyzer manifest application-id .\\installed-old.apk
apkanalyzer manifest version-code .\\installed-old.apk
apkanalyzer manifest version-name .\\installed-old.apk
```

保存旧包的 applicationId、versionCode 和 signer certificate SHA-256。不得卸载、清数据或改包名。

在本地仓库根目录构建正常 Release：

```powershell
if (-not (Test-Path .\\android\\key.properties)) {
  throw "android/key.properties missing; refusing to build an upgrade APK."
}
$env:ORG_GRADLE_PROJECT_ciArm64Only = 'true'
try {
  flutter pub get --enforce-lockfile
  flutter build apk --release --no-pub --target-platform android-arm64
  if ($LASTEXITCODE -ne 0) { throw "Release build failed." }
}
finally {
  Remove-Item Env:ORG_GRADLE_PROJECT_ciArm64Only -ErrorAction SilentlyContinue
}
$apk = ".\\build\\app\\outputs\\flutter-apk\\app-release.apk"
apksigner verify --verbose --print-certs $apk
Get-FileHash $apk -Algorithm SHA256
apkanalyzer manifest application-id $apk
apkanalyzer manifest version-code $apk
apkanalyzer manifest version-name $apk
```

只有以下条件全部满足才可安装：

- applicationId 与旧包完全一致；
- 新 versionCode 严格大于旧 versionCode；
- 新旧 signer certificate SHA-256 完全一致，或有 Android 平台认可的 signing lineage；
- APK 含 `arm64-v8a`，签名校验成功，SHA-256 已记录；
- Release 构建必须使用原 keystore。Gradle 现为 fail-closed；缺少签名材料会失败，不会 fallback 到 Debug。

执行原位升级：

```powershell
adb install -r .\\build\\app\\outputs\\flutter-apk\\app-release.apk
```

安装后确认版本、包路径、收藏、诊断历史、历史会话、设置等旧数据仍在。任何签名不一致、versionCode 不足或安装器拒绝均判 `BLOCKED`，停止操作；**禁止卸载旧版、执行 `pm clear` 或删除数据库来绕过。**

## 3. 第二阶段：折叠屏与基础应用回归

在真实设备按 [Find N2 真机折叠屏验收](find-n2-real-device-acceptance.md) 完成：

- 外屏竖屏、完整展开内屏、半折叠/桌面姿态；记录实际 dp 尺寸、折痕/DisplayFeature 和窗口 Insets。
- 首页、知识、工具、问诊、收藏、诊断历史、排盘/详情等关键页面无横向溢出、黑边、错误裁剪或内容跨越铰链。
- 输入法弹出/收起、系统字号 100%/150%/200%、底部弹层、全屏路由、相机和文件选择器往返。
- 折叠/展开、旋转、Activity 重建后当前 Tab、滚动位置和未提交文本保持合理连续。
- 升级后执行基础冒烟，确保收藏、历史、设置及旧会话未丢失。

每一项记录 PASS / FAIL / BLOCKED / MISSING 与对应截图、短录屏或日志；不能用模拟器截图替代真实折叠屏证据。

## 4. 第三阶段：模型下载、校验与离线导入

1. 从 `docs/local-ai-e4b.md` 固定的 Hugging Face revision 下载 `gemma-4-E4B-it.litertlm`；文件不提交仓库。
2. 电脑端校验：

```powershell
Get-FileHash .\\gemma-4-E4B-it.litertlm -Algorithm SHA256
```

必须等于上表 SHA-256，大小必须为 3,659,530,240 bytes。
3. 在 App「问诊 → 本地 AI → 选择并导入模型文件」选择设备本地文件。应用内复制过程再次检查字节数和 SHA-256；验证失败不得加载模型。
4. 记录导入完成、可用空间、模型加载结果。离线验收时开启飞行模式并确认 Wi-Fi / 移动数据均关闭；模型导入完成后问答不得依赖模型服务器。

## 5. 第四阶段：GPU 与 CPU 分开验收

入口：App「设置 → 本地 AI → E4B 推理后端」。GPU 与 CPU 两组独立会话，不得混在一组成绩里。

**GPU 组：** 选择 GPU、加载模型；Native 实际状态必须确认为 GPU 后开始至少 20 轮文字对话。覆盖简单问答、上下文追问、早期实体回指、检索命中/无命中和澄清。

**CPU 组：** 选择 CPU、加载模型；Native 实际状态必须确认为 CPU 后，使用同一脚本完成至少 20 轮。

每组记录：
- 用户偏好 backend；
- Native 返回的实际 backend；
- 每轮是否有新的非空回复、trace_id、耗时和持久化状态；
- GPU 初始化/首轮 OpenCL fallback、CPU fallback、Engine/Conversation 重建；
- state:7、空回复、重复消息、历史串线、内存/温度/降频。

GPU 请求发生 CPU fallback 时，实际 backend 按 CPU 记，不得将 CPU 回复算入 GPU 通过轮数。失败或状态未知的请求不得自动重放。

## 6. 第五阶段：多媒体、恢复、清除与来源锚点

按专项清单执行：

- GPU、CPU 两个实际 backend 分别测试图片与语音正常输入；同时测试取消、无权限、无效文件。不得使用真实患者资料或个人照片。
- 至少 5 轮后执行 Activity recreation 和 `adb shell am force-stop com.nihaisha.nihaisha_app`，恢复原会话；比较 SQLite transcript、Flutter 时间线与 Native completed-turn history。未完成轮不得伪装为成功回复。
- 建立至少两个 AI 会话和非 AI 数据哨兵，执行 App 内「清除全部 AI 数据」。确认 AI 会话、AI 附件、TRACE 和 Native runtime cache 按清除合同移除；收藏、诊断历史、命盘、设置等非 AI 数据保持；模型文件按当前合同保留。不得清除整个 App 数据或共享数据库。
- 针灸来源场景按 `AI-CTX-ACU-01` 执行：分类 01/条目 1 和分类 08/条目 1 必须保持不同 source / anchor / snapshot，不得串线；三个未开放 Tab 记录 `NOT_ENABLED`。

## 7. 第六阶段：Debug-only TRACE 的无损原位切换

TRACE 开关只在 Debug（`kDebugMode`）显示，正常 Release 不显示。**不能安装 CI Debug APK**：CI Debug signer 与原 Release signer 不同，会破坏常规原位安装链。当前 master 已包含 `localDebugUsesReleaseSigning` 本地构建属性。执行前须核对 `android/app/build.gradle.kts`：缺少原签名材料时 fail-closed，CI 拒绝启用该属性。该流程仅用于设备 TRACE，不是 Release 发布方式。

1. 确认 [Find N2 本地 AI 后端验收清单 §2.1](find-n2-local-ai-acceptance-checklist.md) 所述的 `localDebugUsesReleaseSigning=true` 已进入当前 master。
2. 使用本机未跟踪的 `android/key.properties` 和原 keystore，在本地构建 arm64 Debug APK：

```powershell
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
```

3. 比较 Debug APK 的 applicationId、versionCode 和 signer certificate SHA-256 与设备当前包。必须同包、签名 SHA 完全一致、versionCode 不低于已安装版本，才执行：

```powershell
adb install -r .\\build\\app\\outputs\\flutter-apk\\app-debug.apk
```

4. 开启 Debug 设置页「本地 AI 调试 TRACE」。GPU、CPU 分别执行工具、知识检索、普通文本、附件场景；每场景用独立 trace_id，核对阶段、状态、实际 backend、conversation/message IDs、source IDs、SQLite metadata、最终展示。只导出 allowlist 元数据，不导出 prompt/response、症状正文、图片/音频内容、附件路径、身份信息或密钥。
5. TRACE 完成后保持 `localDebugUsesReleaseSigning` 属性未设置，按本文件第 2 节构建正常 Release APK，验证签名 SHA 与原证书一致，然后 `adb install -r` 恢复 Release。重新启动确认旧数据和模型仍在。
6. 该 Debug APK 带调试能力，即使使用原 Release signer，也必须仅在维护者本机短期使用。不得上传仓库、PR、CI artifact、网盘或分发。若原签名材料不可用，TRACE 标记 `BLOCKED / MISSING`，不卸载、不清数据、不改用 CI Debug。

## 8. 证据包与提交格式

每轮建立独立目录，例如 `output/find-n2/<run-id>/`，至少包含：

- `device-metadata.json`：设备型号、Android/SDK/ColorOS、日期；
- `build-metadata.json`：git commit、App version、applicationId、versionCode、APK 文件名、APK SHA-256、signer certificate SHA-256、ABI；
- `model-metadata.json`：模型 revision、字节数、SHA-256、实际导入/加载状态；
- `window-metrics.log`、`capture-summary.json` 和必要截图/10–20 秒短录屏；
- `test-results.md`：逐场景 PASS / FAIL / BLOCKED / MISSING、最小复现、预期/实际、证据文件；
- 脱敏 TRACE 样本及 Native backend 记录（如执行 TRACE）。

**禁止提交：** keystore、key.properties、密码、模型二进制、真实病历/症状、真实出生资料、prompt/response 原文、图片/音频正文、附件绝对路径或个人身份信息。提交证据前先脱敏。

## 9. 全局停止条件与完成定义

遇到以下任一情况立即停止相关安装/验收步骤并记录 BLOCKED / FAIL：签名证书不一致；versionCode 不足；APK 包名变化；Release 签名材料缺失；模型大小/SHA 不符；Native 实际 backend 无法核对；数据清除影响非 AI 数据；来源锚点歧义却仍能打开 AI；TRACE 缺关键跨层 ID；需要卸载或清数据才能继续。

设备验收只能在所有对应场景都有真实设备证据后标记 PASS。云端 CI、Widget 测试、模拟器、静态代码和计划文档均不能代替实机结果。未运行项保留 MISSING，环境/密钥限制导致不能运行的项目保留 BLOCKED；不删除失败记录，不降低验收门槛。


---

## 10. 2026-11-23 本地执行范围与远程交接边界

本文件是 Find N2 / E4B 实际设备验收交接入口。以下事项只能由持有 OPPO Find N2、原签名材料和本地模型文件的执行者完成；云端 CI 不能代做，但这些未执行项不作为其他远程 PR 的合并阻塞条件。

| 项目 | 本地执行内容 | 远程状态口径 |
|---|---|---|
| A：Native 多轮稳定性 | GPU/CPU 各至少 20 轮；多轮追问、图片/语音、Activity recreation、强停/重启与历史一致性 | LOCAL ONLY / MISSING，CI 不能替代 |
| E：AI 数据清除 | 合成会话/任务/附件/TRACE，按现有清除功能执行；确认非 AI 数据与模型文件保留，强停/重启后复查 | LOCAL ONLY / MISSING，不新增数据库/备份架构任务 |
| F：TRACE | Debug-only 本地启用；记录 trace_id、实际 backend、阶段、持久化状态；检查导出内容脱敏 | LOCAL ONLY / MISSING，不上传真实内容 |
| 折叠屏/升级 | 原签名原位升级、外屏/内屏/半折叠、键盘/弹层/路由 | LOCAL ONLY / MISSING，保留设备证据 |

本轮产品范围明确不包括临床红旗门禁。不需要在 Find N2 上测试医学 detector、医生审核或红旗入口拦截；只保留产品定位文件中的免责声明/一般性求助提示。

知识库和医案验收不是书目考古。设备侧只需验证条目可打开、可从详情进入学习助手、实际本地内容进入上下文、对话可基于内容解释和追问；稳定本地 sourceId/anchor 用于回到 App 条目，不要求纸本卷页或外部来源认证。

未执行的设备场景如实保留 MISSING / LOCAL ONLY；不得将其写成代码缺失、医学安全阻塞或远程 CI 失败。

---

## 11. 2026-11-23 远程收尾后的基线校准

- 当前 master 整体 SHA：`396a9cc314994a7da813265706d0fb5441b3fd54`。
- 最新应用代码变更：PR #433 离线协议、PR #437 Android Keystore/AtomicFile、PR #438 Dart Bridge/EntitlementService、PR #442 F0-2a 执行注册边界已合并；PR #431 为文档范围修订，无业务代码变更。
- 产品范围不包含临床红旗 detector、医学审核或全入口拦截；无需在设备上执行相关测试。
- 医案/经典设备验收围绕本地条目打开、实际字段进入 AI 上下文、AI 解读和追问；不执行纸本卷页考据作为学习功能准入测试。
- A/E/F 与折叠屏/原签名升级仍是本地设备工作。任何未执行条目保持 `MISSING / LOCAL ONLY`，不影响已通过远程代码/自动化的无关 PR 收尾。

## 12. 专业版离线授权真机验收（云端收尾后执行）

本节只在云端协议、Android 原生、Dart Bridge/EntitlementService、Release Key Ring 与 FeatureGate 集成完成后执行。当前 CI/JVM/Mock Channel 结果不替代本节。

| 场景 | 操作与观察 | PASS 条件 |
|---|---|---|
| 无 Token 首次启动 | 清洁安装后启动，检查授权状态和 Android Keystore alias | 状态为未授权；不自动创建设备密钥、不授予 Feature |
| 显式激活创建密钥 | 从用户明确触发的激活流程创建 P-256 密钥 | 仅激活动作创建；公钥 SPKI 与 SHA-256 指纹可读取 |
| 日常只读 | 退出并重启 App，多次读取授权状态 | 只读取已有密钥；不自动重建、不轮换、不删除 |
| StrongBox / TEE | 读取设备实际 securityLevel 和 fallback 标记 | StrongBox 可用则记录 StrongBox；不可用时允许受控 TEE fallback，并记录真实原因；不伪造 StrongBox |
| 私钥可用性 | 对随机 challenge 签名并用返回公钥验签 | 验签成功，指纹与 KeyStore 公钥一致 |
| 合法 Token 导入 | 导入与当前 App、产品和设备指纹匹配的离线签名 Token | 先验签再写入；AtomicFile 写入后重读、复验；状态与授权 Feature 一致 |
| 非法 Token | 导入错误签名、错误设备、错误 App、未知发行者或损坏 Token | 不覆盖原 Token、不授予权益；错误原因可区分 |
| 权益减少 | 导入权益少于当前 Token 的新凭证 | 明确展示将失去的 Feature；未经用户确认不得替换 |
| 文件损坏/密钥失效 | 使用专用测试构建或可控夹具验证损坏文件、KeyStore key invalidated | fail closed；不自动重建密钥、不把错误当作未授权后静默覆盖 |
| 原位升级 | 使用原签名、递增 versionCode 的新 APK 覆盖安装旧版 | 不卸载、不清数据；数据库、学习资料、AI 历史与用户设置保留 |

### 证据要求

- 每项记录设备型号、Android 版本、APK SHA-256、versionName/versionCode、签名证书指纹、测试时间和结果。
- 提供必要的设置页/状态页截图、脱敏日志和短录屏；不得输出私钥、完整 Token、激活请求签名、密码或用户个人数据。
- 失败项记录最小复现、预期/实际和原始证据；未执行项保持 `MISSING / LOCAL ONLY`。
- 生产 Release 必须使用真实 Release Key Ring 和本地签名材料；测试发行公钥/私钥不得混入生产包。


## 13. 2026-11-24 云端收尾后的基线刷新

- 当前 master 文档基线：`b884b0bfc5b4fe94e50fbf1bd1bdc54771b48c1b`（PR #462 合并）。
- 当前应用运行时代码基线：`1717b36ba0c2359a1526e22d23f75befacd80628`（PR #455 合并）。对比该代码提交与当前 master，后续只有 `.reuse/dep5`、执行台账、真机验收和 Release 配置文档变更；没有新的应用运行时代码差异。
- 当前 App 版本仍为 `2.0.0+8048`，包名仍为 `com.nihaisha.nihaisha_app`；构建前必须以 `pubspec.yaml`、设备已安装包和本地签名证书重新核对。
- PR #462 为执行台账单文件文档变更。该 PR 精确 HEAD 的 Flutter 全量回归、Android arm64/JVM 与 Fork license boundary 均 SUCCESS；Branch validation 为 SKIPPED，不计 PASS。合并后 master `b884b0bfc5b4fe94e50fbf1bd1bdc54771b48c1b` 的 Flutter Quality Gate run `45351039842`、Flutter tests run `45351039926` 和 Fork license boundary run `45351039841` 均 SUCCESS；Flutter regression job `138297255914`、Android arm64/JVM job `138300772054` 均 SUCCESS，Branch validation `138297257868` 为 SKIPPED。
- 本节只刷新执行基线，不将任何 Find N2/E4B 设备项目升级为 PASS；全部设备场景仍为 `MISSING / LOCAL ONLY / UNKNOWN`。


## 14. 2026-11-24 当前主线基线刷新

- 本轮实测读取到的 master HEAD：d6db3c9e7093bbe0619abf431199a18f2d6d6593。
- 该提交修改 lib/licensing/license_model.dart 与 lib/services/entitlement_service.dart，协议修订 2 新签发单一 ai_access；协议修订 1 的历史 Token 中，ai_advanced 或 contextual_assistant 任一有效声明映射到同一个 ai_access。修订 2 不再接受旧 Feature ID 作为权益。
- pubspec.yaml 当前仍声明 2.0.0+8048，应用包名仍为 com.nihaisha.nihaisha_app。是否可覆盖升级仍以 Find N2 当前已安装 versionCode 和签名证书实测为准。
- 本节更新覆盖本文件 §0 和历史 §13 中“最新 master”为 b884b0… 的旧快照描述。历史记录保留作为审计轨迹，不得当作本次构建基线。
- 执行专业版授权实机测试时，必须把协议 v2 单一 ai_access 权益和 Native AiModelAccessGate 纳入范围。UI 显示授权状态、Dart 单测或 Native mock 均不能替代设备 Gate 的实际拒绝/放行证据。
- 当前仓库远程核验没有连接 OPPO Find N2，也没有读取用户本地签名材料、设备 Token、Keystore、E4B 模型运行状态或真实 backend。上述所有本地测试仍为 MISSING / UNKNOWN / LOCAL ONLY，不得因为文档更新而变更状态。
