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


## 10. 2026-11-12 当前主线增量复核（基线：`28b6bbf5928c44e2befb85b3fbaa6220827634e7`）

> 本节只记录本轮重新读取的 master 代码、已合并 PR 和当前 CI 证据。未合并 PR 不计入 master 已实现；CI 运行中/失败不得写 PASS；Find N2 真机没有本轮 TRACE，相关能力仍为 PARTIAL/UNKNOWN。

### 10.1 当前主线与集成状态

| 对象 | 状态 | 当前证据 / 处理 |
|---|---|---|
| master | 当前审计基线 | `28b6bbf5928c44e2befb85b3fbaa6220827634e7`；由 PR #73 合并后形成 |
| PR #71 红旗 provenance 契约 | MERGED | 合并至 master；Flutter regression + Android arm64 CI run `43143105547` SUCCESS。仅证明策略契约，不证明自然语言 detector、生产入口门禁或医学审核完成 |
| PR #73 TRACE 清理生命周期协调 | MERGED | 合并至 master；run `43143105547` Flutter regression SUCCESS、Android arm64 CI SUCCESS；Branch validation 为 SKIPPED |
| PR #74 旧附件迁移分支 | CLOSED / SUPERSEDED | 旧 base `bc29aef2` 已过期；实现从当前 master 重建为 PR #78。旧 CI 不继承 |
| PR #76 设置页清除入口 | OPEN / CI RE-RUN PENDING | 最新 head `3d8c02448d580ea2758c373e36536e8bdbbf3d93`；首次全量回归 run `43144522461` 1325 passed / 1 failed / 15 skipped。唯一失败为本 PR 新增直接 `showDialog` 违反 fold-aware navigation contract；已改为 `showFoldAwareDialog`，新 run `43145157603` pending，未验收 |
| PR #77 SQLite 原子轮次故障注入测试 | OPEN / IN_PROGRESS | head `f52ecfbd8dd0627fe608f3152744ed146a205dec`；run `43144699629` 全量回归执行中。新测试通过 SQLite trigger 注入 assistant insert 失败，验证 user insert 同事务回滚 |
| PR #78 生产附件归属迁移 | OPEN / IN_PROGRESS | head `e6935ce45e7499ceac5f7bb7d3903692234684eb`；run `43144948665` 正在执行录音重试 Widget 回归。未通过前不合并 |

### 10.2 A-G 当前核验结果

| ID | 状态 | 当前已核验事实 | 未闭环 / 下一项 |
|---|---|---|---|
| A 多轮稳定性与 Native 生命周期 | PARTIAL | `MainActivity.runAiTask` 使用单线程 `aiExecutor`；Native 多轮失败恢复此前成功轮次，不自动重放当前 UNKNOWN 请求；`DatabaseHelper.saveAssistantTurn` 已用 SQLite transaction 写入 user/assistant pair；`LocalAiInterviewScreen._persistSuccessfulTurn` 对历史持久化失败显示可见错误 | PR #77 故障注入测试待 CI；`onDestroy` 只排队释放并 shutdown executor，未等待 teardown 完成；Find N2 GPU/CPU 各 20 轮和跨层 TRACE UNKNOWN |
| B 全模式红旗安全门禁 | PARTIAL / RELEASE BLOCKED | `RedFlagPreflight` 已有 source、detector/rule-set version provenance 与 subject/time/polarity 状态契约；PR #71 已合并，测试在 run `43143105547` 通过 | 没有自然语言 detector；尚未接入所有模型调用/普通业务路由入口；没有医学词表、阈值和处置文案审核记录。不得用人工构造的 `RedFlagAssessment` 单测替代真实 detector |
| C 检索黄金行为基线 | PARTIAL | `test/ai_retrieval_golden_snapshot_test.dart` 与 `test/fixtures/ai_retrieval_golden_metadata.json` 已形成可版本控制基线；run `43143105547` 的 golden snapshot 步骤成功，artifact `13911060760` 可复核 | 本轮快照：原始自然语言 query 命中 0；派生 query “桂枝汤” 196、“桂枝” 294、“伤寒论” 121；上下文 RETRIEVED、9 个 source IDs、纸本/卷页定位 9 项均 MISSING。上下文含 4 个方剂 ID，其中 3 个并非用户直接点名；当前实现会按组成药名扩展方剂候选，需评估相关性，但在完成对照测试前不改变排序/检索语义 |
| D Headless Capability | PARTIAL | `AssistantToolRouter` 当前 24 项注册；结构化辨证在统一对话内联执行，其余 23 项仍为 Widget/page builder；参数验证目前为 date/integer/choice/text 基础校验 | 未发现统一 Headless execute/result 协议、统一权限/取消/超时和结果回传证据；先逐项盘点真实业务函数及现有行为基线，再选最小适配器，不以页面打开冒充执行 |
| E 本地 AI 数据保护 | PARTIAL | PR #73 已提供 TRACE 停止/flush、清理期间生命周期协调；PR #76 增加设置入口；PR #78 将新建图片/录音迁移到 AI-owned 目录。SQLite 清理测试覆盖 AI 会话表清理和非 AI 数据保留 | #76/#78 CI 未通过前不合并；旧共享 temp 孤儿附件没有可靠归属证据；Android Manifest 当前未显式声明 `allowBackup`、`fullBackupContent` 或 `dataExtractionRules`，合并 Manifest/备份行为尚未核验。不得未经独立决策全局禁用 Android backup |
| F TRACE 与隐私 | PARTIAL | TRACE writer/recorder 默认关闭；事件字段白名单、失败不阻断业务、关闭后拒绝新事件等已有单测；PR #73 将 writer/recorder 进程级共享并与清理生命周期协调 | trace_id 尚未贯穿 Dart 输入、MethodChannel、Native 推理、检索/工具、最终展示和 SQLite 持久化；未完成设备级端到端 TRACE |
| G 文档与版本一致性 | PARTIAL | README 与 `pubspec.yaml` 均显示 `1.11.30+8039` | 本次新增审计报告和台账更新仍在独立文档 PR；能力盘点文件需继续按最新审计 SHA 维护 |

### 10.3 当前执行顺序（不等待用户逐项点名）

1. 完成 PR #76 的 fold-aware dialog 修复后全量 Flutter 回归与 Android arm64 验收；失败则按失败测试继续修复。
2. 完成 PR #77 原子事务故障注入测试；若失败，核对真实 SQLite transaction 和 test factory 隔离，不弱化回滚断言。
3. 完成 PR #78 录音重试及全量 Flutter/Android CI；若失败，查路径注入、录音状态与测试等待条件，不通过跳过测试处理。
4. 小批量集成上述通过的独立切片；每次集成后刷新 master 基线并重新校验后续分支。
5. E：核查旧共享 temp 附件的历史命名和持久化引用；只对可证明属于 AI 的路径制定清理策略。补充 Android merged manifest / backup 行为证据；备份策略变更单独评估。
6. A：补 Native Activity destroy / executor teardown 可注入测试；继续核对 SQLite、Flutter UI、Native 成功轮次的一致性。真机 GPU/CPU TRACE 必须由 Find N2 实测提供。
7. F：冻结跨层 trace_id 契约后，再按输入→门禁→路由→检索→模型→工具→展示→持久化逐段接入；TRACE 默认关闭且不记录敏感正文。
8. B：在没有医学审核记录前，不引入未经审核的词表/阈值/处置文案；先完成 detector 入口清单和 fail-closed 接入设计，避免静默放行。
9. C：围绕当前黄金快照中方剂候选扩展行为补相关性对照用例；保持原始基线，任何检索语义变化必须显式更新 golden fixture 并说明影响。
10. D：按 24 项工具逐项建立输入/输出、参数、权限、取消、错误和执行证据表；只对已有确定性业务函数建立 Headless adapter。
11. 每个已合并代码切片立即更新本台账；真机未测、merged manifest 未核验、医学审核缺失等项目继续保持 PARTIAL/UNKNOWN。



