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


## 9. 2026-11-11 20:11（+08:00）远端状态增量复核

> 本节只记录本次实际读取的远端证据，优先于第 1、3、8 节中已过期的初始状态。核验时 master HEAD 为 `c7a12ed32140fb2e8e97ea406e5fdc6504216907`。CI 时间以 GitHub UTC 时间为准。

### 9.1 当前打开 PR 与 CI

| PR | 工作流/分支 | HEAD | 已读取 CI 证据 | 当前判定 |
|---|---|---|---|---|
| #39 | E 数据清除 / `work/ai-data-clear-v3-final` | `85f5a3d08393f2f2bd3f6e54705967cf6d6b38c6` | Flutter regression run `43015771142` SUCCESS；Android arm64 APK + unit tests SUCCESS | 自动化 CI PASS；Find N2 清除后重启不可恢复 TRACE 仍 UNKNOWN；PR 未合并 |
| #38 | F 本地 TRACE writer / `work/ai-trace-local-writer` | `056cceb8f096982ea3d120148b8db5faf1bc973d` | Flutter regression run `43015461548` SUCCESS；Android arm64 APK + unit tests SUCCESS | writer 切片自动化 CI PASS；尚未端到端贯穿生产调用链，整体 F 仍 PARTIAL；PR 未合并 |
| #36 | G 台账刷新 / `work/ai-ledger-refresh-2026-11-11-v2` | `4a79fe6b8a34442262d41d7ae04562ccae71a3f5` | Flutter regression run `43015840243` SUCCESS | 文档切片 CI PASS；内容在本次核验后仍需以最新状态增量修订；PR 未合并 |
| #19 | E Android 备份策略 / `work/ai-data-protection` | `b012d03e2acbca822982c91aab49089c2c418908` | 本次未发现对应最新 PR-level Android merged manifest/build 通过证据 | BLOCKED / UNKNOWN；不得合并。全应用 allowBackup=false 的非 AI 数据迁移影响仍未决 |
| #40 | D 工具能力目录审计 / `work/ai-capability-catalog-audit` | `c4de95c5f06502e5d7e3c03a403baf36bf81b30c` | 文档审计 PR 新建，CI 待完成 | IN_PROGRESS；只读审计，不改业务行为 |

旧分支 `work/ai-data-clear-v2` 的 run `43008080016` 在 branch validation 的 changed tests 失败，Flutter regression 与 Android job 均 skipped。该失败属于旧 SHA `ec3d391365025e5be58f3f9bdac9441e15dc500f`，不能覆盖 PR #39 新 SHA 的成功结论，也不能忽略其失败事实。

### 9.2 A-G 当前状态校正

| ID | 当前状态 | 本次可确认事实 | 尚未关闭的硬缺口 |
|---|---|---|---|
| A | PARTIAL | 既有 Native 生命周期审计与若干自动化修复已合并/有测试证据 | Find N2 GPU/CPU 各至少 20 轮、图片/语音、进程恢复真实 TRACE 未提供；不能标 IMPLEMENTED |
| B | PARTIAL / RELEASE BLOCKED | 已有纯 Dart preflight 策略契约和语义测试切片 | 所有模型入口/附件/结构化问诊/历史恢复的前置覆盖与医学审核记录未闭合；未经审核规则不得生产放行 |
| C | PARTIAL | 已有检索黄金请求及部分真实本地命中快照/审阅材料 | 古籍版本、卷页/条文原始定位、来源可信度和逐项校勘未完成；不得将讲稿命中表述为已核验古籍原文 |
| D | PARTIAL | master 的 `AssistantToolRouter._all` 静态盘点为 24 项；23 项为 Widget builder，structured_diagnosis 由统一对话内联接管；只有 yunqi 有 `builderWithArguments` | Headless/Executed 需逐项向下追踪业务函数、结果回传、权限、取消和错误语义；PR #40 审计文档 CI 待完成 |
| E | PARTIAL | PR #39 最新 HEAD 的 Flutter regression 与 Android arm64 APK/native unit tests 均通过 | Find N2 清除全量 AI 数据后重启不可恢复验证未执行；备份策略 PR #19 未完成 merged manifest 验证及非 AI 数据影响决策 |
| F | PARTIAL | PR #38 本地 writer 切片 Flutter regression 与 Android arm64 APK/native unit tests 均通过 | trace_id 尚未贯穿输入、安全、路由、检索、模型、工具、展示和持久化；隐私与 TRACE 关闭时行为不变需端到端验证 |
| G | PARTIAL | 多分支协议已存在 master；PR #36 文档切片 CI 通过 | README/pubspec 版本一致性与本台账实时性仍须核验；PR #40、#39、#38 等当前状态须在后续更新 |

