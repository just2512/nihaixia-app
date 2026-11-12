# AI 能力静态/动态审计报告

- 审计日期：2026-11-12
- 仓库：`just2512/nihaixia-app`
- 审计基线：`master @ eefa56e9cf159c5533de1c35556f82aa4c873a4f`（2026-11-12，#86/#87/#88 集成后）
- 约束来源：`docs/ai-capability-audit.md`、`docs/ai-modernization-execution-ledger.md`
- 方法：读取当前 master 代码、专项测试、PR diff、GitHub Actions job/step/log、CI 生成的检索快照；未执行 Find N2 真机测试。

## 1. 审计结论

当前系统已具备统一助手主入口、确定性问诊规则引擎、本地知识检索、SQLite 会话持久化、基础工具路由、TRACE 事件记录骨架和 AI 数据清理编排。但“有代码/有页面/有测试”不等于端到端能力完成。

| 工作流 | 状态 | 关键结论 |
|---|---|---|
| A 多轮稳定性 | PARTIAL | Native Activity teardown 串行化、SQLite 原子轮次与错误可见性已有 CI 证据；Find N2 GPU/CPU、媒体和进程恢复 TRACE 未闭环 |
| B 红旗安全 | PARTIAL / RELEASE BLOCKED | preflight provenance 契约存在；自然语言 detector、全生产入口 fail-closed 和医学审核仍缺失 |
| C 检索基线 | PARTIAL | 黄金快照与精确方剂修正已合并；候选身份、谓词、sourceId、原始位置及来源逐条审查仍未完成 |
| D Headless Capability | PARTIAL | 主线已有 2 项 Headless/Executed（yunqi、almanac）；其余 22 项仍为 Page-only，结构化问诊为内联流程 |
| E 数据保护 | PARTIAL | 清理入口、附件归属、SQLite 边界测试、模型/TRACE 备份排除已合并；混合 SQLite 备份、旧共享图片与真机重启验证仍未闭环 |
| F TRACE | PARTIAL | per-turn trace_id 已接入普通文本/图片/语音统一助手轮次和消息 metadata；结构化问诊、工具/检索阶段及真机 TRACE 未闭环 |
| G 文档治理 | PARTIAL | 审计报告、能力清单和执行台账已更新；README/pubspec 自动防漂移检查仍待实现 |

## 2. A：多轮稳定性与持久化

### 已核验

- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt`
  - MethodChannel 任务通过单线程 `aiExecutor` 串行执行。
  - `runAiTask` 对 Exception 与 Throwable 都回传错误，避免 Dart Future 因 Native 任务失败永久 pending。
  - 多轮推理失败后只恢复此前成功轮次，不自动重放当前执行状态未知的请求。
  - `onDestroy` 将 `releaseLocalModel` 排入 executor 后调用 `shutdown()`，没有等待 teardown 完成的确认。
- `lib/data/database_helper.dart`
  - `saveAssistantTurn` 在同一个 SQLite transaction 中写入 user/assistant 消息并更新 conversation metadata。
  - 任一插入/更新失败应整体回滚。
- `lib/screens/local_ai_interview_screen.dart`
  - `_persistSuccessfulTurn` 调用 `saveAssistantTurn`。
  - 持久化异常会向用户显示“本轮回复已生成，但保存到历史记录失败”的状态。

### 当前新增验证

PR #77 已合并：真实 SQLite FFI 测试成功写入两条消息；使用 SQLite trigger 拒绝 assistant insert，断言 user insert 一并回滚。CI run `43144699629` Flutter 1326 passed / 15 skipped / 0 failed，Android arm64 APK/ABI 与 unit tests SUCCESS。合并提交 `e279d7a4ce65edc5a32d7521231f57c413db6895`。

### 未闭环

- Native Activity destroy / executor shutdown 与新 Activity 初始化之间的竞态尚未被设备/集成测试证明。
- Native transcript、Flutter UI、SQLite transcript 的逐轮一致性仍缺少设备 TRACE。
- Find N2 GPU/CPU 各至少 20 轮、图片/语音、进程中断恢复均未取得本轮真实 TRACE。

## 3. B：红旗门禁

### 已核验

- `lib/services/red_flag_preflight.dart` 已定义 input source、subject、time、polarity、detector ID/version、rule-set version、coverage 与 reviewed 状态。
- provenance 缺失、未知语义范围或未审核规则集不能返回 CLEAR。
- PR #71 已合并；CI run `43143105547` 的 Flutter regression 与 Android arm64 CI 成功。

### 发布阻断

- 该文件只负责评估结构化 `RedFlagAssessment`，本身不从自然语言识别红旗。
- 当前没有证据证明 `LocalAiInterviewScreen` 每轮发送、历史恢复、附件转写、工具结果回流、Native 直接调用等所有路径都在模型和普通业务路由之前执行 preflight。
- 医学词表、阈值和处置文案没有医学背景审核记录。

因此 B 仍为 PARTIAL / RELEASE BLOCKED。不能通过写一组人工构造 assessment 的单测来宣称真实自然语言门禁已完成，也不能自行补充未经医学审核的规则。

### 生产入口逐项定位（本轮补充）

- `LocalAiInterviewScreen._send()` 先处理活动中的结构化问诊选项，再调用 `AssistantConversationOrchestrator.resolve`；当返回 `decision.tool` 时直接进入 `_requestTool`，发生在普通模型发送之前。
- 普通文本随后进入 `_sendTextWithKnowledgeContext`，其中 automatic 无知识命中时调用 `LocalAiService.sendMessage`，其余模式调用 `sendMessageWithContext`；两者最终均通过 Native MethodChannel 的 `sendMessage`。
- 图片/录音分别调用 `LocalAiService.sendImage` / `sendAudio`，最终进入 Native `sendImage` / `sendAudio`。
- “整理本次症状”调用 `LocalAiService.extractSymptoms`，最终进入 Native `extractSymptoms`。
- 当前 `local_ai_interview_screen.dart` 未接入 `RedFlagPreflight`。因此门禁不能只放在 `sendMessage`；必须先于活动问诊答案处理、工具路由、文本模型调用、图片/录音模型调用和症状整理调用。历史恢复还需保留原始轮次的门禁 provenance，不能把历史文本当作新输入重复生成。
- Native MethodChannel 当前模型相关入口为 `sendMessage`、`sendImage`、`sendAudio`、`extractSymptoms`；另有 `restoreConversation` 恢复历史上下文。Native 层仍可被绕过 Flutter UI 的调用触达，因此生产契约还需确定是否在 Native 层做第二道边界校验。
- 图片/录音的红旗语义不能假设等同于用户文字；如果没有可审计的转写/视觉 detector 和输入来源证明，状态必须是 UNKNOWN/REVIEW_REQUIRED，不能静默 CLEAR。


## 4. C：检索黄金基线与发现

### 基线证据

- 测试：`test/ai_retrieval_golden_snapshot_test.dart`
- 固定夹具：`test/fixtures/ai_retrieval_golden_metadata.json`
- CI：run `43143105547`，golden snapshot 步骤 SUCCESS
- CI artifact：`ai-retrieval-golden-snapshot`，artifact ID `13911060760`
- 主请求：`查桂枝汤组成，并找《伤寒论》对应条文`

### 快照结果

| Query | 命中总数 | 捕获数 | 前三来源 |
|---|---:|---:|---|
| 原始自然语言 query | 0 | 0 | 无 |
| 桂枝汤 | 196 | 40 | `shanghan:assets/shanghan/clause_001.md`、`clause_014.md`、`clause_015.md` |
| 桂枝 | 294 | 40 | 同上 |
| 伤寒论 | 121 | 40 | `clause_000.md`、`clause_008.md`、`clause_013.md` |

最终上下文状态为 RETRIEVED，9 个 source IDs；所有 9 项书目/卷页定位均为 MISSING。命中来源是 App 本地资料，其中伤寒论命中标识为“伤寒论讲稿”，不能冒充已核验的仲景原文版本。

### 需要继续审查的行为

最终上下文含 `formula:guizhi_tang`、`formula:mahuang_tang`、`formula:wumeiwan`、`formula:wuling_san` 四个方剂来源。当前 `AssistantKnowledgeContextBuilder.build` 会按方剂组成药名扩展候选；请求中“桂枝”是“桂枝汤”的子串，因此可能带入用户未直接点名的方剂。该现象目前作为相关性审查项记录，不直接判定为错误，也不在没有对照用例前修改检索语义。

## 5. D：工具能力边界

- 文件：`lib/screens/assistant_tool_router.dart`
- 当前注册表有 24 项定义。
- `structured_diagnosis` 由 `LocalAiInterviewScreen` 内联执行；其余 23 项通过 Widget builder 打开既有页面。
- `AssistantToolArguments.validateAgainst` 目前提供 tool ID、未声明参数、必填项、日期、整数、枚举值校验。
- 未发现统一 Headless execute/result 协议、可取消执行器、统一超时/失败语义、权限域声明及真实执行回传证据。

因此页面打开仍不能算工具执行。后续须按工具逐项确认实际业务函数、参数和结果来源，再选择最小 adapter；不得以注册表名称或模型口头声称成功作为证据。

## 6. E：数据清理与附件

- PR #73 已将 TRACE writer/recorder 进程级共享，并与清理流程协调停止、flush 和恢复。
- PR #76 增加设置页清除入口、二次确认、逐域结果和模型保留说明。首次全量回归唯一失败为新增直接调用 `showDialog` 违反 `fold_aware_navigation_contract_test.dart`；已改用 `showFoldAwareDialog`。前一修复 head 的 run `43145157603` Flutter 1326 passed / 15 skipped / 0 failed；当前 head `5ee908134f27e15caf907a0751c580fbed92a13a` 的 run `43147357775` PENDING。前一 head run `43146455398` 唯一失败是测试仍查找旧警告文案，已同步更新断言；更早 head `43145157603` Flutter 1326 passed / 15 skipped，但不是当前 head 结论。
- PR #78 从当前 master 重建生产附件归属迁移；新图片/录音进入 AI-owned 目录。成功复制后，仅删除 app temp root 内的 image_picker 缓存源文件；外部 provider 路径不删除。清理流程仅额外删除 temp root 下精确匹配 `local_ai_<digits>.wav` 的旧录音，不递归、不清除普通文件或未知图片。当前 head `6c3fb70bba38bff3831fea27dfcdadba5994dc48` 的 run `43148511074` PENDING。前一 head的 targeted recorder test 已通过；full regression 发现另一录音文件检查测试仍使用真实 store，已注入 fake store 并固定帧等待。
- `LocalAiAttachmentStore.clearAll` 只枚举专属目录的直接子项，不递归共享 temp 目录。
- Android 主 Manifest 未显式设置 `allowBackup`，未声明 `fullBackupContent` / `dataExtractionRules`；当前没有 merged manifest 证据，不能推断 Android 各版本实际备份结果。

旧版本共享临时目录中的孤儿图片缺乏足够的 AI 归属证据，不能按通用 image_picker 文件名前缀批量删除。Android backup 全局禁用会影响非 AI 用户数据，必须单独论证，不属于本轮设置入口切片。

## 7. F：TRACE

- writer/recorder 默认关闭。
- 已有字段 allowlist、关闭后不生成 ID/不写入、写入失败不传播、disableAndFlush 等自动化测试。
- PR #73 只解决进程级 runtime 共享和清理生命周期协调。
- 尚无同一 trace_id 从 Dart 输入贯穿红旗、路由、检索、Native MethodChannel、模型调用、工具结果、UI 展示和 SQLite 持久化的完整证据。

F 仍 PARTIAL。

### F 契约冻结

本轮新增 `docs/ai-trace-contract.md`，明确单轮唯一 trace_id、默认关闭时不生成 ID、Dart→MethodChannel→Kotlin 原样回传、SQLite 复用 `assistant_messages.metadata`、UNKNOWN 状态和隐私字段 allowlist。该文档是实现约束，不是实现证据；当前生产代码仍没有 trace_id 全链路，F 继续 PARTIAL。


## 8. G：文档与版本

- `pubspec.yaml`：`1.11.30+8039`
- `README.md`：`1.11.30+8039`
- 版本文本一致。
- `docs/ai-capability-audit-report.md` 作为审计报告独立于约束文件创建；不得将审计结论写入/覆盖 `docs/ai-capability-audit.md` 的规范部分。

## 9. 当前 CI / PR 快照

| PR | Head SHA | CI | 结论 |
|---|---|---|---|
| #73 | `81e4ba88010954f8437a6c42ff281e871e732e0e` | run `43143105547` | MERGED；Flutter SUCCESS；Android arm64 SUCCESS；Branch validation SKIPPED |
| #76 | 已合并 `eaa83b440ddb1299a7eac58b70067de38ad44ea2` | run `43147357775` | MERGED；Flutter/Android SUCCESS |
| #77 | `f52ecfbd8dd0627fe608f3152744ed146a205dec` | run `43144699629` | MERGED；Flutter/Android SUCCESS |
| #78 | `6c3fb70bba38bff3831fea27dfcdadba5994dc48` | run `43148511074` | PENDING；录音文件检查测试已补 fake store |

旧 PR #74 已关闭，由当前 master 基线 PR #78 替代。所有未完成 CI 均不得作为合并依据。

## 12. PR #76 集成与 A Native teardown 后续

- 当前 master：`eaa83b440ddb1299a7eac58b70067de38ad44ea2`；PR #76 设置页清理入口已通过 Flutter regression 和 Android arm64 CI 并合并。
- PR #78 当前 head `6c3fb70bba38bff3831fea27dfcdadba5994dc48`，run `43148511074` PENDING；旧版录音 allowlist 和 picker app-temp source cleanup仍未进入 master。
- PR #80 新增进程级单线程 Native 队列，Activity teardown release 排在新 Activity model work 前；当前 head `fc640d431eb58a62a81d507e663674fd1a746e28`，run `43148298845` Flutter regression IN_PROGRESS，Android arm64 尚未启动。
- PR #80 不是 Find N2 真机验收；Activity recreation、GPU/CPU 后端和多轮 TRACE 仍 UNKNOWN。
## 11. 最新 CI 纠偏

- #76 当前 head `5ee908134f27e15caf907a0751c580fbed92a13a`，run `43147357775` PENDING；上一 head 的唯一失败为测试断言仍匹配旧警告文案，已修复。
- #78 当前 head `23efe6b625b88eabeae475c5374a8cea8dd8b9a4`，run `43147189070` PENDING；上一 head 的失败包括 malformed raw RegExp 与 widget test fakeAsync 文件系统边界，已重建 store 并用 fake store 隔离录音重试 UI 测试。
- #79 文档 PR 本身会因本次报告/台账更新继续产生新 head；合并前必须读取 PR 最新 head 并验收对应 CI，不能沿用旧文档提交的 run。
- 任何旧 head 的成功/失败都不能替代当前 head 的最终验收。

## 10. 下一步

1. 先完成 #76 fold-aware 修复后的 Flutter 全量回归和 Android arm64。
2. 完成 #77 SQLite trigger 故障注入测试。
3. 完成 #78 附件归属迁移的录音重试、全量 Flutter 和 Android 验收。
4. 每个切片通过后小批量合并并刷新 master SHA。
5. 继续 E 的旧附件归属和 Android merged manifest/backup 核验；不删除无法证明属于 AI 的文件。
6. 继续 A 的 Native teardown 状态矩阵和 Find N2 真机测试准备。
7. 继续 F trace_id 契约与生产调用链接入。
8. 继续 B 全入口 detector 接入设计，医学审核未完成前保持发布阻断。
9. 继续 C 相关性对照测试，不擅自改变已锁定检索行为。
10. 继续 D 24 项工具逐项 Headless 审计。


---

## 2026-11-12 当前主线增量复核（master b786f84）

本节覆盖旧审计结论中与本次合并发生冲突的状态；未列为完成的项目仍按原审计标准处理。

### A. Native 与会话可靠性：PARTIAL

- PR #80 已合并：Activity 销毁时把 Native release 排在进程级串行队列中；新 Activity 的模型初始化排在释放之后；销毁后尚未执行的任务被拒绝。
- PR #78 已合并：生产问诊图片、录音进入 AI 专属附件目录，不再把共享临时目录当作 AI 所有权目录。
- PR #77 已合并：assistant turn 的双消息持久化原子性测试。
- 尚缺 Find N2 真机 GPU/CPU 长轮次、图片/语音、多轮切换、进程重启与 TRACE 证据；设备验收保持 UNKNOWN。

### B. 医学红旗安全：PARTIAL / RELEASE BLOCKED

- PR #71 已合并：结构化 preflight 的 detector/rule-set provenance 契约；缺失 provenance 不可标 CLEAR。
- 当前 preflight 仍不是自然语言 detector；已审查的红旗词表、阈值、处置文案和医学审核缺失。
- 生产聊天文本、图片/语音转写和 Native 直接调用路径仍未证明全部经过 fail-closed gate。系统提示词中的急症提醒不等于确定性安全门。
- 不得自行补造医学规则；在 detector 与医学审核完成前，B 不得标 PASS。

### C. 检索与方剂匹配：PARTIAL

- PR #81 已合并：精确方名查询优先返回精确方剂，单味药组成检索仍保留独立候选路径；黄金 metadata 已按实际输出差异复核。
- 后续仍需逐条审查 subject/object、sourceId、原始位置、来源可靠性和重复候选；不以候选数量增加为目标。

### D. 工具能力：PARTIAL

- 24 项 AssistantToolRouter 注册能力已在能力清单逐项列出：23 个 Widget 页面 builder，1 个结构化问诊特殊内联流程。
- PR #85 正在实现第一个双入口能力：`yunqi` 保留页面 builder，同时增加同步 Headless executor；只有显式日期才自动执行，无日期仍走页面确认。当前 PR 尚未合并，不能计入主线 Headless/Executed 数量。
- 其他页面不因注册、匹配或打开而视为 Executed。

### E. 本地 AI 数据清理与备份：PARTIAL

- PR #76：设置页清理入口已合并。
- PR #78：生产附件归属迁移已合并。
- PR #82：SQLite FFI 集成测试已合并，覆盖 AI 表清理、非 AI 表保留、数据库重开后状态，以及删除失败时事务回滚。
- PR #83：已合并 Android 备份规则，排除本地模型目录和 TRACE 文件；Android CI 的 merged manifest 检查通过。
- AI 会话与非 AI 业务数据仍共用 SQLite 数据库，故 Android 系统备份仍可能保留 AI 会话行。禁止排除整个数据库或关闭全应用备份来掩盖该问题。
- 无法可靠归属的旧共享临时图片、外部导出副本仍不在可证明清理范围；Find N2 真机清理后重启仍 UNKNOWN。

### F. trace_id：PARTIAL

- PR #73：默认关闭的 writer/recorder 与清理生命周期协调已合并。
- PR #84：Dart → MethodChannel → Native 推理响应的可选 `trace_id` 桥接已合并；采用 snake_case、32 位小写十六进制校验，Native 回显不一致时失败。
- 尚未在统一聊天 UI 每轮生成 ID、将其写入 SQLite message metadata，也未串联 dispatch/retrieval/tool/result/presentation 阶段。F 不能标为端到端完成。

### G. 审计与治理：PARTIAL

- 本次审计台账、能力清单、TRACE 契约正在当前基线更新；README/pubspec/CI 版本一致性检查仍需单独闭环。


## 2026-11-12 后续增量复核（master `5f7bf738ad5894e2de7fd5903d8d6002e3fe6502`）

### D：Headless capability

- PR #85 已合并，主线 `yunqi` 具备 Page + Headless 双入口；复用既有确定性计算，结果校验参数、source ID 与 status。主线 Headless / Executed 当前各 1 项。
- PR #86 为第二项候选 `almanac`，复用 `getDailyAlmanac`，限制日期格式和 1900-2100 范围，拒绝非法日期/未知参数；未合并前仍计为 Page-only。当前 head `18ecc81a...`，changed-test validation SUCCESS，PR Flutter regression PENDING，尚无 Android arm64 证据。

### F：TRACE per-turn

- PR #87 将默认关闭 recorder 接入统一助手普通文本、图片、语音模型轮次，并把同一 trace_id 写入现有 user/assistant message metadata；不新增表/列。
- 独立症状提取调用也接入 traced Native API。已记录 input、native inference、model output、persistence、final render；持久化失败不会记为成功。
- PR #87 当前 head `abef4bb9...`，changed-test validation SUCCESS，PR Flutter regression IN_PROGRESS；旧 head 静态分析和测试注入错误已修复，不能把旧失败算作当前 head 结果。
- structured diagnosis、clarification/tool dispatch、retrieval 分阶段、失败轮次持久化关联和 Find N2 真实 TRACE 仍缺失。

### A-G 当前结论

- A PARTIAL：Native teardown 串行化已合并；设备级 GPU/CPU 长轮次与媒体/重启 TRACE UNKNOWN。
- B PARTIAL / RELEASE BLOCKED：没有经医学审核的自然语言 detector、词表、阈值和处置文案；不自行补造。
- C PARTIAL：精确方剂检索修正已合并；候选身份、谓词、来源、原始位置继续逐条审计。
- D PARTIAL：主线 1 项 Headless/Executed；#86 待验收。
- E PARTIAL：设置清理、附件归属、SQLite 边界和模型/TRACE 备份规则已有 CI 证据；混合数据库 AI 行备份、无法归属的旧共享图片和真机清理重启仍缺证据。
- F PARTIAL：#87 待验收；跨所有路由与端到端设备 TRACE 未完成。
- G PARTIAL：本轮 ledger/inventory/report 已刷新；版本一致性自动检查仍待实现。

当前 master workflows：Flutter Quality Gate run `43161470395` IN_PROGRESS，Flutter tests run `43161470467` PENDING。PR #86/#87 的所有状态均按当前 head 记录，不得用旧 SHA 的 CI 覆盖。


---

## 13. 2026-11-12 #86/#87/#88 集成后复核（master `eefa56e9cf159c5533de1c35556f82aa4c873a4f`）

### 13.1 主线集成事实

- PR #86 已 squash merge，提交 `870362ae8ba92e25b195c62d9fc0be653d19600f`：`almanac` 复用 `getDailyAlmanac`，保留页面入口，增加日期参数校验、结构化结果、source ID 和民俗免责声明。
- PR #87 已 squash merge，提交 `34c1fa11c61b83d75b0c01ac6272a39d0cbf4537`：统一助手普通文本/图片/语音轮次按 TRACE 开关使用 traced Native API，同一 trace_id 写入 user/assistant message metadata；不新增表或列。
- PR #88 已 squash merge，提交 `eefa56e9cf159c5533de1c35556f82aa4c873a4f`：审计报告、能力清单、执行台账更新进入主线。该文档提交本身的状态记录由本节覆盖。
- PR #86 最新 head `18ecc81a4ff6a18757386d39632b9a8567ae8b37`：Flutter regression run `43162562989` SUCCESS；Android arm64 APK/ABI、merged manifest 和 Native unit tests 同一 run SUCCESS；Branch validation SKIPPED。
- PR #87 最新 head `abef4bb9dc09ed6f2e690a06bdc76669067b7432`：Flutter regression run `43162529437` SUCCESS；Android arm64 APK/ABI、merged manifest 和 Native unit tests同一 run SUCCESS；Branch validation SKIPPED。
- PR #88 最新 head `68e4e9ccf1c845bfe1d11b7bcae07af3d9d282f2`：Flutter regression run `43162775931` SUCCESS，Android arm64/merged manifest/Native unit tests SUCCESS；独立 branch validation run `43162770440` SUCCESS（其 Flutter/Android job按文档变更跳过）。
- PR #86/#87 的旧 head failure/cancelled 记录不覆盖上述最终 head 的成功结果。

### 13.2 当前主线 CI

当前 master `eefa56e9cf159c5533de1c35556f82aa4c873a4f` 的合并后 CI：
- Flutter tests run `43164417582`：IN_PROGRESS（本节写入时）。
- Flutter Quality Gate run `43164416766`：IN_PROGRESS（本节写入时）。
- 不能沿用父提交 `5f7bf738...` 的 SUCCESS 代替新 master 验收；待本 SHA 两个 workflow 结束后更新最终结论。

### 13.3 A-G 状态（本次复核）

| ID | 状态 | 当前证据与未闭环项 |
|---|---|---|
| A | PARTIAL | Native teardown 串行化、SQLite 原子轮次、CI 回归已合并；Find N2 GPU/CPU 各至少 20 轮、图片/语音、Activity/进程恢复 TRACE 仍 UNKNOWN。 |
| B | PARTIAL / RELEASE BLOCKED | provenance 契约已合并；无自然语言 detector、全入口 fail-closed 证据及医学审核记录。不得编造词表/阈值/处置文案。 |
| C | PARTIAL | 精确方剂匹配与黄金快照已合并；继续按 subject/object ID、类型、文本、谓词、sourceId、原始位置和来源逐条审查；不以候选数量增加为目标。 |
| D | PARTIAL | 主线 Headless = 2、Executed = 2（`yunqi`、`almanac`）；其余 22 项 Page-only，结构化问诊保持独立内联流程。 |
| E | PARTIAL | 清理入口、生产附件归属、SQLite 清理边界/回滚测试、模型与 TRACE 文件备份排除已合并；混合 SQLite 中 AI 行仍可能进入系统备份，旧共享图片归属未知，Android 清理后进程重启/不可恢复 TRACE 缺失。 |
| F | PARTIAL | per-turn trace_id 已覆盖普通文本/图片/语音 unified assistant 调用、Native response 校验和 user/assistant metadata；结构化问诊、澄清/工具执行、检索阶段细分、失败轮次持久化关联和 Find N2 TRACE 未完成。 |
| G | PARTIAL | 三份治理文档已刷新；README/pubspec 自动版本一致性 guard 尚未实现。 |

### 13.4 下一批自动推进任务

1. **B（最高优先级，安全阻断）**：完成五种模式、initialPrompt、历史续聊、图片/录音、症状整理、工具回流、Native 入口的调用旁路矩阵；先实现无医学规则时不会返回 CLEAR 的 fail-closed 契约和纯 Dart 测试。未经医学审核的词表/阈值不得启用。
2. **F（依赖 B 接口）**：将 per-turn trace context 延伸至结构化问诊、澄清/工具 dispatch、检索、结果验证/展示；每一阶段保留默认关闭和不记录敏感正文。
3. **E**：核对清理 coordinator 每个数据域的真实删除调用，特别是 Native model cache、TRACE、AI-owned attachments；验证 Android 进程重启后状态。混合 SQLite 备份的 AI 行风险单独记录，不误排除整个数据库。
4. **C**：执行候选身份/关系/来源逐条审查，比较原始候选与过滤后候选，检查 subject/object ID、实体类型、文本、谓词、sourceId、原始位置；不以数量作为目标。
5. **A**：补充 Native teardown/Activity recreation 的自动化状态矩阵；Find N2 GPU/CPU、媒体和多轮 TRACE 必须由真实设备提供。
6. **D**：对剩余 22 项 Page-only 工具逐项确认是否存在可复用的确定性业务函数；每次只实现一个有行为基线的低风险 Headless adapter。
7. **G**：建立 README 与 pubspec 版本单一来源检查，并将当前审计 SHA、workflow/run ID 纳入自动一致性验证。

### 13.5 当前边界

- CI SUCCESS 仅证明指定提交的自动化构建/测试；不替代 Find N2 真机 TRACE。
- B 在 detector 和医学审核完成前保持 RELEASE BLOCKED。
- E 不得删除无法证明属于 AI 的共享临时文件；不得全局关闭 Android backup 或排除混合数据库。
- F 不得把 per-turn 的普通文本/图片/语音接入夸大为所有模式的端到端 TRACE。


---

## 14. 2026-11-12 集成复核（master `b47397922d9348f89cc7a5586b7ca1b0659a63f5`）

### 14.1 本轮已合并交付

- #93：新增 `RedFlagGate` / `RedFlagDetector` 纯 Dart fail-closed 契约。detector 未配置、异常、超时、assessment 缺失、来源不匹配、来源未知或内容缺失时返回 REVIEW_REQUIRED；扩展 image/audio/toolResult/retrievalContext 来源类型。**未接入生产入口，不含医学 detector。**
- #94：统一助手检索路径新增 retrieval、contextAssembly、modelInput TRACE 阶段；检索只记录状态、耗时、source IDs 和稳定错误码，不记录 query/正文。修复玄学模式普通文本绕过 traced API 的路径。
- #95：刷新 E 数据清除审计，确认 coordinator、AI 专属附件目录、Native runtime cache、TRACE writer、设置 UI 与 SQLite 四表事务均已落地；保留混合 SQLite 备份和 Find N2 重启缺口。
- #96：用真实 CI artifact 更新经典检索黄金复核，补充 120 条 hit 的 sourceId/asset 一致性和跨 query 重叠分析。
- #92：在 #94 合并后又向主线补入玄学模式 TRACE 测试（commit `8f7aa7c5d5ad7805f0b985cb583edacac722f935`）。

### 14.2 CI 证据

| PR | 最新相关 run | Flutter | Android arm64 / Native | 结论 |
|---|---:|---|---|---|
| #89 | `43164663954` | SUCCESS | SUCCESS | 文档同步已合并 |
| #91 | `43164955584` | SUCCESS | SUCCESS | 红旗入口旁路审计已合并 |
| #93 | `43165576958` | SUCCESS | SUCCESS | B1 gate contract 已合并；Branch validation `43165568953` SUCCESS |
| #94 | `43165512584` | SUCCESS | SUCCESS | 检索/上下文 TRACE 已合并；Branch validation `43165481369` SUCCESS |
| #95 | `43165925272` | SUCCESS | SUCCESS | E 数据清除审计已合并 |
| #96 | `43166311719` | SUCCESS | SUCCESS | C 黄金检索审计已合并 |

#93 初始提交曾因 const 构造器中的 Duration 比较断言触发编译错误；已移除不兼容的 const assert，最终 head `3ec9a8c3...` 的 Flutter 与 Android CI 均通过。旧失败 run 不覆盖最终 head 的成功结果。

当前 master `b47397922d9348f89cc7a5586b7ca1b0659a63f5`：
- Flutter tests run `43167309805`：IN_PROGRESS（本节写入时）。
- Flutter Quality Gate run `43167309687`：IN_PROGRESS（本节写入时）。
- 不沿用父提交 SUCCESS 代替当前 SHA 的验收。

### 14.3 A-G 状态

| ID | 状态 | 当前事实 | 未闭环 |
|---|---|---|---|
| A | PARTIAL | Native teardown/串行任务、SQLite 原子轮次、错误可见性有 CI 证据 | Find N2 GPU/CPU 多轮、媒体、Activity/进程恢复 TRACE |
| B | PARTIAL / RELEASE BLOCKED | fail-closed gate contract 已合并 | 自然语言 detector、医学审核、全生产入口调用及旁路测试；gate 尚未接入生产 |
| C | PARTIAL | 黄金 artifact、metadata fixture、4 query、候选身份结构核对已合并 | 83 个不同讲稿资产的内容/条文映射逐条人工核验；纸本版本/卷页仍 MISSING |
| D | PARTIAL | Headless/Executed = 2（yunqi、almanac） | 其余 22 项 Page-only；第三个 adapter 需先证明确定性业务函数与来源 |
| E | PARTIAL | 清理 coordinator、附件归属、Native cache、TRACE、SQLite 边界测试和 UI 已落地 | 混合 SQLite 备份副本、旧共享图片、外部副本、Find N2 强制停止/重启证据 |
| F | PARTIAL | per-turn trace_id 覆盖普通文本/图片/语音；新增 retrieval/contextAssembly/modelInput；玄学模式走 traced API | structured diagnosis、clarification/tool dispatch、Headless/Page 工具、失败轮次及 Find N2 TRACE |
| G | PARTIAL | 审计报告、能力清单、执行台账、B/C/E 专项审计已刷新 | README/pubspec 版本单一来源 guard 和证据状态自动防漂移 |

### 14.4 本轮关闭的过期/冲突 PR

- #19：关闭。全局 `android:allowBackup=false` 会连带关闭收藏、设置、诊断历史等非 AI 数据备份，违背 AI-only 范围要求。
- #60、#70、#90：关闭。旧执行台账分支已被当前主线文档刷新覆盖。
- #69：关闭。TRACE runtime/coordinator 生命周期逻辑已进入主线，当前主线版本包含后续错误处理和并发保护。
- #72：关闭。旧数据清除审计已由 #95 当前基线复核覆盖。
- 上述 PR 均以 superseded/冲突范围为由关闭，不合并旧基线内容。

### 14.5 下一批工作队列（按依赖顺序）

1. **B2：生产入口接入设计与测试 seam**。以 #91 的旁路矩阵为依据，先补所有入口的注入点和调用顺序测试；在医学 detector 未审核前，不得让缺失 detector 伪装 CLEAR。全局 REVIEW_REQUIRED 对助手可用性的影响需要单独明确，不能静默关闭全部能力。
2. **F4：工具与结构化问诊 TRACE**。先覆盖 clarification/dispatch、Headless executor、Page 工具返回、structured diagnosis 状态变化；继续只写阶段、状态、耗时、source IDs，不记录敏感正文。
3. **C2：83 个 distinct sourceId 逐条内容核验**。检查标题/正文命中位置、讲稿解释与原文边界、候选是否真正对应查询；无底本证据继续 MISSING，不改排序/检索算法。
4. **E2：Find N2 清除后进程重启验收**。覆盖 Native 运行中/空闲、附件存在、TRACE 开关两态、部分失败、强制停止/重启；同步评估 AI 独立数据库隔离，不能用全局禁用 backup 代替。
5. **A2：Find N2 多轮稳定性与恢复**。补 GPU/CPU 真实模型长轮次、图片/语音、Activity recreation、进程重启及 TRACE。
6. **D2：审计剩余 22 个 Page-only 工具**。逐个确认纯业务函数、参数契约、副作用、来源 ID 和可重复结果；选择一个低风险候选做最小 adapter，不批量迁移。
7. **G2：版本与证据治理自动化**。README/pubspec 单一版本来源、审计 SHA、CI run 和 A-G 状态一致性 guard。

### 14.6 执行规则

- 不创建定时任务或周期性巡检；CI 只作为当前代码切片验收。
- 独立分支按文件所有权隔离；小批量集成后以最新 master SHA 重新跑 CI。
- 普通测试失败自动定位修复并继续；架构、安全、数据不可逆和产品决策边界才暂停。
- 本轮未执行 Find N2 真机测试；A/E/F 设备级结论保持 UNKNOWN。
