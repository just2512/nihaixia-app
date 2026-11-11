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


## 9. 2026-11-11 当前执行检查点（权威快照）

> 本节覆盖第 1-8 节中早期历史状态。审计时间 2026-11-11；基线 master SHA `c7a12ed32140fb2e8e97ea406e5fdc6504216907`。后续续接必须刷新，不得将本快照当作永久现状。

### 9.1 主线和已合并切片

| 工作流 | 已合并内容 | 当前结论 | 未关闭条件 |
|---|---|---|---|
| A 多轮 Native 稳定性 | PR #30，merge `2c95d2311cf7bca3c0b9b71113b2d871d7e1e42b`；transcript 按成功 user/model 轮次保存，重建 Conversation 时回放 | 代码/自动化 CI PASS | Find N2 GPU/CPU 各连续 20 轮、附件后续轮、进程恢复真实 TRACE 均 UNKNOWN |
| B 红旗策略 | PR #25，merge `32da9187ed1ad021408b85f462ab8c680daaa7d0`；纯 Dart preflight 契约和语义单测 | POLICY CONTRACT PASS；生产门禁 BLOCKED | 无真实医学审核 detector；未接入所有 Flutter/Native 入口；未完成每入口正反向测试 |
| C 检索基线 | PR #29 与 PR #31 已合并；黄金测试及审阅记录 `docs/classic-retrieval-golden-review.md` | 行为观测基线 PASS；检索正确性 PARTIAL | 原始自然语言 query 命中 0；派生 query 结果是讲稿索引，纸本书目/卷页定位 MISSING；同 commit 重复快照未证明排序稳定；禁止算法重构/FTS5 |
| F TRACE | master `c7a12ed` 已含默认关闭的 typed trace contract、allowlist 和单测 | CONTRACT PASS；端到端 TRACE NOT IMPLEMENTED | 尚无持久化 writer/用户开关/业务层注入/Native 贯穿/设备 TRACE |
| G 文档与版本 | PR #26 已合并 README/pubspec 一致性测试；PR #22 已合并折叠屏布局修复 | 相关切片 CI PASS | 持续检查版本更新和规范/报告是否漂移 |

### 9.2 活动 PR / 分支

| 工作流 | PR / 分支 | HEAD / CI | 当前状态与动作 |
|---|---|---|---|
| E AI 数据清除 | PR #39 `work/ai-data-clear-v3-final` | HEAD `85f5a3d08393f2f2bd3f6e54705967cf6d6b38c6`；PR run `43015771142` Flutter regression IN_PROGRESS；push branch validation run `43015756947` IN_PROGRESS | 已将 PR #34 的 13 个文件移植到当前 master；恢复 `AdaptiveSinglePane`/640dp 约束、补齐 `adaptive_master_detail.dart` import，并把清除确认改为 `showFoldAwareDialog`。等待最新 PR #39 全量 Flutter + Android APK/Kotlin tests |
| G 台账刷新 | 本分支 `work/ai-ledger-refresh-2026-11-11-v2` | 基线 `c7a12ed` | 正在同步本节及跨对话协议入口；仅文档改动 |
| E 旧数据清除 PR | PR #34 `work/ai-data-clear-v2` | HEAD `c4e50f7`；run `43008411362` | Flutter 1286 PASS / 9 FAIL / 15 skipped；8 项折叠屏测试因分支屏幕实现删除 `AdaptiveSinglePane` 而失败，1 项 fold-aware contract 因新增直接 `showDialog` 而失败。PR #39 是当前替代分支；PR #35 因缺少 `adaptive_master_detail.dart` import 已关闭；PR #37 因 body 缺少 `local-ai-content-width` 宽度约束已关闭；PR #39 已恢复完整 body 约束 |
| E Android 备份 | PR #19 `work/ai-data-protection` | base `60011c4`；head `b012d03` | BLOCKED：`allowBackup=false` 影响整个应用私有数据，包括非 AI 数据；缺少在最新 master 上的 merged manifest/build 证据。不得直接合并 |
| G 旧台账 PR | PR #32 `work/ai-ledger-refresh-2026-11-11` | base `7c16534`；head `74ce5c7`；CI run `43008912112` Flutter PASS、Android PASS | 内容快照已过期且漏记当前 master `c7a12ed` 的 TRACE 合约与 PR #35；由本分支替代，不应合并旧快照 |

