# AI 改造执行台账（约束性跟踪文件）

> 本文件与 [全局 AI 能力审计与改造执行约束](ai-capability-audit.md) 配套使用。
> `ai-capability-audit.md` 定义不可绕过的架构边界与验收门槛；本文件记录每一工作流的当前状态、证据、阻塞和下一步。
> 状态必须由实际源码、测试、CI 或设备记录更新。不得根据计划、代码文件存在或模型回复推定完成。

## 1. 当前核验基线

| 项目 | 当前值 | 说明 |
|---|---|---|
| 仓库 | `just2512/nihaixia-app` | Fork 独立仓库 |
| 主分支 | `master` | 集成基线；每个实现切片从 master 派生独立工作分支，按小批量 PR 集成 |
| 本台账建立时 HEAD | `78f8f2bda9adb3adcb74ff46984c9a06284a2f58` | 约束文件更新提交 |
| 应用版本 | `1.11.30+8039` | 以 `pubspec.yaml` 为准 |
| README 版本说明 | `1.11.30+8039` | 已与 `pubspec.yaml` 同步；由版本源 guard 持续检查 |
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
| B | 全模式红旗安全门禁 | `PARTIAL / RELEASE BLOCKED`（fail-closed Gate 契约存在；医学审核 detector 与生产入口接入缺失） | 与 A/C/E 并行 | 所有模型/业务路由入口前置确定性门禁；歧义澄清；医学词表审核；正反向测试通过 |
| C | 知识检索黄金行为基线 | `PARTIAL`（黄金快照和 sourceId/asset 一致性已建立；书目 locator 仍缺失） | 与 A/B/E 并行 | 桂枝汤组成 + 《伤寒论》条文黄金用例有原始检索与展示记录；抽适配器前后行为可比较 |
| D | Headless Capability 盘点与最小适配器 | `PARTIAL`（6 项 Headless；17 项 Page-only；结构化问诊独立内联） | 目录审计可并行；适配器须等待对应基线 | 每项能力有输入/输出 schema、校验、权限、取消/错误语义及真实执行证据 |
| E | 低成本数据保护 | `PARTIAL`（Manifest/清理代码有 CI 证据；真机清除后重启不可恢复未验收） | 与 A/B/C 并行 | Android 备份配置核验、清除全部 AI 数据、附件缓存生命周期与重启后不可恢复验证 |
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


---

## 17. 2026-11-12 PR #106/#107 集成后执行台账

### 17.1 主线基线与 CI

- 当前 master：5a9d2c7fccd4b291982d39699fe929eaa968a6fe。
- PR #106：merge commit fb315306bf76dd1a3545b50758e92214e888cac0（台账刷新）。
- PR #107：merge commit 5a9d2c7fccd4b291982d39699fe929eaa968a6fe。
- PR #107 head：db6309d29e847fe9c4bad3c53921d240f681fcdd；run 43187508718：Flutter regression SUCCESS；Android arm64 APK/ABI、merged backup manifest、Native unit tests SUCCESS；Branch validation SKIPPED。
- master push runs：Flutter Quality Gate 43195424227、Flutter tests 43195424259；本次记录时均 IN_PROGRESS。必须等待这两个 run 结束，不能用 PR head SUCCESS 代替。

### 17.2 本轮 F 工作完成项

PR #107 修复失败轮次阶段误归因：
1. 成功 Native inference 与 resultValidation 分开记录。
2. EMPTY_REPLY 记录 Native 已完成、resultValidation FAILED；trace ID mismatch 保持 UNKNOWN。
3. Native 失败时 persistence 记录 NOT_STARTED 和 conversationId；不将未持久化的输入写入历史。
4. persistence 已开始但状态不确定时记录 UNKNOWN；明确返回失败记录 FAILED。
5. 症状整理路径分别记录 Native inference 与 resultValidation 状态。
6. 手动重试仍生成独立 trace_id；不自动重放 UNKNOWN 请求。
7. 未改 SQLite schema、用户流程或历史 restore 语义。

### 17.3 A-G 最新状态

| ID | 状态 | 当前结论 / 未闭环 |
|---|---|---|
| A | PARTIAL / 设备 UNKNOWN | Find N2 GPU/CPU、多轮、媒体、Activity recreation、进程重启真实 TRACE 缺失 |
| B | PARTIAL / RELEASE BLOCKED | Gate contract/test 已有；无自然语言 detector、医学审核规则集、生产入口调用和 Native 纵深门禁 |
| C | PARTIAL | 83/83 lecture assets 存在可读，但 83/83 bibliographic locator MISSING；12 条 combinedPatterns 来源记录与代码中的 12 个 conditionKey 精确一一对应、无重复；其中 7 online text cross-checked、3 conditions cross-checked、2 MISSING；纸本版次/卷页/影像 12/12 缺失 |
| D | 2 Headless / 2 Executed | yunqi、almanac；不为数量扩展 |
| E | PARTIAL | 混合 SQLite AI 行备份、旧共享图片归属、外部副本、清理后真机重启不可恢复证据缺失 |
| F | PARTIAL | #107 已补失败轮次 Native/resultValidation/persistence 状态；结构化问诊、工具、恢复全链路及设备 TRACE 仍缺 |
| G | 版本源子目标 IMPLEMENTED | 当前 master 的独立 post-merge workflows 尚未结束 |

### 17.4 下一批仅保留以下必要工作

1. **B：安全入口**：完成 Flutter/Native 入口调用顺序矩阵和可注入 gate seam 测试；不创建未经医学审核的 detector，不默认 CLEAR，也不擅自全局阻断现有产品能力。医学审核与设备验收未完成前继续 RELEASE BLOCKED。
2. **C：来源核验**：对 83 个 sourceId 保留 ASSET_EXISTS 与 BIBLIOGRAPHIC_LOCATOR_MISSING 的区分；为 12 条规则逐条核验可取得的底本/版本/卷页/影像；证据不足保持 MISSING。检索行为冻结，不改 query/排序/top-40/去重。
3. **A/E：设备和数据边界**：Find N2 真机验证 GPU/CPU 多轮、图片/语音、Activity/进程恢复、清理后强停重启；同时核实混合 SQLite 备份和旧共享附件归属，不误删、不全局关闭备份。
4. **F：TRACE**：后续只补真实用户轮次缺失节点；历史 restore 不生成新 trace_id；不扩展通用 Agent/工作流平台。
5. **D/G**：保持当前能力和版本 guard，不新增无证据 adapter 或第二套版本系统。

### 17.5 执行约束

- 每次代码 PR 以最新 master 为基线，先核对 compare/mergeability，再按最新 head 检查 Flutter 全量回归与 Android arm64/Native CI。
- master 合并后独立 workflow 未完成前，状态为 IN_PROGRESS/UNKNOWN，不写 PASS。
- CI、模拟设备、静态代码不能替代 Find N2 真机 TRACE。
- 医学审核、真机硬件、纸本底本/原始影像属于外部证据依赖；不能由代码或模型自我生成。
- 不创建定时任务；本轮只在实际执行时检查 CI。

---

## 18. 2026-11-12 PR #109 红旗门禁调用顺序契约集成

### 18.1 主线与自动验收

- 基线：PR #109 以 master `cf83cf03478ea4fede960d16b903630a466d1253` 为 base。
- PR #109：`feat(ai): add red-flag gate operation sequencing seam`，已 squash merge。
- 合并提交：`00258671cf87188ac7ef82f5121c6f5bea48ef7e`。
- PR head：`591d9b9c25d2c62d41e8a0b3b1ffb91180650f50`。
- Flutter 全量回归与 Android arm64 APK/ABI、merged backup manifest、Native unit tests：run `43200924284`，必要 job 均 SUCCESS。
- 独立 branch validation（静态分析 + changed tests）：run `43200883925`，SUCCESS。
- PR run 内 Branch validation job 为 SKIPPED；该 job 不计 PASS。独立 branch validation run 已成功。
- 合并提交的独立 push workflow run 尚未取得可核验证据；post-merge CI 状态保持 UNKNOWN，不以 PR head CI 替代。

### 18.2 本次代码交付与边界

- `lib/services/red_flag_gate.dart` 新增泛型 `RedFlagGateRun<T>`，显式区分 blocked/executed，并提供 `RedFlagGateExecution.runBefore`。
- `test/red_flag_gate_test.dart` 覆盖 gate 先于副作用、detector 缺失时不执行副作用、原始图片附件不能绕过评估。
- 本次未增加医学词表、阈值、detector 或急救文案；未接入任何 Flutter/Native 生产入口；未改变现有用户流程。
- 该 PR 只证明可复用的调用顺序契约，不证明真实入口已受保护，不证明自然语言红旗识别准确性。

### 18.3 B 工作流当前状态

- Gate sequencing contract：CODE + TEST + PR CI 已通过。
- 自然语言 detector 与医学审核：MISSING。
- Flutter 生产入口（普通发送、结构化问诊、工具分发、附件、症状整理）：未接入，MISSING。
- Native MethodChannel 纵深入口：未接入，MISSING。
- Find N2 真机入口 TRACE：UNKNOWN。
- B 继续 PARTIAL / RELEASE BLOCKED。

### 18.4 下一步与明确阻塞

1. B2 继续核对并设计统一可注入 seam，覆盖 `_send`、结构化问诊选项、工具分发、文本/图片/语音、症状整理和 Native MethodChannel；测试必须断言门禁严格早于 route/tool/model side effect。
2. 不允许把可选 Gate 缺省为空后继续执行作为“已接入”；这会形成安全旁路。
3. 当前 Gate 在 detector 缺失时返回 REVIEW_REQUIRED。若直接接入所有生产入口，将阻断现有 AI 流程；在没有医学审核 detector 和明确产品影响决策前，不得擅自全局启用，也不得默认 CLEAR。
4. 因此 B2 的生产行为接入暂 BLOCKED；可继续做不改变产品行为的调用链审计、测试 seam 设计和独立工作，但发布状态维持 RELEASE BLOCKED。
5. A/E 真机验收仍依赖 Find N2；C 的普通学习来源回链已有证据，只有指定原文/诊断规则来源需要继续核验；D/G 不扩展。旧的红旗入口审计分支和策略测试分支分别落后当前 master 56 commits，禁止直接合并；如复用内容，必须在最新 master 上重新审查和移植。



---

## 19. 2026-11-12 PR #113/#114/#115 集成后执行快照

### 19.1 当前主线与代码集成

- 当前主线：`master @ bfb518ef68bfc674d1af9699e410f4729dbbc3bc`。
- PR #113：`test(ai): cover rejected Headless result TRACE terminal states`，merge commit `1b13dea7d1b239089d7d14e2810febf9a6f343bf`。
- PR #114：`fix(ai): trace Page Tool result continuation`，merge commit `bb7d2897105c0a52577924ea3d35ccee8ea735cf`。
- PR #115：`fix(ai): close send and symptom TRACE final states`，merge commit `bfb518ef68bfc674d1af9699e410f4729dbbc3bc`。
- 三项均以当时最新 master 为 base，按独立分支、小批量集成；没有改写 `ai-capability-audit.md` 的约束条文。

### 19.2 PR 与 CI 证据

| PR | 独立分支验证（push） | PR 全量验收 | 结果 |
|---|---|---|---|
| #113 | run `43217158541` SUCCESS | run `43214895957`：Flutter regression、Android arm64 APK/ABI、merged backup manifest、Native unit tests SUCCESS | MERGED |
| #114 | run `43217978870` SUCCESS | run `43217988520`：Flutter regression、Android arm64 APK/ABI、merged backup manifest、Native unit tests SUCCESS | MERGED |
| #115 | run `43219357882` SUCCESS | run `43219648145`：Flutter regression、Android arm64 APK/ABI、merged backup manifest、Native unit tests SUCCESS | MERGED |

说明：上述 PR workflow 中 Branch validation job 为 `SKIPPED`，不计作分支验证通过；表中的独立 push run 才是静态分析与 changed-tests 的分支验证证据。

当前最新主线 `bfb518e` 的独立 post-merge workflow：
- Flutter Quality Gate：run `43221099813`，本次台账更新时 `IN_PROGRESS`。
- Flutter tests：run `43221099907`，本次台账更新时 `PENDING`。
- 必须以这两个 run 对应 `bfb518e` 的终态更新主线 CI；不得用 PR head CI 替代 post-merge CI。若后续有新 master commit，改查新 SHA 的两条 workflow。

### 19.3 F：本轮 TRACE 断点修复

1. **PR #113 — Headless 结果契约负向路径**
   - 通过注入 toolId 不匹配的 typed result，直接执行 `RESULT_CONTRACT_INVALID` 分支。
   - 断言 `resultValidation=FAILED`、`persistence=NOT_STARTED`、`finalRender=SUCCEEDED`，并确认无错误结果写入会话。
   - 本项补的是失败分支证据，不以既有成功路径测试代替。

2. **PR #114 — Page Tool 延续同一用户轮次**
   - Page Tool 请求按钮回调携带原请求 `trace_id`；页面返回的结构化结果、结果消息 metadata 继续使用同一 ID。
   - 记录页面执行、业务执行、结果契约验证、SQLite persistence、persisted state 与 final render。
   - 历史恢复时仅复用消息中已有的 `trace_id`；旧消息没有 ID 时保持 TRACE disabled，不为历史恢复伪造新用户轮次。
   - 区分 SQLite 消息持久化与 Native `restoreConversation` 上下文重建；上下文恢复成功不能冒充 SQLite 已持久化。