## 11. 2026-11-12 PR #77 集成后复核（当前 master：`e279d7a4ce65edc5a32d7521231f57c413db6895`）

PR #77 已 squash merge。其 Flutter full regression `43144699629` SUCCESS（1326 passed / 15 skipped / 0 failed）；Android arm64 APK/ABI build 与 unit tests SUCCESS；Branch validation SKIPPED。合并后当前 master 为 `e279d7a4ce65edc5a32d7521231f57c413db6895`。

### 11.1 最新未合并切片

| PR | Head SHA | CI run | 当前状态 |
|---|---|---|---|
| #76 设置页清理入口 | `daf8cc732b902540089be8173e9df726075c38ae` | `43146455398` | Flutter regression IN_PROGRESS；前一修复版 run `43145157603` Flutter SUCCESS（1326 passed / 15 skipped），Android arm64 job仍在该旧head上执行；当前 head包含清理范围文案修订，必须等新head完整验收 |
| #78 生产附件归属迁移 | `bddf71287b499edb807ec90e8c6b635d7ca76798` | `43146481834` | Flutter regression IN_PROGRESS；已增加固定泵帧等待，测试临时目录IO使用 tester.runAsync；仍待录音重试和图片归属回归通过 |
| #79 审计/台账/能力/TRACE 契约文档 | head 随本 PR 文档提交持续更新 | `43146991805` 为较早 head 的 run | 较早 head Flutter SUCCESS；Android arm64 job IN_PROGRESS；当前 head 必须重新触发并验收 |

### 11.2 E 清理范围增量

PR #78 现在同时包括：
- 图片/录音进入 `local_ai_attachments` AI-owned 目录；
- 成功复制后，仅在来源路径位于 app temp root 内时删除 image_picker 的缓存副本；外部 provider 路径不删除；
- `LocalAiAttachmentStore.clearAll` 除专属目录外，只额外清理共享 temp root 下精确匹配 `local_ai_<digits>.wav` 的旧版录音；不递归子目录，不删除泛化图片文件或其他 temp 文件；
- 对上述 allowlist 新增单测，验证旧录音被清除、普通文件与嵌套目录文件保留。

因此 E 的旧附件边界更新为：已知旧版录音有精确清理策略；旧版共享 temp 图片缺少稳定归属标识，仍不清理。Android backup 行为仍 UNKNOWN，不禁用全局备份。

### 11.3 A-G 状态更新

- A：原子轮次事务故障注入测试已合并并通过 Flutter/Android CI；Native Activity teardown 与 Find N2 真机一致性仍 PARTIAL/UNKNOWN。
- B：仍 PARTIAL / RELEASE BLOCKED。已定位所有 Flutter 生产入口：活动结构化问诊答案、工具路由、文本 sendMessage、图片 sendImage、录音 sendAudio、症状整理 extractSymptoms；Native 对应 MethodChannel 入口仍无真实自然语言/多模态 detector。
- C：黄金基线不变；候选相关性问题继续待对照用例，不直接改排序。
- D：24 项注册表完整清单已追加至能力盘点；23 项仍是页面 builder，Headless 协议缺失。
- E：#76/#78 当前 head 的 CI 未结束，不合并；旧版精确录音清理已加入 #78。
- F：trace_id 端到端契约仍未实现。
- G：README/pubspec 版本一致；审计报告和台账仍待文档 PR #79 最新 head 验收。

### 11.4 下一步

1. 完成 #76 当前 head Flutter/Android CI，成功后合并并验证主线。
2. 完成 #78 当前 head 录音重试、图片复制/安全清理、旧录音 allowlist 测试及全量 Flutter/Android CI；成功后合并。
3. 合并后重新读取 master，更新 #79 文档基线和 PR/CI 状态。
4. 继续 A Native teardown 矩阵、F trace_id 契约、B detector 入口门禁设计、C 检索相关性对照、D Headless 适配。
5. 真机、医学审核、Android merged manifest/backup 未取得证据的项目继续保持 UNKNOWN / RELEASE BLOCKED。


## 12. F：trace_id 端到端契约已冻结为文档基线（尚未实现）

新增 `docs/ai-trace-contract.md`，基于当前 `AiTraceRecorder`、`AiTraceEvent`、`LocalAiTraceFileWriter` 和 `assistant_messages.metadata` 现状定义传播契约。

关键约束：
- TRACE 关闭时不生成 ID、不传递、不写 SQLite metadata；开启时每个用户轮次只生成一个 32 位小写十六进制 trace_id。
- trace context 必须显式贯穿结构化问诊、工具路由、文本、图片、录音、症状整理、Native MethodChannel、最终展示和 SQLite。
- MethodChannel 增加可选 `trace_id`，Native 原样回传；缺失/错配标记 UNKNOWN，不重新生成 ID。
- SQLite 复用现有 `assistant_messages.metadata TEXT`，user/assistant 两条消息写入相同 trace_id；不增加 conversation table/schema column。
- 复用已有 AiTraceStage/AiTraceStatus；只写 allowlisted metadata，不记录用户原文、prompt、response、症状、附件路径、ASR/OCR 或身份信息。
- writer 现有 500 events / 7 days 限额保持；清理仍由 process-wide runtime disableAndFlush → clear → restore 负责。

实施按文档第 7 节逐层推进：Flutter context → Dart MethodChannel → Kotlin 原样回传 → SQLite metadata → 跨层故障注入/隐私测试 → Find N2 真机 TRACE。当前 F 仍 PARTIAL；文档冻结不等于代码实现完成。


## 13. 2026-11-12 最新 CI 纠偏记录

本节覆盖第 11 节之后的新提交，防止台账继续引用旧 head 或把失败写成运行中：

| PR | 最新 head | 最新 CI | 处理 |
|---|---|---|---|
| #76 设置页清理入口 | `5ee908134f27e15caf907a0751c580fbed92a13a` | run `43147357775` PENDING | 前一 head run `43146455398` 的 1327 tests 中仅 1 项失败：测试仍查找旧警告文案；已同步更新断言。更早 head `43145157603` Flutter 1326 passed / 15 skipped，但不是当前 head 结论 |
| #78 附件归属迁移 | `23efe6b625b88eabeae475c5374a8cea8dd8b9a4` | run `43147189070` PENDING | 旧 head run `43146732341` Flutter FAIL：附件存储文件 raw RegExp 字符串损坏、widget test 在 fakeAsync 中做真实文件系统操作且产生两个不必要非空断言 warning；已重建完整 store 文件，测试改用 fake recording store，清理 allowlist 由非-widget SQLite/文件系统单测覆盖 |
| #79 审计/台账/能力/TRACE 契约文档 | head 随本 PR 文档提交持续更新 | run `43146991805` 为较早 head | 较早 head Flutter regression IN_PROGRESS；本轮更新后需验收新 head |

### 当前执行约束

- #76/#78 当前 head 的 CI 必须从头通过 Flutter regression 和 Android arm64；不能沿用旧 head 的部分成功。
- #78 的生产代码保留图片来源清理：仅当来源路径位于 app temp root 内才删除；外部 provider 路径不删除。
- #78 的旧录音清理严格使用 `local_ai_[0-9]+.wav` 文件名 allowlist，单层枚举，不递归；未知图片/普通文件/子目录均保留。
- #76 警告文案区分“已知旧录音会清理”与“无法可靠归属的旧共享临时图片不清理”。
- #79 只在其最新文档 head CI 完成后合并；合并前再次更新本台账中的当前 master SHA 和所有 PR/CI 状态。


