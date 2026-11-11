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
| README 版本说明 | `1.11.30+8039` | 2026-11-11 从当前 master README 重新核验，与 pubspec 一致；历史漂移已消除 |
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



### 10.6 E-03 Native 资源释放 UNKNOWN 状态保护已实现，待 CI

- PR #39 当前工作分支新增 E-03 切片：`LocalAiResourceLifecycle` 状态机（RELEASED/READY/UNKNOWN），并接入 MainActivity 的模型加载与释放路径。
- close 成功后状态为 RELEASED；close 抛错后状态为 UNKNOWN。UNKNOWN 时禁止再次 close、禁止后续清理流程删除 runtime cache、禁止重新加载模型；进程重启后 Native Activity 状态重新初始化。
- RELEASED 重复 release 为幂等空操作。
- 新增 Native unit tests：正常释放、close failure 后二次 close/cache 删除被阻止、UNKNOWN 阻止 reload、重复成功释放。
- 相关提交已推送 PR #39；最新 CI 尚待完成。不能把测试文件存在视为测试通过。
- 若最新 CI 失败，先读失败 job/log；若通过，再复核 MainActivity 的状态接入和清除失败后的 Flutter 状态同步。Find N2 真机清除与重启验收仍 UNKNOWN。


E-03 实现复核补充：LocalAiResourceLifecycle 使用进程级 singleton，避免 Activity recreation 将 UNKNOWN 状态清零；AndroidManifest 对常见折叠屏/配置变化由 Activity 自行处理。跨 Activity 实例并发 Native 操作仍未单独验收。PR #39 最新提交仍需重新运行 CI；任何中间 SHA 的 cancelled run 不作为失败或通过证据。


## 11. 2026-11-11 最新复核（master 392f977c）

> 本节覆盖前面历史段落中的旧分支/旧 CI 状态。当前 master HEAD 为 `392f977c0c54603bf54daf9c7284e698ffee8a72`。本节所列 CI 只按对应 head SHA 记录；CI 不替代医学审核或 Find N2 真机 TRACE。

### 11.1 主线与 CI

- master `98521551ac650ac49cb02e38c5cbec886c2c2422`（相对 `dfd5e911` 的直接提交）修复相册菜单不透明背景、录音转写后再以问诊助手身份回应、统一剥离简单 Markdown。对应 Flutter tests run `43028761205` 与 Flutter Quality Gate run `43028761250` 均 SUCCESS；该提交还修改了 `MainActivity.kt` 与 `local_ai_interview_screen.dart`。
- 当前 master `392f977c0c54603bf54daf9c7284e698ffee8a72` 修复半折叠态 AdaptiveSinglePane 空面板黑屏，变更 `lib/widgets/adaptive_master_detail.dart`。对应 Flutter tests run `43031586746` 与 Flutter Quality Gate run `43031585876` 在本次记录时均 IN_PROGRESS，不能提前标 PASS。
- master 运行中不能覆盖上一 SHA 的成功结果；必须等待当前 SHA 两个 workflow 最终结论。

### 11.2 活动 PR 与分支集成判定