3. **PR #115 — 普通发送与症状整理终态**
   - 症状整理的空结果、用户取消、确认成功、Native 异常、输出格式错误及页面卸载路径均记录 `finalRender` 终态。
   - 普通发送的模型未就绪提前退出、页面卸载、Native 平台异常和通用异常路径补齐最终展示状态；不改变模型路由、对话写入或业务结果。
   - 自动回归覆盖症状整理空结果与确认成功、Native 发送异常的最终错误展示；模型未就绪按钮在当前 UI 会禁用，保留 race-safe 代码门禁，不伪造不可达的按钮交互测试。

**F 当前结论：** 本轮已补齐上述可复现的 Headless 结果拒绝、Page Tool 结果延续、普通发送/症状整理终态断点，并有 CODE + TEST + PR CI 证据。但 F 仍为 `PARTIAL`：Find N2 真机 TRACE、GPU/CPU 多轮、媒体输入、Activity/进程恢复以及完整场景集的逐场景 trace 仍未取得；不能因为自动化通过就标记 `IMPLEMENTED`。

### 19.4 A-G 当前状态

| ID | 当前状态 | 已有证据 | 未闭环项 |
|---|---|---|---|
| A Native 多轮与生命周期 | PARTIAL / 设备 UNKNOWN | teardown、轮次状态、历史恢复与 Native bridge 有自动化回归；当前 master Flutter/Android CI 持续验收 | Find N2 GPU/CPU 多轮、图片/语音、Activity recreation、进程杀死/重启后 transcript 一致性真实 TRACE |
| B 红旗安全 | PARTIAL / RELEASE BLOCKED | `RedFlagGate` fail-closed contract、gate-before-operation sequencing contract 与 raw attachment 边界已测试 | 经医学背景人员审核的自然语言 detector/规则集；Flutter/Native 所有生产入口强制调用；真实入口顺序 TRACE。不得默认 CLEAR |
| C 检索来源 | PARTIAL / NOT VERIFIED | 83/83 本地讲稿资产存在且已逐项读取；sourceId 与 asset 一致；12 条 combinedPatterns 来源行与 conditionKey 对应 | 83/83 bibliographic locator 仍 MISSING；12 条规则的纸本底本/版次/卷页/影像仍缺；讲稿不得冒充古籍原文 |
| D Headless Capability | 2 项 Headless / 2 项 Executed | `yunqi`、`almanac` 复用确定性业务函数 | 保持现状；没有可验证的新确定性业务函数与行为基线前不增加 adapter |
| E 数据保护 | PARTIAL | AI 数据清除 coordinator、AI-owned attachments、Native runtime cache、TRACE 文件、SQLite AI 表边界和 Android 模型/TRACE backup manifest 有代码/测试证据 | 混合 SQLite AI 行备份、旧共享图片归属、用户外部导出/备份副本及 Find N2 清理后强停/重启不可恢复实测 |
| F TRACE | PARTIAL | #113 Headless 负向结果终态；#114 Page Tool 结果延续；#115 普通发送与症状整理 finalRender 终态；既有检索/上下文、Orchestrator、结构化问诊 per-turn TRACE | Find N2 场景集全链路 TRACE、多轮/恢复/媒体真实设备证据；任何未执行场景保持 UNKNOWN |
| G 版本/证据治理 | 版本源子目标 IMPLEMENTED | README/pubspec 版本一致性 guard、Flutter/Android CI、Release tag 校验已合并 | 当前 `bfb518e` 的独立 post-merge Flutter tests 与 Quality Gate 尚在执行，按 19.2 记录终态 |

### 19.5 下一阶段：只推进剩余硬门槛

1. **先收尾当前主线 CI**：等待 `bfb518e` 的 run `43221099813` 与 `43221099907` 结束；如失败，只修复失败 job 实际指向的问题，不扩大范围。
2. **A/E 真机验收**：按 `docs/local-ai-e4b.md` 和数据清除验收约束，在 OPPO Find N2（PGU110，16 GB）执行内外屏、GPU/CPU、连续多轮、图片/语音、Activity/进程恢复、AI 数据清除后强停/重启复查；没有设备记录、模型/backend 版本和 trace_id 的场景标 UNKNOWN。
3. **B 医学审核阻塞**：继续保持 RELEASE BLOCKED。需要医学审核 detector/规则集和产品对 REVIEW_REQUIRED 影响的明确决策；完成前不接入会默认阻断现有全部 AI 流程的生产 gate，也不允许 optional gate 缺失时跳过。
4. **C 原始来源核验**：仅接受可回链到真实底本、版次、卷页或原始影像的证据；证据缺失继续 MISSING，不调整 query 派生、top-40、排序、去重或引入 FTS5。
5. **D/G 不扩展**：Headless 保持 2 项；版本 guard 仅维护，不另建系统。

### 19.6 执行边界

- CI、静态代码和模拟环境不能替代 Find N2 真机 TRACE。
- 医学审核、原始纸本/影像、物理设备和外部备份副本属于外部证据依赖；不得由代码或模型自我生成。
- 不把本轮 F 的局部断点修复夸大成 P0–P5 全部关闭；整体仍受 A/B/C/E/F 的真机或外部证据门槛约束。
- 本轮没有增加 Agent/DAG、数据库表、模型/API、检索引擎或新的 Headless adapter。


---

## 20. 2026-11-12 PR #117 结构化问诊批量原子持久化集成

### 20.1 主线与 CI 证据

- 主线基线：`master @ 872a715a3817a57c8b4dd708a33f6b3a13c428c0`。
- PR #117：`fix(ai): persist structured interview transcript atomically`；merge commit `872a715a3817a57c8b4dd708a33f6b3a13c428c0`。
- 独立分支 push run `43237866155`：静态分析与 changed tests SUCCESS。
- PR run `43238225000`：Flutter regression SUCCESS；Android arm64 APK/ABI、merged backup manifest、Native unit tests 及证据上传 SUCCESS。PR workflow 的 Branch validation job 为 SKIPPED，不单独计为 PASS。
- 合并后的主线独立 workflow：Flutter tests run `43239874217`、Flutter Quality Gate run `43239874208`。本节初次更新时两者均为 IN_PROGRESS；必须等待这两个 run 对应 `872a715` 的终态，不用 PR head CI 代替 post-merge CI。

### 20.2 本次代码交付与证据

1. `AssistantMessageDraft` 定义有序消息草稿；`AssistantConversationStore.saveAssistantMessagesAtomically()` 作为现有接口的批量持久化边界。
2. `DatabaseHelper.saveAssistantMessagesAtomically()` 在一个 SQLite transaction 中完成全部 `assistant_messages` 插入以及 `assistant_conversations` 的 title/preview/updated_at 更新；后续任意一条插入或元数据更新失败，整批回滚。
3. 既有 `saveAssistantTurn()` 改为调用批量事务，保持原有 user/assistant 双消息原子写入语义；没有 schema migration、没有新表。
4. 结构化问诊 `_appendTcmInterviewMessages()` 将本次新增 transcript 一次提交；批次失败时不留下前几条消息的半轮历史，并向用户显示历史记录可能不完整的明确提示。
5. 任务快照与 transcript 消息持久化分别处理、分别记录：批量消息保存失败不伪装为消息已持久化；若任务快照本身成功，`persistedState=SUCCEEDED` 可以与 `persistence=FAILED` 同时存在。

**测试证据：**
- `test/assistant_history_persistence_test.dart`：批量成功路径验证消息顺序、metadata trace_id、conversation title 和最终 preview；SQLite trigger 在后续消息插入时注入失败，断言前序消息与 conversation metadata 全部回滚。
- `test/local_ai_interview_screen_test.dart`：注入消息批次失败，断言没有半轮消息、问诊 task snapshot 独立保存、UI 有可见警告，TRACE 为 `persistence=FAILED`、`persistedState=SUCCEEDED`、`finalRender=SUCCEEDED`。
- PR #117 全量 Flutter regression 和 Android arm64/Native CI 均 SUCCESS；合并后的主线 post-merge CI 仍以 20.1 的 run 终态为准。
- 本次没有修改 DiagnosticEngine、DiagnosticRules、方剂规则、问诊提示词、检索排序、红旗策略、Native 模型行为或数据库 schema。

### 20.3 A-G 当前状态

| 工作流 | 当前状态 | 已新增证据 | 未关闭项 |
|---|---|---|---|
| A 多轮与持久化 | PARTIAL | 结构化问诊 transcript 批次原子写入；assistant user/assistant turn 复用事务；SQLite trigger 回滚测试；PR/Android CI 通过 | Find N2 GPU/CPU 多轮、媒体、Activity recreation、进程终止/恢复后的真实 TRACE；不能用 SQLite FFI 或 CI 替代真机 |
| B 红旗安全 | PARTIAL / RELEASE BLOCKED | `RedFlagGate`/`RedFlagPreflight` 的纯策略与 fail-closed contract 存在；PR #109 的 `runBefore` 只证明通用 operation 顺序 | 自然语言 detector、医学审核规则/阈值/文案、实际 Flutter/Native 生产入口覆盖均 MISSING |
| C 检索来源 | PARTIAL / NOT VERIFIED | 83 个本地资产可存在性回链；12 条规则来源 manifest 有状态分类 | 83/83 bibliographic locator 仍 MISSING；纸本版本、卷页和原始影像未核验；不得改 query、top-40、排序、去重 |
| D Headless | 2 Headless / 2 Executed | `yunqi`、`almanac` | 保持 2 项；无独立行为基线前不新增 adapter |
| E 数据保护 | PARTIAL | AI 数据清理和 Android backup manifest 有自动化证据 | 混合 SQLite AI 行备份边界、旧共享附件归属、外部副本、Find N2 清理后强停/重启不可恢复实测 |
| F TRACE | PARTIAL | #113 Headless reject、#114 Page Tool continuation、#115 send/symptom finalRender、#117 structured transcript persistence failure 状态区分 | Find N2 完整场景集、多轮/媒体/Activity/进程恢复真实 TRACE 仍缺 |
| G 版本治理 | VERSION GUARD IMPLEMENTED | README/pubspec/Flutter/Android/Release tag 一致性 guard；#117 主线正在运行新的 post-merge CI | 以 `872a715` 的 run `43239874217` 与 `43239874208` 终态更新 |

### 20.4 B2 全入口静态复核（基线 `872a715`）

这部分是源码调用图复核，不代表红旗门禁已接入：

| 输入/执行入口 | 当前源码定位 | 当前执行顺序 | RedFlagGate/Preflight 生产调用 |
|---|---|---|---|
| `initialPrompt` | `LocalAiInterviewScreen.initState()` 约 286 行 | 只预填输入框；用户提交后进入 `_send()` | 无；它不是自动模型调用入口 |
| 普通文本/五模式 | `_send()` 约 3079 行 | 活动结构化问诊分支 → `AssistantConversationOrchestrator.resolve()` 约 3202 行 → 澄清/工具/模型 | 无 |
| 结构化问诊选项 | `_handleTcmInterviewOption()` 约 1571 行；`_send()` 的活动任务分支直接调用 | `controller.answerOption()` → `_appendTcmInterviewMessages()` → transcript/task-state persistence | 无 |
| 结构化问诊启动 | `_requestTool()` 约 2135 行 → `_startInlineTcmInterview()` 约 1130 行 | 进入既有确定性问诊 controller | 无 |
| Headless 工具 | `_executeHeadlessTool()` 约 1977 行 | 业务 executor → typed result → 结果校验/持久化/展示 | 无 |
| Page Tool | `_requestTool()` → `_openTool()` 约 2382 行 | 用户点击后打开既有 Widget 页面 | 无 |
| 图片/语音 | `_send()` 约 3317/3327 行；`LocalAiService` `_sendAttachment()` 约 154 行 | Dart MethodChannel → Native `sendImage`/`sendAudio` handler（`MainActivity.kt` 约 105/122 行）→ `sendLocalImage`/`sendLocalAudio`（约 677/704 行） | 无 |
| 症状整理 | `_extractSymptoms()` 约 3622 行；`LocalAiService._extractSymptoms()` 约 218 行 | MethodChannel `extractSymptoms` → Native handler 约 94 行 → `extractSymptoms()` 约 729 行 | 无 |
| 文本模型调用 | `_sendTextWithKnowledgeContext()` 约 900 行；`LocalAiService._sendTextMessage()` 约 55 行、`_sendMessageWithContext()` 约 94 行 | Orchestrator/检索完成后 MethodChannel `sendMessage` → Native handler 约 139 行 → `sendLocalMessage()` 约 487 行 | 无 |
| 历史恢复 | `_restoreVisibleConversationToModel()` 约 2247 行；`LocalAiService.restoreConversation()` 约 270 行 | 历史 transcript 回放到 Native Conversation；不是新用户轮次 | 无；历史来源/主体/时间必须保持 provenance，不能重标为当前本人症状 |

静态复核同时确认：
- `local_ai_interview_screen.dart`、`local_ai_service.dart`、`MainActivity.kt` 均没有 `RedFlagGate`、`RedFlagPreflight` 或 `RedFlagDetector` 生产引用。
- `RedFlagGate.runBefore()` 目前只定义通用 fail-closed operation seam；它不证明上述生产入口已经经过 gate。
- Native MethodChannel 是独立模型调用边界；仅在 Flutter 页面层做检查不足以覆盖 Native 直接入口。
- 原始 image/audio attachment 不能用 prompt 文本冒充已评估；`restoreConversation` 是历史上下文恢复，不应当作新的当前症状输入。
- 不得在 detector 未配置时把 `REVIEW_REQUIRED` 改成 `CLEAR`，也不得通过可选 gate 缺失静默跳过。医学审核及产品对 REVIEW_REQUIRED 影响的决策完成前，不接入会无差别阻断现有全部模式的生产 Gate。

