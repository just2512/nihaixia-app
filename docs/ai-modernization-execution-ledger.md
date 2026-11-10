# AI 改造执行台账（约束性跟踪文件）

> 本文件与 [全局 AI 能力审计与改造执行约束](ai-capability-audit.md) 配套使用。
> `ai-capability-audit.md` 定义不可绕过的架构边界与验收门槛；本文件记录每一工作流的当前状态、证据、阻塞和下一步。
> 状态必须由实际源码、测试、CI 或设备记录更新。不得根据计划、代码文件存在或模型回复推定完成。

## 1. 当前核验基线

| 项目 | 当前值 | 说明 |
|---|---|---|
| 仓库 | `just2512/nihaixia-app` | Fork 独立仓库 |
| 主分支 | `master` | 按用户既有要求直接提交 master |
| 本台账建立时 HEAD | `78f8f2bda9adb3adcb74ff46984c9a06284a2f58` | 约束文件更新提交 |
| 应用版本 | `1.11.30+8039` | 以 `pubspec.yaml` 为准 |
| README 版本说明 | `1.11.28+8037` | 已确认文档漂移，待修正 |
| AI 约束文件 | `docs/ai-capability-audit.md` | 本项目最高优先级 AI 改造约束 |
| AI 能力盘点 | `docs/ai-capability-inventory.md` | 现状材料；其中部分内容早于最新审计，必须按新证据更新 |
| 静态/动态审计报告 | `docs/ai-capability-audit-report.md` | 与约束文件分离，不得覆盖约束 |
| 多轮稳定性审计 | `docs/local-ai-multiturn-audit.md` | 只读审计交付物 |

**基线限制：** 当前只核验了 GitHub master HEAD、约束文件、能力盘点文件、pubspec 与 README 版本文字。除文档已明确引用的历史审计证据外，本台账不宣称本轮重新完成全仓代码审计、CI 检查或 Find N2 真机测试。

## 2. 状态定义

| 状态 | 含义 | 转换条件 |
|---|---|---|
| `NOT_STARTED` | 尚未执行 | 只有明确开始并产生证据后才能变更 |
| `IN_PROGRESS` | 正在执行 | 必须记录当前工作范围和最新证据 |
| `PASS` | 验收通过 | 满足该项全部硬性验收条件，证据可复核 |
| `PARTIAL` | 部分实现/部分验证 | 必须列出已完成部分和剩余断点 |
| `FAIL` | 已执行且不满足要求 | 记录复现条件、失败证据和修复项 |
| `BLOCKED` | 有明确外部依赖阻塞 | 写清阻塞原因；无依赖的工作流继续推进 |
| `UNKNOWN` | 证据不足，不能判断 | 不得用推测补齐，不得计为 PASS |

每个任务同时记录证据类型：
- `CODE`：源码路径、类/函数和当前行号或稳定定位。
- `TEST`：测试文件、测试名称、断言内容和实际运行结果。
- `CI`：workflow、run ID、commit SHA、结论及失败步骤。
- `TRACE`：设备、系统、App SHA、模型版本、backend、场景 ID、轮次和日志关联。
- `REVIEW`：医学背景人员对红旗词表、处置文案或其他专业内容的审核记录。

## 3. 总体工作流状态