### 9.3 本轮新增 D-01 审计交付

- 分支：`work/ai-capability-catalog-audit`
- PR：[#40](https://github.com/just2512/nihaixia-app/pull/40)
- 文件：`docs/assistant-tool-capability-audit.md`
- 基线：`c7a12ed32140fb2e8e97ea406e5fdc6504216907`
- 源码证据：`lib/screens/assistant_tool_router.dart` blob `eca8e0d6787274811796d174ec16ff29ccef4ed7`；测试 `test/assistant_tool_router_test.dart` blob `f266d827f4d5a4e5b758366de0bc799550ead909`。
- 结论：24 个注册 toolId；23 个页面 builder；structured_diagnosis 由助手页内联规则问诊接管；仅 yunqi 有 argument-aware builder。注册目录不等于 Headless/Executed 能力。
- 状态：文档已提交，PR CI 待完成；本次没有重新运行 router tests。

### 9.4 下一项自动执行任务（不等待逐项指派）

1. **E**：继续检查 PR #39 具体清除调用链、SQLite 表清单、附件目录边界和清除失败状态；随后补充可自动化的删除/重启恢复测试。真实 Find N2 重启验证仍需设备。
2. **F**：继续从 `LocalAiInterviewScreen` 和 Native MethodChannel 追踪 trace_id 的真实调用链，按文件所有权拆分，不在本地 writer PR 中混入业务路由改造。
3. **D**：PR #40 CI 完成后继续逐项追踪 23 个页面的返回值消费；先挑无敏感数据、已有确定性计算的单个工具作为最小 Headless 候选，先补行为基线再改实现。
4. **C**：继续古籍/医案来源定位与 manifest 核验；没有版本/卷页/原始 source ID 的条目保持 MISSING，不做自动补齐。
5. **B/A**：并行补齐全入口红旗覆盖矩阵与多轮真实设备验收准备；医学审核、Find N2 设备 TRACE 未取得前保持 PARTIAL/UNKNOWN。
6. 所有工作继续遵循 `docs/ai-parallel-execution-protocol.md`：每文件唯一实现所有者、小批量 PR、全量 CI 与设备验收分开记录；不因 PR mergeable 而跳过质量门槛。


D-01 表格复核补充：复核完整注册定义后，`huangdi_siji` 的 modes 为 `tools/metaphysics`（不是 learning）；已在 PR #40 同一分支修正审计表。PR #40 当前 head 更新为 `c4de95c5f06502e5d7e3c03a403baf36bf81b30c`，对应新 CI 需重新等待。


## 10. 2026-11-11 本轮复核增量（D-02 与最新 CI）

> 本节为本轮新增证据；较早小节中的“CI 待完成”以此处最新 SHA 记录为准。master 基线仍为 `c7a12ed32140fb2e8e97ea406e5fdc6504216907`。

### 10.1 最新自动化验收

| PR | 最新 HEAD | Run | 结果 | 实际覆盖 |
|---|---|---|---|---|
| #40 D-01 | `c4de95c5f06502e5d7e3c03a403baf36bf81b30c` | `43018942308` push；`43018950777` PR | SUCCESS / SUCCESS | Flutter regression、Dart/Flutter analyze、AI contract tests、full regression、Android arm64 CI Debug APK ABI verification、Native unit tests |
| #41 G 台账 | `1fe391a8d306b27a67b843af6d253eaa29869dc4` | `43018967324` push；`43018976749` PR | SUCCESS / SUCCESS | 同上完整回归与 Android arm64 CI 验证 |

说明：以上是 D-01/G 对应 SHA 的通过证据；本轮将分别更新 PR #40 与 #41 的文件，因此新 SHA 必须重新等待 CI。Android job 是 CI Debug APK ABI verification，不是 Find N2 真机安装/运行。

### 10.2 D-02 页面调用链审计

- 分支：`work/ai-capability-catalog-audit`
- PR：[#40](https://github.com/just2512/nihaixia-app/pull/40)
- 新增 commit：`f48fb98fd0bb3d00509886c8e78da73ed511264d`
- 文件：`docs/assistant-tool-capability-audit.md`
- 审计基线：master `c7a12ed32140fb2e8e97ea406e5fdc6504216907`
- CODE：`LocalAiInterviewScreen._openTool()`（`lib/screens/local_ai_interview_screen.dart:1629-1715`）；`AssistantToolResult`（`lib/models/assistant_tool_result.dart:1-93`）；23 个页面 builder（`lib/screens/assistant_tool_router.dart:488-525`）。
- 页面回传分类：9 项具备助手回传入口（8 项 String、1 项 typed result），14 项 opens_only；其中至少 4 项确认由本地确定性计算后回传（yunqi、meihua、dosage、almanac）。
- 新发现契约风险：状态枚举缺少 UNKNOWN；String 旧结果默认包装为 succeeded；arguments fallback 会回填请求值而不能证明页面实际使用值；sourceIds 可空；failed 统一提供重试入口。
- 本轮只读审计，不改运行时代码；未重新运行相关测试；真机 TRACE 未执行。D 能力整体仍 PARTIAL，Executed Capability 未证实。

### 10.3 A-G 当前状态与未完成任务

| ID | 状态 | 当前下一步（不等待用户逐项指派） |
|---|---|---|
| A | PARTIAL | 继续审计 Native Conversation 重建/历史回放边界；准备 Find N2 GPU/CPU 多轮实测矩阵。无设备记录的轮次保持 UNKNOWN。 |
| B | PARTIAL / RELEASE BLOCKED | 扩展红旗 preflight 到所有模型/附件/历史/结构化问诊入口；医学审核未完成前保持 REVIEW_REQUIRED。 |
| C | PARTIAL | 对黄金检索快照补 source metadata/provenance；无古籍版本、卷页/条文定位的条目标 MISSING。 |
| D | PARTIAL | D-02 已追踪 23 个页面的助手结果回传；下一步先补 AssistantToolResult 契约测试，再选 almanac/meihua 之一锁定纯函数黄金行为。Headless adapter 暂不启动。 |
| E | PARTIAL | 复核 PR #39 清除调用链、SQLite 表清单、附件路径边界、部分失败恢复；补自动化清除失败与重启测试。Find N2 仍需真实设备。 |
| F | PARTIAL | 从 Native MethodChannel 与助手调用链继续追踪 trace_id 传播；验证 TRACE 关闭不改变业务、日志失败不阻断业务。 |
| G | PARTIAL | PR #41 已有旧 SHA CI PASS；本轮追加台账后以新 SHA 重新验收。同步检查 README/pubspec 版本漂移；不关闭旧 PR #36，直到确认 #41 内容完整替代。 |

### 10.4 分支与集成状态

- PR #40：本轮在其既有文件所有权分支上扩展 D-02 审计，避免第二个分支同时写 `docs/assistant-tool-capability-audit.md`。
- PR #41：仅更新执行台账，和 PR #40 文件所有权分离。
- PR #38/#39：最新已知 CI 通过，但均未据此宣称 Find N2 真实验收完成；不因 mergeable=true 自动合并。
- PR #19：Android 全应用备份策略仍有非 AI 数据迁移影响决策及 merged manifest/build 证据缺口，保持 BLOCKED/UNKNOWN。
- PR #36：旧台账 PR 与 #41 存在内容重复风险，先比较完整内容与最新 CI，再决定关闭；不得合并过期台账。

**下一轮默认执行顺序：** (1) 读取本轮 PR #40/#41 新 SHA CI 与 job 结果；(2) D-03 补结果契约边界测试；(3) E 清除失败/重启测试；(4) F trace_id 贯穿最小切片；(5) C provenance manifest；(6) G 版本漂移检查。任一工作流受阻时继续其余无依赖项。


### 10.5 E-02 Native close failure 后的重试安全复核

- PR：[#39](https://github.com/just2512/nihaixia-app/pull/39)，分支仍为 `work/ai-data-clear-v3-final`。
- 新增审计提交：`e2bc75f42b4eb2b6fa043df0754da3d86690d306`，只修改 `docs/ai-data-clear-audit.md`。
- CODE：`MainActivity.releaseLocalModel()` 在 close 前清空 aiConversation/aiEngine 字段；`ConversationResourceReleasePolicy.closeBoth()` 会尝试关闭两者并聚合异常；`clearLocalAiData()` 在 release 抛错时停止删除 cache。
- 风险：第一次 close 失败时引用已经置空；同一进程第二次清除可能把 null 引用当作释放成功并继续删 cache。当前没有 releaseState 持久状态或二次清除 fail-closed 测试。
- 状态：E PARTIAL；PR #39 的既有 run `43015771142` 通过，但不覆盖本次发现的 close failure 重试路径。真机清除后重启仍 UNKNOWN。
- 下一步：在 E 文件所有权分支内增加 Native releaseState（READY/RELEASED/UNKNOWN）和 close failure 注入测试；UNKNOWN 时禁止 load、clear cache 和把 null 资源当作已释放。只有此切片 CI 通过后，才复核其与 Flutter 清除编排的交互。