### 20.5 下一阶段执行顺序

1. **收尾 `872a715` 主线 CI**：等待 Flutter tests `43239874217` 与 Flutter Quality Gate `43239874208`；如失败，只定位失败 job，不扩展范围。
2. **B2**：基于 20.4 的实际调用图继续完成可注入入口顺序 seam 的设计与测试；不能用可选/null gate 形成旁路，也不能在无医学审核时伪造 detector。生产行为接入继续 BLOCKED，直到医学审核与产品影响决策有记录。
3. **A/E**：Find N2 实机验证 GPU/CPU、连续多轮、图片/语音、Activity/进程恢复，以及 AI 数据清除后强停/重启不可恢复。没有真实设备、模型/backend、App SHA 和 trace_id 的场景维持 UNKNOWN。
4. **C**：只接受可回链到真实底本、版本、卷页或原始影像的书目证据；没有证据继续 MISSING。
5. **D/G**：保持两项 Headless 和当前版本 guard，不增加无证据支持的 adapter 或新的版本治理。

### 20.6 执行边界

- PR #117 提升了结构化问诊消息持久化的一致性，不代表 Find N2 多轮/进程恢复已验收。
- PR/主线 Android arm64 APK 是 ABI/build 证据，不是 OPPO Find N2 实机运行证据。
- B 的 Gate policy tests 不等于医学 detector 准确性或生产入口覆盖。
- 本轮没有引入新的 Agent/DAG、数据库表、模型/API、检索引擎或医疗规则。


---

## 21. 2026-11-13 PR #117/#119/#120 集成后执行快照

### 21.1 当前主线与代码集成

- 当前主线：master @ 849ec817f6e11f154ea662316b32b2fbfa230ffc。
- PR #117：结构化问诊 transcript 原子批量持久化，merge 872a715a3817a57c8b4dd708a33f6b3a13c428c0。
- PR #118：执行台账更新和 B2 全入口静态调用图，merge 2ddbd43b14f4c90d3a328eb53108e2d90d894d03。
- PR #119：transcript 与 task snapshot TRACE 分离，merge 5d73161b49fd3f38ffada31c0da1b06e7d24bec0。
- PR #120：Native Activity release failure fail-closed，merge 849ec817f6e11f154ea662316b32b2fbfa230ffc。
- 四个 PR 均使用独立分支、小范围集成和自动验收；没有直接推送 master，没有修改 ai-capability-audit.md 约束文件。

### 21.2 PR #120 关闭的确定性故障

旧 Activity 销毁时，releaseLocalModel() 若在 Conversation/Engine close 时失败，异常虽被 lifecycle 捕获，但 MainActivity 未提供 release error handler，也没有进程级健康状态。新 Activity 随后仍可能在同一单线程 executor 中创建另一套 Engine，而旧 Native 资源是否释放已经 UNKNOWN。

本次最小修复：
1. 新增 LocalAiProcessHealth，首次 Native release failure 会将当前进程标记为不可用。
2. LocalAiProcessExecutor 持有进程级共享 health；每个 Activity 的 lifecycle 都使用同一状态。
3. LocalAiActivityTaskLifecycle.submit() 在入队前和任务真正出队执行前各检查一次 health，覆盖新 Activity 已排队、旧 Activity release 随后失败的竞态。
4. 后续模型操作/模型导入返回 LOCAL_AI_RUNTIME_RELEASE_FAILED；teardown error 写入 Native log。
5. 用户被明确提示：在系统设置中强行停止 App 进程，再重新打开。当前进程不会通过重新创建 Activity 自动清除 unavailable 状态。
6. 正常释放路径保持单线程串行顺序和 exactly-once release；没有更改 GPU/CPU fallback、推理参数、模型文件、history policy 或数据库 schema。

新增 Kotlin 回归 LocalAiActivityTaskLifecycleTest.releaseFailureBlocksWorkQueuedByARecreatedActivity 使用 latch 固定竞态：阻塞旧 Activity release，确认新 Activity task 已入队后再触发 release failure；断言 queued task 未执行、收到 unavailable 回调、后续提交立即被拒绝。既有正常 teardown 顺序和 exactly-once 测试继续通过。

### 21.3 PR #120 CI 证据

最新 PR head：9ed99aa66f2047b985682ff4df9dd425647600b5。

- Flutter regression run 43342006102 / job 131612308210：SUCCESS。
- Android arm64 CI job 131614130546：SUCCESS。
- arm64 Debug APK build、merged backup manifest、ABI/SHA-256：SUCCESS。
- Android Native unit tests、XML 报告校验、APK/测试报告上传：SUCCESS。
- Branch validation job：SKIPPED，不单独计为 PASS。
- PR #120 已合并，merge commit 849ec817f6e11f154ea662316b32b2fbfa230ffc。

早期 head 43ebdb5931111ae75631a4a2942514f65e32371f 曾因 Kotlin constructor 参数顺序与既有 trailing-lambda 调用不兼容而在 compileDebugUnitTestKotlin 失败。已将可选 processHealth 参数放在 release lambda 之前，最终 head 9ed99aa 的完整 Flutter/Android 验收成功。早期失败 head 不作为最新验收结果。

合并后的主线 post-merge CI：
- Flutter tests：run 43343151516，head 849ec817f6e11f154ea662316b32b2fbfa230ffc。
- Flutter Quality Gate：run 43343151619，head 同上。
- 本节初次更新时两条 run 均为 IN_PROGRESS；必须按终态回填，不能用 PR head CI 代替 post-merge CI。

### 21.4 A-G 当前状态

| 工作流 | 当前状态 | 已有代码/自动化证据 | 未关闭项 |
|---|---|---|---|
| A Native 多轮与持久化 | PARTIAL | #117 普通成功轮次和结构化问诊 transcript 使用 SQLite 原子 batch；#119 分离 transcript 与 task snapshot TRACE；#120 Native release failure fail-closed；PR/Android CI 通过 | Find N2 GPU 至少 20 轮、CPU 至少 20 轮、图片/语音、Activity recreation、进程强停/重启、SQLite/UI/Native history 逐轮对照仍无实机 TRACE；state:7 根因 UNKNOWN；context budget 不得凭猜测设阈值 |
| B 红旗安全 | PARTIAL / RELEASE BLOCKED | RedFlagGate / RedFlagPreflight 策略及 fail-closed contract 有测试；B2 入口调用图已静态盘点 | 自然语言 detector、医学审核后的规则/阈值/文案、所有 Flutter/Native 生产入口强制覆盖、真实入口 TRACE、产品对 REVIEW_REQUIRED 的影响决策均 MISSING |
| C 检索来源 | PARTIAL / NOT VERIFIED | 83 个本地讲稿资产存在并有 sourceId 回链；12 条 combinedPatterns 来源 manifest 已分类 | 83/83 bibliographic locator 仍 MISSING；12 条规则真实底本、版次、卷页/影像仍缺；讲稿不得冒充古籍原文；不改 query/top-40/排序/去重 |
| D Headless Capability | 2 项 Headless / 2 项 Executed | yunqi、almanac | 保持 2 项；无独立行为基线前不新增 adapter；Page Tool 导航不等于 Headless execution |
| E 数据保护 | PARTIAL | 本地 AI data clear coordinator、SQLite AI 表清理事务、reopen tests、Android backup manifest contract tests | AI 与非 AI 业务行共用 nihaisha.db；当前不能排除整个 database domain，否则会一并丢失 bookmarks、diagnosis history、settings、search history；系统备份中的 AI 行副本、旧共享附件、孤儿文件和外部导出副本仍未闭环 |
| F TRACE | PARTIAL | #113 Headless reject、#114 Page Tool continuation、#115 普通发送/症状整理终态、#117 transcript batch failure、#119 message/task snapshot 独立状态、#120 lifecycle error fail-closed | Find N2 全场景链路 TRACE、多轮/媒体/Activity/进程恢复真机证据缺失 |
| G 版本与证据治理 | VERSION GUARD IMPLEMENTED | README/pubspec/Flutter/Android/Release tag guard；PR 与主线 CI 分开记录 | 849ec817 的 post-merge runs 43343151516 与 43343151619 待终态回填 |

### 21.5 B2 当前结论不变

PR #118 的全入口静态调用图仍是当前红旗接入边界基线。PR #120 只改变 Native Activity lifecycle，不涉及 red-flag：
- local_ai_interview_screen.dart、local_ai_service.dart 和 MainActivity.kt 仍没有 RedFlagGate / RedFlagPreflight / reviewed detector 的生产调用。
- Native MethodChannel 是独立执行边界；只在 Flutter 页面层检查不足以覆盖 Native 直接入口。
- 原始图片/音频不能用 prompt 文本冒充已评估；历史恢复必须保留历史主体和时间来源。
- detector 未配置、超时或覆盖不足时不得 CLEAR；未经医学审核的规则不得成为 production detector。
- 不把 REVIEW_REQUIRED 静默接入全部现有模式，也不允许 optional gate 缺失后静默旁路。
- B 继续 PARTIAL / RELEASE BLOCKED。

### 21.6 下一阶段：只推进剩余硬门槛

1. 等待当前 master 的 43343151516 和 43343151619 两条 post-merge CI；失败时只修复失败 job 实际指向的问题。
2. A/E 真机验收：按 local-ai-e4b.md、find-n2-ai-trace-acceptance-plan.md 和数据清除约束，在 Find N2 完成 GPU/CPU、至少 20 轮、多媒体、Activity recreation、进程强停/重启和清除后复查。每个场景记录设备、Android、App SHA、模型/backend、轮次和 trace_id；缺记录保持 UNKNOWN。
3. B 医学审核阻塞：取得医学背景审核记录、detector 覆盖与产品 REVIEW_REQUIRED 影响决策前，不接入 production gate，不生成医学词表、阈值或处置文案。
4. C 原始来源核验：只接受真实底本、版次、卷页或原始影像回链；83/83 locator 缺失时不能宣称文献来源闭环。
5. E 备份边界：评估 AI conversation 数据与非 AI 业务数据分离或可验证的自定义备份方案；不能通过排除整个数据库来解决 AI 行备份问题。
6. D/G 不扩展：维持 2 项 Headless 和现有版本 guard；不增加无行为基线的新 adapter 或新的治理系统。

### 21.7 执行边界

- #117/#119/#120 关闭了三个由代码与自动化精确复现的故障，不等于 A 整体 PASS。
- arm64 APK/ABI 和 JVM unit tests 不等于 OPPO Find N2 真机 GPU/CPU、多轮和生命周期验收。
- B 的纯策略测试不等于自然语言 detector 准确性、医学审核或 Flutter/Native 全入口覆盖。
- E 的应用内清除不等于系统备份和外部副本已删除；混合数据库备份边界仍未闭环。
- C 不允许推测或补造书名版本、卷页和底本证据。
- 本轮没有引入新数据库表、Agent/DAG、模型/API、检索引擎、FTS5 或额外 Headless adapter。

---

## 22. 2026-11-13 最新主线复核（PR #121 与 master 07cae681）

### 22.1 基线与集成事实

- 原运行时代码复核基线：`07cae6810db412e608ff0d3e2c0dcf1c872105be`；后续 PR #122/#123/#124 只更新执行台账、审计报告和来源 manifest，已依次合并，当前 master 文档集成基线为 `a2450f12220444225a33c4882d65ce4e4b9b3eab`。
- PR #121 `docs(ai): reconcile multiturn audit and execution ledger with merged fixes` 已合并，merge commit 即上述 SHA。
- PR #121 将 #117/#119/#120 的持久化与 Native Activity 生命周期修复纳入审计；PR #122/#123/#124 后续只更新文档和来源登记，没有新增业务行为。
- 本节以前的历史快照保留，不再把其中标记为 IN_PROGRESS/PENDING 的旧 CI 状态当作当前状态。

### 22.2 当前 master CI 终态

| Workflow | Run | Head SHA | 结果 | 说明 |
|---|---:|---|---|---|
| Flutter tests | 43344902200 | 07cae6810db412e608ff0d3e2c0dcf1c872105be | SUCCESS | Flutter regression、Dart/Flutter static analysis、全量 regression、SQLite persistence/reopen、assistant history、AI contract 与 retrieval golden snapshot 均通过 |
| Flutter Quality Gate | 43344902148 | 07cae6810db412e608ff0d3e2c0dcf1c872105be | SUCCESS | static analysis、Dart tests、Android Native unit tests、Find N2 arm64 Debug APK build 均通过 |

- Flutter tests run 的 Android arm64 CI job同时完成 APK/ABI、merged backup manifest、Native unit tests 与报告校验；全部 SUCCESS。
- Flutter tests workflow 内的 Branch validation job 为 SKIPPED，不计为通过；该 run 是 master push 验收，不以该 job 的跳过状态否定已完成的 regression/Android jobs。
- 两条主线 workflow 均已完成，当前 master 自动化 CI 可记录为 PASS。
- arm64 APK build、merged manifest 检查和 JVM/Kotlin tests 只证明构建与自动化行为；均不能替代 OPPO Find N2 真机运行 TRACE。

### 22.3 A-G 当前硬门槛