| ID | 工作流 | 当前状态 | 允许并行关系 | 完成定义 |
|---|---|---|---|---|
| A | P0 本地模型多轮稳定性与生命周期 | `IN_PROGRESS` | 与 B/C/E 并行 | 多轮审计报告完成；修复有自动化回归；Find N2 GPU/CPU 各至少 20 轮实测通过 |
| B | 全模式红旗安全门禁 | `PARTIAL`（规则仅在提示词层的历史审计结论） | 与 A/C/E 并行 | 所有模型/业务路由入口前置确定性门禁；歧义澄清；医学词表审核；正反向测试通过 |
| C | 知识检索黄金行为基线 | `NOT_STARTED` | 与 A/B/E 并行 | 桂枝汤组成 + 《伤寒论》条文黄金用例有原始检索与展示记录；抽适配器前后行为可比较 |
| D | Headless Capability 盘点与最小适配器 | `PARTIAL`（Page Tool 与 Headless 尚未统一） | 目录审计可并行；适配器须等待对应基线 | 每项能力有输入/输出 schema、校验、权限、取消/错误语义及真实执行证据 |
| E | 低成本数据保护 | `UNKNOWN` | 与 A/B/C 并行 | Android 备份配置核验、清除全部 AI 数据、附件缓存生命周期与重启后不可恢复验证 |
| F | 统一 TRACE 与审计证据 | `PARTIAL`（已有部分结果/来源链路，不等于端到端 TRACE） | 与 A-E 按需并行 | 默认关闭、脱敏、trace_id 贯穿、关闭时行为不变、完整链路可复核 |
| G | 文档与版本一致性 | `PARTIAL` | 可独立执行 | README 与 pubspec 一致；审计报告/规范文件分离；文档状态不与代码事实冲突 |

> A 的问题不能冻结 B/C/E。D 的适配器实现不得先于对应能力的行为基线，但其目录审计不受此限制。

## 4. 分工作流任务与验收清单

### A. P0 多轮稳定性与 Native 生命周期

- [ ] 只读完成 `docs/local-ai-multiturn-audit.md`，逐结论附源码行号。
- [ ] 画出 Engine 与 Conversation 独立状态迁移图，标出 null、半初始化、已释放引用和重入状态。
- [ ] 逐条审计 GPU 首轮失败 fallback、非首轮异常、空回复重试、Conversation-only 重建、Engine 重建及二次失败。
- [ ] 核对 Native Conversation 重建后历史回放；对比 SQLite transcript、Flutter UI messages、Native model context。
- [ ] 核对用户取消、Dart Future 超时、Native 仍运行、Activity 销毁、Engine 释放和 Conversation 复用。
- [ ] 核对 user/assistant 消息写入顺序、仅 user 落库的未完成轮次、重复发送与幂等性。
- [ ] 对 state:7 和无有效文本分别记录证据；无设备日志时根因标 `UNKNOWN`。
- [ ] 完成最小修复与 Kotlin/Flutter 自动化回归。
- [ ] Find N2 GPU 连续至少 20 轮；CPU 连续至少 20 轮；覆盖文字、图片、语音输入及进程中断/恢复。

**A 验收：** 不允许状态错乱、并发重入导致会话污染、空回复被当作成功、恢复后静默丢失上下文、取消后错误复用旧 Conversation。Native 执行状态未知时不自动重放。真机每轮可追溯；未实测保持 `UNKNOWN`。

### B. 全模式红旗安全门禁

- [ ] 列出自动、问诊、学习、工具、玄学五种模式所有模型调用入口。
- [ ] 覆盖 initialPrompt、历史续聊、附件转写/图像描述、工具结果回流等旁路。
- [ ] 对明确红旗在模型调用和普通业务路由之前确定性拦截。
- [ ] 区分本人、他人、知识性提问、假设句、引用、既往史、否定表达和时间信息。
- [ ] 歧义输入先澄清；不得让模型 prompt 决定安全放行。
- [ ] 医学词表、阈值和处置文案经医学背景人员审核并留存版本/审核记录。
- [ ] 为每个入口建立红旗正向、否定、他人、历史、知识性提问和歧义测试。

**B 验收：** 所有入口无绕过；明确高危输入在任何模型调用前命中；歧义不误判为安全放行；知识讨论/他人症状不会被静默当作用户本人急症；所有安全测试通过。任何红旗门禁缺口阻断相关发布。

### C. 检索黄金行为基线

- [ ] 建立黄金请求：“查桂枝汤组成，并找《伤寒论》对应条文”。
- [ ] 记录检索 query、命中条目 ID、排序、来源、原文定位、上下文注入和最终回答。
- [ ] 保存可复现测试夹具，不把一次模型自由生成文本当作唯一基线。
- [ ] 测试当前内存经典检索的召回与排序；明确漏召回、错排序和来源断链。
- [ ] 先锁定行为，再抽取 Headless adapter；对比前后输出与来源。
- [ ] FTS5 保持暂缓，除非黄金集证明现有检索存在可复现问题并有对照实验支持。