## 14. PR #76 集成后当前执行快照（2026-11-12）

PR #76 已 squash merge，提交 `eaa83b440ddb1299a7eac58b70067de38ad44ea2`；Flutter full regression SUCCESS，Android arm64 APK/ABI + unit tests SUCCESS。当前 master 为 `eaa83b440ddb1299a7eac58b70067de38ad44ea2`。

| PR | 最新 head | CI | 当前状态 |
|---|---|---|---|
| #76 | 已合并 | run `43147357775` | MERGED；Flutter + Android SUCCESS |
| #78 附件归属/旧录音 allowlist | `6c3fb70bba38bff3831fea27dfcdadba5994dc48` | run `43148511074` | PENDING；前一 head targeted recorder test 已通过，full regression 因另一录音文件检查测试未注入 fake store失败，已补注入并改为固定帧等待 |
| #80 Native Activity teardown 序列化 | `fc640d431eb58a62a81d507e663674fd1a746e28` | run `43148298845` | Flutter full regression IN_PROGRESS；Android job 尚未启动 |
| #79 审计/台账/能力/TRACE 契约文档 | head 随本 PR 更新 | run `43147546530` | 该 run 的 Flutter + Android SUCCESS；本次台账更新后必须按新 head 重新验收 |

### 14.1 A / E 当前状态

- A：SQLite 原子轮次测试已合并；Native teardown 改为进程级单线程队列，Activity destroy 后拒绝未开始旧任务并将 release 排入共享队列，新 Activity 的模型任务排在 release 后。PR #80 仍待 CI；真机折叠屏/Activity recreation 和 GPU/CPU TRACE UNKNOWN。
- E：设置页清理入口、二次确认、逐域结果和失败域中文说明已合并。附件归属迁移、旧版精确录音清理和 image_picker app-temp 缓存副本清理仍在 PR #78，未通过当前 head CI 前不合并。
- #78 录音重试 UI 测试和文件存储测试分层：Widget 测试用 fake store 验证录音状态恢复；文件系统测试验证 AI-owned 目录与精确 legacy allowlist，不在 fakeAsync 中执行真实目录创建。
- PR #80 的 process executor 是进程级 daemon 单线程队列，不在 Activity onDestroy 时 shutdown；这是为了确保旧 Activity release 先于新 Activity load。若模型调用永久不返回，新 Activity 也会等待旧任务结束；不能通过并行加载绕过该安全边界。

### 14.2 下一步

1. 完成 #78 当前 head 全量 Flutter regression 与 Android arm64；通过后小批量合并。
2. 完成 #80 Flutter/Android CI；失败按真实日志修复，不降低队列顺序断言。
3. #78/#80 合并后刷新 master，再更新 #79 的最终基线/PR 状态并合并文档。
4. 继续 F trace_id 跨层实现；B 仍等待医学审核 detector；C 做检索相关性对照；D 做确定性 Headless adapter；真机证据由 Find N2 本地 TRACE 提供。


---

## 9. 2026-11-12 11:42（UTC+8）主线续接复核

本节覆盖此前 2026-11-10 记录及 2026-11-12 早间增量记录；如状态冲突，以本节对应 SHA 的最新远端证据为准。

### 9.1 当前主线与 CI

- 当前 master：`eaa83b440ddb1299a7eac58b70067de38ad44ea2`。
- Flutter 全量回归：run `43148541339`，job `130952021084`，SUCCESS。
- Android arm64 APK/ABI 构建与 Native unit tests：run `43148541339`，job `130953844163`，SUCCESS。该 job 是 ABI/build 验证，不是 Find N2 真机运行。
- `Analyze and test`：job `130952020768` 在本次记录时仍 IN_PROGRESS；因此 master CI 总状态不能标为全绿。
- Branch validation 在主线事件中 CANCELLED/SKIPPED，不计 PASS。

### 9.2 PR 与集成状态

| PR | 工作流 | 当前状态 | 基线 / head | 证据与下一步 |
|---|---|---|---|---|
| #71 | B 红旗 provenance 契约 | MERGED | merge 已进入主线历史 | 仅证明结构化 provenance 契约；自然语言 detector、全入口 fail-closed、医学审核仍缺失 |
| #73 | F TRACE runtime 与清理协调 | MERGED | merge commit `28b6bbf5928c44e2befb85b3fbaa6220827634e7` | 仅证明 recorder 生命周期协调；端到端 trace_id 仍 PARTIAL |
| #76 | E 设置页清理入口 | MERGED | merge 已进入当前主线 | 入口/二次确认已存在；删除边界和重启后不可恢复尚未证明 |
| #77 | A SQLite assistant turn 原子持久化测试 | MERGED | merge commit `e279d7a4ce65edc5a32d7521231f57c413db6895` | 测试覆盖 assistant insert 失败时 user insert 同事务回滚；不替代真机 transcript 一致性 |
| #78 | E 生产附件归属 | OPEN | base `eaa83b44...`；head `7a03023aab43ac3fcae6af744fd94c571a8f92ae` | 已从旧基线重放到当前 master；Flutter regression 与 branch validation 仍运行。此前旧基线 Flutter/Android 通过不能替代新 head 验收 |
| #79 | G 审计报告/能力盘点/台账/TRACE 契约 | OPEN | base `eaa83b44...`；head `5ecdfe8511aee825b2676541f2d3188acd29855f`（本台账更新前） | 已重放到当前 master；本次追加记录后 head 将变化，需以 GitHub 最新 head/CI 为准 |
| #80 | A Native Activity teardown 串行化 | OPEN | base `eaa83b44...`；head `46ad1bb4c9c10a793b1d8808b7b6870fd00567d5` | 已从旧基线重放到当前 master；Flutter regression 与 branch validation 仍运行，等待新 head CI |
| #81 | C 精确方剂查询避免无关候选扩展 | OPEN | base `eaa83b44...`；head `bff30502a261ecbc67b519991808cdeb39168a12` | Flutter regression FAIL，Android arm64 SUCCESS；失败见 9.3，修复并更新黄金快照前禁止合并 |
| #74/#75 | 旧附件分支 / 旧台账分支 | CLOSED, NOT MERGED | base 为 `bc29aef2...` | 不再作为集成候选；对应工作已分别由 #78/#79 当前基线分支承接 |

### 9.3 C 精确方剂检索失败基线（PR #81）

- CI run `43148982819` Flutter job `130953417214`：失败；Android arm64 job `130954217277`：成功。
- 新增的“单味药查询仍按方剂组成匹配相关方剂”测试在 `test/assistant_knowledge_context_test.dart:40` 失败：查询“桂枝”时，受 `maxFormulaEntries = 4` 上限影响，结果没有包含测试硬编码期待的“桂枝汤”。这是候选排序/上限与测试断言的冲突，不能通过扩大上限来掩盖。
- `test/ai_retrieval_golden_snapshot_test.dart:183` 失败：精确方剂过滤后上下文构成变化，新增来源 ID `herb:桂枝`，与旧黄金快照不同。该变化必须基于实际输出审核并更新快照；不能删除快照断言或把变化默认为正确。
- 下一步：分别审查“精确方名查询”与“单味药成分查询”的业务契约；保留精确方名不扩展无关方剂的目标，修正不合理测试前先确认候选截断行为；记录新旧来源 ID、排序和上下文差异，再更新黄金快照并跑完整回归。

### 9.4 A-G 当前状态与可执行缺口

