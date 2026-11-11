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


## 10. 2026-11-11 最新执行检查点（覆盖历史快照）

> 本节是本次复核时的权威状态；第 8、9 节保留历史记录，不能覆盖本节。基线 SHA：`7c16534c7a064e1fc756a681d1099269cc77f255`。

### 10.1 主线与已集成切片

- 当前 master：`7c16534c7a064e1fc756a681d1099269cc77f255`。
- PR #28（`501c6a584a08b38c0c273a0c9ccdc73c040358bc`）已合并：Gradle 9.1.0 setup，真正执行 `:app:testDebugUnitTest`，CI 统计 47 tests / 0 failures / 0 errors。
- PR #29（`ef5ab388f01983e19b3d83a24dfb4dae7cf33c3e`）已合并：黄金检索测试与 CI artifact。PR full Flutter regression 与 Android arm64 APK/Kotlin unit tests 均 PASS；artifact 已审阅，观察结果详见 `docs/classic-retrieval-golden-review.md` 对应 PR。
- PR #26（`7c16534c7a064e1fc756a681d1099269cc77f255`）已合并：README 与 pubspec `1.11.30+8039` 一致，并新增版本防漂移测试。
- master 最新 Flutter regression run `43003668218` PASS；Quality Gate run `43003667206` 当时仍执行中；Android arm64 run `43003668218` 对应 job `130467999673` 当时仍执行中。后续必须以最新 head 的最终结果更新状态。

### 10.2 活动 PR 与分支

| 工作流 | 分支 / PR | 基线/HEAD | 状态 | 下一动作 |
|---|---|---|---|---|
| A 多轮 Native transcript | PR #30 `work/ai-p0-transcript-rehydration-v3` | base `7c16534`；head `abef47b212fababc516440bbdf2231312d0903af` | IN_PROGRESS | Flutter full regression `43003852143` 执行中；push branch validation `43003814683` 执行中，必须确认 Kotlin test task 真正运行并通过；之后设备 TRACE 仍必需 |
| C 黄金快照审阅 | PR #31 `work/ai-retrieval-golden-review` | base `7c16534`；head `52ccbbc4ff454f588ee9f1363c1b962bca794890` | IN_PROGRESS | 文档修正了 MISSING 的语义：书目/纸本定位缺失，不等于本地讲稿文件回链不可用；等待 PR CI；继续核查 metadata manifest，不改检索算法 |
| G 执行台账刷新 | 本分支 `work/ai-ledger-refresh-2026-11-11` | base `7c16534` | IN_PROGRESS | 更新本台账与审计文件；CI 通过后集成 |
| B 红旗策略 | PR #25 已合并 | head `87bf7b2e11d784d300baeb0c954eb739c85807d8` | POLICY CONTRACT PASS / PRODUCTION BLOCKED | 当前仅纯 Dart 策略，无自然语言 detector、无所有入口接入、无医学审核；保持 REVIEW_REQUIRED，不得宣称门禁完成 |
| E 数据清除 | `work/ai-data-clear-audit` | head `c8053074e3ebac1cf51a71152dca69a4efc64802`；落后 master 7 commits | IN_PROGRESS / NOT MERGEABLE | 最近 branch validation `42920881688` PASS；四张 AI 表事务清除、专属附件目录、UI 二次确认和 Native cleanup helper 已实现；Dart `clearAiData` 调用仍缺 MainActivity Native handler，必须等待 A 释放 MainActivity 所有权后接入 |
| D Capability | `work/ai-capability-inventory` | head `a28e3acfa2770b7e5fe849372e477a44398f9697`；落后 master 7 commits | AUDIT PASS / IMPLEMENTATION PARTIAL | Router 24 toolId、22 个页面卡片、9 项页面结果回传设计、Headless 0；先完善 schema/执行证据，不抽 adapter |
| F TRACE | `work/ai-trace-audit` | head `16616b4677d5e87766877df6d0a0c04c233b0b1e`；落后 master 7 commits | AUDIT PASS / IMPLEMENTATION NOT STARTED | 端到端 trace_id、默认关闭审计开关、NOT_STARTED/SUCCEEDED/FAILED/UNKNOWN 状态链仍 MISSING |
| E Android 备份 | PR #19 `work/ai-data-protection` | base `60011c4`；head `b012d03e2acbca822982c91aab49089c2c418908` | BLOCKED / 不可合并 | `allowBackup=false` 影响全应用非 AI 数据；不得直接合并，须重新评估 AI-only 数据域和设备迁移影响 |
| A 旧分支 | PR #21 | CLOSED / SUPERSEDED | 已将四个文件移植到最新 master 并建立 PR #30；旧 PR 已关闭 |

### 10.3 C 黄金快照的真实观察