| 工作流 | 当前状态 | 已闭环事实 | 仍未闭环的硬门槛 |
|---|---|---|---|
| A Native 多轮与持久化 | PARTIAL / DEVICE UNKNOWN | #117 成功轮次与结构化问诊 transcript 原子持久化；#119 transcript 与 task snapshot TRACE 分离；#120 Activity release failure 后进程级 fail-closed；最新 master CI PASS | Find N2 GPU 至少 20 轮、CPU 至少 20 轮；图片/语音；Activity recreation；强制停止/进程重启；SQLite、Flutter UI、Native history 逐轮一致性；`state:7` 根因仍 UNKNOWN |
| B 红旗安全 | PARTIAL / RELEASE BLOCKED | Gate fail-closed、来源 provenance、gate-before-operation 顺序契约及测试；B2 全入口静态调用图已有记录 | 经医学背景人员审核的规则/阈值/处置文案；可审计的自然语言 detector；Flutter 与 Native 所有生产入口强制调用；真实入口 TRACE；对 `REVIEW_REQUIRED` 产品影响的明确决策 |
| C 知识来源 | PARTIAL（学习来源回链已实现；原文/规则来源分层） | 83 个讲稿 sourceId 与 83 个本地 Markdown 资产对应；检索上下文/引用尾注带 sourceLabel、sourceKind、sourceId 和本地回链；12 个 conditionKey 与规则来源 manifest 对应 | 一般学习资料不要求逐本逐页校勘；仍需对明确声称“古籍原文”或被 DiagnosticEngine 使用的规则来源保持核验。12 条规则当前 7 条 ONLINE_TEXT_CROSS_CHECKED、3 条 CONDITIONS_CROSS_CHECKED、2 条 MISSING；不得把讲稿观点当作规则来源。医案仅作为本地整理资料，不作为疗效证据 |
| D Headless Capability | 2 项 Headless / 2 项 Executed | `yunqi`、`almanac` 复用确定性业务逻辑 | 无新能力的行为基线与实际需求；保持现状，不以数量为目标 |
| E 数据保护 | PARTIAL | 应用内 AI 数据清除 coordinator、AI 专属新附件目录、Native runtime cache 与 TRACE 清除、SQLite AI 表事务、Android 模型/TRACE backup exclusion 均有代码与测试证据 | AI 与非 AI 业务行仍共用 `nihaisha.db`；Android XML 不能按表/行选择性排除；旧共享图片所有权 UNKNOWN；系统备份/迁移副本、外部导出副本及 Find N2 清除后强停/重启不可恢复证据缺失 |
| F TRACE | PARTIAL | #113/#114/#115/#117/#119/#120 已补齐 Headless 拒绝、Page Tool 延续、发送/症状整理终态、transcript 原子批量失败、task snapshot 独立状态及 Native lifecycle 失败终态 | Find N2 场景集完整链路、多轮、媒体、Activity/进程恢复真实 TRACE |
| G 版本与证据治理 | VERSION GUARD IMPLEMENTED | README/pubspec/Flutter/Android/Release tag 一致性门禁；当前 master 两条 post-merge workflow SUCCESS | 仅维护既有 guard，不新增第二套版本治理 |

### 22.4 下一阶段执行顺序（只处理硬门槛）

1. **A/F 真机验收**：在 OPPO Find N2 按 `docs/local-ai-e4b.md` 与 `docs/find-n2-ai-trace-acceptance-plan.md` 执行 GPU/CPU 各至少 20 轮，覆盖文字、图片、语音、Activity recreation、请求中断、强停/重启和历史恢复。每条记录设备型号、Android 版本、App SHA、模型版本/SHA、backend、轮次和 trace_id；缺任何关键证据的场景保持 UNKNOWN。不得用 CI、模拟器或 arm64 APK 代替。
2. **B2/B4/B5 安全闭环**：先取得医学审核记录（规则 ID、适用范围、阈值、例外、处置文案、规则版本及审核责任），再确定 detector 覆盖和 `REVIEW_REQUIRED` 对产品流程的影响；之后才允许在独立分支接入 Flutter/Native 门禁并验证每条入口均先 gate、后 route/tool/model side effect。审核前不得生成医学规则、不得把 Gate 接入生产、不得默认 CLEAR，也不得用 optional/null gate 形成旁路。
3. **C 学习来源与原文分层**：普通学习检索以实际 sourceId、来源类别/标题和本地回链为最低标准；现有83个讲稿资产已具备该回链，不再把83条逐本逐页校勘作为知识库完成条件。只有明确声称引用某版古籍原文、或该来源被用于 DiagnosticEngine 诊断规则时，才逐条核对可用的原文出处、规则适用条件与必要版本定位；缺失项仍标 MISSING，不猜测补齐。
4. **E 备份边界决策**：先明确是接受当前 Android 系统备份中可能包含 AI 会话，还是批准将 AI 对话迁移至独立数据库文件并制定迁移/回滚/恢复方案。Android XML 不能选择性排除 SQLite 表/行；不得排除整个 `nihaisha.db`，不得全局关闭 backup 来冒充 AI-only exclusion。
5. **E 真机清除验收**：按合成数据执行模型运行中/空闲、附件存在、TRACE 开关开启/关闭、清除成功/部分失败、强制停止和重启复查；确认 AI 数据不可恢复，同时收藏、设置、诊断历史及模型文件保留。旧共享图片无法证明归属时保留，不扫描清空共享临时目录。
6. **D/G 冻结**：保持 2 项 Headless 与现有版本 guard；除非出现可复现失败证据，不增加 adapter、Agent/DAG、数据库表、检索引擎或治理模块。

### 22.5 验收与停止条件

- 本次复核未发现需要重跑的 master CI；后续只对实际修改的代码运行对应 changed tests，并按影响范围执行 Flutter regression、Android Native/arm64 与 post-merge CI。
- B 的医学审核、A/E 的 Find N2、C 中具体原文/诊断规则的来源依据，以及 E 的备份产品决策属于不同性质的硬条件。一般学习讲稿无需纸本/影像校勘；对外声称指定版本原文或将来源用于诊断规则时，缺失证据必须保持 MISSING。不得以文档更新或自动化测试代替真机、医学审核或原文核验。
- 本节只同步已核实的主线状态和下一阶段硬门槛；不改变业务行为、不新增医学规则、不触碰数据库迁移或备份策略。


---

## 23. 2026-11-13 C：古籍馆藏见证补充（不提升条目来源状态）

### 23.1 基线与新增证据

- 核验基线：`master @ 3363a29d94fa0c9e0c87587d71553fc870fcede7`。
- 更新文件：`docs/classic-rule-source-manifest.json`；仅新增 `archivalWitnesses` 与 `researchUpdatedAt`，不修改12条规则的既有来源/校勘状态。
- 本节内容已随 PR #124 合并到 master `a2450f12220444225a33c4882d65ce4e4b9b3eab`；馆藏见证一：国家图书馆“中华古籍智慧化服务平台”资源记录 `1047540`，著录《仲景全书》二十六卷，为明万历二十七年（1599）赵开美刻本；馆藏单位上海中医药大学，索书号 `94014-23`，线装10册。记录列出第一册卷前、卷一至二以及后续册卷结构。
- 馆藏见证二：国家图书馆数字古籍扫描文件 `NLC892-1244-209199`，著录为《仲景全书》第1册，馆藏机构国家图书馆，善本书号 `CBM1499`；扫描文件为122页，元数据列出卷首、目录及《伤寒论》卷第一至卷第四。该文件记录的出版年代只到“明万历”，未在文件元数据中确认1599具体年。
- 两项是不同馆藏见证，不得合并成同一册、同一索书号或同一数字文件；公开记录也没有证明现有三芦书屋转录直接据上述任一馆藏抄录。

### 23.2 状态边界

- 这两项仅是可选的古籍馆藏/扫描参考资源，供将来需要核对指定版本原文时使用；不是一般学习资料检索、引用或知识库上线的前置条件。
- 12条 `records[]` 的 `baseEdition`、`volume`、`page` 和 `primaryImageVerification` 均保持 `MISSING`；其中第32、33、36、172、256、268条的 `ONLINE_TEXT_CROSS_CHECKED` 仍只代表在线文本交叉核对。
- 当前 `articleNumber` 使用 `1955-chongqing-398` 编号体系。赵开美本须按其原书册、卷、叶/面重新定位；不得把1955年条文编号直接写成赵本页码或卷号。
- 83个讲稿 `sourceId` 的书目定位仍为 `MISSING`；本次两项馆藏目录记录不能替代83条逐项映射。
- 本次未修改检索 query、排序、去重、上下文注入、规则适用条件或任何运行时代码；未引入新依赖、数据库表、检索引擎或 Headless adapter。

### 23.3 后续动作

1. 日常学习场景继续使用已经可反查的本地讲稿 sourceId 与回链；不开展83条讲稿的逐页/逐影像映射工程。
2. 只有具体回答需要声称某一指定版本的仲景原文，或某一条被用于诊断规则的来源时，再对该条做定点核验，记录可取得的数字文本/版本/卷页/影像信息。
3. 馆藏见证仅作为可选研究线索；没有实际使用到的版本定位，不要求填入12条规则的 `baseEdition`、`volume`、`page` 或 `primaryImageVerification`。

---

## 24. 2026-11-13 C：学习知识库来源分层决策（用户产品定位确认）

### 24.1 决策理由

- 产品定位是中医学习与知识检索，不是古籍版本校勘或学术影印数据库。来源工作应保证用户知道资料是什么、内容来自哪里、能否回到实际资料；不把“每条讲稿都找到纸本卷页/原始影像”作为一般学习检索的前置门槛。
- 该决策不改变 `docs/ai-capability-audit.md` 第4.3节的来源区分要求：原文、规则结果、App数据、AI归纳仍必须分开；引用仍需能回链到真实 sourceId/业务结果；缺失不得伪造。
- 本决策只调整不同资料用途所需的来源粒度，不降低医学安全、诊断规则审核、原文真实性声明或真机 TRACE 门槛。

### 24.2 来源分层与允许用途

| 来源层 | 最低可用来源信息 | 允许用途 | 仍需保留的限制 |
|---|---|---|---|
| 课程讲稿/整理讲义（`sourceKind=lecture`） | sourceLabel、title、稳定 sourceId、本地 Markdown 回链 | 一般学习检索、知识解释、按讲稿观点进行归纳 | 明确标注为课程讲稿/整理资料；不得冒充已校勘的仲景原文，不单独作为 DiagnosticEngine 规则来源或临床证据 |
| App 古籍文本资产（`sourceKind=classic_text`） | 书名/篇章、sourceId、本地章节回链 | 学习性阅读、内容检索 | 未核验时不声称特定版本、卷页或异文；需要精确原文引用时再核对该条文本 |
| 规则来源（12个 `conditionKey`） | 条件键、引用条文/数字文本来源、规则条件与来源状态 | 为确定性辨证规则提供可审查依据 | 仍按条目核实原文条件；当前7条在线文本交叉核对、3条条件交叉核对、2条 MISSING；讲稿不能替代规则依据 |
| 本地医案整理记录 | 医案 sourceId、内部回链、来源账本状态 | 作为学习案例/检索线索 | 不把内部序号冒充原始出处，不把病例内容当作疗效证据；来源状态如实显示 |
| App 方剂/本草/针灸等结构化数据 | 数据类型、条目 ID/sourceId、本地数据文件或仓储回链 | 查询 App 内已维护数据 | 不把 App 数据说成已核验的古籍版本或临床指南 |

### 24.3 本轮代码和测试调整

- `AssistantKnowledgeContextBuilder` 继续输出来源类别、标题、sourceId 与本地回链；课程讲稿引用尾注显示为“课程讲稿/整理讲义（学习资料）”，不再把缺少纸本页码显示成讲稿条目的检索失败。
- 讲稿上下文明确提示：实际引用来源是本地课程讲稿/整理讲义；其中所引古籍文字未自动等同于指定版本原文。古籍文本资产和医案仍保留各自的来源核验状态。
- `docs/classic-rule-source-manifest.json` 新增 `learningMaterialCollections`，登记伤寒讲稿集合的 sourceId 模式、本地资产模式、Golden Snapshot 中83个 distinct sourceId 到83个本地资产的回链证据及使用边界。12条诊断规则的原有状态未被升级。
- 自动化回归只验证上述来源文案/结构化引用契约；不增加无关的全量测试，不宣称完成纸本校勘或 Find N2 真机验收。

### 24.4 C 项新的完成定义

1. **一般学习检索来源：** 返回的来源能区分讲稿、古籍文本、医案和 App 数据；每条命中可通过 sourceId 回到实际本地资料；不把二次讲稿标成原文。当前83条 golden source 的资产身份/本地回链和引用测试已满足这一层要求。
2. **指定古籍原文引用：** 只有在回答明确声称某条是某一古籍原文或指定版本原文时，才需要该条文本的可靠数字文本/版本定位；无法核实时改为“讲稿所引/本地文本摘录”或明确 MISSING。
3. **诊断规则来源：** 12条规则继续按各自 `sourceVerificationStatus` 管理；要成为诊断规则依据，必须验证原文前提和规则适用边界，不能用讲稿解释代替条文证据。
4. **医案学习：** 1256条本地医案可以作为整理案例检索，但逐案原始出处和来源统计差异不再是一般学习检索的上线阻断项；不得据此形成疗效证明、个体治疗建议或虚构原始出处。

**明确不做：** 不开展83个讲稿的逐册逐页考古映射；不为一般学习答案追逐纸本影印坐标；不因`locatorStatus=MISSING`就把有稳定本地回链的讲稿资料判成“没有来源”。

### 24.5 本轮主线基线与 CI

- PR #123 已合并：`e5932a2ecf59167c7456d9348bcc61d68e473799`；PR #124 已合并：`a2450f12220444225a33c4882d65ce4e4b9b3eab`。两者均为文档/来源登记改动，PR head 的 Flutter regression 与 Android arm64/Native job 均 SUCCESS，Branch validation SKIPPED。
- 当前 master：`a2450f12220444225a33c4882d65ce4e4b9b3eab`。合并后的 Flutter tests run `43350618944` 与 Flutter Quality Gate run `43350618932` 当前 IN_PROGRESS；在终态完成前不把新 master post-merge CI 记为 PASS。
- 本工作分支以 `a2450f1` 为基线，只修改学习资料来源展示、对应测试和来源分层文档；没有改检索算法、诊断规则、模型 prompt、Android 配置或数据库 schema。