| PR | 工作流 | HEAD | CI 证据 | 与当前 master 的关系 | 判定 |
|---|---|---|---|---|---|
| #38 | F 本地 TRACE writer | `056cceb8f096982ea3d120148b8db5faf1bc973d` | 历史 Flutter regression 与 Android arm64 CI 验证通过；writer 文件专项切片 | 与 master merge-base 为 `c7a12ed`，落后 4 commits；变更仅 `docs/ai-trace-local-writer.md`、`lib/services/ai_trace_store.dart`、`test/ai_trace_store_test.dart`，未与最近两笔 master 变更文件重叠 | PARTIAL；需在最新基线重验后再集成，不能据 writer 存在宣称端到端 TRACE |
| #39 | E AI 数据清除 | `9badee489e49e73137ca4482e587cdaa96cde811` | push run `43023123535`、PR run `43023135382` SUCCESS；包含 Flutter 全量回归与 Android arm64 CI APK/native tests | 落后 4 commits；变更 `MainActivity.kt`、`local_ai_interview_screen.dart`，与 master `98521551` 的这两个文件均有修改，必须逐段语义整合 | 不合并；先解决 Native transcript/录音和数据清除的重叠语义，再重跑 CI。Find N2 清除后重启 TRACE UNKNOWN |
| #40 | D 能力目录审计 | `f48fb98fd0bb3d00509886c8e78da73ed511264d` | push run `43021937936`、PR run `43021949777` SUCCESS | 落后 4 commits；仅改 `docs/assistant-tool-capability-audit.md` | 审计文档 CI PASS；D 整体 PARTIAL，未证明 Executed Capability |
| #42 | D-03 参数来源契约 | `670ecee54c2e94e4eae20c5ef7ba6ee31acfd540` | push run `43027995552`、PR run `43028036727` SUCCESS；PR 回归含静态分析、全量 Dart regression、Android arm64 CI APK/native tests | 基于 `dfd5e911`，落后当前 master 2 commits；变更仅 `assistant_tool_result.dart` 与对应测试，无当前 master 文件重叠 | 契约切片 CI PASS；PR 仍 open/draft，未合并；D 整体仍 PARTIAL |
| #43 | B-02 preflight 语义边界测试 | `f1a39ecb3eaafb03e77e6e6db10d4ca139504810` | push run `43031537234` 的 analyze + changed tests SUCCESS；PR run `43031570066` 全量 regression IN_PROGRESS | 基于 `98521551`；仅改 `test/red_flag_preflight_test.dart`，与 master `392f977c` 的 AdaptiveSinglePane 变更不重叠 | 等待 PR 全量回归；不代表 detector 或入口接入完成 |
| #19 | E Android backup policy | `b012d03e2acbca822982c91aab49089c2c418908` | 当前未取得 merged manifest + Android build 的完整通过证据 | merge-base `60011c4`，落后 16 commits；变更 Manifest/backup XML/测试 | BLOCKED/UNKNOWN；需重新基于当前 Android 配置审查，不能直接合并 |

- PR #36（旧台账 v2）与 PR #41（台账 v3）均已关闭，原因是它们基于旧 master，PR #41 与当前 master compare 为 diverged（6 ahead / 4 behind），不应合并旧基线台账。
- 本次台账由新分支 `work/ai-ledger-refresh-2026-11-11-v4` 从当前 master `392f977c` 创建；本 PR 仅负责本文件，替代 #36/#41 的旧台账分支。
- PR 的 `mergeable` 字段不作为质量结论；合并前必须以当前 master 重新比较、检查变更文件和语义冲突。

### 11.3 A-G 当前状态（按证据，不按文件存在）