- A：PARTIAL。SQLite 成功轮次原子写入测试已合并；PR #80 在当前 master 上重新验收。Find N2 GPU/CPU 各至少 20 轮、图片/语音和进程恢复 TRACE 仍 UNKNOWN。
- B：PARTIAL / RELEASE BLOCKED。结构化 preflight 与 provenance 存在，但当前代码没有经医学审核的自然语言 detector；不能将无 detector 的输入当作 CLEAR，也不能自行编造医学词表/阈值/处置文案。下一步是全入口调用图和 fail-closed 接入设计，正式词表等待医学审核。
- C：PARTIAL。黄金快照 CI 可执行；PR #81 当前行为变化未通过快照回归，暂停合并。
- D：PARTIAL。按审计报告，24 项注册能力中 23 项为页面 builder；需继续逐项确认 Page Tool / Headless / Executed，不能将页面打开计作工具执行。
- E：PARTIAL。设置入口已合并；PR #78 当前基线附件归属迁移正在 CI。旧共享临时目录中无法可靠归属的图片、Android 备份副本及外部导出副本不在可证明清理边界；SQLite 数据库混合 AI 与非 AI 数据，禁止直接排除整个数据库备份或全局关闭备份。
- F：PARTIAL。writer/recorder 默认关闭且清理协调已合并；trace_id 尚未贯穿输入、安全、路由、检索、模型、工具、结果展示和 SQLite。
- G：PARTIAL。PR #79 更新审计报告、能力盘点、TRACE 契约和本台账；README 与 pubspec 当前版本仍需自动一致性检查。

### 9.5 当前并行调度

1. 等待 #78/#80/#79 当前 master head 的 CI 完成；逐项读取失败日志，不用旧基线 CI 代替。
2. #81 保持未合并，先修候选截断测试契约和黄金快照差异。
3. E 下一切片：核对清理 coordinator 的每个数据域与 Android merged manifest；数据库/附件/Native runtime/TRACE 的清理结果分别报告，重启验证缺失时保持 UNKNOWN。
4. B 在不修改 Native 共享文件的前提下，推进纯 Dart 入口清单、调用边界测试和 fail-closed 契约；不启用未经医学审核的 detector。
5. D 完成 24 项 ToolRouter 注册表逐项分类，优先只读盘点，不抽取未有行为基线的 Headless adapter。
6. F 先冻结跨层 trace_id 传递契约，再按文件所有权分批接入；不得将 #73 生命周期协调等同于端到端完成。

### 9.6 证据边界

本次状态只依据 GitHub master/PR、源码、测试文件和 Actions job/log。未执行 Find N2 真机测试；未取得用户设备的 GPU/CPU、图片/语音、进程恢复 TRACE。所有相关设备验收继续标记 UNKNOWN。


## 10. 2026-11-12 后续增量：当前主线并行验收续接

- PR #78 附件归属迁移已重放到 master `eaa83b440ddb1299a7eac58b70067de38ad44ea2`，当前 head `7a03023aab43ac3fcae6af744fd94c571a8f92ae`；Flutter regression 仍 IN_PROGRESS，branch validation changed tests 已 SUCCESS，另一轮 branch validation SKIPPED。Android arm64 job 尚未在该 head 上执行成功，不得标完整 CI PASS。
- PR #80 Native Activity teardown 串行化已重放到同一 master，当前 head `46ad1bb4c9c10a793b1d8808b7b6870fd00567d5`；Flutter regression 和 branch validation 均 IN_PROGRESS；Android arm64 仅旧 head 有 SUCCESS，新 head 尚待验证。
- PR #81 精确方剂检索当前 head 已更新为 `f26455f0ec1bcabaf04c5fa91ab4c8821274f827`。针对前次失败做了两项修订：成分匹配测试改用当前方剂库中唯一包含“白蜜”的“大半夏汤”，避免把前 4 条截断结果写成固定方剂排序契约；黄金 metadata 按 CI 实际观察到的差异更新为 sourceIds `formula:guizhi_tang`、`herb:桂枝` 和四条伤寒条目，context textLength 2199、MISSING locator 6。新 head Flutter regression 尚在 QUEUED/IN_PROGRESS，不能标 PASS。
- PR #82 新增 `test/local_ai_data_clear_database_boundary_test.dart`，head `6089c4bcc73a00e749b7dfc413d15f87f42f5275`，从当前 master 创建。该测试使用真实 SQLite FFI，验证 assistant_conversations、assistant_messages、tcm_interview_tasks、legacy chat_history 清空，同时 bookmarks、diagnosis_history、search_history、user_settings 保留，并在关闭/重开数据库后复验。该测试只覆盖数据库边界，不替代附件、Native cache、TRACE、Android 备份和真机清理验收；CI 尚未结束。
- PR #79 本台账分支在本节追加后会产生新 head，必须在 GitHub 上重新读取最终 SHA 和 CI，不得继续引用更新前 head `601606aa...`。

### 后续执行约束

1. #78/#80/#81/#82 的新 head CI 全部结束前不合并；每个失败必须读具体 job/step/log。
2. #82 若通过，数据库清理子项可记为 CODE+TEST+CI 的 PARTIAL 证据；清理后重启仅由 FFI 文件重开证明数据库持久化结果，不代表 Android 进程重启或全数据不可恢复。
3. #81 只有在新 head 的检索专项、黄金快照和完整 Flutter regression 通过后，才可进入小批量集成。
4. 当前主线 Android arm64 build/Native unit tests 已 SUCCESS；主线 `Analyze and test` 仍以 Actions 最新状态为准，不沿用早前 IN_PROGRESS 记录。


## 11. 2026-11-12 12:05（UTC+8）D 目录审计与 E 备份边界增量

### 11.1 D：24 项工具注册表已完成源码逐项分类（审计完成，不等于功能改造完成）

- 在 `docs/ai-capability-inventory.md` 新增 24 项逐项清单，按 `lib/screens/assistant_tool_router.dart` 的实际常量和 `_all` 列表核对。
- 结论：24 项注册能力中，23 项是 Widget Page Tool；`structured_diagnosis` 是由 `LocalAiInterviewScreen` 特殊接管的内联问诊流程，其注册 builder 主动抛出 StateError；该注册表没有可证明的通用 Headless Capability。
- 注册参数目前只有 `yunqi.date` 一个可选日期字段；没有统一 typed result、cancel、timeout、来源 ID 或通用执行状态协议。
- 这完成的是代码盘点，不是 D 完成。下一步按页面逐项检查纯计算函数、输入、结果回传、持久化，再选一个低风险纯计算能力做最小 Headless adapter；不一次性改造 23 个页面。

### 11.2 E：Android 备份规则的最小安全切片

- PR #83：`work/ai-targeted-backup-exclusions-2026-11-12`，当前 head `f1f196ce0651cf37aea23a2739891d4ac47ea891`。
- 配置 `fullBackupContent` 与 Android 12+ `dataExtractionRules`，只排除 `files/ai_models/`、`ai_trace.jsonl`、`ai_trace.jsonl.tmp`；不设置 `allowBackup=false`，不排除数据库 domain。
- 清理确认页同步披露：AI 会话与非 AI 业务数据共用 SQLite，数据库备份副本仍可能保留。
- 新增静态契约测试，锁定 manifest 两个规则引用、AI 文件排除项和“不全局关闭备份/不排除混合数据库”的约束。
- 这只是降低模型/TRACE 进入系统备份的风险。最终 merged manifest 与 Android build 验收仍需当前 PR head 的 Android CI；AI 会话数据库备份问题保持 PARTIAL。

### 11.3 E：SQLite 清理范围回归