**C 验收：** 黄金输入可重复；召回 ID、排序、原文定位与上下文内容有记录；适配器重构不改变既有正确行为，或所有有意变化有原因、测试和用户可见说明。无实证不更换检索技术。

### D. Page Tool 与 Headless Capability

- [ ] 逐项盘点 AssistantToolRouter 注册能力。
- [ ] 标明 Page Tool、Headless Capability、Executed Capability，禁止混称。
- [ ] 只有页面 builder 的项目继续标记 Page Tool，不得标为 AI 可执行。
- [ ] 每个 Headless 接口定义 typed args/result、必填参数、单位、权限、来源、错误、取消和超时语义。
- [ ] 对医疗、个人生辰、健康历史等敏感数据设置显式授权和领域隔离。
- [ ] 通过工具执行 trace 证明模型/调度层实际触发业务函数，并验证结果回流。

**D 验收：** 页面打开不算执行；工具名出现在 prompt 不算执行；模型口头声称成功不算执行。必须有实际函数调用、参数校验、结果验证、source ID 和会话回传证据。

### E. 低成本数据保护

- [ ] 核对 `allowBackup`、`fullBackupContent`、`dataExtractionRules` 与最终合并 Manifest。
- [ ] 清点 SQLite 会话/消息/问诊任务、附件原件、转写文本、缩略图、临时文件和中间缓存。
- [ ] 增加清除全部 AI 数据入口及二次确认。
- [ ] 清除时处理数据库记录、文件、关联引用和孤儿缓存；记录部分失败。
- [ ] 清除后强制重启 App，验证数据不可恢复。
- [ ] SQLCipher 单独评估，不与本轮低成本保护混做。

**E 验收：** 备份策略在 Android 版本范围内有配置和合并结果证据；清除范围完整；清除后重启无会话、消息、问诊快照、附件原件、转写与缓存残留。数据库加密若未立项，明确记录为未实施，不得宣称已加密。

### F. TRACE 与隐私

- [ ] trace_id 从输入贯穿安全、路由、检索、上下文、模型、工具、结果、展示、持久化。
- [ ] 默认关闭；显式审计开关开启。
- [ ] 普通日志不保存健康正文、生辰、图片、音频和个人身份信息。
- [ ] TRACE 关闭时证明业务结果与执行顺序不变。
- [ ] 日志写入失败不阻断业务。
- [ ] 执行状态区分 NOT_STARTED / SUCCEEDED / FAILED / UNKNOWN。

**F 验收：** 已执行场景可从输入追到最终展示；关键节点缺失即不通过；敏感数据不进入公共 CI 日志或仓库。

### G. 文档与版本一致性

- [ ] README 版本从 `pubspec.yaml` 单一来源同步为 `1.11.30+8039`（若版本有更新，以更新后的 pubspec 为准）。
- [ ] `docs/ai-capability-audit.md` 只放规范与硬门槛。
- [ ] `docs/ai-capability-audit-report.md` 放静态/动态审计报告。
- [ ] `docs/local-ai-multiturn-audit.md` 放 Native 多轮专项审计。
- [ ] `docs/ai-capability-inventory.md` 逐次更新现状，注明审计 SHA 与日期。
- [ ] 增加文档版本一致性检查，避免 README 与 pubspec 再次漂移。

**G 验收：** 文档命名无覆盖冲突；所有状态均注明证据日期和 commit SHA；历史审计与当前状态分开，不能将旧报告误当最新。

## 5. 统一验收记录格式

每次更新任务状态必须使用以下格式：

| 字段 | 必填内容 |
|---|---|
| Task ID | A/B/C/D/E/F/G + 子项编号 |
| Status | NOT_STARTED / IN_PROGRESS / PASS / PARTIAL / FAIL / BLOCKED / UNKNOWN |
| Commit | 对应源码/文档 SHA |
| CODE | 文件、类/函数、行号 |
| TEST | 测试文件、测试名称、实际结果 |
| CI | Workflow、run ID、head SHA、结论 |
| TRACE | 场景 ID、设备、系统、模型、backend、轮次、日志 |
| Gap | 尚未满足的验收条件 |
| Next action | 可执行的下一步，不写泛化口号 |