| ID | 状态 | 当前可确认事实 | 未关闭的硬缺口 | 下一项可执行工作 |
|---|---|---|---|---|
| A | PARTIAL | master 已合入 Native transcript rehydration；相关 Native/Flutter 自动化回归已在 master SHA `dfd5e911` 及后续 SHA 通过 | Find N2 GPU/CPU 各至少 20 轮，图片/语音、进程中断恢复的真实 TRACE 未提供 | 审核 Native Conversation 重建与 transcript 三方一致性；准备设备矩阵，设备未测项保持 UNKNOWN |
| B | PARTIAL / RELEASE BLOCKED | master 有纯 Dart `RedFlagPreflight` 策略与 10 项原始测试；PR #43 增加 UNKNOWN/quoted/no-match coverage 语义测试 | `RedFlagPreflight` 尚未接入 `LocalAiInterviewScreen._send()`、结构化问诊分支、附件、症状提取、历史恢复或 Native MethodChannel；没有生产 detector；医学审核记录缺失 | 先完成入口调用图与统一边界接口审计；医学词表/阈值/处置文案在 REVIEW 前不得启用。PR #43 CI 完成后再进入入口接入设计 |
| C | PARTIAL | 真实检索黄金快照及审阅记录已存在；记录明确原始 query 0 命中、派生 query 命中讲稿 | 讲稿命中不等于古籍原文；纸本版本、卷页、source ID、派生 query provenance 未闭合 | 补 source manifest 与可回链定位；不改检索算法、不引入 FTS5 |
| D | PARTIAL | PR #40 已完成 23 个页面入口分类审计；PR #42 将参数 fallback 与实际执行参数分离，并新增 UNKNOWN 状态 | 未证明工具实际调用业务函数、结果来源校验与会话回传的端到端闭环；其他 enum/switch/持久化兼容需继续审查 | 在 #42 基于当前 master 做最终调用点/序列化复核；再选一个非敏感、已有确定性函数的工具锁定黄金行为 |
| E | PARTIAL | PR #39 自动化回归及 Android arm64 CI APK/native tests 通过；清除目录与 SQLite/附件策略已有实现 | PR #39 与 master 的 MainActivity/Flutter screen 变更重叠；Find N2 真机清除、close failure 注入、重启后不可恢复及附件/DB 部分失败恢复 UNKNOWN | 先解决 PR #39 与 master 的语义冲突；随后在设备上验收清除/重启，不能把 CI 通过当作真实数据删除证明 |
| F | PARTIAL | PR #38 有界本地 writer 仅 allowlist 元数据、默认不接入生产路径 | trace_id 未贯穿 input/redflag/route/retrieval/model/tool/result/render/persistence；TRACE off 等价性、写入失败不影响业务未做端到端验证 | 基于最新 master 定义跨层 trace_id 最小契约，先从不与 #38 writer 文件冲突的单一入口切片开始 |
| G | IN_PROGRESS | README/pubspec 曾同步；执行协议已在 master；本轮新台账从 `392f977c` 重建 | README/pubspec 当前版本仍需重新核验；历史记录需与当前证据分层；新台账 PR CI 未完成 | 本 PR CI 通过后再核对 README/pubspec 和审计报告 SHA，保持单一 ledger 文件所有者 |

### 11.4 B 线本轮新增切片（PR #43）

- 任务：B-02，扩展 `RedFlagPreflight` 的纯 Dart 状态契约测试。
- 基线：`98521551ac650ac49cb02e38c5cbec886c2c2422`；HEAD：`f1a39ecb3eaafb03e77e6e6db10d4ca139504810`。
- 文件：仅 `test/red_flag_preflight_test.dart`。
- 新增覆盖：无命中但语义主体/时间/极性未知时 CLARIFY；候选命中但语义未知/引用时 CLARIFY；他人否定/本人既往史不作为当前急症；coverage 不完整优先 REVIEW_REQUIRED；所有非 CLEAR 状态不得继续普通流程。
- CI：push run `43031537234` changed-tests + analyze SUCCESS；PR run `43031570066` 全量回归截至本记录 IN_PROGRESS。
- 重要限制：该切片只验证既有策略，不创建医学 detector，不覆盖入口接入，不构成医学审核。B 继续 RELEASE BLOCKED。

### 11.5 继续执行队列（按依赖自动推进）

1. **CI**：先取得 master `392f977c` 的 Flutter tests / Quality Gate 最终结果；取得 PR #43 全量 regression 结果，失败时读取具体 step/log 后修复。
2. **D-03**：复核 PR #42 UNKNOWN enum 的全部 switch、序列化/反序列化、旧 String 结果包装与实际调用链；确认 master 前进后无语义冲突，再决定是否集成。
3. **E-03**：PR #39 先做与当前 master `MainActivity.kt`、`local_ai_interview_screen.dart` 的逐段合并审查；不能从旧分支整分支合并。无设备期间继续自动化故障注入和清除范围审计。
4. **B-03**：从所有 Flutter/Native 模型调用点建立入口矩阵，识别统一 preflight 可强制执行的最小边界；不增加未经医学审核的词表，不把未知覆盖判为 CLEAR。
5. **F-02**：TRACE writer 与生产链路分开；建立 trace_id 传播接口契约后，选择单一入口推进，确保 TRACE 关闭/写入失败不改变业务。
6. **C-02**：补齐黄金快照 source metadata、derived query provenance、原始书目/卷页定位。
7. **G**：本台账通过 CI 后，核验 README/pubspec 版本与审计文件 SHA；关闭旧 PR 已完成，不再并行编辑本文件。

### 11.6 设备与专业审核依赖