- PR #82：`work/ai-database-clear-boundary-test-2026-11-12`，当前 head `6089c4bcc73a00e749b7dfc413d15f87f42f5275`。
- 新增 SQLite FFI 测试：写入 assistant_conversations、assistant_messages、tcm_interview_tasks、legacy chat_history；同时写入 bookmarks、diagnosis_history、search_history、user_settings。
- 断言清理后 AI 表为空、非 AI 表保留，并关闭/重开同一数据库文件后复验。
- 当前 Flutter 全量回归仍 IN_PROGRESS；测试通过前不标记数据库清理边界 PASS。即使通过，也只证明数据库行级范围和重开持久性，不证明 Android 进程重启、文件取证不可恢复或其他数据域已清理。

### 11.4 当前并行 CI（本节记录时）

| PR | 当前 head | Flutter regression | Android arm64 | Branch validation |
|---|---|---|---|---|
| #78 | `7a03023a...` | SUCCESS | IN_PROGRESS | 最新完整 changed-test 检查 SUCCESS；另有 SKIPPED |
| #79 | `68fc10b2...` | IN_PROGRESS | SKIPPED（文档变更） | SUCCESS |
| #80 | `46ad1bb4...` | SUCCESS | IN_PROGRESS | SUCCESS |
| #81 | `f26455f0...` | SUCCESS（修订后） | IN_PROGRESS | SUCCESS |
| #82 | `6089c4bc...` | IN_PROGRESS | SKIPPED（Dart 测试切片） | SUCCESS |
| #83 | `f1f196ce...` | SKIPPED | SKIPPED | IN_PROGRESS |

- 当前 master `eaa83b44...` 的 Flutter regression、Android arm64 build/Native unit tests、Analyze and test 均已 SUCCESS；branch validation CANCELLED/SKIPPED 不计 PASS。
- 表内每个 PR 的 CI 都绑定具体 head；任何新 commit 都必须重新核对该 SHA 的 Actions。

### 11.5 下一项自动推进

1. #78/#80/#81 等待当前 head Android arm64；不以 Flutter 单项 SUCCESS 代替完整验收。
2. #82 等待完整 Flutter regression；若失败读取 SQLite FFI 日志修复。
3. #83 需要确保 Android manifest merge/build 真正执行；若 PR 工作流不触发 Android job，不能用静态契约测试代替，需通过可用 CI 入口补充 build 证据。
4. #81 全量 Flutter 已 SUCCESS，Android arm64 完成后进入小批量集成候选。
5. #79 审计文档 PR 本次继续追加了 D/E 证据，必须读取更新后的最新 head 和 CI。


## 12. 2026-11-12 当前主线合并台账（master b786f84）

### 12.1 已合并且有 CI 证据的切片

| PR | 合并提交 | 内容 | 状态 |
|---|---|---|---|
| #80 | `f59e66fa11c2b69c960f0dc6e4aa8d24dc28e647` | Native Activity teardown 串行化 | MERGED；Flutter/Android/Native tests PASS |
| #78 | `7562c637c97c961e1690d31be7e925e6403c55db` | 生产附件归属 | MERGED；Flutter/Android PASS |
| #81 | `2c1d363633b215e07135c827f282867e983c501c` | 精确方剂匹配与黄金快照更新 | MERGED；Flutter/Android PASS |
| #82 | `021eecf00ce98e5118b6b77f6974375b911784b5` | SQLite 清理范围、非 AI 数据保留、事务回滚测试 | MERGED；Flutter/Android PASS |
| #83 | `9fcc7b82e7e8a66b3f8b42d47caff4850af03eef` | 模型/TRACE 备份排除与 merged manifest 验证 | MERGED；Flutter/Android PASS，merged manifest step PASS |
| #84 | `b786f84df0452b9771e341c818e0d06a12451ef3` | Dart/Native trace_id bridge | MERGED；Flutter/Android/Native tests PASS |

当前 master：`b786f84df0452b9771e341c818e0d06a12451ef3`。该合并后的 master 全量 Flutter regression 与 Analyze and test 在本节记录时仍 IN_PROGRESS；完成前不把主线 CI 标为 PASS。

### 12.2 当前唯一代码 PR

- PR #85：`work/ai-headless-yunqi-executor-2026-11-12`。
- Base：master `b786f84...`；head：`21470fd5a14c3cee4b9ff4245f6c1cd59a3093c3`。
- 目标：复用既有 `YunQiEngine`，给 `yunqi` 增加 Headless + Page 双入口。
- 显式日期才自动执行；无日期继续打开页面确认。无效日期、越界日期、未知参数均拒绝执行。
- 测试覆盖 executor、router、原始日期参数校验、助手直接执行和消息 metadata 持久化。
- 当前 Flutter regression/branch validation IN_PROGRESS；尚未合并，不能将 Headless 数量计入主线。

### 12.3 A-G 主线状态

- A PARTIAL：Native 生命周期和生产附件归属已合并；真机多轮、媒体和进程重启证据 UNKNOWN。
- B PARTIAL / RELEASE BLOCKED：provenance 契约存在；自然语言 detector 与医学审核缺失。
- C PARTIAL：精确方剂检索与黄金快照已合并；候选身份、来源和原始位置的逐条人工/规则审查继续。
- D PARTIAL：24 项目录已逐项分类；PR #85 是第一个 Headless 候选，待完整 CI/合并。
- E PARTIAL：入口、附件、SQLite 范围测试、模型/TRACE 备份排除已合并；混合数据库备份、旧共享临时图片和外部副本未闭环。
- F PARTIAL：TRACE 生命周期和 Native bridge 已合并；per-turn UI 生成、SQLite trace_id、阶段事件尚未接入。
- G PARTIAL：本审计文档正在刷新；README/pubspec/CI 版本一致性仍待自动检查。

### 12.4 后续顺序

1. 完成 PR #85 当前 head 的 Flutter regression、Android arm64 和 branch validation；失败按具体日志修复，不绕过。
2. PR #85 合并后立即推进 F2：统一聊天每轮 trace context、Native traced API 调用、assistant message metadata 持久化和清理测试。
3. E 继续审查清理 coordinator 的各域结果、Native cache、TRACE 文件和 Android 重启行为；不排除混合 SQLite 数据库。
4. B 继续做生产入口调用图和 fail-closed 契约；正式 detector 仍需医学审核，不编造规则。
5. D 继续从纯计算、无敏感数据页面挑选第二项 Headless 候选；不批量迁移 22 个页面。
6. Find N2 真机验收仍由本地设备执行，未收到真实 TRACE 前保持 UNKNOWN。


## 13. 2026-11-12 当前主线与并行执行续接（基线：`5f7bf738ad5894e2de7fd5903d8d6002e3fe6502`）

> 本节覆盖第 12 节之后的实际合并和当前 PR 状态。CI 只按精确 head SHA 认定；旧 head 失败/取消不能覆盖新 head，运行中不能标 PASS。

### 13.1 主线基线与已集成切片

- PR #85 已 squash merge：`yunqi` 增加 Headless executor，保留 Page builder；合并后的代码提交为 `b786f84df0452b9771e341c818e0d06a12451ef3`。
- PR #79 已 squash merge：审计报告、执行台账、能力清单和 TRACE 契约刷新；当前 master 为 `5f7bf738ad5894e2de7fd5903d8d6002e3fe6502`。
- PR #85 的 Flutter regression run `43156803669` SUCCESS；Android arm64 build/native unit tests SUCCESS；Branch validation SKIPPED。此处按完整 Flutter + Android 证据集成，SKIPPED 不单独计 PASS。
- PR #79 文档切片已合并；其代码基线没有替代主线测试。合并后 master workflows：Flutter Quality Gate run `43161470395` IN_PROGRESS；Flutter tests run `43161470467` PENDING。不得把旧 SHA 的成功结果冒充当前 master 全量 CI。

### 13.2 当前代码 PR 与 CI