未执行测试不得写 PASS；测试通过但真机未测，整体能力不能标 IMPLEMENTED；设备不可用写 UNKNOWN，不得用模拟器结果代替。

## 6. 发布硬门槛（不可豁免）

以下任一项 FAIL，阻断相关功能发布；任一项 UNKNOWN，不能宣称该能力完成：

1. 全模式红旗前置安全门禁。
2. 问诊与玄学领域隔离，规则引擎结果不可被模型覆盖。
3. 工具执行状态安全；未知执行状态不盲目重放。
4. 来源可信；不伪造原文、诊断、计算值和业务执行结果。
5. 会话隔离、跨轮历史一致性和恢复可验证。
6. “清除全部 AI 数据”真实删除数据库与附件/缓存。
7. Find N2 目标设备的关键多轮 GPU/CPU 场景有真实 TRACE。

## 7. 变更控制

- 本台账和 `docs/ai-capability-audit.md` 是后续 AI 改造的执行依据。
- 新增抽象、依赖、数据库表、会话体系、向量检索、DAG 或 Agent 平台必须先给出失败证据、收益/风险、替代方案和回滚路径；未经项目决策不得引入。
- 任何降低安全门槛、改变数据模型、改变检索语义或扩大模型权限的修改，必须单独说明并经用户明确决策。
- 每次改造提交都要更新本台账对应项；只改代码不更新证据台账，不视为完成交付。
- 后续复核必须读取最新 master，不沿用旧 SHA、旧行号和过期 CI 结果。

## 8. 多分支并行执行协议（跨对话强制续接）

本项目后续执行必须遵循 [AI 改造多分支并行执行协议](ai-parallel-execution-protocol.md)。该协议是执行方法的持久化依据，优先用于分支创建、文件所有权、并行调度、小批量集成、CI 分层验收和跨对话恢复；不得仅依赖聊天上下文。

每轮继续时必须先读取最新 master、本台账、`docs/ai-capability-audit.md` 和并行协议，再刷新分支/PR/CI 状态。应主动推进所有无依赖的未完成任务，不等待用户逐项点名。分支验证通过不等于全量回归或真机验收通过；PR 不得在质量门槛未满足时合并。

本次复核记录（2026-11-10）：
- master 基线：`60011c4d237cd8d80659038beb6a3a7257228e01`；本次并行协议已提交 master：`4504a5bfee3b7193989a968485ec66b7f567e5cf`。后续以更新后的 master SHA 为准。
- A 多轮审计报告已提交独立分支；审计交付存在，但修复与 Find N2 GPU/CPU 各 20 轮 TRACE 未完成。
- B 全入口红旗审计报告已提交独立分支；策略实现、入口接入、医学审核与完整测试矩阵未完成。
- C 黄金基线规范已提交独立分支；真实检索快照仍 UNKNOWN，不能启动检索行为重构。
- E Android 备份限制 PR #19 已打开；PR-level Flutter regression run `42845985076` 正在执行，当前多个专项步骤已通过，后续全量回归尚未开始；Android merged manifest/build 证据仍缺失。不得合并。
- 主线全量 Flutter 测试的既有失败原因尚未取得完整日志，保持 UNKNOWN；不得把它归因于本轮文档变更。
- 下一项自动执行：继续 A 最小 transcript rehydration 修复前的 LiteRT-LM API/Native 生命周期核验；并行启动 B 纯 Dart 红旗 preflight 状态契约与语义单测；C 生成真实黄金检索快照；E 完成 merged manifest/build 与 AI 数据/附件清除范围盘点。各项按协议使用独立分支/文件所有权。


## 9. 2026-11-11 复核检查点（以最新远端证据为准）

### 9.1 主线基线