- Find N2（PUG110）真机 GPU/CPU 多轮、附件、进程恢复、清除后重启等 TRACE 当前未提供；相关项保持 PARTIAL/UNKNOWN。
- B 红旗词表、阈值与处置文案缺少医学背景人员审核记录；不能以代码测试或模型提示词替代。
- 不引入新数据库、向量检索、Agent/DAG 平台或外部模型 API；没有失败证据和独立决策前维持现有架构。


## 12. 2026-11-11 最新基线与并行分支复核

> 本节覆盖较早段落中的旧 SHA、旧 CI 状态和旧 PR 基线。当前 master HEAD：`05f118e1d0b090cee7dbeaa37669c410dae0e876`。当前应用版本：`1.11.30+8039`。

### 12.1 主线新增真机记录

- master 新增 `docs/find-n2-test-results-final.md`，记录 OPPO Find N2（PGU110）、Android 16、版本 `1.11.30+8039` 的 A-K 真机验收。
- A-K 覆盖外屏、内屏展开、半折叠、紫微排盘、系统字号、键盘 Insets、弹窗路由、相机/相册入口、折叠循环、结构化辨证、原位覆盖升级；文档记录均 PASS。
- 同一记录列出 AI 助手 10 项修复的设备验证摘要，包括 JNI keep、第二轮 GPU 失败后 CPU 重建、空回复恢复、录音转写后问诊回答等。
- 证据边界：该文档没有提供 AI 连续 GPU/CPU 各 20 轮的逐轮 TRACE、附件多轮关联、进程中断后 transcript/Native context 三方一致性、清除全部 AI 数据后重启不可恢复的场景记录。不得把 A-K 汇总扩大解释为这些独立场景已经验收。

### 12.2 README / pubspec 版本核对

- `pubspec.yaml` 当前版本：`1.11.30+8039`。
- 当前 master 的 `README.md` 中版本字符串为 `1.11.30+8039`，与 pubspec 一致；旧台账中“README 仍为 1.11.28+8037”的记录已过期。
- 尚未建立防漂移自动化检查；G 仍需补充可重复的版本一致性测试或 CI 检查。

### 12.3 PR / CI 状态（按当前可读取证据）

| PR | 工作流 | 当前基线 / HEAD | 已取得 CI | 当前状态 |
|---|---|---|---|---|
| #43 | B-02 红旗语义边界测试 | base 已改为 master `05f118e`；HEAD `f1a39ec` | 旧 base 下 PR run `43031570066`：Flutter regression SUCCESS、Android arm64 CI SUCCESS；branch validation SKIPPED | 新 base 需要重新验收；B 仍 PARTIAL / RELEASE BLOCKED |
| #44 | G 执行台账 | base 已改为 master `05f118e`；HEAD `e335bfe` | 旧 base 下 PR run `43032237167`：Flutter regression SUCCESS、Android arm64 CI SUCCESS；branch validation SKIPPED | 本台账已更新；新 base/新提交 CI 待完成 |
| #45 | B-03 红旗入口审计 | base 已改为 master `05f118e`；HEAD `e67fc5d` | 旧 base 下 PR run `43032477615`：Flutter regression SUCCESS、Android arm64 CI SUCCESS；branch validation SKIPPED | 新 base 需要重新验收；审计结论仍为 detector MISSING、全入口接入 MISSING、医学审核 MISSING |
| #46 | D-03 参数来源契约 | base master `05f118e`；HEAD `63336da` | 新 PR CI 尚未取得 | 新建于当前 master；仅修改 `assistant_tool_result.dart` 和对应测试 |
| #42 | D-03 旧基线 PR | 已关闭，由 #46 替代 | 旧 base 下 PR run `43028036727` SUCCESS | 不再集成，避免旧基线重复文件所有权 |
| #39 | E 数据清除 | HEAD `9badee4` | 历史 CI SUCCESS | 与当前 master 的 `MainActivity.kt`、`local_ai_interview_screen.dart` 存在语义重叠；仍禁止整 PR 合并 |
| #38 | F TRACE writer | HEAD `056cceb` | 历史 CI SUCCESS | writer 独立切片，不代表生产链路 trace_id 已贯穿 |
| #40 | D 能力目录审计 | HEAD `f48fb98` | 历史 CI SUCCESS | 审计文档完成；Executed Capability 仍未证实 |
| #19 | E Android backup | HEAD `b012d03` | 未取得当前 master 下完整 merged manifest/build 证据 | BLOCKED / UNKNOWN，不合并 |