| PR | 目标 | 最新 head | 当前 CI | 处理 |
|---|---|---|---|---|
| #86 | D：每日黄历 `almanac` Headless + Page | `18ecc81a4ff6a18757386d39632b9a8567ae8b37` | changed-test Branch validation run `43162555492` SUCCESS；PR Flutter regression run `43162562989` PENDING；Android arm64 尚待对应 job 结论 | 前一 head 的日期正则双重转义、测试 const map 编译错误已在当前 head 修正；等待新 head 全量验收，不跳过失败测试 |
| #87 | F：统一助手 per-turn trace_id、Native traced API 与 SQLite metadata | `abef4bb9dc09ed6f2e690a06bdc76669067b7432` | changed-test Branch validation run `43162523644` SUCCESS；PR Flutter regression run `43162529437` IN_PROGRESS；Android arm64 尚待对应 job 结论 | 等待当前 head 分析、Flutter 全量回归和 Android arm64；不继承旧 head 结论 |

PR #86 当前 base 仍记录为 `4100f153...`，master 已推进到 `5f7bf738...`；GitHub 当前 mergeable=true，changed-test 验证已通过，合并前仍须等待最新 PR 全量回归与 Android arm64。PR #87 直接以 `5f7bf738...` 为 base，changed-test 验证已通过。

### 13.3 D：Headless 能力当前状态

- 主线 Headless = 1：`yunqi`；主线 Executed = 1；其 Page builder 保留。
- PR #86 为第二个候选：复用 `getDailyAlmanac`，不复制历法算法、不读取用户命盘；显式日期/相对日由设备本地日历解析，日期与未知字段 fail closed；结果包含结构化字段、`local-engine:almanac` source ID 和民俗免责声明。
- #86 未合并前，主线仍只有 1 个 Headless。其余 Page-only 工具不得计为已执行。

### 13.4 F：TRACE per-turn 当前状态

- PR #87 复用默认关闭的 `AiTraceRuntime.recorder`；关闭时不生成 ID、不传 traced 参数、不在 SQLite metadata 增加 trace_id。
- TRACE 开启时，普通文本、图片、语音调用已有 traced Native API；Native 响应由 `LocalAiService` 验证回传 ID。
- 同一 ID 写入 user/assistant message metadata；未新增表/列；记录 input、native_inference、model_output、persistence、final_render 阶段。
- 独立症状提取入口也已使用 traced API 并记录 Native 结果，但草稿不持久化 trace_id。
- PR #87 尚未通过当前 head CI；结构化问诊、澄清/工具分支、检索阶段细分和设备 TRACE 仍未闭环。

### 13.5 A-G 当前状态与后续自动推进

| ID | 当前状态 | 下一步，不等待用户逐项点名 |
|---|---|---|
| A Native 多轮与生命周期 | PARTIAL / 真机 UNKNOWN | 复核 Activity teardown 串行队列和任务终态；继续 Find N2 GPU/CPU、图片/语音、多轮、重启实机 TRACE，不能用 CI 替代 |
| B 红旗安全 | PARTIAL / RELEASE BLOCKED | 完成所有调用入口旁路矩阵与 fail-closed 集成设计；自然语言 detector 词表、阈值和处置文案必须有医学审核，未审核不自行编造或放行 |
| C 检索来源与黄金行为 | PARTIAL | 按 subject/object/sourceId/原始位置/来源逐条审查候选身份与谓词分布；保持黄金快照，不为增加数量改排序 |
| D Headless 工具 | PARTIAL | 先完成 #86；之后只挑一个无敏感数据、已有确定性函数的工具继续，不批量抽象 |
| E 数据清理与备份 | PARTIAL | 继续审查旧共享 temp 图片无法归属的边界、混合 SQLite 的 AI 行备份影响及清理后进程重启；不误删非 AI 数据、不全局禁用备份 |
| F TRACE | PARTIAL | 完成 #87；之后接入 structured diagnosis / clarification / tool dispatch / retrieval / result presentation，保持默认关闭和正文零记录 |
| G 治理 | PARTIAL | 本次更新 inventory/ledger/report；补 README/pubspec/CI 版本单一来源检查，所有状态绑定最新 SHA 与 CI |

### 13.6 本轮集成硬门槛

1. #86/#87 均按各自最新 head 重新核对；任何失败先定位并修复，不得跳过或只跑 changed tests 后声称全量通过。
2. 每个代码 PR 合并后刷新 master SHA，再对后续 PR 重新核对 base、mergeability、CI。
3. 仅代码 + 自动化测试 + 目标设备 TRACE 三者齐全才可将设备相关能力标为 IMPLEMENTED。
4. 医学审核、Find N2 真机、旧附件归属和混合数据库备份边界未完成前继续标记 PARTIAL / UNKNOWN / RELEASE BLOCKED。


---

## 14. 2026-11-12 #86/#87/#88 集成后执行快照（master `eefa56e9cf159c5533de1c35556f82aa4c873a4f`）

### 14.1 本轮集成记录

| PR | 合并提交 | 交付 | 当前证据 |
|---|---|---|---|
| #86 | `870362ae8ba92e25b195c62d9fc0be653d19600f` | `almanac` Headless + Page | head `18ecc81a...`；Flutter run `43162562989` SUCCESS；Android arm64/merged manifest/Native unit tests SUCCESS；Branch validation SKIPPED |
| #87 | `34c1fa11c61b83d75b0c01ac6272a39d0cbf4537` | per-turn TRACE ID、Native traced API、message metadata | head `abef4bb9...`；Flutter run `43162529437` SUCCESS；Android arm64/merged manifest/Native unit tests SUCCESS；Branch validation SKIPPED |
| #88 | `eefa56e9cf159c5533de1c35556f82aa4c873a4f` | 审计报告、能力清单、台账更新 | head `68e4e9cc...`；Flutter run `43162775931` SUCCESS；Android arm64/merged manifest/Native unit tests SUCCESS；Branch validation run `43162770440` SUCCESS（文档专属 workflow） |

### 14.2 当前主线 CI

- master：`eefa56e9cf159c5533de1c35556f82aa4c873a4f`
- Flutter tests：run `43164417582`，IN_PROGRESS（本次记录时）。
- Flutter Quality Gate：run `43164416766`，IN_PROGRESS（本次记录时）。
- 父 SHA `5f7bf738...` 的旧 SUCCESS 不代替当前 SHA 验收；新主线两个 workflow 结束后更新本节，不得把 IN_PROGRESS 提前改为 PASS。

### 14.3 A-G 状态与下一步

- A PARTIAL：Native teardown 串行化、原子轮次持久化已有 CI；Find N2 GPU/CPU 各 20 轮、图片/语音、进程重启/Activity recreation TRACE UNKNOWN。下一步补 Native teardown 状态矩阵与真实设备验收。
- B PARTIAL / RELEASE BLOCKED：结构化 provenance 契约存在；自然语言 detector、所有模型/工具入口前置 fail-closed 和医学审核缺失。下一步完成全入口旁路矩阵、无审核规则时不返回 CLEAR 的纯 Dart gate contract；不自造医学词表。
- C PARTIAL：精确方剂检索和黄金快照已合并；按候选 subject/object ID、类型、文本、谓词、sourceId、原始位置、来源逐条审查，不以候选数量增加作为目标。
- D PARTIAL：主线 Headless = 2 / Executed = 2（`yunqi`、`almanac`）；其余 22 项仍 Page-only，结构化问诊为独立内联流程。下一步逐项核实确定性函数后每次只抽取一个 adapter。
- E PARTIAL：清理入口、AI-owned 附件、SQLite 清理边界与回滚测试、模型/TRACE 备份排除已合并；混合 SQLite 中 AI 行仍可能被备份、旧共享图片无法可靠归属、Android 清理后进程重启不可恢复证据缺失。
- F PARTIAL：per-turn trace_id 覆盖普通文本/图片/语音统一助手及 user/assistant metadata；structured diagnosis、clarification/tool dispatch、retrieval、result validation/render、失败轮次和真机 TRACE 未闭环。
- G PARTIAL：治理文档已刷新；README/pubspec 自动版本一致性 guard 未实现。