---

## 25. 2026-11-13 AI 结果理解、知识综合与术数排盘解释能力

### 25.1 本轮确认的产品目标

本 App 定位为以本地中医学习资料与确定性领域功能为基础的学习助手，不是医学诊断软件。本轮按以下目标复核 AI 能力：

1. **知识库综合：** AI 必须调取 App 本地知识条目，对检索命中内容做总结、比较、归纳与解释；回答标示实际来源类型、标题、sourceId/本地回链和缺失项，不把模型记忆当成检索证据。
2. **已有问诊结果解释：** 六经、证型、方剂等结果由 App 的 DiagnosticEngine 和现有任务状态生成。AI 可以解释、归纳、比较该结果与本地知识依据；不得另起一套诊断、改写规则输出、补出未确认症状或给出个体处方/剂量。
3. **八字/紫微结果解释：** 排盘由 App 确定性引擎执行。AI 接收已计算的结构化结果，再总结关系、分层解释与时间脉络；不得重新排盘、改写四柱/宫位/四化或补造 MISSING。
4. **职责分层：** App 负责数据检索、来源定位、规则执行和确定性计算；AI 负责理解用户追问、跨字段关联、语言化归纳和解释。输出应区分 App 原始字段、App 规则/模板、AI 归纳。

医学审核不是所有 AI 功能的总门槛。它限于健康风险、红旗识别与规则依据/处置文案；不得以医学审核未完成为由阻断普通中医知识学习或八字/紫微文化结果解释。红旗安全边界仍须保持：没有经审核的 detector 时不得默认 CLEAR，也不得把一般学习提问直接升级为个体诊断。

### 25.2 已有链路与本轮代码落地

| 能力 | 当前链路 | 本轮核验/改动 |
|---|---|---|
| 本地中医知识检索 | `AssistantKnowledgeContextBuilder.buildAsync` 按模式取本地公式、本草、经络穴位、经典文本/讲稿等资料，按来源元数据构建上下文 | 学习模式提示改为围绕命中资料总结、比较、归纳与解释；清楚区分讲稿、古籍文本、医案、App 数据和 AI 归纳；未命中或缺依据保持 MISSING |
| 已完成结构化辨证 | `LocalAiInterviewScreen` 保存 transcript 与问诊 task snapshot；恢复会话时由 `_restoreVisibleConversationToModel` 把可见历史交给 `LocalAiService.restoreConversation` | 问诊提示明确允许解释已有 DiagnosticEngine 结果，并结合本轮本地知识来源说明依据；新增恢复回归，断言模型恢复 transcript 包含六经、证型、方剂结果 |
| 八字排盘 | `BaZiPaipanScreen(returnResultOnComplete: true)` → 工具结果回传 → 助手时间线持久化 → 恢复 Native 模型上下文 | 新增 `formatBaZiChartForAssistant`，输出四柱、十神、纳音、旬空、刑冲合害、十二长生、藏干十神、日主、格局、强弱依据、五行状态、用忌神、建议、神煞、大运及每步大运所辖流年 |
| 紫微排盘 | `ZiweiChartScreen(returnResultOnComplete: true)` → 工具结果回传 → 助手时间线持久化 → 恢复 Native 模型上下文 | 新增 `formatZiweiChartForAssistant`，输出十二宫星曜、命/身宫、命主/身主、生年四化、整体规则模板解读、大限区间及逐限解读；并把用户当前选择的流年、流月、流日和流曜落宫一起回传 |
| 工具结果解释 | Page Tool 完成后返回字符串结果；`_openTool` 将结果加入助手消息并恢复本地模型上下文 | 工具模式提示明确：实际计算由 App 工具完成，回传后 AI 基于结果字段总结和解释，不猜算；区分 App 确定性计算与 AI 解释 |

### 25.3 解释数据边界

- 八字与紫微格式化层只读 App 已产生的数据；强弱权重内部数值不暴露给模型，仅传递可读判断依据。
- 紫微仅传递排盘、流曜定位及页面已有非健康规则模板；不向 AI 传递 `analyzeHealthWatch` 健康提醒清单，也不把疾厄宫/身体部位文本作为医学结论。
- 若没有选择流年/流月/流日，不为用户自动补选日期；若选择了，回传当前页面实际计算结果。
- 所有字段如缺失则输出 MISSING/未选择，不由 AI 补造。
- 普通知识答案仍依来源状态区分课程讲稿、古籍文本、医案与 App 结构化数据；83 个学习讲稿的本地 sourceId 回链口径按第 21、24 节执行，不重新开启逐册逐页考古映射。
- 不改 DiagnosticEngine 规则、问诊流程、红旗门禁实现、检索排序、数据库 schema、模型下载/配置或 Android backup policy。

### 25.4 针对性自动化验收

本轮新增或补强以下回归，不扩展成全新测试框架：

- `test/assistant_chart_result_formatter_test.dart`：用真实本地八字/紫微计算样例核对关键字段；核对大运所辖流年和已选流年/流月/流日；核对紫微健康提醒未进入回传文本。
- `test/assistant_tool_result_handoff_test.dart`：从统一助手触发八字/紫微 Page Tool，真实走页面本地计算和“返回 AI 助手”，再核对完整摘要进入会话消息并进入 `restoreConversation` transcript。
- `test/local_ai_interview_screen_test.dart`：核对问诊模式上下文包含“解释和归纳已有结果”指令；恢复已完成的结构化问诊会话后，模型 transcript 包含六经、证型和方剂结果。
- `test/assistant_tool_router_test.dart`：锁定学习、问诊、工具、玄学四种角色的知识综合/结果解释提示，防止后续回归成仅导航或原样复述。

这些测试证明**来源/结果数据确实被组织并交给本地模型上下文**，不等于证明 E4B 在 Find N2 上对每类问题都能生成正确、充分的自然语言解释。语义回答质量仍需设备实测；未实测场景保持 UNKNOWN。

### 25.5 A-G 状态与下一阶段

| 项目 | 状态 | 当前边界 |
|---|---|---|
| A Native 稳定性 | PARTIAL / DEVICE UNKNOWN | GPU/CPU 多轮、图片/语音、Activity/进程恢复与真实设备 transcript 一致性仍需 Find N2 验收 |
| B 健康风险与规则边界 | PARTIAL / 健康风险路径受限 | 只对健康红旗、潜在个体诊疗输出及规则依据实施相应审核；不把医学审核泛化为全部学习/术数解释的前置条件。自然语言 detector 与 Flutter/Native 全入口红旗门禁仍不能默认为已完成 |
| C 知识来源 | 一般学习资料回链已满足当前口径；规则来源 PARTIAL | 83 条讲稿按本地学习资料回链使用；12 条规则来源仍为 7 ONLINE_TEXT_CROSS_CHECKED、3 CONDITIONS_CROSS_CHECKED、2 MISSING |
| D Headless Capability | 2 项 Headless / 2 项 Executed | 保持冻结，不为增加数量而扩展 |
| E 数据保护 | PARTIAL | 混合 SQLite 备份边界决策、旧共享图片归属及 Find N2 清除后强停/重启不可恢复仍未闭环 |
| F TRACE | PARTIAL / DEVICE UNKNOWN | Debug-only 本地采集入口已实现；完整场景 TRACE 与设备采证仍未完成 |
| G 版本治理 | VERSION GUARD IMPLEMENTED | 维持现有版本源 guard，不增加第二套治理 |

**接下来优先顺序：** 完成当前独立分支的最新 head changed tests；创建 PR 后执行完整 Flutter regression、Android arm64 APK/Manifest/Native CI；合并后核验 master post-merge CI。随后在 Find N2 上用合成/非敏感测试数据完成实际 E4B 回答验证，检查知识来源引用、结构化问诊结果解释、八字详批、紫微命盘/大限/已选流层的总结质量。未执行的真实设备场景不写 PASS。



---

## 26. 2026-11-13 PR #128 集成与主线验收状态

### 26.1 集成事实

- PR #128「feat(ai): synthesize knowledge and explain returned domain results」已 squash 合并。
- Merge commit / 当前 master：`5edba1ea894a435536430640f575f395c42f932e`。
- PR head：`d4a0351fe6216887d1507af0be11c1237708d835`。
- PR 修改 11 个文件，包含知识/问诊/术数提示、八字/紫微完整结果格式化与回传、四组针对性回归及本执行台账/审计报告。
- PR 本身 CI run `43359969709`：Flutter regression SUCCESS；Android arm64 Debug APK、合并 Manifest、ABI/SHA-256 和 Native unit tests SUCCESS。独立 push branch validation `43359725232` SUCCESS；PR 事件里的 Branch validation SKIPPED 单独记录，不计 PASS。
- Review threads 无未解决项；PR 已合并。

### 26.2 Master post-merge CI

| Workflow | Run | Head | 当前状态 |
|---|---:|---|---|
| Flutter tests | `43360881240` | `5edba1e` | SUCCESS；包含 Flutter regression、Android arm64 APK/Manifest/Native job |
| Flutter Quality Gate | `43360881283` | `5edba1e` | SUCCESS；静态分析、assistant history resume、全量 Dart tests、Android Native unit tests、Find N2 arm64 Debug APK build 全部 SUCCESS |

Flutter tests 与 Quality Gate 是两条独立 workflow，现均已在同一 master head `5edba1e` 上终态 SUCCESS。

### 26.3 AI 能力交付结论

- **已具备代码/自动化证据：** 本地知识命中进入上下文并要求总结比较；既有 DiagnosticEngine 问诊结果进入历史恢复 transcript；八字详批、大运/流年和紫微十二宫、四化、大限及页面已选流层可回传本地模型上下文。
- **未被本轮 CI 证明：** E4B 在 OPPO Find N2 上是否能稳定生成正确、充分、可追溯的自然语言解释。fake/recording service 测试证明的是上下文交付，不是模型语义质量。
- **真实设备待办：** 使用合成/非敏感数据完成本地知识对照、既有问诊结果追问、八字详批、紫微整体/大限及已选流年/流月/流日解释；记录 App SHA、模型版本、backend、原始输入摘要、真实输出及来源核对。未执行场景保持 UNKNOWN。
- **其他独立外部边界：** A/F 真机多轮和生命周期 TRACE、B 健康风险红旗 detector/审核、E 混合 SQLite 备份决策及清除后强停/重启验证仍保持 PARTIAL/UNKNOWN；不阻断普通学习与术数解释代码链路，也不被本 PR 宣称完成。

---

## 27. 2026-11-13 PR #131：八字对话内 Headless 执行闭环集成

### 27.1 主线集成与 CI 证据

- PR #131「feat(ai): collect Bazi inputs in chat and execute headlessly」已 squash 合并。
- PR head：`a1b3d63713eedcbdbf3195a5c32105a83548fea2`；merge commit / 当前 master 基线：`5f81d48b29cf2680daf6a1ce902b2758db2a771d`。
- PR 修改 9 个文件：Headless Bazi executor、工具参数类型/注册、助手对话参数收集和结果回传，以及对应单元/Widget/路由测试；未修改八字计算规则、问诊辨证规则或知识库。
- PR Flutter workflow run `43397003322`：SUCCESS；全量 Flutter regression `1398 tests passed, 15 skipped`。
- 同一 PR workflow 的 Android arm64 job：SUCCESS；Debug APK 构建、合并 Manifest 校验、ABI/SHA-256 校验、Android Native unit tests 与测试报告/XML 校验均 SUCCESS；Android unit tests `66 tests, 0 failures, 0 errors, 0 skipped`。
- 独立 push branch validation run `43396994807`：SUCCESS（Static analysis + changed tests）。PR 事件里的 branch-validation job 是 SKIPPED，不能把它单独计为 PASS；对应的独立 push validation 才是通过证据。
- PR #131 已关闭且 merged；当前 master 为 merge commit `5f81d48b29cf2680daf6a1ce902b2758db2a771d`。
- 合并后的 master Flutter tests run `43398367412` 和 Flutter Quality Gate run `43398367761` 在本节记录时均为 IN_PROGRESS；终态尚未取得，不得写为 PASS。

### 27.2 本次交付边界

- 新增 `BaziToolExecutor`，复用原有 `computeBaZiPaipan`、`computeBaZiFortune`、结果格式化器和本地城市位置数据。参数校验、地点唯一性校验通过后才执行；不使用示例日期、默认性别或默认经纬度。
- 统一助手对话内收集公历出生日期、出生地当地钟表时间、性别、出生地点；支持分轮补齐、待补参状态恢复、文本取消。成功计算结果、实际参数和来源 ID 被写回会话；仅成功且通过结果契约校验时出现「AI总结解读」入口。
- 结果解释输入来自 App 实际排盘结果；AI 只解释，不重算、不改四柱、不补造字段。当前计算仍沿用原有真太阳时设置及其时间口径声明；不做历史时区/夏令时换算。
- 当前字段提取仍是确定性解析（日期、时间、性别、出生地标签），不是通用 E4B 结构化自然语言理解；不得将本 PR 记为 P4 L1 完成。
- 本 PR 只把用户明确指定的八字用例新增为第三项 Headless 能力；未把其它 Page Tool 批量改成后台执行。

### 27.3 D Headless Capability 状态更新