说明：PR #43/#44/#45 的旧 base CI 成功只证明当时对应 SHA 的构建/回归结果；retarget 到当前 master 后，不能沿用旧 CI 作为新 base 的 PASS。当前 master `05f118e` 的 push workflow runs 未能通过本轮可用的 commit-run 查询取得，主线最新完整 CI 结论保持 UNKNOWN，不能据此声称 master CI 全绿。

### 12.4 A-G 状态与下一步执行队列

| ID | 状态 | 下一项自动执行工作 | 仍未满足的条件 |
|---|---|---|---|
| A | PARTIAL | 继续审计 GPU→CPU fallback 后的 transcript replay、Engine/Conversation 重建状态和请求未知状态；用自动化测试锁住可复现边界 | 指定多轮、附件、进程恢复及持久化 TRACE 的独立设备证据未进入仓库 |
| B | PARTIAL / RELEASE BLOCKED | 在不启用未经审核医学词表的前提下，补齐纯策略边界与所有 Flutter/Native 入口的可达性矩阵；明确每个旁路的阻断点 | detector、全入口接入、医学审核记录均缺失 |
| C | PARTIAL | 为黄金检索结果补 source manifest、原始书目/版本/卷页定位和 derived-query provenance | 命中讲稿不能冒充古籍原文；缺少定位的来源继续标 MISSING |
| D | PARTIAL | 完成 #46 UNKNOWN 状态在所有消费点、序列化和旧 String 结果包装中的兼容复核；再选非敏感工具锁定确定性行为基线 | 工具调用、参数、source ID、业务结果和会话回传尚无端到端 TRACE |
| E | PARTIAL | 继续复核 Native 释放 UNKNOWN 状态、附件/数据库部分失败和清除编排；不得把 PR #39 旧分支整体并入 | 当前主线与 #39 有重叠；清除范围、失败恢复与不可恢复证据仍需闭合 |
| F | PARTIAL | 从单一入口开始定义 trace_id 注入契约，并验证 recorder 默认关闭、写入失败隔离；与 #38 writer 保持文件所有权隔离 | 生产调用链未贯穿，TRACE off 等价性未证明 |
| G | IN_PROGRESS | 更新本台账后等待 #44 新 CI；另建独立小切片实现 README/pubspec 版本防漂移测试 | README 当前值已一致，但自动防漂移检查缺失 |

### 12.5 当前执行约束

- Find N2 真机 A-K 已有独立汇总；未记录的 AI 多轮/附件/进程恢复/清除场景不得推断为通过。
- 用户明确表示会自行执行并拉取所需真机 TRACE；本工作流继续完成代码、测试、文档和验收方案，不将设备侧操作作为本轮自动任务。
- 医学审核仍是 B 的外部专业依赖；不生成或启用未经审核的红旗词表、阈值和处置文案。
- 继续按主线基线、独立工作分支、单文件所有权、小批量集成、CI 分层验收执行；不因旧 CI 通过或 GitHub mergeable 状态而合并。


## 13. 2026-11-11 22:20 并行执行增量

> 当前 master 基线仍为 `05f118e1d0b090cee7dbeaa37669c410dae0e876`。本节记录本轮在当前基线上重建的切片；CI 结论按本节列出的 run ID 刷新。

### 13.1 旧 PR 清理与当前分支

| 已关闭 PR | 原工作 | 替代 PR | 原因 |
|---|---|---|---|
| #38 | F 本地 TRACE writer（基于 c7a12ed） | #50 | 在当前 master 重建 writer，并补 Find N2 AI TRACE 验收方案 |
| #42 | D-03 UNKNOWN 参数来源契约（基于 dfd5e911） | #46 | 在当前 master 重建两文件切片 |
| #43 | B-02 红旗语义测试（基于 98521551） | #47 | 在当前 master 重建测试切片 |
| #45 | B-03 红旗入口审计（基于 392f977c） | #48 | 在当前 master 重建审计文档 |