### 14.4 当前工作会话内的执行顺序

1. B：只读核验并建立五模式/所有入口旁路矩阵，先实现 fail-closed 状态契约和测试；医学规则等待审核。
2. F：在不改 B 的 Native 共享文件前提下，推进 Dart per-turn trace context 至 structured diagnosis/clarification/tool dispatch/retrieval/result validation。
3. E：审计清理 coordinator 的数据库、附件、Native cache、TRACE 清理结果；验证进程重启边界，不删除无法归属的旧共享图片。
4. C：继续候选身份/关系/来源逐条审查；黄金快照保留，任何语义变化必须对照记录。
5. A：补 Activity teardown 可注入状态测试；真实设备 GPU/CPU/媒体/恢复 TRACE 单独验收。
6. D：盘点剩余 22 个 Page-only 工具的确定性函数，按行为基线挑选一个最小 adapter。
7. G：增加 README/pubspec 单一版本来源检查和审计证据一致性检查。

### 14.5 约束

- 本轮未运行 Find N2 真机；设备相关项目继续 UNKNOWN。
- B 医学审核缺失，保持 RELEASE BLOCKED；不得自行生成医学规则。
- E 混合数据库备份与旧共享临时文件归属仍有风险；不得全局禁用备份或误删非 AI 数据。
- F 的已合并 per-turn TRACE 不是全链路完成证明。


---

## 15. 2026-11-12 #92/#97/#99/#100/#101/#102 集成后执行快照

### 15.1 主线与集成证据

当前主线基线：`master @ 2d2df1393cc5e77e6a7a8ce71f4fb52f11bf603c`。

| PR | 状态 | 交付 | 当前 head CI 证据 |
|---|---|---|---|
| #92 | MERGED | 修复玄学模式普通文本绕过 traced Native API 的路径 | head `bf7cefae...`；run `43165079874`：Flutter SUCCESS、Android arm64/ABI/Native unit tests SUCCESS；Branch validation SKIPPED |
| #97 | MERGED，merge commit `776a1e7af2c19815cf9d5d772e0bb7bb6720bf1d` | Orchestrator route/dispatch、Headless 参数校验/执行/结果校验/持久化/展示 TRACE | run `43167373011`：Flutter SUCCESS、Android arm64/ABI/Native unit tests SUCCESS；Branch validation SKIPPED |
| #99 | MERGED | 原始图片/录音来源 fail-closed，提示文字不能冒充附件已检查 | run `43168152545`：Flutter SUCCESS、Android arm64/ABI/Native unit tests SUCCESS；Branch validation SKIPPED |
| #100 | MERGED，merge commit `f4188927df3b15d3edfc553d3b113cbdfd5a68c9` | README/pubspec 版本检查进入 Flutter/Android CI；Release tag 与 pubspec 版本一致性门禁 | run `43168612465`：Flutter SUCCESS、Android arm64/ABI/Native unit tests SUCCESS；Branch validation SKIPPED |
| #101 | MERGED，merge commit `2d2df1393cc5e77e6a7a8ce71f4fb52f11bf603c` | structured diagnosis 启动、选项回答、舌脉提交和消息 metadata per-turn TRACE | run `43169514825`：Flutter SUCCESS、Android arm64/ABI/Native unit tests SUCCESS；Branch validation SKIPPED |
| #102 | MERGED，merge commit `cbd6ffc4973a6734856880ac64143a9a1d3d7e2d` | 83 个检索候选 Markdown 内容核验记录 | 文档 PR；不把它计为代码 CI 验收 |

- 以上 PR 的 Branch validation 均为 SKIPPED；不得把 SKIPPED 记为 PASS。对应代码 PR 的 Flutter regression 与 Android arm64/Native tests 均 SUCCESS。
- PR #90 的旧文档分支因主线文档已更新而关闭；以本次在最新 master 上追加的台账/报告为准，未用旧基线覆盖新内容。
- squash merge 后没有取得 `master` 独立 workflow run 证据；当前主线合并后 CI 状态记为 **UNKNOWN**，不能用 PR head CI 代替。

### 15.2 F：TRACE 当前覆盖

- 已有检索阶段与上下文组装阶段事件（`retrieval`、`contextAssembly`），以及统一助手 Native inference/model output 事件。
- PR #97 增加 Orchestrator route/dispatch；Headless 执行路径记录 argument validation、business execution、result validation、persistence、final render。Page Tool 记录 `NOT_STARTED`，不冒充业务执行。
- PR #101 为结构化问诊启动、每次选项回答、舌脉输入、结构化澄清分别建立/继承 per-turn trace context；新增消息 metadata 关联 trace_id；业务执行与持久化失败分别记录。
- Headless `cancelled` 现在记录 FAILED + `BUSINESS_EXECUTION_CANCELLED`，不再误记 SUCCEEDED。
- TRACE 仍默认关闭；未将正文、prompt、模型回复、症状、附件路径写入 trace events。
- F 仍为 PARTIAL：`persistedState`/恢复链路、模型响应结构验证、失败轮次完整持久化关联、历史恢复后的 trace 关联，以及 Find N2 真机 TRACE 尚未形成完整证据。

### 15.3 A-G 当前状态

| ID | 状态 | 已完成证据 | 未闭环项 |
|---|---|---|---|
| A Native 多轮与生命周期 | PARTIAL / 设备 UNKNOWN | 既有 teardown/原子轮次保护与 Android arm64 CI | Find N2 GPU/CPU 多轮、图片/语音、Activity recreation、进程杀死/重启恢复的真实 TRACE |
| B 红旗安全 | PARTIAL / RELEASE BLOCKED | fail-closed gate contract；原始 image/audio 即使有 prompt text 也返回 `RAW_ATTACHMENT_NOT_ASSESSED`；必须先有独立 `attachmentTranscript` 来源 | 经医学审核的自然语言 detector/规则集；所有生产模型入口旁路矩阵和模型调用前 fail-closed 集成证据。不得自造词表、阈值或处置文案 |
| C 检索来源 | PARTIAL | 83/83 source asset 存在且已逐项读文件；标题/正文命中层次记录于 `docs/classic-retrieval-golden-review.md` | 83/83 仍为 `bookId/chapterIndex` 缺失、locator MISSING；需逐条建立经人工核验的经典原文/版本/卷页来源 manifest |
| D Headless | 当前主线 2 项 Headless / 2 项 Executed | `yunqi`、`almanac`；两项均复用既有确定性函数并保留 Page builder | 不以数量为目标；剩余 Page-only 工具逐项审计，未找到满足边界的确定性候选前不新增 adapter |
| E 数据清理与备份 | PARTIAL | AI 数据清理范围审计、混合数据库边界和 Android backup manifest CI 检查 | 混合 SQLite 中 AI 行备份边界、旧共享临时图片归属、外部导出副本、Find N2 清理后进程重启与不可恢复证据 |
| F TRACE | PARTIAL | 普通文本/图片/语音、检索/上下文、Orchestrator/Headless、结构化问诊 per-turn TRACE | persistedState/恢复/失败关联、模型结果验证、Find N2 真机 TRACE |
| G 版本治理 | IMPLEMENTED（版本一致性子目标） | README 当前仓库版本与 pubspec 一致性脚本；Flutter regression 和 Android CI 执行；Release tag `vX.Y.Z` 必须匹配 pubspec `X.Y.Z+N` | 需要主线独立 CI 证据；不将历史 changelog 版本强行改成开发版本 |