### 9.3 最近 CI 事实

- 当前 master `c7a12ed`：runs `43007532654`、`43007532722` 均 SUCCESS。
- A PR #30 head `abef47b`：run `43003852143` 的 Flutter regression PASS；Android arm64 APK + Kotlin unit tests PASS。
- C PR #29：run `42922894553` Flutter regression PASS；Android arm64 APK + Kotlin unit tests PASS；golden artifact `13811868576` 已审阅。
- E PR #34 head `c4e50f7`：run `43008411362` Flutter regression FAIL（1286 passed / 9 failed / 15 skipped）；Android arm64 APK + Kotlin unit tests PASS。失败均已定位到该 PR 的 UI 变更，不应归因于主线。
- E PR #35 head `c5cad02`：run `43014163904` 正在执行；不能以旧 PR #34 的 Android PASS 代替 #35 的验证。

### 9.4 下一项自动执行队列

1. 监测 PR #39 最新 head 的 Flutter regression、Android APK 和 Kotlin unit tests。若 Flutter 仍失败，读取具体失败断言并修复；不得盲目重跑。
2. #35 全量 CI 通过后审查 SQLite 四表事务、附件专属目录与 symlink 防护、Native Engine 释放顺序、导入模型保留、非 AI 数据保留，再小批量合并。
3. PR #35 合并后在 A 已释放 `MainActivity.kt` 所有权的基础上，完成 Find N2 清除实测：模型加载时清除、清除期间发送/导入被拒绝、附件/运行缓存/四张 AI 表清空、收藏/设置/命盘保留、重启后不可恢复。
4. 并行推进 C 元数据源审计：为讲稿建立人工核验 manifest 的方案与数据质量报告；不得把讲稿条目冒充《伤寒论》经校勘原文，不改检索算法。
5. 并行推进 D 工具逐项能力清单：为 24 个 toolId 补齐参数 schema、结果 schema、执行函数、sourceIds、错误/取消/超时语义和真实执行证据；只做审计，不先抽 adapter。
6. B 继续保持 REVIEW_REQUIRED / BLOCKED，直到医学审核人员提供规则版本、阈值、例外和处置文案审核记录；可以继续入口覆盖审计，但不能启用未审核 detector。
7. F 在独立分支推进本地 opt-in writer 与有界保留/删除策略；不与业务路由/Native 文件同时修改，先做 writer contract 和脱敏/保留测试，再分层接入。
8. 重新评估 PR #19 的 AI-only 备份策略；未解决全应用数据迁移影响前保持 BLOCKED。



### 9.5 2026-11-11 追加执行：F 本地 TRACE writer

- PR #38 `work/ai-trace-local-writer`，head `056cceb8f096982ea3d120148b8db5faf1bc973d`，从 master `c7a12ed` 创建。
- 新增 App 私有目录 JSONL writer，只写 allowlist metadata；默认保留 7 天、最多 500 条；串行写入/清除；不连接生产调用路径。
- 单测覆盖隐私字段、TTL、最大条数、并发写入顺序、清理边界。
- PR run `43015461548` 正在执行；push run `43015425132` pending。即使通过也只能标 F / PARTIAL，不代表设置页开关、生产链路或 Native TRACE 已完成。
- 风险：文件替换采用临时文件后 delete/rename，存在极短的文件缺失窗口；TRACE 是 best-effort，不得影响 AI 主流程。



### 9.6 E 数据清除分支的失败闭环（按日志修复，不盲目重跑）

- PR #34 run `43008411362`: Flutter 1286 PASS / 9 FAIL / 15 skipped。8 个布局测试失败，另 1 个 fold-aware dialog contract 失败。
- PR #35 run `43014163904`: Flutter 失败、Android 构建失败；日志定位为 `AdaptiveSinglePane` 引用缺少 `adaptive_master_detail.dart` import。
- PR #37 run `43014813485`: import 修复后编译通过，但 8 个布局测试仍找不到 `local-ai-content-width`；说明只恢复外层 pane wrapper 不够，必须同时恢复 Scaffold.body 的 LayoutBuilder/Center/ConstrainedBox/SizedBox 高度约束。
- PR #39 已按该证据恢复完整 body wrapper，并保留 fold-aware dialog。该 head 的 full CI 尚待完成。
- 旧 PR #34/#35/#37 已关闭，不得从这些旧 head 合并；唯一有效 E 候选为 PR #39。