| 状态 | 能力 | 当前实现 |
|---|---|---|
| Headless / Executed | `yunqi` | 原有确定性执行器 |
| Headless / Executed | `almanac` | 原有确定性执行器 |
| Headless / Executed | `bazi` | 本 PR 新增；真实参数与结果契约校验、来源 ID、对话持久化和解释入口 |

- D 从「2 项 Headless / 2 项 Executed」更新为「3 项 Headless / 3 项 Executed」。这是用户明确要求的八字对话场景，不是增加数量目标。
- 其余工具维持既有 Page Tool/能力路径；只有出现明确用户需求、可复用确定性逻辑和独立验收方案时才开新切片，不做批量 Headless 转换。

### 27.4 AI 能力总状态与后续顺序

1. **P4 结构化意图理解仍待实现：** 当前 L0 主要由确定性关键词/别名路由；Bazi 参数字段抽取也仍是确定性格式解析。下一阶段按审计要求设计有界候选集和参数 schema，由 E4B 只在候选范围内做复杂/歧义意图选择与 slot filling；所有输出经 schema/业务约束校验后才能调用工具。简单请求继续走确定性路径，不允许模型自由指定工具名。
2. **自然语言问诊前置理解仍待实现：** 当前规则问诊仍沿用既有十问/问诊控制器流程。目标是保留用户原始自由文本，由 AI 提取候选症状事实、标记未确认/缺失项，只追问必要字段；用户确认后再调用既有规则问诊和 DiagnosticEngine；结果继续来自 App 已审核知识库/规则，再由 AI 总结解释。不得重建知识库、修改诊断规则或把 AI 推断标为诊断。
3. **健康红旗门禁是问诊自然语言入口前置硬门槛：** 当前原始文本 detector、医学审核记录和 Flutter/Native 全入口强制拦截仍未形成完整证据。取得医学审核的 detector 规则、阈值、例外、处置文案和版本记录之前，不得让症状抽取/普通模型路径绕过门禁，不得自行编造医学词表，也不得默认 CLEAR。此限制只针对健康风险/潜在个体诊疗路径，不应扩展到普通学习或非医疗术数解释。
4. **结果解释的真实设备语义验收仍待完成：** 自动化证明真实 App 结果与来源上下文进入本地模型调用链，不证明 E4B 已在 OPPO Find N2 上稳定正确回答。需用合成/非敏感样例核对本地知识综合、已有问诊结果追问、八字详批、紫微整体/大限及已选流年/流月/流日解释，并记录模型/设备/backend/App SHA/真实输出/来源一致性；未实测场景保持 UNKNOWN。
5. **A/F 与 E 的设备级硬门槛未因本 PR 改变：** Find N2 多轮、媒体、Activity/进程中断恢复和完整 TRACE 采证仍待设备执行；SQLite 混合数据库备份产品决策、清除后的强停/重启不可恢复性仍为 PARTIAL/UNKNOWN。

### 27.5 冻结范围与停止条件

- 不重新建设知识库，不重复医学审核已经完成的知识内容，不改 DiagnosticEngine/辨证/剂量/八字算法。
- 不引入第二套 Orchestrator、Agent/DAG 框架、云模型或向量数据库。
- 不批量 Headless 化所有工具；不以测试数量或工具数量作为目标。
- 后续每个代码切片只围绕上述明确缺口；先检查现有能力和文档，再创建独立分支，修改最少文件，运行 changed tests 与对应 CI，最后核对主线 head。
- 未取得医学审核、Find N2 真机记录或数据清除证据的事项，继续保持 PARTIAL / UNKNOWN；自动化 CI 不能替代外部验收。

---

## 28. 2026-11-13 P4 受限意图选择与八字缺参追问收敛

### 28.1 主线基线与已集成能力

- PR #133「feat(ai): add bounded E4B intent selection for Headless tools」已 squash 合并；merge commit / 当前主线基线：`2418a8c5460f4d619aea71f5aa1037b7c38d3a9d`。
- PR head：`9db9edc231f346a19d93d8b2e759148662ad4ca3`；PR Flutter run `43403342243` SUCCESS；独立 push validation `43403333810` SUCCESS。
- PR 事件中的 Branch validation 为 SKIPPED，不计为 PASS。合并后的 master Flutter tests `43405595087` 与 Quality Gate `43405595090` 在本执行记录开始时尚未取得终态；后续必须以同一 master SHA 的终态记录为准。
- PR #133 之后 master 无其他开放 PR；新的八字缺参追问修正以该 SHA 为独立分支基线。

### 28.2 P4 受限意图选择现状

- L0 仍由 Dart 确定性识别模式、意图与候选集合；只有出现多个明确候选且候选均有 Headless executor 时才调用 E4B。
- E4B 输入仅包括用户原文和 2–6 个已登记候选，输出严格 JSON 的 `select / clarify / none`；Dart 校验 schema、TRACE ID 和候选成员关系。
- 模型不能生成工具名、参数或业务结果；Page Tool 不加入模型候选；模型不可用、输出非法或调用异常时退回确定性澄清。
- 本轮不因普通单意图请求调用模型，不批量把 Page Tool 改成 Headless。此项是 bounded intent selection 的 CODE + TEST 证据，不等于全局自然语言 slot filling，也不等于 Find N2 真实模型语义验收。

### 28.3 八字对话缺参追问修正（PR #134）

- 原有 `BaziToolExecutor` 已复用 App 本地确定性排盘函数，必填字段为公历出生日期、出生地当地钟表时间、性别、出生地点；字段缺失或格式错误时不会调用排盘。
- 本轮只改助手缺参回复：通过已有 `AssistantToolDefinition.parameters` 列出已识别字段、尚缺字段和需要更正字段；不再每轮都要求用户重复提供全部四项。
- 分轮收参、会话状态、取消、Headless 执行、参数校验、结果契约及来源 ID 沿用现有实现；不改排盘算法、时间口径、城市目录或结果格式化。
- PR #134 已 squash 合并：PR head `0b7e31ad62f434326444df5f5ebc8b0babff2e27`，merge/master SHA `34a839ed661740ab7350e61ce8ca90ccc9a3c283`。
- PR head Flutter regression `43407071833` SUCCESS，push validation `43407063342` SUCCESS；master post-merge Flutter tests `43408434463` 与 Flutter Quality Gate `43408434562` 均在 merge SHA `34a839e` 上 SUCCESS。
- 前一轮 run `43406215264` 的测试失败来自断言误写：正确回复显示已识别日期，错误断言要求整条回复不出现日期；已修正为“目前还缺少”列表不含已提供字段。
- PR #134 只完成确定性缺参列表的动态展示；不将其记为通用 E4B slot filling 完成。

### 28.4 当前边界与下一阶段

| 领域 | 当前状态 | 下一步硬条件 |
|---|---|---|
| P4 工具意图 | Headless 候选受限选择已落地（CODE + TEST）；Find N2 真实推理仍 DEVICE UNKNOWN | 保持 2–6 个候选、候选 ID 白名单和 TRACE 契约；不扩为模型自由选工具 |
| P4 参数收集 | 八字具备 L0 确定性解析 + 有界 E4B 自然语言候选抽取（PR #135）；PR #134 已合并 | 槽位结果必须逐字证据、只填当前缺项、Dart 校验后再走 App 参数校验；不推广到症状/诊断参数 |
| 自由文本问诊 | 尚未形成审计要求的“自述理解—必要澄清—用户确认—既有规则执行”闭环 | 先满足独立红旗门禁；不得以普通模型 Prompt 或事后用户确认代替模型调用前的确定性门禁 |
| 问诊规则与知识库 | 既有审核知识库和 DiagnosticEngine 保持原样 | 不重复审核知识库、不重建问诊十问、不修改辨证规则；只改善交互和结果解释链 |
| 真机语义 | DEVICE UNKNOWN | Find N2 实测知识综合、既有问诊结果解释、八字与紫微结果解释；记录 App SHA、模型、backend、TRACE、真实输入输出 |
| A/F/E | 仍 PARTIAL / UNKNOWN | Find N2 多轮/生命周期/TRACE，混合 SQLite 备份决策和清除后重启不可恢复证据 |

### 28.5 执行冻结

- AI 负责理解、澄清与解释；App 确定性代码负责参数校验、知识检索、排盘/问诊/计算和结果校验。
- 未通过结果契约验证的执行结果不得交给 AI 当作事实；AI 不得更改辨证、排盘或剂量规则。
- 不新增 Agent/DAG、第二套 Orchestrator、向量数据库、云 API 或通用工具平台；不为测试数量或 Headless 数量扩展。
- 医学知识内容审核与红旗入口安全门禁不是同一件事：既有知识库内容不重复审核；但缺少完整、经过审核的红旗 detector 规则与 Flutter/Native 全入口拦截证据时，问诊自然语言抽取链仍不得绕过安全门禁。

---

## 29. 2026-11-13 PR #135：八字自然语言槽位抽取（受限 E4B）

### 29.1 主线基线与当前验收

- 基线为 master `34a839ed661740ab7350e61ce8ca90ccc9a3c283`，即 PR #134 合并后的主线。PR #134 的 PR Flutter regression、push changed tests 与 master post-merge Flutter tests / Quality Gate 均已 SUCCESS。
- PR #135：`https://github.com/just2512/nihaixia-app/pull/135`，分支 `work/p4-bazi-evidence-slot-filling-2026-11-13`。代码头 `140232868612d9e581d8d28d87713db052bab780`；push Branch validation run `43412646761` SUCCESS（Static analysis + changed tests）。PR 触发的全量 Flutter regression run `43412653762` 在本记录时仍运行中；以后续 PR 最终 head 的完整 workflow 终态为准。不能用 push changed-tests 代替 Flutter regression / Android CI。
- 早期 CI 暴露的 service 文件编辑破坏已从 master 基线重建；后来修正 fake service 的 override 位置，修复了集成测试未真正调用槽位抽取的问题。当前 Branch validation 对最新 head 已通过。

### 29.2 槽位抽取调用链

1. L0 先用既有 `AssistantConversationOrchestrator.argumentsFor` 提取稳定格式的出生日期、HH:mm 时间和明确性别。
2. 仅当必填参数仍缺失、当前用户消息含有对应自然语言线索、本地模型 ready 且存在 TRACE ID 时才调用 E4B；无出生资料线索的“帮我排八字”不调用模型。检测到症状 cue 的消息不进入该非医疗槽位抽取器。
3. Native `extractBaziSlots` 只接收本轮用户原文、缺失字段集合和 TRACE ID；字段集合由 Native 再次限制为 `birth_date / birth_time / gender / birthplace`。模型只输出固定四字段 JSON，不执行排盘。
4. 每个非空候选必须带原文逐字 `evidence`。Dart 验证 JSON schema、用户原文包含证据、字段属于当前缺项、不得覆盖已解析字段，并校验日期日历有效性、公历口径、中文时间语义、性别和出生地完整名称。
5. 验证失败、无效输出或 Native 错误时丢弃全部模型候选，回到确定性缺参追问；不会用部分/猜测结果执行。通过后仍必须通过 `AssistantToolArguments.validateAgainst`，才允许调用既有 `BaziToolExecutor`。
6. 执行结果仍须通过 `AssistantToolResult.validateFor` 和参数匹配校验，来源 ID 保留；未执行、失败或契约校验失败的结果不得提供给 AI 当作事实。

### 29.3 明确边界

- 没有改变八字排盘算法、真太阳时校正、城市目录或输出格式。
- E4B 不创建工具名、不生成默认出生资料、不换算农历、不推算时区/夏令时/真太阳时，不会覆盖已确定参数。
- 本切片只针对八字非医疗出生资料；不表示问诊自然语言抽取已完成，也不表示通用参数槽位抽取已完成。
- 当前成功排盘后仍由用户点击“AI总结解读”触发模型；“业务结果自动返回后由 AI 主动归纳”的无额外点击体验仍是后续任务，不能写成已闭环。

### 29.4 下一步按依赖顺序收尾

| 事项 | 当前状态 | 下一步范围 |
|---|---|---|
| PR #135 集成 | Branch validation SUCCESS；PR 全量 Flutter/Android 终态待定 | 只在最终 head 全量 CI 终态成功后合并；复核相同 merge SHA 的 master workflow |
| 结果自动解释 | 已有结果解释 helper，但八字结果需要用户再点按钮 | 先从成功且契约校验通过的 Headless 结果做自动解释；模型只接收真实结果与 source IDs，不生成/修正业务结果；允许用户继续追问 |
| Page Tool 对话内执行 | 当前 24 个注册工具中仅 `yunqi / almanac / bazi` 具备 Headless executor | 逐项审计纯业务函数与页面依赖，只挑有真实用户场景且可复用确定性函数的下一项；不批量迁移页面、不以数量为目标 |
| 自然语言问诊 | 仍 PARTIAL / BLOCKED BY RED-FLAG GATE | 不重复审核既有知识库、不改 DiagnosticEngine/十问；先具备医学审核的红旗规则及所有入口模型调用前拦截，再做“症状事实草稿—必要追问—用户确认—既有规则问诊—AI解释” |
| Find N2 真实模型 | DEVICE UNKNOWN | 用合成/非敏感数据核实 slot extraction、排盘结果解释、知识检索和 TRACE；CI 不替代设备验证 |

### 29.5 冻结

- 维持“AI 理解与解释，App 确定性执行与校验”；不新增第二套 Orchestrator、Agent/DAG、向量数据库或云服务。
- 既有医学知识库的内容审核不重复做；医学红旗门禁是独立的调用前安全约束，不因知识库已审核而自动视为完成。
- 只把已校验结构化结果提供给 AI；没有结果、结果状态 UNKNOWN、执行失败或 source ID 缺失时不得生成事实性结果解读。