### 15.4 下一阶段只保留必要工作

1. **F**：先完成 persistedState/恢复和失败轮次 trace 关联，再补模型响应结构验证；不再扩展新工具平台。
2. **A/E**：设备验收集中在 OPPO Find N2，验证 GPU/CPU、媒体输入、Activity recreation、进程中断/恢复、AI 数据清理后重启；CI 不能替代真机。
3. **B**：继续只读审计所有生产模型调用入口；无医学审核 detector 时保持 RELEASE BLOCKED，不允许通过默认 CLEAR 绕过。
4. **C**：仅补书目/底本 locator manifest；不改排序、召回上限或引入 FTS5。
5. **D**：当前两项 Headless 保持稳定；不为数量目标新增 adapter。
6. **G**：版本源 guard 已落地；后续只维护，不另造版本系统。


---

## 16. 2026-11-12 PR #93-#96 / #104 集成后执行快照

### 16.1 当前主线与 CI

- master：`d2d1250807a55a4912f9bda4aa65964d068a5896`（PR #104 squash merge）。
- PR #104：`feat(ai): trace structured persisted state and presentation`，merge commit `d2d1250807a55a4912f9bda4aa65964d068a5896`。
- PR #104 head `b47f27cc5dbc0679136940fb43fe3a354dc99d43`，run `43171252541`：Flutter regression SUCCESS；Android arm64 APK/ABI、merged backup manifest、Native unit tests SUCCESS；Branch validation SKIPPED。
- master push Flutter run `43175683193`：Flutter regression SUCCESS；Android arm64 job在本次记录时仍 IN_PROGRESS（仅剩 job 收尾步骤）。
- master Flutter Quality Gate run `43175683140`：Analyze and test / Find N2 arm64 build 在本次记录时仍 IN_PROGRESS。master post-merge CI 尚未全部结束，不写整体 PASS。

### 16.2 补齐此前遗漏的 #93-#96 主线证据

| PR | 合并提交 | 已集成范围 | 自动验收 |
|---|---|---|---|
| #93 | `9f995a30b38ecf171295615f10d09b5074836ac6` | fail-closed RedFlagGate contract、detector interface、source types | run `43165576958` Flutter + Android SUCCESS；Branch validation `43165568953` SUCCESS |
| #94 | `ce0d5fa650872559dfe3b15e8cd524e2c6ca3162` | retrieval/contextAssembly/modelInput TRACE；修复玄学普通文本 traced API 旁路 | run `43165512584` Flutter + Android SUCCESS；Branch validation `43165481369` SUCCESS |
| #95 | `b4cd3a91a10426e9c825188dd5e344e3bb4c48b3` | E 数据清除范围审计刷新 | run `43165925272` Flutter + Android SUCCESS |
| #96 | `b47397922d9348f89cc7a5586b7ca1b0659a63f5` | C 检索黄金 artifact 与候选身份结构核验 | run `43166311719` Flutter + Android SUCCESS |

### 16.3 A-G 当前状态

| 工作流 | 状态 | 已落地事实 | 尚未闭环 |
|---|---|---|---|
| A 多轮与 Native 生命周期 | PARTIAL / 设备 UNKNOWN | Activity teardown 串行化、SQLite 原子轮次、Native bridge 有自动化证据 | Find N2 GPU/CPU 长轮次、图片/语音、Activity recreation、进程中断/重启 TRACE |
| B 红旗安全 | PARTIAL / RELEASE BLOCKED | #93 的 fail-closed gate 在 detector 缺失、异常、超时、assessment/source 不完整时返回 REVIEW_REQUIRED | gate 未接入所有生产入口；无经医学审核的自然语言 detector/词表/阈值/处置文案；不得默认 CLEAR |
| C 检索来源 | PARTIAL | #96 真实 CI artifact：4 个 query、120 条 top-40 hits、83 个 distinct sourceId；sourceId 与 asset 一致；context 2199 字符、6 个 source IDs（formula 1、herb 1、lecture 4） | 120 条 locator 均 MISSING；仍需逐条核验古籍底本/版本/卷页。不得把讲稿资产当作古籍原文 |
| D Headless | PARTIAL | 主线 Headless/Executed = 2：`yunqi`、`almanac` | 其余 Page-only 能力不计 Headless；没有新的确定性候选前不扩展 |
| E 数据清理与备份 | PARTIAL | AI 清理 coordinator、AI-owned attachments、Native runtime cache、TRACE 文件、设置 UI、SQLite AI 四表事务及 Android 模型/TRACE 备份排除已有代码/CI 证据 | 混合 SQLite 中 AI 行仍可能备份；旧共享图片/外部导出副本归属未知；Find N2 清理后强制停止/重启不可恢复验收缺失 |
| F TRACE | PARTIAL | #94 retrieval/contextAssembly/modelInput；#97 route/dispatch/Headless stages；#101 structured per-turn；#104 structured persistedState/presentation。TRACE 默认关闭，正文不入事件 | 失败轮次与消息持久化关联、失败/恢复终态关联、完整模型结果验证审计和 Find N2 TRACE 仍未闭环 |
| G 版本/证据治理 | PARTIAL（版本源子目标已完成） | README/pubspec 版本一致性 guard、Flutter/Android CI 检查、Release tag 校验已合并 | 当前 master 的 post-merge CI 收尾；本轮文档证据同步 |

### 16.4 F 的当前代码边界

- #104 将结构化问诊任务快照/诊断历史写入阶段记录为 `persistedState`，消息行保存仍单独记录 `persistence`，界面追加/滚动后记录 `presentation`。
- #104 没有改变辨证规则、问诊结果、SQLite schema 或用户流程。
- 历史 `restoreConversation` 明确不是新的用户轮次；按 `docs/ai-trace-contract.md` 第 2.3 节恢复时保留原消息 metadata，不生成新 trace_id。违反该约束的尝试 PR #105 已关闭，未合并。
- 下一项 F 只处理真实用户轮次的失败状态与持久化关联；不得自动重放 Native 状态 UNKNOWN 的请求，不得把历史恢复伪装成新轮次。

### 16.5 下一批执行顺序

1. **F：失败轮次关联**：先锁定失败用户消息是否进入历史、`replayable` 语义和 UNKNOWN/FAILED 的持久化表示；只复用现有 metadata，不自动重放，不记录正文到 TRACE。
2. **B：生产入口门禁**：先完成所有调用入口注入顺序测试；detector 未经医学审核前保持 REVIEW_REQUIRED/RELEASE BLOCKED，不启用自造规则，也不静默阻断全部模式。
3. **C：来源 manifest**：仅补可由原始底本证据确认的书目/卷页定位；证据不足继续 MISSING，不改召回和排序。
4. **A/E：Find N2 设备验收**：GPU/CPU、媒体、多轮、Activity/进程恢复、清理后重启；CI 不能替代设备 TRACE。
5. **D/G**：Headless 维持 2 项；版本 guard 只维护，不另造系统。

### 16.6 本轮 PR 队列

- PR #104：MERGED。
- PR #105：CLOSED / NOT MERGED。原因：为 `restoreConversation` 新建 trace_id 违反 `ai-trace-contract.md` 第 2.3 节；该路径是历史上下文恢复，不是用户轮次。
- PR #98：仍是基于旧 master 的文档分支，behind 当前主线；本轮后续文档刷新应从最新 master 重建，不合并旧基线。
- 本轮不创建定时任务或会话外周期性监控。