### 13.2 当前活动 PR 与 CI

| PR | 任务 | HEAD | Run | 当前 job 状态 | 结论 |
|---|---|---|---|---|---|
| #44 | G 执行台账 | `7eb83dce910cefc1662f87815b99bc3235a43fcc` | `43036909745` | Flutter regression SUCCESS；Android arm64 CI APK/native tests IN_PROGRESS；branch validation SKIPPED | 台账更新已完成，等待 Android job |
| #46 | D-03 UNKNOWN 参数来源 | `63336da27cc87355f6be142f987e93aa9449030f` | `43036665826` | Flutter regression SUCCESS；Android arm64 CI APK/native tests IN_PROGRESS；branch validation SKIPPED | 等 Android job；不代表 Headless/Executed 完成 |
| #47 | B-02 红旗语义边界测试 | `074619a4efb2fa9b50eca964d75c8c4b94e1f579` | `43037173941` | Flutter regression IN_PROGRESS；branch validation SKIPPED | 等待 |
| #48 | B-03 红旗入口审计 | `fd2e1b5766215ee454996fd0bdc78fa83b38faf9` | `43037179378` | Flutter regression IN_PROGRESS；branch validation SKIPPED | 等待 |
| #49 | G README/pubspec 防漂移测试 | `c63632e3b8dd45bdc5dfd9acb1e26654a4b866b0` | `43037313916` | Flutter regression IN_PROGRESS；branch validation SKIPPED | 等待；测试只新增文件，不改版本 |
| #50 | F 本地 TRACE writer + 真机验收方案 | `8e5c02303032d5109363b89f8caaa7005d621fa6` | `43037747686` | Flutter regression IN_PROGRESS；branch validation SKIPPED | 等待；writer 尚未接生产调用链 |

CI 说明：branch validation job 因 workflow 条件显示 SKIPPED；不能把它写成通过。Flutter regression 和 Android arm64 job 必须分别等待完成。Android arm64 是 CI APK/native unit tests，不是 Find N2 真机 TRACE。

### 13.3 本轮实现内容

**D-03 / PR #46**
- 文件：`lib/models/assistant_tool_result.dart`、`test/assistant_tool_result_test.dart`。
- `AssistantToolExecutionStatus.unknown` 纳入状态枚举与显示映射。
- `withArguments(fallback)` 不再把请求候选参数复制成页面实际执行参数；实际参数缺失且请求参数非空时标 UNKNOWN。
- `validateArgumentsMatch` 对缺少实际参数返回明确契约错误。
- 旧 PR #42 已关闭；新 PR #46 从当前 master 建立。

**B-02/B-03 / PR #47/#48**
- #47 只增加策略语义测试：UNKNOWN/quoted/主体时间极性不明进入 CLARIFY；coverage 不完整进入 REVIEW_REQUIRED；非 CLEAR 不得继续普通流程。
- #48 更新 Flutter/Native 红旗入口审计；明确 RedFlagPreflight 不是自然语言 detector。
- 不增加医学词表、阈值或处置文案。生产 detector、全入口接入、医学审核仍 MISSING；B 继续 RELEASE BLOCKED。

**G / PR #49**
- README 当前版本已与 pubspec 一致，新增自动测试防止未来漂移。
- 测试只读取 pubspec version 并断言 README 当前版本声明一致；不自动改版本号，不触碰历史 Release Notes。

**F / PR #50**
- 在当前 master 重建 `LocalAiTraceFileWriter` 和 writer 单测。
- 新增 `docs/find-n2-ai-trace-acceptance-plan.md`，包含 GPU/CPU 各至少 20 轮、图片/语音、进程强制终止恢复、AI 数据清除后重启的步骤、证据字段和 PASS/FAIL/BLOCKED/UNKNOWN 判定。
- 关键限制：当前 master 的 `AiTraceRecorder` 默认关闭且尚无 writer/生产调用点；PR #50 仅提供 writer，不会凭空生成端到端 TRACE。完整设备 TRACE 仍依赖后续 F 生产接线和 E 清除实现集成。

### 13.4 下一步