- 当前 master：`32da9187ed1ad021408b85f462ab8c680daaa7d0`。
- PR #22 已于 2026-11-10 合并；其折叠屏布局修复进入主线。
- master 最新 SHA `1dbe0b66` 的 Flutter regression `42920932125` 与 Quality Gate `42920932160` 当时仍在执行；PR #24 对应 full Flutter `42919508990` PASS、Android arm64 APK/unit tests `130192845225` PASS。PR #25 的 full Flutter `42919976936` PASS、Android arm64 APK/unit tests PASS。
- master Quality Gate 旧 run `42852721157` FAIL；失败测试为 `HomeScreen passes the inherited system text scaler to tab scaffolds`，退出时仍有 sqflite FFI 的 10 秒 `txnSynchronized` timer。PR #24 已通过完整 Flutter regression 与 Android CI；合并后最新 master Quality Gate 仍需以 run `42921529249` 结果确认。
- 该失败并非产品布局断言失败；它是测试隔离/异步 I/O 生命周期问题。不能因为另一条 full regression 通过就忽略 Quality Gate。

### 9.2 当前 PR / 活动分支

| 工作流 | 分支 / PR | 最新证据 | 状态 | 下一动作 |
|---|---|---|---|---|
| CI 测试配对规则 | PR #23 `work/ci-kotlin-test-pairing` | branch validation `42918552544` PASS；PR full Flutter run `42918880155` FAIL（复现 master 的 HomeScreen timer 泄漏）；Android arm64 APK/unit tests `130190180984` PASS | BLOCKED_BY_BASELINE | 等 PR #24 修复主线测试隔离，再更新本 PR 并重跑 full Flutter + Android |
| HomeScreen 测试隔离 | PR #24 `work/ci-home-screen-db-prewarm` | branch validation `42919236594` PASS；PR full Flutter run `42919508990` PASS；Android arm64 APK/unit tests `130192845225` 仍在排队/执行 | IN_PROGRESS | 等 full Flutter 与 Quality Gate 相关检查完成；若失败读取准确测试和栈，不跳过 |
| A 多轮 Native transcript | PR #21 `work/ai-p0-transcript-rehydration` | head `9deebb4772877bbb33a754d1b46e21bb710f7955`；branch validation `42851799278` 因 Kotlin-only 改动未被 Dart-only pairing 规则识别而 FAIL；早期 Android run `42849947422` APK build PASS、Kotlin 单测因 JDK17 加载 Java21 LiteRT Message FAIL | BLOCKED | PR #23 集成后，从最新 master 新建干净分支，只移植 4 个文件；运行 Kotlin unit tests、Android APK、Flutter full regression；设备 TRACE 仍 UNKNOWN |
| B 红旗 preflight | `work/ai-redflag-policy-v2` | branch validation `42919610457` PASS；PR #25 full Flutter run `42919976936` IN_PROGRESS；纯策略没有 detector、未接生产路由 | PARTIAL | 测试通过后开 PR；保持 `REVIEW_REQUIRED`，不接入生产放行，等待医学审核和真实 detector |
| C 检索黄金快照 | `work/ai-retrieval-golden-snapshot` | branch validation `42848410995` PASS；测试会生成 `build/ai-retrieval-golden/current.json` 并由 CI artifact 保存，但旧分支 workflow 与 PR #23 同时改动，暂不集成 | IN_PROGRESS | PR #23 合入后，从最新 master 移植黄金测试，并将 artifact step 叠加到最新 workflow；审阅真实 JSON 后才固定 expected snapshot |
| D Capability 盘点 | `work/ai-capability-inventory` | branch validation `42851493100` PASS；Router 24 toolId、22 个 ToolsScreen 卡片、9 个页面结果回传设计、Headless 0 | AUDIT PASS / IMPLEMENTATION PARTIAL | 逐能力补 typed args/result、sourceIds、取消/失败语义；对应行为基线前不抽 adapter |
| E AI 数据清除 | `work/ai-data-clear-audit` | 旧 run `42850952252` FAIL：`local_ai_data_clear_screen_test.dart` 超时 10 分钟；已把无界 `pumpAndSettle` 改为 bounded pump + `tester.runAsync`，但仍存在 DB 依赖；进一步增加 `aiConversationDataClearer` 测试 seam 并使用内存 ConversationStore，DB 删除行为由 `ai_conversation_data_clear_test.dart` 独立验证。最新 head `c8053074e3ebac1cf51a71152dca69a4efc64802`，run `42920881688` branch validation PASS（Dart analyze + changed tests）；该切片仍未集成 Native clearAiData handler | IN_PROGRESS | 等新测试结果；失败继续定位；Native `clearAiData` MethodChannel handler 仍待 A 释放 MainActivity 文件所有权后接入 |
| F TRACE / 隐私 | `work/ai-trace-audit` | branch validation `42851304632` PASS；审计发现端到端 trace_id/审计开关/状态链仍缺失 | AUDIT PASS / IMPLEMENTATION NOT STARTED | 先定义脱敏事件契约与关闭时行为等价测试，再分层接入 |
| G 版本文档 | `work/ai-version-doc-consistency` | branch validation `42851411393` PASS；README/pubspec 一致性测试通过，旧版 `1.11.30+8039` | IN_PROGRESS | 从最新 master 单独集成 README 与一致性测试；不与规范文档变更捆绑 |
| E 备份策略 | PR #19 `work/ai-data-protection` | head 基于旧 master `60011c4`；全应用 `allowBackup=false` 影响收藏/设置等非 AI 数据 | BLOCKED / PRODUCT IMPACT | 不合并；重新设计 AI-only 数据备份/迁移边界，先核对最终 merged manifest |