CI artifact `13811868576`（ZIP SHA-256 `51311b321511dcf93603097efc4eea6f0c6eab0af251760d70815968b27be1ea`；JSON SHA-256 `d5612a59de89f98775e5e354a1bc4d5b8b51f8df25d289fb49772d118fb6a688`）显示：

- 原始完整自然语言 query 命中 0；派生 query `桂枝汤` total 196、`伤寒论` total 121，各返回最多 40 条。
- 80 条派生 query 命中记录均标为“伤寒论讲稿”；每条均有本地 Markdown asset/backlink。
- 80 条 `locatorStatus=MISSING`、`bookId/chapterIndex=null`，表示纸本书目/卷页定位未核验，不代表本地 asset 不存在。
- 上下文 RETRIEVED，3336 字符，9 个 sourceIds：4 方剂、1 本草、4 讲稿。
- 当前只证明真实快照可生成；不能据此宣称古籍原文版本校勘通过、检索排序正确或算法需要替换。

下一步：核查讲稿/古籍索引元数据 schema 与 `docs/classic-rule-source-manifest.json` 的覆盖关系；先修来源身份和展示语义，再讨论 query 行为；不引入 FTS5、不抽 adapter。

### 10.4 后续自动执行队列（无须用户逐项点名）

1. A：持续监测 PR #30 full Flutter、Kotlin unit tests、Android arm64 APK；修复实际失败；CI 通过后再请求 Find N2 GPU/CPU 20 轮真实 TRACE。未有设备证据保持 UNKNOWN。
2. E：在 A 合并释放 `MainActivity.kt` 所有权后，接入 `clearAiData` MethodChannel：检查未完成模型导入、串行释放 Engine/Conversation、清除 Native runtime cache 与 AI 专属附件目录、返回逐项失败状态；之后更新 E 分支到最新 master 并跑 Dart/Kotlin/Android CI。
3. C：核查 `classic_index.json.gz` 生成脚本对讲稿/古籍的字段差异，审计完整条文 manifest 覆盖；重复同一黄金测试验证输出可重复；来源元数据未修复前不锁定“正确性 expected”。
4. B：扩展输入路径矩阵和 detector 接口契约；没有医学审核记录前只保留 REVIEW_REQUIRED，不把候选规则启用为正式安全门禁。
5. D：逐项补齐 24 个 toolId 的 typed args/result、权限、错误/取消/超时和 sourceIds 证据；按功能文件所有权逐步执行。
6. F：先实现默认关闭、脱敏、无业务副作用的 trace 事件模型和单测，再按文件所有权接入 Flutter/Native 关键节点。
7. E 备份：与清除功能分开决策；保留非 AI 数据自动迁移能力，未证明 AI-only 规则有效前 PR #19 不合并。
8. G：保持 README/pubspec 防漂移测试；每次主线版本变更自动更新报告基线。

### 10.5 跨会话恢复规则

下一次对话不要先问用户“接下来做什么”。先读取最新 master、本文件、`docs/ai-capability-audit.md` 和 `docs/ai-parallel-execution-protocol.md`，检查 PR/CI，并自动执行上述队列中所有当前无依赖的最高优先级任务。若本轮无法后台持续运行，明确说明下一轮从远端状态恢复，不声称后台任务仍在运行。


### 10.6 2026-11-11 后续 CI 状态修订

- PR #30 A 工作流 head `abef47b212fababc516440bbdf2231312d0903af` 已完成 CI：Flutter full regression run `43003852143` PASS；Android arm64 job `130468394894` APK build PASS；`:app:testDebugUnitTest` 实际执行 51 tests / 0 failures / 0 errors / 0 skipped；push branch validation `43003814683` PASS。仅自动化/构建层 PASS，Find N2 真机 20+20 轮及附件/进程恢复 TRACE 仍 UNKNOWN。
- PR #31 C 快照复核 head `8a138ba2af03b9df5c066422abbb720cdeafdde1`：push validation `43004769896` PASS；PR full Flutter run `43004777869` 当时仍执行中。报告已追加索引生成 schema 审计：讲稿索引只写 source/title/asset/text；古籍原文才有 bookId/index；manifest 当前仅覆盖合病规则 12 项，不是全量讲稿清单。
- PR #32 本台账/规范入口 head `f1dca977d005080adb13a7692010ae6cfc7d51d4`：push validation `43004626363` PASS；PR full Flutter run `43004655186` 当时仍执行中。
- PR #33 F TRACE typed contract head `06e689000b40030422e46450ab960bc84f736497`：push branch validation `43005078711` 与 PR full Flutter run `43005113495` 当时仍执行中。此切片仅有默认关闭的 typed schema/单测，无持久化 writer、审计开关、跨层透传或真机 TRACE。
- 当前 master `7c16534c7a064e1fc756a681d1099269cc77f255` 的 Flutter regression `43003668218` PASS，Android arm64 APK + unit tests job `130467999673` PASS；Quality Gate `43003667206` 当时仍执行中，不能提前标为全绿。