1. 监测 #44/#46/#47/#48/#49/#50 CI；对失败读取 job/step/log 后修复，不盲目重跑。
2. D：复核 #46 UNKNOWN 状态的调用点、序列化与旧 String 包装；确认参数校验失败时不会把 UNKNOWN 结果作为成功结果展示或持久化为已验证执行。
3. E：把 #39 作为审查来源，按当前 master 重建无重叠文件切片；MainActivity 与 LocalAiInterviewScreen 必须逐段语义整合，不整 PR 搬运。
4. F：#50 通过后，冻结 Dart/Native trace_id 注入接口；生产接线不得和 B/A 同时争用 MainActivity 或 LocalAiInterviewScreen 文件所有权。
5. G：#49 通过后，将版本一致性检查作为长期回归守护；#44 通过后更新唯一台账。
6. C：补来源 manifest 与 derived-query provenance；不改检索算法，不把讲稿命中表述为古籍原文。
7. B：入口覆盖可继续做只读/测试工作；医学审核未完成前不启用未审查规则。


## 14. D-03 集成与基线再次前进（2026-11-11）

- PR #46 已通过当前 master 基线下的 Flutter regression（run `43036665826`）和 Android arm64 CI APK/native unit tests；branch validation job 为 SKIPPED。检查了 `LocalAiInterviewScreen._openTool()`：`withArguments()` 后立即执行 `validateArgumentsMatch()`；缺少实际执行参数时显示契约错误并提前返回，不会把 UNKNOWN 结果追加到会话或持久化为已验证执行。
- PR #46 已 squash 合并，merge commit / 新 master HEAD：`c0983da895316096d550ea4a4e68e5a8dd354de4`。
- #46 仅改 `lib/models/assistant_tool_result.dart` 和 `test/assistant_tool_result_test.dart`；无 Native、数据库或路由变更。D 工作流仍 PARTIAL，不能宣称工具已成为 Headless/Executed Capability。
- 合并后将 PR #44/#47/#48/#49/#50 的 base 刷新为当前 master `c0983da`；GitHub mergeability 重新计算后均显示可合并，但不能替代各 PR 的当前基线 CI。
- 最新 CI：
  - #44 HEAD `9f7d61b`：run `43037901376`，Flutter regression QUEUED；branch validation SKIPPED。
  - #47 HEAD `074619a`：run `43037173941`，Flutter regression SUCCESS；Android arm64 job `130581944576` IN_PROGRESS。
  - #48 HEAD `fd2e1b5`：run `43037179378`，Flutter regression SUCCESS；Android arm64 job `130582177174` IN_PROGRESS。
  - #49 HEAD `c63632e`：run `43037313916`，Flutter regression SUCCESS；Android arm64 job `130582272371` IN_PROGRESS。
  - #50 HEAD `82d16b2`：run `43038226181`，Flutter regression IN_PROGRESS；branch validation SKIPPED。
- #50 在 #46 合并前开始运行，需确认其当前 PR base 已刷新为 c0983da；如果最终 CI 不覆盖合并后的 master 树，需再触发当前基线验证。
- 当前未取得 master push workflow 的完整 run 列表；不能宣称 c0983da 的主线 CI 全绿。

### 下一项执行队列（最新）

1. 完成 #44/#47/#48/#49/#50 CI；失败时读取具体 step/log 并修复。
2. #47/#48/#49 的旧 run 起始于 #46 合并前，集成前确认最终 merge tree 包含 #46 后重新验收。
3. #50 writer/stage schema 通过后，继续设计 F 的生产 trace_id 注入；目前不能执行完整设备 TRACE。
4. E：重建清除数据实现的无冲突子切片，避免直接合并旧 #39 对 MainActivity/LocalAiInterviewScreen 的整分支改动。
5. B：继续审计结构化问诊、附件、历史恢复、Native MethodChannel 的所有旁路；未完成医学审核时保持 RELEASE BLOCKED。
6. C：补 source manifest 与派生 query provenance；检索算法保持不变。
7. G：#49 防漂移测试通过后集成；保持 README 与 pubspec 的当前版本一致。


## 15. B/G 文档与策略测试切片集成（2026-11-11 最新）