---

## 30. 2026-11-13 PR #136：通过校验的工具结果在统一对话中自动解释

### 30.1 主线基线与集成终态

- PR #136 基线 master：`84a07efbb7713007e30b7a88bff3b4f786b236c6`；最终 PR head：`9c7af72a550928f2f58d98c522e7dc83d2c82dd6`。
- PR #136 已 squash 合并，merge commit / 当前主线集成点：`9fa7f400170569ba6c6b57728c5d26f486b98885`。
- PR head push Branch validation run `43418427885`：SUCCESS。
- PR 全量 workflow run `43418437453`：SUCCESS；Flutter regression job `131862103871` 与 Android arm64 CI verification job `131864278445` 均 SUCCESS。Android job 完成 CI APK 构建、merged Manifest、ABI/SHA-256、Native unit tests、test XML 验证及报告上传。
- 合并后 master Flutter tests run `43419630906`：SUCCESS；master Flutter Quality Gate run `43419630904`：SUCCESS。两者都对应 merge SHA `9fa7f400170569ba6c6b57728c5d26f486b98885`。Quality Gate 包含完整 Dart tests、Native unit tests 和 Find N2 arm64 debug APK 构建。
- 上述 CI 证明构建、自动化回归和原生测试通过；不代表已在 OPPO Find N2 真机安装模型、完成真实 E4B 推理或验证回答质量。设备级语义验收继续标记 DEVICE UNKNOWN。

### 30.2 Headless 工具结果自动解释

- `_executeHeadlessTool` 先执行原有参数校验、确定性业务函数、结果契约和参数匹配校验；只有状态为 `SUCCEEDED` 且 source IDs 非空时，结果才可进入自动解释。
- 本地模型状态明确 ready 时，助手自动调用现有 `_requestAssistantResultInterpretation`；模型未就绪时保留人工“AI总结解读”入口。
- 自动解释前先将当前对话中已经展示的真实执行结果恢复到本地模型上下文；内部解释提示不插入为用户消息，解释内容作为助手消息单独持久化。原业务结果的工具 ID、实际参数、执行状态和来源标识继续保留；解释轮有独立 TRACE，来源合并原业务来源与本次实际知识检索来源。
- Bazi 与 YunQi Headless 的针对性 widget tests 覆盖“执行结果 + 自动解释”两条消息及独立持久化；不改变排盘或五运六气计算函数。

### 30.3 Page Tool 结果回传与来源边界

- Typed `AssistantToolResult` 保留页面提供的原始 source IDs；成功状态、工具 ID 契约、参数回传匹配均通过后，且来源非空/模型 ready 时自动解释。
- 旧页面回传非空 String 时，统一包装为结果字段，并使用 `local-page-tool:<toolId>` 标记“本 App 注册页面的回传路径”。这是页面来源标识，不冒充 `local-engine`、`local-data` 或知识库条目。紫微旧页面回传测试验证该来源口径。
- 结果带显式请求参数但页面没有回传实际执行参数时，现有 `withArguments` 将状态置为 `UNKNOWN`；UNKNOWN 不进入自动解释。无返回、取消、失败、参数不匹配或 source IDs 缺失也不进入自动解释。
- 这只完成“页面结果返回后在助手对话中自动解释”，不等于 Page Tool 已改成后台 Headless 执行；用户仍需进入页面完成相应操作。

### 30.4 自动化验收与失败修正

- Branch validation `43417906260`（早期代码 head）SUCCESS；最终 PR head 的 `43418427885` SUCCESS。
- 最终 PR run `43418437453`、合并后 master runs `43419630906` 与 `43419630904` 全部 SUCCESS。
- 失败修正记录：
  - Bazi 测试仍断言旧手动按钮/旧 prompt；改为断言内部新 prompt 触发且不写成用户发言。
  - Headless 自动解释增加独立 persistence/finalRender TRACE；测试分别核对业务结果与解释消息，不再假定每个阶段只有一个事件。
  - Typed Page Tool mock 自己提供 `local-engine:page-tool-test`；测试保留原始来源，不误判为 legacy String 页面的 `local-page-tool`。
  - 紫微页面旧字符串回传没有底层 engine source ID；代码新增页面路由级 provenance，明确不伪装成 engine 来源。
- PR 最终全量 CI 和合并后 master workflows 均通过；Find N2 真机模型语义不由 CI 代替。

### 30.5 能力状态与冻结

| 领域 | 当前状态 | 仍未完成 |
|---|---|---|
| Headless 结果自动解释 | CODE + TEST + PR CI + master CI PASS | Find N2 实际 E4B 输出语义、速度、来源一致性仍 DEVICE UNKNOWN |
| Page Tool 回传后自动解释 | CODE + TEST + PR CI + master CI PASS | 页面操作仍由用户完成；未批量转换为 Headless |
| 学习助手知识综合 | 继续复用现有本地检索和解释链 | 黄金用例设备级语义验收未完成 |
| 问诊结构化结果解释 | 已有用户主动解释入口；来源标识补齐见第 31 节 | 自由文本问诊自动抽取仍受红旗门禁阻断 |
| 自由文本问诊 | PARTIAL / BLOCKED BY RED-FLAG GATE | 医学审核的红旗 detector、阈值/例外、处置文案及 Flutter/Native 全入口前置拦截证据未齐 |
| 工具覆盖 | 24 项注册工具，3 项 Headless：yunqi/almanac/bazi | 其余工具仅在有纯确定性函数、明确用户场景及独立验收时逐项迁移 |

- 不重复审核已审核知识库，不修改排盘、剂量计算、DiagnosticEngine 或问诊十问。
- 不把 AI 解释写成诊断结论，不让 AI 生成业务事实或修正 App 结果。
- 不新增 Agent/DAG、第二套 Orchestrator、云 API、向量数据库；不批量迁移 Page Tool。

## 31. 2026-11-13 PR #137：结构化问诊结果解释的 DiagnosticEngine 来源追溯

### 31.1 主线基线与集成终态

- 集成前 master 基线：`9fa7f400170569ba6c6b57728c5d26f486b98885`（PR #136 合并后）。
- 独立分支：`work/p4-diagnostic-result-provenance-2026-11-13`；最终 PR head：`2829595ed74d4fe7871831f6938d175b6ffd1ea3`。
- Branch validation run `43421461053`：SUCCESS。
- PR #137 全量 workflow run `43421508491`：SUCCESS；Flutter regression job `131872388262` 和 Android arm64 CI verification job `131874363872` 均 SUCCESS。
- PR #137 已 squash 合并，merge commit / 当前 master：`1bea32a1a81d2a776ddbb6ca7f325b7e6667045d`。
- 合并后 master workflow：Flutter tests run `43427610792` 与 Flutter Quality Gate run `43427610691` 均 SUCCESS，且均对应 merge SHA `1bea32a1a81d2a776ddbb6ca7f325b7e6667045d`；Flutter regression、Android arm64 APK/ABI、Native unit tests 和 Quality Gate 均已完成。此前记录的 IN_PROGRESS 是当时的观察快照，现以 workflow 终态为准。

### 31.2 本次窄范围改动

- 结构化问诊完成并生成非空 `DiagnosisResult` 时，现有结果解释入口将来源标记为 `local-engine:diagnostic-engine`，明确它是 App 确定性规则引擎来源，不冒充知识库条目。
- 用户点击现有“AI解读辨证结果”时，调用既有解释 helper，并把引擎 source ID 传入结果解释 TRACE 和助手消息 metadata；本轮知识检索返回的 `neijing:*` 来源继续与引擎来源合并，不覆盖或丢弃任何一侧。
- 解释提示明确只解释 App 已返回结果，不重新辨证、不补造缺项，不生成个体处方、药物或剂量建议；原结果中的处方字段仅可按原文引用，不得增删改。
- 不改变 `TcmInterviewAdapter`、`DiagnosticEngine`、问诊十问、辨证规则、知识库内容或结果计算；不新增模型调用，也不自动启动问诊解释。

### 31.3 针对性验收和边界

- changed widget test 验证：结果解释消息 metadata 同时保留 `local-engine:diagnostic-engine` 和本轮实际检索到的 `neijing:*` 来源；解释仍处于问诊助手上下文。
- 上一版测试误将来源断言为“只能有一个引擎来源”，但实际知识检索按设计返回了多条 `neijing:*` 引用；已修正为分别断言引擎来源与知识来源均存在。这不是生产代码失败。
- 该改动只是来源追溯，不等于自由文本问诊的理解、澄清或后台规则执行已经完成；也不将现有手动解释按钮改为自动模型调用。
- 自由文本健康叙述仍保持 PARTIAL / BLOCKED BY RED-FLAG GATE；没有经过医学审核的 detector 规则、阈值、例外、处置文案及全入口模型调用前拦截证据，不扩大健康数据进入 E4B 的范围。



### 31.4 主线集成后的验收范围

- PR branch validation、PR 全量 Flutter regression 和 Android arm64/Native CI 均已通过；PR 已合并到 master。
- 合并后 master 的 Flutter tests run `43427610792` 与 Quality Gate run `43427610691` 均已 SUCCESS；后者包含 Android Native unit tests 与 Find N2 arm64 CI APK 构建、ABI 校验。该结果仍只是 CI 构建/自动化证据，不是 OPPO Find N2 真机 E4B 运行证据。
- 本次集成没有在 OPPO Find N2 真机运行 E4B；真机推理质量、GPU/CPU fallback、多媒体多轮和中断恢复 TRACE 仍 DEVICE UNKNOWN。

### 31.5 下一步收尾顺序

1. **B 红旗门禁与自然语言问诊**：唯一允许的下一步是取得医学审核后的 detector 规则、阈值、否定/历史/他人/知识提问处理及处置文案，然后覆盖 Flutter/Native 所有模型入口；完成前不接自由文本症状抽取，不把 REVIEW_REQUIRED 默认放行。
2. **A/F Find N2 真机验收**：用合成/非敏感数据跑 GPU 与 CPU、文本/图片/语音、多轮和 Activity/进程恢复；记录设备、Android、App SHA、模型版本、backend、轮次和 TRACE。CI APK 不替代实机验收。
3. **E 数据清理实机闭环**：复核合并 Manifest 后，在清除全部 AI 数据后重启验证会话、问诊快照、附件原件、缩略图与孤儿文件不可恢复；不把静态测试写成重启验证。
4. **C 来源缺失保持事实状态**：12 条规则 conditionKey 已与 manifest 一一对应；其中 2 条 UNVERIFIED/MISSING 没有可追溯条文或医案来源，继续保留 MISSING，不补造条号、出处或方剂。83 条普通学习讲稿不重复做纸本校勘。

- 冻结：不修改业务辨证/排盘/剂量计算规则，不把 AI 推断作为诊断，不重复审核已有知识库，不批量迁移 Page Tool，不新增 Agent/DAG、云 API 或第二套 Orchestrator。


## 32. 2026-11-13 PR #139：Page Tool 结果持久化失败可见性

### 32.1 基线、变更与集成

- 基线 master：`cb7f2e8fd7fc597f2bafc725e369290ca78bbe34`。
- 独立分支：`work/p4-tool-result-persistence-visible-2026-11-13`；最终 PR head：`19cd6d98bf22c946820f8ee8aabf372682265bca`。
- PR #139 已 squash 合并；merge commit / 当前 master：`04de8e52abdc88d3c6f99d4b0db836721564acf4`。
- 只修改 `lib/screens/local_ai_interview_screen.dart` 和 `test/local_ai_interview_screen_test.dart`；不改工具计算、参数 schema、source IDs、结果契约或模型解释规则。

### 32.2 修复内容

- `LocalAiInterviewScreen._openTool()` 已通过结果/参数契约的 Page Tool 结果，在独立 SQLite 消息保存失败或会话不可用时，原先只有 `debugPrint`，用户看不到历史保存失败。
- 现在当前对话继续显示真实业务结果，同时显示明确的持久化提示：会话不可用时提示未能写入历史；写入异常时提示保存状态 UNKNOWN，并提示离开前先复制结果、核对历史记录。
- 工具执行成功与结果校验成功不被回写成失败；但 SQLite 的 `persistence` / `persistedState` 仍保持原有 `UNKNOWN`。不因写入异常自动重新执行 Page Tool，避免把“执行状态未知/可能已提交”当作安全重试。
- 用户仍可看到本轮真实结果；若保存未确认，不宣称历史已完整持久化。

### 32.3 针对性故障注入与 CI

- 新增单条 `saveAssistantMessage` 故障注入；测试先保存原始请求，再令工具结果消息写入抛错。
- Widget test 验证：工具结果仍在当前对话可见；界面出现“历史保存状态未知”和“不自动重跑”提示；持久化存储中不伪报工具结果已保存；业务结果只返回一次；TRACE 的 `persistence` 与 `persistedState` 均为 `UNKNOWN`。
- Branch validation run `43432527658`：SUCCESS（静态分析 + changed tests）。
- PR #139 full workflow run `43432900614`：SUCCESS；Flutter regression job `131910595578` SUCCESS，Android arm64 CI job `131912798580` SUCCESS。Android job 完成 arm64 Debug APK 构建、merged backup Manifest、ABI/SHA-256、Native unit tests、JUnit XML 校验及报告上传。
- PR #139 已合并；合并后 master runs：Flutter tests `43434084780`、Flutter Quality Gate `43434084865`。本次文档更新时两条仍 IN_PROGRESS；不得用 PR CI 代替 merge SHA 的 post-merge 终态。

### 32.4 D-03 缺口状态更新