### 9.3 本轮根因与纠偏记录

1. Kotlin test pairing 的失败是 workflow 契约错误：旧脚本只把 `test/*_test.dart` 识别为配对测试。PR #23 已修改为同时识别 `android/app/src/test/**/*Test.kt`，并在 Kotlin test 有变化时执行 `./gradlew :app:testDebugUnitTest --no-daemon`。分支级 validation PASS，PR 全量检查仍受 HomeScreen 基线测试阻断。
2. HomeScreen 测试第一次尝试在 `setUpAll` 预热数据库，反而导致三个测试均出现 timer 泄漏；已撤销。当前 PR #24 保留两个真实 HomeScreen 导航测试，只把纯 textScaler 继承测试改为直接测试 `AdaptiveHomeNavigation`，避免无关 DB 初始化副作用。
3. E 数据清除测试之前用 `pumpAndSettle` 等待真实 sqflite FFI 操作，导致 10 分钟 timeout；改为显式 pump 与 `tester.runAsync` 等待异步 I/O。新 run 结果待确认。
4. 所有历史分支仍基于旧 master；只允许挑选文件/提交后在新 master 上重验，不得整体合并。

### 9.4 下一批自动执行顺序

1. PR #24：通过 full Flutter regression 与质量门禁后小批量合并；合并后确认 master Quality Gate PASS。
2. PR #23：更新到新 master，确认 Kotlin-only test pairing 正确执行，并等待 Android arm64 APK/unit tests PASS 后合并。
3. A：在最新 master 创建干净分支移植 transcript rehydration；确认 Kotlin unit test 真正运行，不能再出现 SKIPPED；通过 CI 后才安排 Find N2 GPU/CPU 真实设备场景。
4. E：确认 AI 清除测试不再超时；审计所有表/附件/缓存；A 合并后实现 Native `clearAiData` handler，随后验证 Native Engine 释放顺序和重启后不可恢复。
5. B：完成纯 Dart preflight 单测；规则保持 REVIEW_REQUIRED，等待医学审核记录与 detector，不得仅凭策略单测标记医疗门禁完成。
6. C：生成并审阅黄金 JSON artifact；在 snapshot 之前不抽检索 adapter、不换算法、不引入 FTS5。
7. D/F/G：分别按能力目录、TRACE、版本一致性拆成小 PR；不把审计完成等同实现完成。
8. E 备份：PR #19 保持阻断，直到 AI-only 与非 AI 数据迁移影响得到清晰方案。