- PR #49 G 版本防漂移测试已 squash 合并：`3fed30c73595febc93e355f81b6a0720925c51c9`。测试读取 `pubspec.yaml` 的 version，并校验 README 当前版本声明；历史 Release Notes 不参与比较。
- PR #47 B-02 语义边界测试已 squash 合并：`97c47195f78776aba62ff52b97542b2a15d5a0bd`。新增 UNKNOWN/quoted/主体时间极性不明 -> CLARIFY、coverage 不完整 -> REVIEW_REQUIRED、非 CLEAR 不继续普通流程等测试。只证明策略状态契约，不证明生产 detector/入口接入。
- PR #48 B-03 入口审计已 squash 合并：`ef522bf7cb39c57b0190c1eaad06fbffc1d7088e`。当前 master HEAD 更新为该 SHA。
- #47 的 run `43037173941`：Flutter regression SUCCESS，Android arm64 CI APK/native unit tests SUCCESS，branch validation SKIPPED。
- #48 的 run `43037179378`：Flutter regression SUCCESS，Android arm64 CI APK/native unit tests SUCCESS，branch validation SKIPPED。
- #49 的 run `43037313916`：Flutter regression SUCCESS，Android arm64 CI APK/native unit tests SUCCESS，branch validation SKIPPED。
- 上述 run 在 #46/#49/#47 等集成前后分批触发；所有单项 CI 已通过，但不替代对最终 master 合并树的完整主线 CI。当前未取得 master push run 的完整记录。

### 15.1 仍打开的主工作 PR

| PR | 任务 | HEAD | 最新可读 CI | 状态 |
|---|---|---|---|---|
| #44 | G 唯一执行台账 | `c332f8671660a2b3826f64e00463254e7a0ccbab` | run `43038636801` Flutter regression IN_PROGRESS；branch validation SKIPPED | base 已刷新到 master `ef522bf`；等待 |
| #50 | F TRACE writer + stage schema + Find N2 方案 | `82d16b2cf1b0b53bb33131ee8bcf4a45c68b17c1` | run `43038226181` Flutter regression IN_PROGRESS；branch validation SKIPPED | base 已刷新到 master `ef522bf`；等待 |

#50 的 Android arm64 job 尚未启动/未出现在当前 job 列表；不能将其写为 PASS。#50 的当前工作树在 #47/#48/#49 合并前启动 CI；集成前需确认新 base 下的最终回归。

### 15.2 A-G 状态校正

- A：PARTIAL。master 已有 GPU 失败转 CPU 重建、空回复恢复等修复摘要；未以该摘要代替用户要求的设备 TRACE。
- B：PARTIAL / RELEASE BLOCKED。#47 策略测试、#48 入口审计已集成；自然语言 detector、所有 Flutter/Native 入口前置门禁、医学审核仍缺失。
- C：PARTIAL。真实黄金快照已有；source manifest、原始书目/卷页定位、derived-query provenance 未闭合。
- D：PARTIAL。#46 参数来源 UNKNOWN 契约已合并；工具实际业务执行、source ID、结果验证、跨轮回传未形成完整 TRACE。
- E：PARTIAL。#39 仍是旧基线且与主线 MainActivity/LocalAiInterviewScreen 有重叠；不能整 PR 合并。需重建清除服务/附件/数据库原语后再集成 UI/Native 编排。
- F：PARTIAL。#50 待 CI；即使通过也只是 writer + stage schema，不等于生产 trace_id 接线。
- G：IN_PROGRESS。README/pubspec 自动一致性测试已合并；唯一执行台账 #44 等待 CI。

### 15.3 下一步

1. 等 #44/#50 CI 结束；失败读取日志后修复。
2. #50 通过后，下一独立 F 切片先冻结 Dart/Native trace_id 注入契约，再选择不与 A/B/E 冲突的最小入口。
3. E 从 #39 提取不与 MainActivity/LocalAiInterviewScreen 重叠的数据库与附件清理原语；单独做失败注入和部分失败回滚测试。
4. B 继续只读检查所有入口，医学审核未完成前不得将策略变为生产放行。
5. C 补来源定位和 query provenance；禁止更换检索算法。