- 专项审计第 8.3 节第 7 项“Page Tool 结果写入失败仅 debugPrint、无 UI 可见状态”已由 PR #139 关闭：CODE + 故障注入 TEST + PR Flutter/Android CI PASS。
- 这项修复不是 Headless 迁移，不改变 Page Tool 仍由用户完成页面操作的事实；也不证明 23 个 Page Tool 均已真实执行。
- 当前 24 项注册能力中仍只有 `yunqi / almanac / bazi` 具备 Headless executor；不为数量增加工具适配器。
- 后续只保留有证据的问题：逐项核实工具的实际参数、执行结果来源和取消/失败语义；不得将页面打开或旧式 String 回传一概视为已验证的 Headless Capability。

### 32.5 未完成项与冻结

1. 自由文本问诊：仍 BLOCKED BY RED-FLAG GATE。医学审核后的 detector、阈值/例外/处置文案和 Flutter/Native 全入口前置拦截未齐之前，不启用症状自由文本抽取，不将 REVIEW_REQUIRED 默认放行。
2. Find N2 真机：E4B 真实语义、GPU/CPU 多轮、图片/语音和 Activity/进程恢复 TRACE 仍 DEVICE UNKNOWN；CI APK 不替代真机。
3. 数据清理：清除后完全退出/重启并核对数据库、附件、缩略图和孤儿文件是否不可恢复，仍需真机证据；共享 SQLite 备份边界和外部副本不得写成已清除。
4. 经典来源：两条无可追溯来源的规则继续 MISSING；不补造条号、出处或方剂，普通学习讲稿不重复纸本校勘。

- 冻结：不修改 DiagnosticEngine、问诊十问、排盘/剂量/民俗计算；不新增第二套 Orchestrator、Agent/DAG、云 API 或向量数据库；不批量迁移 Page Tool；不重复审核已经审核的知识库。

## 33. 2026-11-13 PR #141：梅花易数数字起卦对话内 Headless 执行

### 33.1 基线、范围与集成

- 集成前 master：`cdc6d7bb60c7d7b60c4e3cb96f340ae0d019be13`。
- 独立分支：`work/p4-meihua-number-headless-2026-11-13`；最终 PR head：`7173e994958b40a6bffcd3d52f0442a09ffc8e70`。
- PR #141 已 squash 合并；merge commit / 当前 master：`996e019412f1baf8e4896b86cf607a986214525e`。
- 仅涉及 8 个文件：工具注册、对话编排、统一助手入口、新增 `MeihuaToolExecutor`，以及对应 executor/router/orchestrator/widget tests。未改梅花算法实现、卦爻本地数据或起卦规则。
- 本切片只将**数字起卦**从页面操作改为统一助手对话内 Headless 执行；时间起卦与随机起卦继续使用原 Page Tool 页面，不计为 Headless。

### 33.2 交互与确定性执行边界

- 助手只从用户明确提供的数字中提取第一数、第二数；两个数字都是必要参数。缺项时在当前对话追问，可跨轮补齐并从历史恢复未完成参数；不从生日、日期或其他无关文本推断起卦数字。
- 日期是可选上下文。两个数字明确且没有另给日期时，执行器使用设备本地当天日期，并在结构化结果中回显；显式公历/相对日期按确定性解析；不支持的农历日期进入澄清，不暗中猜测或换算。
- `MeihuaToolExecutor` 只做参数边界校验、日期/农历月上下文准备、调用既有 `computeMeihuaByNumber`、结构化结果封装和来源标识。卦象、动爻、互卦及变卦仍由 App 现有确定性函数产生。
- 只有 Headless 执行成功、请求参数匹配、结果契约通过且来源非空，才进入现有解释链。模型未就绪、参数不完整、结果 UNKNOWN/失败或契约失败时，不生成事实性解释。
- 时间/随机方法明确走原页面路由；由页面采集它们自己的输入，不被数字 Headless 的 first/second 必填校验拦截，并以 `PAGE_OWNS_METHOD_INPUT` 记录相应 TRACE 状态。
- 简单数字输入采用确定性槽位解析，不为体现 AI 能力而额外调用 E4B；复杂歧义仍按现有受约束澄清路径处理。

### 33.3 针对性验收与 PR CI

- 最终分支 validation run `43440528168`：SUCCESS；静态分析与 changed tests / test-pairing 检查均通过。
- PR #141 全量 workflow run `43440833538`：SUCCESS；Flutter regression job `131937690657` 与 Android arm64 CI verification job `131940462857` 均 SUCCESS。
- Flutter job 完成全量 Dart/Flutter regression、local AI contract tests、助手历史恢复、问诊快照、工具参数/重试、知识引用、检索 golden snapshot 和 legacy ChatScreen audit。
- Android job 完成 arm64 Debug CI APK 构建、merged backup Manifest 验证、ABI/SHA-256 校验、Native unit tests、JUnit XML 验证及报告上传。
- 可复核的 CI artifacts：`android-arm64-ci-debug-abi-evidence`（artifact `14045987493`）、`android-unit-test-reports`（artifact `14044624749`）。这些是 CI 构建证据，不是 Find N2 真机运行证据。
- PR #141 没有 review thread 或未解决 review comment；最终 head 与合并时 expected head 一致。

### 33.4 集成后主线 CI

- 合并后 master workflow 对应 merge SHA `996e019412f1baf8e4896b86cf607a986214525e`：
  - Flutter tests run `43442279739`；
  - Flutter Quality Gate run `43442277653`。
- 本台账更新时，两条 post-merge workflow 均仍为 `IN_PROGRESS`：Flutter full regression 正在 `Run full regression suite`；Quality Gate 已通过静态分析及 history-resume 专项回归，完整 Dart test suite 仍在运行。**不得把 PR CI 的 SUCCESS 折算成这两条 master workflow 的 PASS。**
- 后续必须继续复核这两个 run 的终态，并只按同一 merge SHA 的实际结果更新主线状态。

### 33.5 Capability 状态与剩余事项

| 项目 | PR #141 集成后状态 | 边界 / 剩余验收 |
|---|---|---|
| 注册工具 | 25 项 | 仅增加本项数字起卦能力，不以覆盖数量为目标 |
| Headless executor | 4 项：`yunqi / almanac / bazi / meihua` | 其他 Page Tool 仍逐项审计，不批量迁移 |
| 梅花数字起卦 | CODE + TEST + targeted validation + PR Flutter/Android CI PASS | Find N2 真实 E4B 语义与运行性能仍 DEVICE UNKNOWN |
| 梅花时间/随机起卦 | 保留 Page Tool | 由原页面采集时间/随机输入，不归类为 Headless |
| 自由文本问诊 | PARTIAL / BLOCKED BY RED-FLAG GATE | 医学审核 detector、阈值/例外/处置文案和 Flutter/Native 全入口前置拦截未齐 |
| Find N2 真机 | DEVICE UNKNOWN | GPU/CPU、多媒体、多轮、Activity/进程恢复与真实 E4B TRACE 仍需设备证据 |
| AI 数据清除 | PARTIAL / DEVICE UNKNOWN | 清除后重启，验证会话、问诊快照、附件、缩略图和孤儿文件不可恢复 |

- 继续遵守：AI 理解/澄清/解释，App 确定性执行；没有校验的结果不得交给 AI 作为事实；AI 解释不得变成新的卦象或业务计算。
- 不修改 DiagnosticEngine、问诊十问、排盘或剂量规则；不重复审核已有医学知识库；不新增第二套 Orchestrator、Agent/DAG、云 API 或向量数据库。
- 两条无可追溯经典来源的规则继续保持 MISSING，不补造条号、出处或方剂；83 条普通学习讲稿不重复做纸本校勘。


---

## 34. 2026-11-14 PR #144/#145/#146 集成及当前执行状态

### 34.1 集成基线和 PR 证据

- 本节基线：`master @ 67bb3597e9abb411627545a8e2a3b25105633c52`。
- PR #144「称骨对话内执行」：最终 head `e0d8eddc9155ffd5dd8c670e3db6eedaba26ffe2`，merge commit `34906712b42c78a4e6ff5e60172ae9517d16d657`；PR workflow `43458542859` 的 Flutter regression 与 Android arm64/Native job 均 SUCCESS。
- PR #145「黄帝四季歌对话内执行」：最终 head `8f9ffb1816f48cfbc0b9234f8248322e93720052`，merge commit `d328afbd6d346ba9cfbf06fe289020fc79e86186`；PR workflow `43543965618` 的 Flutter regression 与 Android arm64/Native job均 SUCCESS。
- PR #146「规则问诊结果自动解释」：最终 head `a42af20a29fe6f5c64bf1cf5afe32b57716bc061b`，merge commit / 当前 master `67bb3597e9abb411627545a8e2a3b25105633c52`；独立 Branch validation `43547647496` SUCCESS；PR workflow `43547653711` 中 Flutter regression job `132302637020`、Android arm64/Native job `132303970143` 均 SUCCESS。PR 内 Branch validation job 为 SKIPPED，独立 push run 才是该项验证证据。
- PR #146 Android CI 已完成 arm64 Debug APK、merged backup Manifest、ABI/SHA-256、Android Native unit tests、JUnit XML 与 evidence artifact 检查。APK 证据不代表 Find N2 真机运行。

### 34.2 PR #146 的行为边界

- 只有现有 `DiagnosticEngine` 产生 typed `DiagnosisResult`，问诊消息和 completed task snapshot 已成功持久化、可见对话上下文已成功恢复、本地模型状态为 ready 且 source ID 可用时，才自动请求 AI 解释。
- 自动解释使用 `local-engine:diagnostic-engine` 标识业务结果来源；prompt 只允许总结/解释现有字段和检索上下文，不重新辨证、不增加规则结论、不补造缺失字段、不生成个体处方/药物/剂量建议。
- 历史结果保留显式手动解释入口；未完成问诊、结果为空、持久化失败、上下文恢复失败或模型未就绪时不触发解释。
- 该改动只修改助手编排与 widget test；未修改 `DiagnosticEngine`、`DiagnosticRules`、剂量/排盘业务计算或既有知识库内容。
- 这不是自由文本问诊的交付：现有十问/规则追问流程仍在。用户提出自然语言症状后由 AI 自动识别缺项、只追问必要信息、后台组合规则问诊的目标仍未完成。

### 34.3 D 工作流当前能力基数

- `AssistantToolRouter` 有 24 个定义：23 个页面工具入口和 1 个 `structured_diagnosis` 特殊内联流程。
- 页面入口中 6 项配置 Headless executor：`yunqi`、`almanac`、`bazi`、`meihua`、`chenggu`、`huangdi_siji`；其余 17 项为 Page-only。
- Page Tool 可以保留页面 builder，同时也具有 Headless executor；数量不能重复累计。只有实际执行且参数、结果契约、来源和消息回传均验证成功，才记为 Executed。
- 下一项候选是紫微斗数 `ziwei`：当前仅有页面入口，既有 `ziwei_engine.dart` 提供确定性排盘函数。实施前需要先对照原页面的时间处理、子时口径、地点经纬度、真太阳时和设置读取建立行为基线；不得复制算法或使用样例默认值。该切片不得与其它分支同时修改统一助手入口文件。

### 34.4 A-G 状态与后续顺序

| 工作流 | 当前状态 | 下一项最小工作 |
|---|---|---|
| A Native 多轮/生命周期 | PARTIAL / DEVICE UNKNOWN | 保持只修复有复现证据的 CI/自动化问题；Find N2 GPU/CPU、多媒体、Activity/进程恢复至少 20 轮记录仍需设备 |
| B 红旗安全 | PARTIAL / RELEASE BLOCKED | 不编造自然语言 detector；等待医学审核版本、阈值/例外/处置文案和产品决策；在此之前不开放症状自由文本抽取或自动模型诊断 |
| C 检索来源 | PARTIAL | 保留既有黄金快照；书目 locator/纸本底本缺失独立列出，不重复审核已审核知识库内容 |
| D 确定性工具 | PARTIAL | 在紫微工具上先做页面行为基线，再抽一个最小 Headless executor；其余 Page-only 不批量迁移 |
| E 数据保护 | PARTIAL / DEVICE UNKNOWN | 合并 Manifest 与 CI 检查已通过；完成清除全部 AI 数据后的强停/重启不可恢复验证及共享 DB/附件边界核验 |
| F TRACE | PARTIAL / DEVICE UNKNOWN | 自动解释沿用既有结果来源 metadata；设备真实 TRACE 与失败轮次/恢复链仍需核验 |
| G 文档治理 | IN_PROGRESS | 当前分支同步 inventory、audit report 与本台账；合并后再记录 master 文档提交及对应 post-merge CI |

### 34.5 当前 master CI

- merge SHA `67bb3597e9abb411627545a8e2a3b25105633c52` 的 Flutter tests run `43548507345` 与 Flutter Quality Gate run `43548507387` 均 SUCCESS，且两条 run 的 head_sha 均匹配该 merge SHA。
- PR #146 的 Flutter regression、Android arm64/Manifest/Native CI 已 SUCCESS；不能替代 merge SHA 的 post-merge 两条工作流。
- 后续在合并文档 PR 前后分别复核以上 run；只有同一 SHA 对应的终态 SUCCESS 才能记为 master CI PASS。

### 34.6 冻结项

- 不改 DiagnosticEngine、DiagnosticRules、问诊十问、排盘算法、剂量换算和民俗计算规则。
- 不重复审核已经完成医学审核的知识库。
- 不在缺少医学审核 detector 时启用自由文本症状抽取；不把 `REVIEW_REQUIRED/UNKNOWN` 视为安全放行。
- 不新增第二套 Orchestrator、Agent/DAG、云 API、向量数据库或批量 Page Tool 迁移。
