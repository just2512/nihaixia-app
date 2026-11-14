# AI 能力静态/动态审计报告

- 审计日期：2026-11-14（PR #153 易经四种起卦模式 Headless 集成后增量复核）
- 仓库：`just2512/nihaixia-app`
- 最新复核基线：`master @ 59ca2a746d8dc4d29abb06f52697d02ce52a26df`
- 约束来源：`docs/ai-capability-audit.md`、`docs/ai-modernization-execution-ledger.md`
- 方法：以 master 当前 HEAD 对照规范性审计文件和执行台账，复核 AssistantToolRouter 的 24 项注册、10 项 Headless executor、PR/merge SHA 与 Actions；未重新执行全仓逐层静态审计，未执行 Find N2 真机测试。历史章节的旧 SHA 仅代表当时审计快照。

## 1. 审计结论

当前系统已具备统一助手主入口、确定性问诊规则引擎、本地知识检索、SQLite 会话持久化、基础工具路由、TRACE 事件记录骨架和 AI 数据清理编排。但“有代码/有页面/有测试”不等于端到端能力完成。

| 工作流 | 状态 | 关键结论 |
|---|---|---|
| A 多轮稳定性 | PARTIAL | Native Activity teardown 串行化、SQLite 原子轮次与错误可见性已有 CI 证据；Find N2 GPU/CPU、媒体和进程恢复 TRACE 未闭环 |
| B 红旗安全 | PARTIAL / RELEASE BLOCKED | preflight provenance 契约存在；自然语言 detector、全生产入口 fail-closed 和医学审核仍缺失 |
| C 检索基线 | PARTIAL / NOT VERIFIED | 已复核 83 个 distinct sourceId 的本地资产存在性、身份和正文命中语境；83/83 bibliographic locator 仍 MISSING，纸本底本/版本/卷页/影像未核验 |
| D Headless Capability | PARTIAL | 当前 24 个定义中，23 个常规页面入口有 10 项 Headless executor（yunqi、almanac、bazi、xiaoliuren、meihua、chenggu、huangdi_siji、ziwei、solar_terms、yijing），13 项仍 Page-only；structured_diagnosis 为单独内联确定性流程 |
| E 数据保护 | PARTIAL | 清理入口、附件归属、SQLite 边界测试、模型/TRACE 备份排除已合并；混合 SQLite 备份、旧共享图片与真机重启验证仍未闭环 |
| F TRACE | PARTIAL | 已覆盖检索/上下文、Orchestrator/Headless、结构化问诊 per-turn；#113 补 Headless 结果契约失败终态，#114 补 Page Tool 结果延续，#115 补普通发送/症状整理 finalRender；Find N2 场景集 TRACE 仍未闭环 |
| G 文档治理 | 版本源子目标 IMPLEMENTED | README/pubspec/Flutter CI/Android CI/Release tag 一致性 guard 已合并；当前 master post-merge CI 需以最新 SHA 的两条独立 push workflow 为准 |

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

## 14. 2026-11-12 当前主线复核（master `2d2df1393cc5e77e6a7a8ce71f4fb52f11bf603c`）

### 14.1 本轮已集成

- #92：修复玄学模式普通文本调用 bypass，统一走 traced Native API。
- #97：Orchestrator route/dispatch 与 Headless 执行阶段 TRACE。
- #99：raw image/audio 红旗输入不能被伴随 prompt text 冒充已评估；返回 `RAW_ATTACHMENT_NOT_ASSESSED`。
- #100：README/pubspec 版本源检查进入 Flutter regression 和 Android arm64 CI；Release tag 与 pubspec 版本校验。
- #101：structured diagnosis 启动、选项回答、舌脉提交和消息 metadata per-turn TRACE。
- #102：83 个 classic retrieval source assets 内容核验文档合并。

### 14.2 CI 证据

| PR | Flutter regression | Android arm64/Native tests | Branch validation |
|---|---|---|---|
| #92 | `43165079874` SUCCESS | `43165079874` SUCCESS | SKIPPED |
| #97 | `43167373011` SUCCESS | `43167373011` SUCCESS | SKIPPED |
| #99 | `43168152545` SUCCESS | `43168152545` SUCCESS | SKIPPED |
| #100 | `43168612465` SUCCESS | `43168612465` SUCCESS | SKIPPED |
| #101 | `43169514825` SUCCESS | `43169514825` SUCCESS | SKIPPED |

PR #102 为文档更新。当前 master 合并提交 `2d2df139...` 没有可核验的独立 post-merge workflow run，主线独立 CI 状态仍为 UNKNOWN。

### 14.3 A-G 状态

- **A PARTIAL / UNKNOWN：**自动化 teardown 与 Android arm64 构建证据存在；OPPO Find N2 GPU/CPU 多轮、图片/语音、Activity recreation、进程恢复 TRACE 未执行。
- **B PARTIAL / RELEASE BLOCKED：**raw attachment 来源边界已 fail closed；仍缺经医学审核的自然语言 detector 和所有生产模型入口的 fail-closed 集成证明。
- **C PARTIAL：**83/83 本地讲稿资产存在并逐项读取；83/83 bibliographic locator 仍 MISSING。经典原文/版本/卷页溯源不能由讲稿标题推断。
- **D 2/2 Headless + Executed：**`yunqi`、`almanac`；不为数量扩展第三项。
- **E PARTIAL：**数据清理范围与 backup manifest 有 CI 检查；混合 SQLite 备份、旧共享附件归属、外部导出副本和真机重启后不可恢复性仍需核验。
- **F PARTIAL：**检索/上下文、route/dispatch、Headless、structured diagnosis per-turn TRACE 已接入；persistedState/恢复/失败轮次与真机 TRACE 未闭环。
- **G IMPLEMENTED（版本源子目标）：**README/pubspec/Flutter CI/Android CI/Release tag 版本一致性门禁已合并；主线 post-merge CI 仍 UNKNOWN。

### 14.4 版本审计旧记录更新

本报告早期版本基线曾记录 README `1.11.28+8037` 漂移。该旧问题已由 PR #100 解决：README 当前仓库版本与 `pubspec.yaml` 的 `1.11.30+8039` 一致；新增 `tool/check_version_source.sh`，并由 Flutter regression、Android arm64 CI 执行；Release workflow 强制 `vX.Y.Z` 与 pubspec `X.Y.Z+N` 的 `X.Y.Z` 匹配。旧记录作为历史审计发现保留，不再代表当前状态。


---

## 15. 2026-11-12 PR #93-#96 / #104 增量复核

- #93 已集成 fail-closed RedFlagGate contract：detector 缺失、异常、超时、assessment 缺失、source mismatch/unknown、输入内容缺失时返回 REVIEW_REQUIRED。该契约尚未接入生产调用入口，也没有医学审核 detector；B 继续 PARTIAL / RELEASE BLOCKED。
- #94 已集成 retrieval、contextAssembly、modelInput TRACE，并修复玄学模式普通文本 traced Native API 旁路；只记录状态、耗时、source IDs 和稳定错误码。
- #95 已更新数据清除范围证据：coordinator、AI-owned attachments、Native runtime cache、TRACE 文件、设置 UI 和 SQLite AI 四表事务有代码/测试证据；混合 SQLite backup、旧共享图片/外部副本及 Find N2 重启验收仍缺。
- #96 的真实 CI artifact 包含 4 个 query、120 条 top-40 hits、83 个 distinct sourceId；sourceId/asset 一致，但 120 条 locator 均 MISSING。该结果证明快照可复现，不证明古籍出处已核实。
- #104 已将 structured interview 的任务状态持久化和 UI presentation 纳入 TRACE；Flutter regression、Android arm64/merged manifest/Native unit tests 均通过。master post-merge workflow 仍在执行时，不把当前主线 CI 写为整体 PASS。
- 历史 `restoreConversation` 不属于新用户轮次，按 TRACE 契约不得生成新 trace_id；PR #105 因违反该约束关闭，未合并。

### A-G 结论
A PARTIAL / 设备 UNKNOWN；B PARTIAL / RELEASE BLOCKED；C PARTIAL / locator MISSING；D Headless/Executed = 2；E PARTIAL / 真机重启 UNKNOWN；F PARTIAL / 失败轮次关联和真机 TRACE 未闭环；G 版本源一致性子目标已完成，master post-merge CI 尚待最终结论。


---

## 17. 2026-11-12 PR #106/#107 集成后复核（master 5a9d2c7fccd4b291982d39699fe929eaa968a6fe）

### 17.1 集成与自动验收

- PR #106 已合并，merge commit：fb315306bf76dd1a3545b50758e92214e888cac0（执行台账刷新）。
- PR #107 已合并，merge commit：5a9d2c7fccd4b291982d39699fe929eaa968a6fe；只修改 local_ai_interview_screen.dart 与对应 widget test。
- PR #107 head db6309d29e847fe9c4bad3c53921d240f681fcdd，run 43187508718：Flutter 全量 regression SUCCESS；Android arm64 APK/ABI、merged backup manifest、Native unit tests SUCCESS；Branch validation SKIPPED（不计 PASS）。
- 新 master 5a9d2c7 的独立 push workflows：Flutter Quality Gate run 43195424227、Flutter tests run 43195424259。本次复核时两者均 IN_PROGRESS；因此 master post-merge CI 暂记 IN_PROGRESS，不沿用 PR head CI 代替。

### 17.2 F：失败轮次状态关联增量

- Native 推理完成与结果校验完成分别记录；EMPTY_REPLY 表示 Native 调用完成但回复契约校验失败；TRACE ID mismatch 保持 UNKNOWN。
- Native 推理失败且持久化未开始时记录 persistence=NOT_STARTED、conversationId（若可得）及稳定错误码，不把未保存用户输入伪装成历史消息。
- 持久化开始后异常时记录 persistence=UNKNOWN，不错误标记为 NOT_STARTED；持久化明确返回失败时仍记录 FAILED。
- 症状整理成功与格式失败分别记录 Native inference / resultValidation 状态。
- 不新增数据库表/列，不自动重放 UNKNOWN 请求，不改变用户输入保留、手动重试和历史恢复语义。
- F 仍 PARTIAL：该增量不是所有模式的完整 TRACE；结构化问诊/工具/恢复的端到端失败终态与 Find N2 真机 TRACE 仍缺。

### 17.3 B：红旗门禁生产入口复核

当前主线静态复核确认：
- RedFlagGate / RedFlagPreflight 已有 fail-closed 策略契约与纯 Dart 测试；Gate 只接收外部 detector assessment，没有自然语言 detector 实现。
- local_ai_interview_screen.dart、local_ai_service.dart、Android MainActivity.kt 未引用/调用 RedFlagGate 或 RedFlagPreflight；生产入口尚未接入。
- Flutter 入口包括活动结构化问诊选项、Orchestrator/工具路由、Headless/Page 工具、文本/图片/语音发送、症状整理；Native MethodChannel 仍可直接进入对应模型函数。
- 未取得医学审核规则集、detector 语义覆盖证明或 Find N2 入口 TRACE。B 继续 PARTIAL / RELEASE BLOCKED。
- 不把 detector 缺失时的 REVIEW_REQUIRED 偷换为默认 CLEAR；也不在没有产品影响评估和医学审核的情况下静默启用全局阻断。

### 17.4 C：来源身份与定位复核

- 经典检索黄金快照已有 83 个 distinct lecture sourceId；83/83 本地 Markdown asset 存在且可读，sourceId 与 asset 路径对应。
- 83/83 的 bookId/chapterIndex 缺失，locatorStatus=MISSING，bibliographicLocatorVerified=false。本地文件可回链不等于古籍底本/版本/卷页已核验。
- docs/classic-rule-source-manifest.json 的范围仅为 DiagnosticRules.combinedPatterns 当前 12 条：7 条 ONLINE_TEXT_CROSS_CHECKED、3 条 CONDITIONS_CROSS_CHECKED、2 条 MISSING；12/12 的纸本底本、卷、页和原始影像核验字段仍为 MISSING。
- 该 12 条规则 manifest 不能替代 83 个讲稿 sourceId 的来源映射；不得据此补造讲稿到古籍条文的一对一关系。另行对照 DiagnosticRules.combinedPatterns：12/12 conditionKey 与 manifest 精确对应，无缺项、额外项或重复键；这证明清单覆盖完整，不代表来源真实性已核验。
- 不调整 query 派生、top-40 上限、排序、去重或引入 FTS5。

### 17.5 A-G 状态与剩余硬门槛

| 项目 | 当前状态 | 尚未关闭的工作 |
|---|---|---|
| A Native 多轮/生命周期 | PARTIAL / 设备 UNKNOWN | Find N2 GPU/CPU 多轮、图片/语音、Activity recreation、进程中断/恢复真实 TRACE |
| B 红旗安全 | PARTIAL / RELEASE BLOCKED | 经过医学审核的 detector/规则集；Flutter 与 Native 全生产入口强制门禁；入口顺序测试与设备 TRACE |
| C 检索来源 | PARTIAL | 83 个讲稿条目的人工条文映射/底本定位；12 条规则 manifest 的纸本版本与影像核验 |
| D Headless | 2 项 Headless / 2 项 Executed | 保持现状；无确定性业务函数与行为基线前不新增 adapter |
| E 数据清理/备份 | PARTIAL | 混合 SQLite AI 行备份边界、旧共享附件归属、外部副本、Find N2 清理后强停/重启不可恢复验收 |
| F TRACE | PARTIAL | 失败轮次基础状态已补；结构化问诊/工具/恢复端到端状态与 Find N2 TRACE 仍缺 |
| G 版本治理 | 版本源子目标 IMPLEMENTED | master 5a9d2c7 post-merge workflows 尚在运行；以两条主线 run 终态为准 |

**下一步顺序：** B 先完成无医学规则的入口调用顺序 seam/测试设计，但不擅自上线未审核 detector；并行推进 C 来源 manifest 真实性核验；随后 A/E 真机与备份边界验收。D/G 不扩展。

---

## 18. 2026-11-12 PR #109 集成后红旗门禁复核

- 当前 master：`00258671cf87188ac7ef82f5121c6f5bea48ef7e`（PR #109 squash merge）。
- 新增 `RedFlagGate.runBefore` 仅提供通用 gate-before-operation 顺序和显式执行状态；配套测试证明 gate 先于副作用、detector 缺失和 raw image attachment 时不执行受保护操作。
- 本次 PR 未将 Gate 接入 `LocalAiInterviewScreen`、`LocalAiService` 或 Android `MainActivity`。生产入口状态不变，仍为 MISSING。
- PR head 的 Flutter regression、Android arm64/Native tests 通过（run `43200924284`）；独立 branch validation 通过（run `43200883925`）。PR run 中被跳过的 branch validation job 不计为 PASS。合并提交的独立 post-merge workflow 尚无可核验 run，保持 UNKNOWN。
- B 状态：Gate sequencing contract = IMPLEMENTED（CODE + TEST + PR CI）；自然语言 detector = MISSING；医学审核 = MISSING；Flutter/Native 全入口调用 = MISSING；Find N2 TRACE = UNKNOWN。B 仍 PARTIAL / RELEASE BLOCKED。

### 下一步限制

B2 生产接入不能采用“可选 Gate 为空时跳过”方案，否则形成旁路；也不能在无医学审核 detector 时把 REVIEW_REQUIRED 默认改为 CLEAR。将 Gate 直接接入全部入口会阻断现有 AI 流程，需先完成医学审核和产品影响决策。未取得这些外部条件前，只推进不改变产品放行行为的入口审计、顺序契约与测试准备，不宣称生产门禁已完成。


---

## 19. 2026-11-12 PR #113/#114/#115 集成后复核（master `bfb518ef68bfc674d1af9699e410f4729dbbc3bc`）

### 19.1 最新主线与验收证据

- 当前 master：`bfb518ef68bfc674d1af9699e410f4729dbbc3bc`。
- PR #113（merge `1b13dea7d1b239089d7d14e2810febf9a6f343bf`）：为 Headless 结果契约失败分支增加可控负向回归；PR run `43214895957` 的 Flutter regression、Android arm64 APK/ABI、merged backup manifest、Native unit tests 均 SUCCESS；独立分支验证 run `43217158541` SUCCESS。
- PR #114（merge `bb7d2897105c0a52577924ea3d35ccee8ea735cf`）：修复 Page Tool 结果 continuation TRACE；PR run `43217988520` 的 Flutter regression 和 Android arm64/Native CI 均 SUCCESS；独立分支验证 run `43217978870` SUCCESS。
- PR #115（merge `bfb518ef68bfc674d1af9699e410f4729dbbc3bc`）：补普通发送与症状整理的 finalRender 终态；PR run `43219648145` 的 Flutter regression 和 Android arm64/Native CI 均 SUCCESS；独立分支验证 run `43219357882` SUCCESS。
- PR workflow 中被跳过的 Branch validation job 不计 PASS；上列独立 push run 是各分支的静态分析与 changed-tests 证据。
- 最新 master 独立 post-merge workflow：Quality Gate run `43221099813`（本次复核时 IN_PROGRESS），Flutter tests run `43221099907`（本次复核时 PENDING）。在两者终态完成前，当前 master 的整体 post-merge CI 保持 IN_PROGRESS/UNKNOWN。

### 19.2 F TRACE 最新复核

**#113 Headless 结果拒绝**
- 真实进入 `RESULT_CONTRACT_INVALID` 分支，断言 `resultValidation=FAILED`、`persistence=NOT_STARTED`、`finalRender=SUCCEEDED`。
- 断言无无效结果写入会话，避免以成功路径测试冒充失败分支覆盖。

**#114 Page Tool 返回结果**
- Page Tool 打开动作沿用原始 user-turn `trace_id`；结果消息 metadata 保存同一 ID。
- 同一 TRACE 记录 `toolExecution`、`businessExecution`、`resultValidation`、SQLite `persistence`、`persistedState` 与 `finalRender`。
- 历史恢复仅复用消息内已有 ID；旧历史无 ID 时保持 TRACE disabled，不为 `restoreConversation` 创建新用户轮次。
- SQLite 消息持久化与 Native context restore 分开记录，避免将模型上下文重建成功误报为 SQLite 持久化成功。

**#115 普通发送与症状整理**
- 症状整理的空结果、用户取消、确认成功、Native 异常、模型输出格式错误和 screen disposal 均补齐 `finalRender`。
- 普通发送的模型未就绪早退、screen disposal、Native 平台异常和通用异常补齐最终展示状态；不改变模型路由、对话内容、规则问诊和数据库 schema。
- 自动回归覆盖症状整理空结果/确认成功，以及 Native 发送异常后的可见错误和 `finalRender` 终态。

**判定：** 本轮 F 的三个具体断点已合并，并具备 CODE + TEST + PR CI 证据。整体 F 仍为 PARTIAL，因为完整场景集、GPU/CPU 真机、多媒体、多轮、Activity/进程恢复和数据清理后的设备 TRACE 尚未取得；不得把代码覆盖面增加等同于 Find N2 实测通过。

### 19.3 A-G 当前结论

| 工作流 | 状态 | 当前证据与未闭环项 |
|---|---|---|
| A 多轮稳定性 | PARTIAL / DEVICE UNKNOWN | 生命周期、轮次持久化和恢复路径有自动化证据；Find N2 GPU/CPU、媒体、Activity recreation、进程杀死/重启后的 transcript 一致性仍无真实 TRACE |
| B 红旗安全 | PARTIAL / RELEASE BLOCKED | fail-closed Gate 与调用顺序 contract 已测试；自然语言 detector、医学审核规则集、Flutter/Native 生产入口强制门禁和入口 TRACE 缺失。不能默认 CLEAR |
| C 检索来源 | PARTIAL / NOT VERIFIED | 83/83 Markdown assets 存在并已逐项读取；sourceId/asset 身份、query 重叠和正文命中语境已复核；83/83 bibliographic locator 仍 MISSING。12 条规则来源行中 7 条 ONLINE_TEXT_CROSS_CHECKED、3 条 CONDITIONS_CROSS_CHECKED、2 条 MISSING；纸本版次/卷页/原始影像 12/12 缺失 |
| D Headless Capability | 2 HEADLESS / 2 EXECUTED | `yunqi`、`almanac`；不以数量为目标 |
| E 数据保护 | PARTIAL | 数据清除链、AI-owned attachments、Native cache、TRACE 文件、SQLite AI 表事务和 backup manifest 有代码/测试；混合 SQLite 备份、旧共享图片归属、外部副本和 Find N2 清除后强停/重启仍未核验 |
| F TRACE | PARTIAL | #113 Headless reject、#114 Page Tool continuation、#115 send/symptom finalRender 已合并；Find N2 场景级完整 TRACE 仍缺 |
| G 版本治理 | VERSION GUARD IMPLEMENTED | README/pubspec/Flutter/Android/Release tag 一致性 guard 已合并；`bfb518e` 独立 post-merge CI 尚未结束 |

### 19.4 下一阶段与禁止扩展项

1. 收尾 master `bfb518e` 的两条独立 post-merge workflow；若有失败，仅根据失败 job 修复。
2. A/E：按 `docs/local-ai-e4b.md` 执行 OPPO Find N2 实机验收，覆盖内外屏、GPU/CPU、连续多轮、图片/语音、Activity/进程恢复、数据清理后强停/重启；没有设备/模型/backend/trace_id 记录的场景保持 UNKNOWN。
3. B：没有医学审核 detector 和产品放行决策前，维持 RELEASE BLOCKED；不得将可选 Gate 缺失当作放行，也不得全局阻断现有功能来制造“已接入”假象。
4. C：只接受能回链到真实底本、版次、卷页或原始影像的 locator 证据；无证据仍 MISSING，不改 query、top-40、排序、去重，不引入 FTS5。
5. D/G：维持 2 项 Headless 和现有版本 guard；不增加无失败证据支持的 adapter 或第二套版本治理。

本次不引入 Agent/DAG、额外数据库表、向量数据库、云端模型/API 或新的业务产品能力。静态/自动化证据、模拟设备与 Find N2 真机 TRACE 分开判定。



---

## 20. 2026-11-13 PR #117/#119/#120 集成后的 A/F 增量复核

### 20.1 基线与范围

- 复核对象：`master @ 3363a29d94fa0c9e0c87587d71553fc870fcede7`。
- 运行时代码对应 `07cae6810db412e608ff0d3e2c0dcf1c872105be`；`3363a29` 是随后仅更新执行台账的文档提交，不改变应用代码。
- 本节只补充此前报告第 19 节之后已合并的 A/F 代码增量。没有重新执行五种模式的全仓静态审计；B/C/D/E/G 状态以同日执行台账第 22 节为准。
- `docs/ai-capability-audit.md` 仍是约束文件，本轮没有修改或降低其验收门槛。

### 20.2 已合并代码与可复核定位

| PR | 合并提交 | 变更事实 | CODE / TEST |
|---|---|---|---|
| #117 结构化问诊 transcript 原子写入 | `872a715a3817a57c8b4dd708a33f6b3a13c428c0` | 引入有序消息批量写入；一组 transcript 行和 conversation 标题/预览在同一个 SQLite transaction 中提交或回滚；普通 user/assistant turn 复用该事务；无 schema migration / 新表 | `lib/data/assistant_conversation_store.dart:33-40`；`lib/data/database_helper.dart:438-531`；`lib/screens/local_ai_interview_screen.dart:1509-1519`；`test/assistant_history_persistence_test.dart:404-545` |
| #119 transcript 与 task snapshot TRACE 分离 | `5d73161b49fd3f38ffada31c0da1b06e7d24bec0` | `_appendTcmInterviewMessages` 返回 typed persistence result；`persistence` 只反映 transcript batch；`persistedState` 单独反映可恢复问诊快照；快照写入失败不再把已成功提交的 transcript 错报为失败，并向用户显示恢复风险 | `lib/screens/local_ai_interview_screen.dart:1422-1597`；`test/local_ai_interview_screen_test.dart:1049-1110` |
| #120 Native Activity release failure fail-closed | `849ec817f6e11f154ea662316b32b2fbfa230ffc` | 新增进程级 `LocalAiProcessHealth`；Engine/Conversation 释放失败后当前进程不可继续执行本地模型任务；任务入队前和串行队列实际执行前均检查健康状态，关闭 Activity 重建竞态；需强制停止并重启进程后才能恢复 | `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiActivityTaskLifecycle.kt:14-96`；`android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiActivityTaskLifecycleTest.kt:75-140` |

### 20.3 回归断言与 CI 证据

- `assistant_history_persistence_test.dart` 的原子成功用例核对消息顺序、metadata、conversation title 和最后一条 preview；后续插入失败用例通过 SQLite trigger 注入失败，断言前序消息与会话 metadata 一并回滚。
- `local_ai_interview_screen_test.dart` 的“结构化问诊消息已保存但任务快照失败时分别标记 persistence 和 persistedState”用例验证：transcript 已保存、task snapshot 缺失、用户收到恢复警告、`persistence=SUCCEEDED`、`persistedState=FAILED` 且错误码为 `TASK_STATE_PERSISTENCE_FAILED`，最终展示状态闭合。
- Kotlin 用例 `releaseFailureBlocksWorkQueuedByARecreatedActivity` 验证旧 Activity release 失败后，新 Activity 已排队任务在触及 Engine 前被拒绝；后续提交也被立即拒绝。它验证的是同进程队列竞态，不是设备上的 Engine 真实释放行为。

| PR head | Workflow run | Flutter regression | Android arm64 / Native | Branch validation |
|---|---:|---|---|---|
| #117 `132f6c4f` | `43238225000` | SUCCESS | SUCCESS | SKIPPED |
| #119 `94964cb6` | `43242639810` | SUCCESS | SUCCESS | SKIPPED |
| #120 `9ed99aa6` | `43342006102` | SUCCESS | SUCCESS | SKIPPED |

PR head 的 Flutter regression 和 Android job 均已成功；Branch validation 是该触发事件下被跳过的独立 job，不计为 PASS，也不影响上述已完成 job 的结论。

PR #121 合并后的主线 `07cae681` 自动化验收：
- Flutter tests run `43344902200`：Flutter regression、静态分析、全量回归、SQLite persistence/reopen、assistant history、AI contract、retrieval golden snapshot 和 Android arm64/Native job SUCCESS。
- Flutter Quality Gate run `43344902148`：静态分析、Dart tests、Android Native unit tests、Find N2 arm64 Debug APK build SUCCESS。
- Flutter tests 内的 Branch validation 为 SKIPPED，单独保留该事实。
- PR #122 只更新执行台账；其 PR run `43346632662` 的 Flutter regression 与 Android arm64/Native jobs SUCCESS。它不是 Find N2 真机验收。

### 20.4 A/F 当前判定

| 工作流 | 当前状态 | 本轮已证实 | 仍未证实 / 硬缺口 |
|---|---|---|---|
| A Native 多轮、生命周期与持久化 | PARTIAL / DEVICE UNKNOWN | 结构化问诊 transcript 原子批量持久化；SQLite 后续行失败整体回滚；transcript 与 task snapshot 的持久化状态分开报告；Native release failure 后进程级 fail-closed；相关 Flutter/Kotlin 回归及 PR/master CI 通过 | OPPO Find N2 GPU 至少 20 轮、CPU 至少 20 轮；图片/语音；Activity recreation；请求中断、强停/重启与历史恢复；SQLite、Flutter UI、Native history 逐轮一致性；`state:7` 根因仍 UNKNOWN |
| F TRACE 与隐私 | PARTIAL / DEVICE UNKNOWN | #113/#114/#115 的 Headless reject、Page Tool continuation、send/symptom finalRender，及 #117/#119/#120 的 transcript rollback、task snapshot 独立状态、Native lifecycle release failure 终态均有 CODE + TEST + PR CI | Find N2 场景集从输入到最终展示/持久化的真实完整 TRACE；多轮、媒体、Activity/进程恢复与数据清除后复查 |

以上证据只支持对应代码路径与自动化测试通过，不将 A 或 F 标为 IMPLEMENTED。

### 20.5 A-G 全局状态与下一步

当前 A-G 状态与下一动作以执行台账第 22 节为准，摘要如下：

| 工作流 | 当前状态 | 下一项允许推进的工作 |
|---|---|---|
| A 多轮稳定性 | PARTIAL / DEVICE UNKNOWN | Find N2 GPU/CPU 多轮、媒体、Activity/进程恢复真实 TRACE；不再用 CI 代替设备结果 |
| B 红旗安全 | PARTIAL / RELEASE BLOCKED | 先取得医学审核记录与 detector/REVIEW_REQUIRED 产品决策；未审核前不接入生产放行路径、不默认 CLEAR |
| C 知识来源 | PARTIAL（学习资料回链已实现；原文/规则来源分层） | 83 个讲稿 sourceId 对应本地 Markdown 资产，检索结果携带来源类别、标题、sourceId 和回链；12 个规则 conditionKey 对应 manifest | 一般学习资料不要求逐页纸本校勘；指定古籍原文和诊断规则仍需单条来源核验。12 条规则当前7条在线文本交叉核对、3条条件交叉核对、2条 MISSING |
| D Headless Capability | 2 项 Headless / 2 项 Executed | 冻结；没有可复现失败和真实需求，不新增 adapter |
| E 数据保护 | PARTIAL | 明确混合数据库备份边界决策；Find N2 上验证清除后强停/重启不可恢复；旧共享附件归属不明时保留 |
| F TRACE | PARTIAL / DEVICE UNKNOWN | 与 A 同批完成 Find N2 端到端场景 TRACE，不另建埋点体系 |
| G 版本与证据治理 | VERSION GUARD IMPLEMENTED | 只维护现有版本 guard 和证据一致性，不新增第二套治理 |

**停止条件：** A/F 的设备门槛需要真实 OPPO Find N2 与本地模型；B 需要医学背景人员审核和产品决策；C 需要可回链的原始底本/影像；E 需要备份边界决策及设备清除验证。缺少这些外部条件时，相关项保持 PARTIAL / UNKNOWN / RELEASE BLOCKED。不得通过增加普通 CI、模拟器测试、文档描述或重复静态检查将其改写为 PASS。

**范围约束：** 本轮没有更改问诊/辨证规则、红旗词表、模型 prompt、检索 query/ranking、数据库 schema、Android backup policy 或业务路由；没有引入 Agent/DAG、FTS5、向量检索、云端 API 或额外 Headless adapter。

---

## 21. 2026-11-13 C：学习知识库来源验收口径收敛

### 21.1 已有来源链路事实

- `ClassicSearchService` 为命中生成稳定 sourceId：讲稿使用 `shanghan:assets/shanghan/<asset>.md`；古籍文本使用书名/章节标识。sourceId 是可反查的 App 内来源键，不冒充纸本页码。
- `AssistantKnowledgeContextBuilder` 通过 sourceId 反查命中，输出 `sourceLabel`、`sourceKind`、本地回链和来源状态；测试覆盖稳定 ID、未知 ID 不模糊回退、引用反查、讲稿与古籍文本区分，以及医案来源缺失边界。
- 2026-11-13 的来源分层 manifest 记录：Golden Snapshot 中83个 distinct sourceId 对应83个不同本地 Markdown 资产。该证据证明检索来源能回到本地资料，不证明这些讲稿是原始古籍版本。
- 当前 `assets/shanghan/clause_*.md` 的实际性质是课程讲稿/整理讲义，内容可能混合条文摘录、讲解和经验性观点；应作为学习资料归属展示，不得把讲稿内摘录自动等同已核验的仲景原文。

### 21.2 本次用户确认的产品定位

- 本应用知识库用于中医学习，不以建设古籍校勘数据库为目标。一般学习检索只要求资料类别清楚、来源名称/标题清楚、sourceId 可反查、本地内容可定位。
- 不再将83条讲稿逐一追溯到纸本版本、卷、页或原始影像作为普通学习检索的完成条件。`bibliographicLocator=MISSING` 继续保留为事实状态，但不再等价于“没有学习资料来源”。
- 对明确声称某一古籍原文/指定版本，或来源被用于 DiagnosticEngine 诊断规则的内容，继续执行更严格的单条文本与适用条件核验；不能核实时说明是“讲稿所引/本地摘录”或标记 MISSING。
- 医案仍明确标记为本地整理案例；来源缺失不阻止一般学习检索，但内部序号不能冒充原始出处，病例不能被描述为疗效证据。

### 21.3 C 项当前拆分状态

| 子项 | 状态 | 说明 |
|---|---|---|
| 学习讲稿 sourceId/本地资产回链 | PASS（源码与自动化契约范围） | 83/83 Golden Snapshot sourceId 与本地资产对应；可按 sourceId 反查；未把它扩大解释为纸本溯源 |
| 学习内容来源标识展示 | PASS（当前来源契约） | 具备来源类型、来源标签/标题、sourceId 和本地回链；本轮将讲稿引用尾注调整为学习资料语义 |
| 83条讲稿的纸本卷页/原始影像定位 | NOT REQUIRED FOR GENERAL LEARNING | 仅在某条内容被明确当作指定版本原文引用时定点核验，不做全量考古式映射 |
| 12条规则来源 | PARTIAL | 7 ONLINE_TEXT_CROSS_CHECKED、3 CONDITIONS_CROSS_CHECKED、2 MISSING；规则运行安全边界不因讲稿回链通过而放宽 |
| 医案来源/疗效证据 | PARTIAL / MISSING | 作为本地整理案例检索；未核实原始出处不做确切归属或疗效论证 |

本拆分不修改 `docs/ai-capability-audit.md` 第4.3节的来源类型与反伪造要求，也不放宽红旗门禁、医学审核、规则引擎或 Find N2 真机验收标准。

---

## 22. 2026-11-13 AI 结果解释与知识库综合能力复核

### 22.1 验收目标

用户确认的产品定位是：本 App 是本地中医学习知识库和领域工具，不是医学诊断软件。AI 不应替代确定性业务引擎，而应利用已有数据做理解、总结、关联、比较与解释。

本轮将“发挥 AI 能力”拆成三条可核验链：

1. 本地知识库命中资料 → 来源可回链的上下文 → AI 总结/比较/解释。
2. App DiagnosticEngine 已完成的结构化问诊结果 → transcript/task snapshot → 会话恢复 → AI 解读既有六经/证型/方剂结果，并引用本地知识依据。
3. App 八字/紫微确定性排盘 → Page Tool 结果返回助手 → 结果持久化及 Native transcript 恢复 → AI 解释字段关系、格局/强弱/大运或命宫/四化/大限/已选流层。

AI 只能解释和归纳已有结果，不得新增/修改辨证规则结果、重新排盘、补造缺失来源或把术数内容包装成科学预测。

### 22.2 代码核验结果

**A. 知识库检索与总结**

- `lib/services/assistant_knowledge_context.dart` 的 `AssistantKnowledgeContextBuilder.buildAsync` 继续从 App 本地资料构建上下文，包含来源类型、标题、sourceId、本地回链和使用边界。
- 学习模式 Prompt 已明确要求基于检索命中资料进行总结、比较、归纳和解释，指出共同点、差异、适用条件与来源分歧；课程讲稿、古籍文本、医案、App 数据、AI 归纳必须区分。
- 未检索命中或缺少依据时保持 MISSING，不补造出处。
- 不调整检索 query、top-40、排序、去重或来源状态。

**B. 已完成问诊结果解释**

- 结构化问诊结果由 App DiagnosticEngine 生成并作为消息/transcript 与 task snapshot 持久化。
- 历史恢复路径 `_restoreVisibleConversationToModel` 将可见 transcript 传入 `LocalAiService.restoreConversation`。
- 问诊 Prompt 明确允许 AI 解释、归纳历史中已有的 DiagnosticEngine 结果，并结合本轮知识检索条目说明依据；不得自行新增/改写证型或规则结论，不独立作个体诊断、处方或剂量建议。
- 回归测试用已完成任务状态验证 Native 恢复 transcript 包含“六经/证型/方剂”；这证明数据确实可供模型使用，不替代模型自然语言输出的真机质量验证。

**C. 八字结果解释**

- 八字工具此前返回摘要字段不完整；本轮通过 `lib/services/assistant_chart_result_formatter.dart` 和 `BaZiPaipanScreen._returnAssistantResult` 扩展为完整学习解释上下文。
- 包含出生/排盘口径、四柱、十神、纳音、旬空、刑冲合害、十二长生、各柱自坐、胎元胎息、藏干十神、日主、格局与说明、强弱与可读依据、五行分布状态、用神/忌神、建议、神煞、大运起运时间、每步大运和其所辖流年。
- 不传递内部数值权重；模型被要求基于 App 结果解释强弱、格局、五行与大运关系，不能改四柱或补造缺失值。

**D. 紫微结果解释**

- 紫微工具此前返回结果只有生辰、五行局、命/身宫、命主/身主、生年四化；未包含完整宫星和页面既有解读。
- 当前格式化结果包含 12 宫及星曜、命/身宫、生年四化、`summarizeOverall` 和 `summarizeDecades` 的 App 规则模板结果。
- 如果页面已选择流年、流月、流日，则一并传入对应年份/日期、干支、命宫位置和流曜落宫；没有选择时不自动补算。
- 不包含 `analyzeHealthWatch` 健康提醒，不把疾厄宫/身体部位解释作为医学诊断。
- Prompt 要求先归纳命宫、身宫、四化与十二宫关系，再结合大限分层解释，并区分 App 排盘字段、规则模板和 AI 归纳。

### 22.3 回归证据

| 测试 | 实际验证内容 |
|---|---|
| `test/assistant_chart_result_formatter_test.dart` | 真实本地八字/紫微样例生成摘要；核对八字详批/十年流年、紫微十二宫/四化/整体和大限模板，以及已选流年/流月/流日字段；排除紫微健康提醒 |
| `test/assistant_tool_result_handoff_test.dart` | 通过统一助手打开八字/紫微页面、本地计算并返回；确认结果已保存到助手 timeline 并进入 `restoreConversation` Native model transcript |
| `test/local_ai_interview_screen_test.dart` | 确认问诊上下文具备既有结果解释指令；恢复已完成的结构化辨证会话后，Native transcript 包含六经、证型和方剂 |
| `test/assistant_tool_router_test.dart` | 锁定学习、问诊、工具和术数模式的结果综合提示，不退化成只会导航或原样复制 |

以上是 CODE + TEST 证据。测试使用 fake/recording service 验证上下文交付，**没有调用真实 E4B 模型验证生成答案的语义质量**；Find N2 实机结果需单独提供设备、模型、backend 和实际回答/TRACE 证据。

### 22.4 风险与边界

- 优势：把 App 已经投入开发的本地知识、诊断规则和排盘引擎转换为 AI 可理解的数据上下文，使 AI 可以发挥跨字段总结与解释能力；不需要云 API、向量库、新数据库表或 Agent/DAG。
- 风险：上下文存在长度上限；超长历史、资料冲突、规则未核验、模型对传统术数的概念理解可能影响回答。AI 回答不能反过来修改原始规则/排盘数据；来源 MISSING 时不能补造。
- 医学审核只针对健康风险和红旗门禁等受控路径，不作为普通学习或术数文化解释的统一前置条件。当前红旗 detector/全入口门禁仍需按规范继续收敛，不能默认 CLEAR。
- 真实模型质量（是否能正确比较不同来源、理解字段间关系、解释大运/流年、对缺失项保持克制）仍是 DEVICE UNKNOWN，不能以回归通过替代。

### 22.5 下一步

1. 最新分支 head 的静态分析与 changed tests 成功后创建独立 PR。
2. PR 执行全量 Flutter regression 和 Android arm64 APK、合并 Manifest、Native unit tests；不将 push workflow 的 SKIPPED job 计作 PASS。
3. 合并后确认 master Flutter tests 与 Quality Gate 终态成功，并更新本报告/台账基线。
4. Find N2 本地 E4B 做小批量语义验收：一条本地知识对照、一条完成的结构化问诊结果追问、一条八字详批、一条紫微整体/大限解释、一条选定流年/流月/流日追问。只记录实际返回，逐项核对来源、字段、推理边界与 MISSING 处理；未执行保持 UNKNOWN。



---

## 23. 2026-11-13 PR #128 合并后主线验收记录

### 23.1 交付与 PR CI

- PR #128 已合并，merge commit / 当前 master：`5edba1ea894a435536430640f575f395c42f932e`。
- PR head：`d4a0351fe6216887d1507af0be11c1237708d835`。
- PR CI run `43359969709`：全量 Flutter regression SUCCESS；Android arm64 CI Debug APK build、merged Manifest verification、ABI/SHA-256、Native unit tests 与 XML 结果核验全部 SUCCESS。
- 独立分支 changed-tests/static-analysis run `43359725232` SUCCESS。PR workflow Branch validation SKIPPED 不计 PASS。
- PR 无 unresolved review threads。

### 23.2 Master post-merge

- Flutter tests run `43360881240`：head `5edba1e`，整体 SUCCESS；Flutter regression 与 Android arm64/Native job 均 SUCCESS。
- Flutter Quality Gate run `43360881283`：head `5edba1e`，终态 SUCCESS；静态分析、Dart 全量测试、Native unit tests 和 Find N2 arm64 Debug APK build 全部 SUCCESS。
- 两个 workflow 分开核验后，Flutter tests 与 Quality Gate 均 SUCCESS。

### 23.3 当前 AI 交付边界

- CODE + TEST 证明本地知识命中、已完成结构化辨证结果、八字/紫微完整确定性结果能进入本地模型历史上下文；提示词要求模型做知识综合和结果解释。
- 这不证明真实 E4B 已在 OPPO Find N2 产生正确答案。设备上的回答完整性、来源引用、字段关联、缺失项克制和模型性能仍为 DEVICE UNKNOWN。
- 下一步用合成/非敏感数据做五类 Find N2 真实模型语义验证：本地知识对照、既有问诊结果追问、八字详批、紫微整体/大限、已选流年/流月/流日。记录设备/App SHA/模型/backend/实际输出；未执行保持 UNKNOWN。
- A/F 多轮与生命周期真机验收、B 健康风险红旗门禁和医学审核、E 备份决策与清除后进程重启验收仍各自 PARTIAL/UNKNOWN，不因 PR #128 合并而变更状态。

---

## 24. 2026-11-13 P4 受限意图选择与八字对话收参复核

### 24.1 PR #133：受限 E4B 意图选择已集成

- 主线 merge SHA：`2418a8c5460f4d619aea71f5aa1037b7c38d3a9d`；PR #133 head：`9db9edc231f346a19d93d8b2e759148662ad4ca3`。
- 候选由 `AssistantConversationOrchestrator` 的 L0 产生；仅 2–6 个、ID 唯一且每项都具备 Headless executor 时才可进入模型。
- Native 一次性本地会话只接收用户原文和候选清单；要求严格 JSON `select / clarify / none`。Dart 对输出 schema、TRACE ID、候选 ID 做验证；异常回退 L0。
- 个人健康/症状文本不进入该工具意图分类器；Page Tool 不进入 E4B 候选。此处不能扩写为“所有工具均由 AI 在对话内执行”。

### 24.2 八字 Headless 已有能力与本轮缺参追问

- 已有八字执行器复用本地排盘函数；四项必填出生资料经 Dart 校验后执行；成功结果校验并带来源 ID 后才提供 AI 总结入口。
- 当前参数抽取仍以确定性标签/日期/时间解析为主，不是通用模型槽位抽取。PR #134 只将缺参回复改为动态列示已识别字段、缺失字段及错误字段。
- PR #134 已 squash 合并到 master：merge SHA `34a839ed661740ab7350e61ce8ca90ccc9a3c283`。PR Flutter regression `43407071833`、push validation `43407063342`、master post-merge Flutter tests `43408434463` 和 Quality Gate `43408434562` 均 SUCCESS。
- 该 PR 只动态列示已识别、缺失及错误字段，没有为确定性缺参提示增加模型调用；不计为通用 E4B slot filling。

### 24.3 问诊自然语言入口：当前真实边界

- 当前自由文本症状摘要通过助手界面的“整理本次症状”按钮由用户显式触发 `extractSymptoms`；结果经用户核对/确认后，才出现继续规则辨证操作。
- 但 `_extractSymptoms` 在 Native 模型调用前尚未呈现审计要求的完整确定性红旗拦截证据；现有 Prompt 中的急症提示不等同于代码门禁。
- 因此不得把现状写为已完成“AI 先理解全部症状并按需追问，再后台调用规则问诊”的完整链路。问诊自然语言自动收集/槽位提取仍为 PARTIAL / BLOCKED BY RED-FLAG GATE。
- 此处不要求重新审核已有医学知识库，也不改 DiagnosticEngine 或既有十问；待有审核记录的 detector 规则、阈值、例外和处置文案，并覆盖自动/问诊/学习/工具/玄学、initialPrompt、历史续聊及附件路径后，再接入自由文本症状抽取。

### 24.4 A-G 状态与任务边界

| 项目 | 状态 | 说明 |
|---|---|---|
| A Native 稳定性 | PARTIAL / DEVICE UNKNOWN | Find N2 GPU/CPU 多轮、媒体和进程恢复未完成 |
| B 红旗/问诊安全 | PARTIAL / RELEASE BLOCKED | 缺少全入口模型调用前的确定性 detector 与医学审核记录；不能用 Prompt 替代 |
| C 知识来源 | 当前普通学习来源口径已满足；规则来源 PARTIAL | 不重做 83 条学习讲稿溯源；规则来源缺项维持原状态 |
| D Headless | 3 项：yunqi、almanac、bazi | 不为数量批量转换 Page Tool |
| E 数据保护 | PARTIAL | SQLite 混合备份边界及清除后强停/重启证据未完成 |
| F TRACE | PARTIAL / DEVICE UNKNOWN | 真机跨场景 TRACE 未完成 |
| G 版本治理 | VERSION GUARD IMPLEMENTED | 不新增平行版本治理机制 |

下一步保持窄范围：PR #135 正在实现八字非医疗出生资料的有界 E4B slot extraction（仅缺项且当前消息包含字段线索时触发，逐字 evidence + Dart 语义/业务校验）。完成 PR 全量 CI 和主线复核后，优先补齐已校验工具结果自动解释体验；问诊自由文本入口继续保持在红旗门禁之外不可执行。Find N2 真实模型质量、A/F/E 设备验收不由 CI 代替。

---

## 25. 2026-11-13 PR #135：八字出生参数自然语言槽位抽取

### 25.1 交付边界

- 目标是让 E4B 理解用户自然语言中已有的出生资料，并帮助补充当前缺失项；不是让模型推测资料或执行排盘。
- L0 先执行已有确定性解析。只有缺项且本轮原文出现对应字段线索、本地 E4B ready、TRACE 可用时才调用 Native `extractBaziSlots`；普通“帮我排八字”不为体现 AI 能力而调用模型。
- 原文含症状 cue 时排除该非医疗槽位抽取器；它不承接问诊、辨证、诊断或处方参数。

### 25.2 证据与业务校验链

- 模型只接收本轮用户原文、缺失字段白名单和 TRACE ID；输出固定四字段 JSON。每个非空候选都必须有逐字 evidence。
- Dart 检查证据确实连续出现在用户原文、字段属于本轮缺项、非缺项字段为空、日期/时间/性别/出生地语义有效；任一候选不通过则整体丢弃。
- 候选仍需通过 App `AssistantToolArguments.validateAgainst`；只有四项必填资料完整合法后才调用原有 `BaziToolExecutor`。排盘结果再经过现有结构化结果契约和来源 ID 校验。
- 失败/证据不足回退确定性追问；不会使用模型的猜测值执行。未变更排盘、时区、真太阳时和城市目录算法。

### 25.3 CI 与剩余状态

- PR #135：`https://github.com/just2512/nihaixia-app/pull/135`；master 基线 `34a839ed661740ab7350e61ce8ca90ccc9a3c283`；当前代码 head `140232868612d9e581d8d28d87713db052bab780`。
- 最新 push Branch validation run `43412646761` SUCCESS（Static analysis + changed tests）。PR 全量 Flutter regression run `43412653762` 在本记录时仍运行中；最终合并判定必须以最终 head 的全部必需 job 和 merge 后 master run 为准。
- 当前八字排盘结果的 AI 解读仍需用户点击“AI总结解读”；自动解释仍 PARTIAL。Find N2 真实 E4B 语义、速度和多轮表现仍 DEVICE UNKNOWN。

### 25.4 下一步

1. 合并前完成 PR 最终 head 的全量 Flutter regression、Android arm64 APK/Manifest/ABI/SHA-256 与 Native unit tests，并在 merge SHA 上检查 master workflow。
2. 将“通过结果契约的 Headless 结果自动交给解释 helper”作为下一代码切片，首先覆盖八字，确保显示/持久化仍保留真实结果、source IDs 与模型解释边界。
3. 其余 Page Tool 不批量改造成 Headless。逐项核对是否存在无需 Widget/BuildContext 的确定性业务函数，再挑选下一项最有价值的用户场景。
4. 问诊自然语言入口仍受前置红旗门禁阻断；不重审知识库内容，不修改既有问诊十问或 DiagnosticEngine。医学红旗 detector 的审核记录与全入口覆盖尚未 PASS。

---

## 26. 2026-11-13 PR #136：统一对话中自动解释已校验工具结果

### 26.1 核验结论

- PR #136 基线 master `84a07efbb7713007e30b7a88bff3b4f786b236c6`；最终 PR head `9c7af72a550928f2f58d98c522e7dc83d2c82dd6`；已 squash merge 至 `9fa7f400170569ba6c6b57728c5d26f486b98885`。
- push Branch validation `43418427885` SUCCESS；PR 全量 run `43418437453` SUCCESS（Flutter regression job `131862103871`、Android arm64 job `131864278445` 均 SUCCESS）。
- 合并后 master Flutter tests `43419630906` SUCCESS；master Flutter Quality Gate `43419630904` SUCCESS；两者都对应 merge SHA `9fa7f400170569ba6c6b57728c5d26f486b98885`。
- 自动解释只发生于 App 工具结果成功、结果/参数契约核对通过、source IDs 非空且本地模型 ready 的条件下；否则不把结果交给模型做事实解释。

### 26.2 代码路径核对

- Headless：真实结果与原始来源先进入助手时间线并持久化，再恢复模型上下文，使用助手内部提示调用现有解释 helper；内部提示不伪装成用户发言，解释结果另存为助手消息。
- Page Tool：Typed 结果保留真实 source IDs；旧页面回传 String 用 `local-page-tool:<toolId>` 标记页面回传来源，不冒充本地引擎来源。若用户请求参数没有被页面结果回传确认，状态为 UNKNOWN，不自动解释。
- 结果失败、取消、NO_RESULT、UNKNOWN、缺少来源、参数不匹配均不会自动解释。现有工具计算和页面执行流程未被替换。
- 针对性测试覆盖 Bazi、YunQi Headless、Ziwei legacy Page Tool 返回、隐藏内部 prompt、source provenance 和额外 TRACE/persistence 阶段。
- PR 与 master CI 均 PASS；CI build 的 arm64 APK 不代表已在 Find N2 真机安装/运行模型，也不代表真实 E4B 语义质量已完成验收。

### 26.3 与审计发布门槛的关系

- 这项交付仅补足“已执行且校验结果的解释交互”，不等于全部工具均能在对话后台执行。
- 工具目录仍有 24 项注册能力，其中 Headless 只有 `yunqi / almanac / bazi`；Page Tool 结果可以在用户返回后解释，但用户仍须先完成页面操作。
- 自由文本症状问诊仍 PARTIAL / BLOCKED BY RED-FLAG GATE；本 PR 不增加症状抽取，不修改医学知识库、问诊十问、DiagnosticEngine 或辨证规则。
- A/F/E 的 Find N2 设备稳定性、真实 E4B 语义与 TRACE/data-clear 验收不由 CI 替代。普通学习、工具和玄学结果的设备级知识综合仍需合成/非敏感样例采证。

### 26.4 下一步

1. 在现有结构化规则问诊结果链补齐确定性引擎 source provenance；PR #137 已合并，来源标记及知识来源并存已由测试覆盖（见第 27 节）。
2. 自由文本问诊需先有医学审核的红旗 detector 和全入口前置拦截证据；没有这些材料时不启用症状自由文本抽取或自动模型调用。
3. 在 Find N2 真机验证 E4B 对八字/紫微/工具结果的归纳是否完整、是否保留来源和 MISSING，并记录 App SHA、设备、backend、TRACE 和真实输出。

## 27. 2026-11-13 PR #137：结构化问诊结果的引擎来源追溯

### 27.1 集成基线与变更范围

- 集成前 master：`9fa7f400170569ba6c6b57728c5d26f486b98885`；独立分支 `work/p4-diagnostic-result-provenance-2026-11-13`；最终 PR head `2829595ed74d4fe7871831f6938d175b6ffd1ea3`。
- PR #137 已 squash 合并，merge commit / 当前 master：`1bea32a1a81d2a776ddbb6ca7f325b7e6667045d`。
- 对现有结构化 `DiagnosisResult` 的解释入口加上 `local-engine:diagnostic-engine` 来源标识；用户触发现有解释动作时，source ID 随解释请求 TRACE 和持久化 metadata 保存。
- 本轮实际知识检索返回的 `neijing:*` 来源继续合并保存；不把引擎来源伪装成知识库条目。
- prompt 只允许解释 App 已返回结果，不重新辨证、不补造缺失项，也不生成个体处方、药物或剂量建议。

### 27.2 验收状态

- 独立 Branch validation run `43421461053` SUCCESS。
- PR 全量 run `43421508491` SUCCESS；Flutter regression job `131872388262` 与 Android arm64 CI verification job `131874363872` 均 SUCCESS。
- 合并后 master runs：Flutter tests `43427610792` 与 Flutter Quality Gate `43427610691` 均 SUCCESS，均对应 merge SHA `1bea32a1a81d2a776ddbb6ca7f325b7e6667045d`；Android arm64 APK/ABI、Native unit tests 和 Flutter/Dart 回归均通过。该结论不替代 Find N2 真机 E4B 语义验收。
- 本次不自动触发健康结果解释，不修改问诊规则或知识库，也不绕过红旗门禁；当前自由文本问诊仍 BLOCKED BY RED-FLAG GATE。



## 28. 2026-11-13 PR #139：Page Tool 持久化失败显式反馈

### 28.1 核验结论

- PR #139 基线 master `cb7f2e8fd7fc597f2bafc725e369290ca78bbe34`；最终 head `19cd6d98bf22c946820f8ee8aabf372682265bca`；已 squash 合并至 `04de8e52abdc88d3c6f99d4b0db836721564acf4`。
- PR full run `43432900614` SUCCESS：Flutter regression job `131910595578` 和 Android arm64 CI verification job `131912798580` 均 SUCCESS。Android job 包含 CI APK、backup Manifest、ABI/SHA-256、Native unit tests、JUnit XML 和报告上传。
- 合并后 master runs `43434084780`（Flutter tests）与 `43434084865`（Flutter Quality Gate）在本报告更新时仍 IN_PROGRESS；不预先记 PASS。

### 28.2 代码修复和状态语义

- Page Tool 的实际业务结果、工具 ID、执行参数与 source IDs 已通过契约校验后，若 SQLite 单条结果消息写入失败或当前会话不可用，统一助手现在显示明确警告；当前时间线继续显示本轮真实结果。
- 写入异常不能证明后端事务一定未提交，所以 `persistence` / `persistedState` 继续标记 `UNKNOWN`；不自动重跑工具，避免重复执行。执行与结果校验仍按各自阶段记录，不将持久化失败伪装成业务计算失败。
- 故障注入 widget test 覆盖写入失败、当前结果仍可见、历史未伪报保存、警告可见、只返回一次结果及两个 TRACE 持久化阶段均为 UNKNOWN。
- 本 PR 不把 Page Tool 转成 Headless，不触碰任何排盘、问诊、剂量、民俗计算，也不改 source provenance 和模型解释 prompt。

### 28.3 当前 D 项范围

- 24 个注册能力仍应分开记录：Page Tool 代表页面导航/页面执行路径；Headless 仅指无 Widget/BuildContext 的确定性 executor；Executed 需本轮真实执行并回传验证结果。
- 当前已核实的 Headless executor 是 `yunqi / almanac / bazi`；其余页面不因有结果回传或自动解释就升级为 Headless。
- 专项目录审计第 8.3 节第 7 项已从“持久化失败仅 debugPrint”更新为“CODE + TEST + PR CI PASS”；设备端逐项执行、取消/失败和多轮 TRACE 仍 UNKNOWN。

### 28.4 剩余优先事项

1. 自由文本问诊仍 BLOCKED BY RED-FLAG GATE；医学审核 detector 与全部 Flutter/Native 模型入口的调用前拦截是自然语言问诊的前置条件。
2. Find N2 GPU/CPU、多媒体、多轮和中断恢复的真实 E4B/TRACE 仍待设备验收。
3. AI 数据清除后重启不可恢复验证仍待设备验收；共享 SQLite 的备份副本、旧共享临时目录和外部导出副本不能宣称已被清除。
4. 两条没有可追溯经典来源的规则仍 MISSING；不补造出处。普通学习讲稿不重复审核。

- 不新增 Agent/DAG、云 API、向量数据库或第二套 Orchestrator；不批量迁移 Page Tool；不修改确定性业务规则。

---

## 29. 2026-11-13 PR #141：梅花易数数字起卦的对话内 Headless 执行

### 29.1 交付边界

- PR #141：https://github.com/just2512/nihaixia-app/pull/141；集成前 master `cdc6d7bb60c7d7b60c4e3cb96f340ae0d019be13`；最终 PR head `7173e994958b40a6bffcd3d52f0442a09ffc8e70`；squash merge / 当前 master `996e019412f1baf8e4896b86cf607a986214525e`。
- 仅新增梅花数字起卦 Headless executor 和对话参数收集/结果回传；调用既有 `computeMeihuaByNumber`，不改卦象算法、爻变逻辑或本地卦爻数据。
- 时间起卦和随机起卦保留原 Page Tool 路径；数字起卦的两个必填数缺失时在对话中追问，跨轮保留已提供参数；不从生日、日期或无关文本推断起卦数。
- 只有执行成功、请求参数匹配、结果契约校验通过且 source ID 非空，才把结构化业务结果交给现有解释链。未执行/UNKNOWN/失败/参数不匹配不作为事实解释。

### 29.2 验收证据

- Branch validation run `43440528168` SUCCESS（Static analysis + changed tests/test-pairing）。
- PR full run `43440833538` SUCCESS；Flutter regression job `131937690657` SUCCESS；Android arm64 CI verification job `131940462857` SUCCESS。
- Android CI 已验证 arm64 Debug APK、merged backup Manifest、ABI/SHA-256、Native unit tests 和 JUnit XML；成功上传 `android-arm64-ci-debug-abi-evidence` 与 `android-unit-test-reports` artifacts。
- merge commit：`996e019412f1baf8e4896b86cf607a986214525e`。
- merge 后 master workflows：Flutter tests `43442279739`、Flutter Quality Gate `43442277653`。本次报告更新时两者仍 IN_PROGRESS，不能把 PR 全量 CI 成功替代 post-merge master 验收。

### 29.3 能力状态更新

- 注册工具数由 24 增至 25；Headless executor 由 3 增至 4：`yunqi / almanac / bazi / meihua`。
- 这只表示梅花**数字起卦**已可在统一助手对话内 Headless 执行；不表示时间/随机起卦也变成 Headless，不表示其余 Page Tool 已完成后台执行。
- 简单明确的数字槽位由确定性解析完成，不额外调用 E4B；模型只负责已有结果的解释，不生成卦象或覆盖 App 的计算结果。
- 本次未在 OPPO Find N2 真机安装/运行模型；E4B 语义、速度、GPU/CPU fallback、多媒体多轮和 TRACE 继续 DEVICE UNKNOWN。
- 自由文本问诊仍 BLOCKED BY RED-FLAG GATE；没有医学审核 detector 与全入口调用前拦截证据前，不启用症状自由文本抽取。
- AI 数据清除后的完全退出/重启不可恢复验证仍需真机证据；两条无可追溯经典来源的规则继续 MISSING。

### 29.4 下一步

1. 完成 merge SHA `996e019412f1baf8e4896b86cf607a986214525e` 的 post-merge master Flutter tests 与 Quality Gate 终态核验。
2. 取得医学审核后的红旗 detector、阈值/例外/处置文案，并覆盖 Flutter/Native 所有可能触发模型调用的入口；完成前不接入自由文本问诊抽取。
3. 继续 Find N2 真机 E4B、GPU/CPU、多媒体多轮及中断恢复 TRACE 验收；CI APK 不替代设备验证。
4. 完成“清除全部 AI 数据”后的重启核验，确认会话、问诊快照、附件原件、缩略图和孤儿文件的删除范围。

- 冻结：不修改诊断、排盘、剂量或民俗算法；不重复审核已审核知识库；不批量迁移 Page Tool；不新增 Agent/DAG、云 API、向量数据库或第二套 Orchestrator。


---

## 30. 2026-11-14 PR #144/#145/#146 集成后增量复核

### 30.1 代码与集成结果

- PR #144（称骨）最终 head `e0d8eddc9155ffd5dd8c670e3db6eedaba26ffe2`，merge master `34906712b42c78a4e6ff5e60172ae9517d16d657`。复用既有称骨/历法函数和结果格式化，不复制算法。
- PR #145（黄帝四季歌）最终 head `8f9ffb1816f48cfbc0b9234f8248322e93720052`，merge master `d328afbd6d346ba9cfbf06fe289020fc79e86186`。复用原页面的历法换算、时辰映射和数据，不复制业务规则。
- PR #146（规则问诊结果自动解释）最终 head `a42af20a29fe6f5c64bf1cf5afe32b57716bc061b`，merge master `67bb3597e9abb411627545a8e2a3b25105633c52`。仅改 `local_ai_interview_screen.dart` 与其 widget test，没有修改 `DiagnosticEngine`、`DiagnosticRules` 或知识库。
- PR #146 在问诊结果消息、completed task snapshot 持久化成功、可见对话上下文恢复成功、本地模型状态 ready 且来源 ID 存在时，自动请求解释；未完成任务、结果缺失、持久化失败、上下文恢复失败或模型未就绪时不自动解释。历史结果仍保留手动解释入口。
- 解释 prompt 明确限制为归纳解释 App 已返回字段和已检索来源；不重新辨证、不新增诊断、处方、药物或剂量，不把知识库上下文升级成新的个体诊断依据。

### 30.2 自动化验收证据

- PR #144：Flutter regression 与 Android arm64/Native CI run `43458542859` SUCCESS；push workflow `43458531935` SUCCESS。PR workflow 中 Branch validation 为 SKIPPED，不计 PASS。
- PR #145：Flutter regression 与 Android arm64/Native CI run `43543965618` SUCCESS；最终 head 对应 push workflow `43543961251` SUCCESS。
- PR #146：最终 head 独立 Branch validation run `43547647496` SUCCESS；PR full run `43547653711` SUCCESS，其中 Flutter regression job `132302637020` 和 Android arm64/Native job `132303970143` 均 SUCCESS。后者完成 APK ABI 构建、merged backup Manifest、ABI/SHA-256、Native unit tests、JUnit XML 与 evidence artifact 上传。
- merge SHA `67bb3597e9abb411627545a8e2a3b25105633c52` 的 post-merge Flutter tests run `43548507345` 与 Flutter Quality Gate run `43548507387` 均为 SUCCESS；两条 run 的 head_sha 都与该 merge SHA 一致。

### 30.3 D：当前确定性能力数量

- `AssistantToolRouter` 当前源码有 24 个工具定义：23 个页面工具入口及一个由统一助手特殊处理的 `structured_diagnosis`。
- 23 个页面工具入口中 6 项声明 Headless executor：`yunqi`、`almanac`、`bazi`、`meihua`、`chenggu`、`huangdi_siji`；17 项仍为 Page-only。Page builder 与 Headless 可并存，不应重复相加。
- `structured_diagnosis` 是现有控制器驱动的确定性内联问诊流程，不作为通用 Headless adapter 计数。
- “具备 executor”不等于每个设备场景都已完成真实运行验收。只有本轮实际执行、参数校验、结果契约、来源 ID 和消息回传全部有证据时，才记录为 Executed。

### 30.4 未关闭事项与发布边界

- 自由文本症状问诊仍 PARTIAL / RELEASE BLOCKED：RedFlagGate 有 fail-closed 策略契约，但医学审核自然语言 detector 和 Flutter/Native 所有生产模型入口的前置接入仍缺失。医学知识库已审核不等于 detector 已审核；不重复审核知识库，也不编造 detector 词表。
- 用户所要求的“先理解自由文本，只追问缺失的必要信息，再后台运行规则问诊”尚未完成。PR #146 只完成已有结构化规则结果的自动解释，不将十问直接替换为自然语言问诊。
- 其余简单工具请求继续使用确定性意图/槽位匹配；复杂歧义才进入受约束澄清。没有必要的请求不增加模型调用。
- A/E/F：OPPO Find N2 的 GPU/CPU 多轮、图片/语音、Activity/进程恢复和端到端真实 TRACE 仍 DEVICE UNKNOWN；CI arm64 APK 不替代实机运行。
- C：既有知识库临床审核不重复开展；书目 locator/纸本版本/卷页等来源身份缺口与临床内容审核是不同工作，按来源材料缺失状态继续记录。
- 不改诊断/排盘/剂量算法，不批量迁移 Page Tool，不新增第二套 Orchestrator、Agent/DAG、云 API 或向量数据库。


---

## 31. 2026-11-14 PR #147/#148/#149 合并后增量复核

### 31.1 当前主线和改动摘要

- 当前复核基线：`master @ 8e44e0c7f6f58249e2adc55fbec1afb37610954f`。
- PR #147 合并了能力盘点/审计报告/执行台账刷新；规范性约束文件 `docs/ai-capability-audit.md` 保持未修改。
- PR #148 合并紫微斗数对话内 Headless 执行：复用原 `calculateZiweiChart`、`formatZiweiChartForAssistant`、城市坐标目录及 App 真太阳时/早晚子时设置；不使用页面示例出生资料或默认经纬度，缺失/歧义输入不执行。
- PR #149 合并节气养生对话内 Headless 查询：复用 `getCurrentSolarTerm`、`getSolarTermKnowledge` 和 `solar_term_knowledge.json`。用户明确指定一个节气时查询该项；明确请求当前节气时读取 App 当前服务；泛化请求或多节气歧义先澄清，不擅自选第一项或默认今天。

### 31.2 当前 Headless/Page-only 盘点

- `AssistantToolRouter` 当前 24 个定义：23 个常规页面入口 + 1 个结构化问诊特殊内联流程。
- 23 个常规页面入口中 8 项配置 Headless executor：`yunqi`、`almanac`、`bazi`、`meihua`、`chenggu`、`huangdi_siji`、`ziwei`、`solar_terms`；15 项仍为 Page-only。
- `structured_diagnosis` 由原有确定性问诊控制器内联处理，不计作通用 Headless。页面入口可保留 builder，但页面打开不计为后台执行。
- 所有 Headless 结果必须经过现有 toolId、arguments、status、sourceIds/result contract 校验和持久化后才能交给模型解释。缺参/歧义先澄清；没有明确执行或来源的结果不进入事实解释。

### 31.3 PR 验收和主线 CI

- PR #148：Flutter full regression run `43551889499` SUCCESS；Android arm64/Manifest/ABI/Native tests 与 artifacts 上传 SUCCESS；branch validation push run `43551885608` SUCCESS。
- PR #149：最终 head `26aabe3fc43eb21a943189fea995a82b36465f12`；branch validation run `43553278374` SUCCESS；PR full Flutter run `43553482280` SUCCESS，Flutter regression job `132320970943` SUCCESS；Android arm64 job `132322096941` SUCCESS，包含 Debug APK、merged backup Manifest、ABI/SHA-256、Native unit tests、JUnit XML 和 evidence artifact 上传。
- PR #149 artifacts：`android-unit-test-reports` id `14097701587`、`android-arm64-ci-debug-abi-evidence` id `14097232618`、`ai-retrieval-golden-snapshot` id `14096004897`。
- merge SHA `8e44e0c7f6f58249e2adc55fbec1afb37610954f` 的 post-merge Flutter tests run `43554222428` 仍 IN_PROGRESS（全量 regression job `132323303067`）；重复触发的 Flutter tests run `43554273400` 已被并发策略 CANCELLED；Flutter Quality Gate run `43554222553` 仍 IN_PROGRESS。**master CI 尚未终态通过**，需按该 SHA 复核 `43554222428` 与 `43554222553` 两条有效 workflow。

### 31.4 未关闭的发布阻塞和验收项

- 自由文本问诊仍 PARTIAL / RELEASE BLOCKED：现有 `RedFlagGate` / `RedFlagPreflight` 是 fail-closed 策略契约与 fake-detector 测试 seam，不是生产医学 detector。当前没有可追溯的医学审核自然语言 detector 版本，也没有所有 Flutter/Native 模型入口的调用前接入证据。不能用已审核知识库代替 detector 审核；不重复审核知识库，也不编造红旗词表。
- 用户希望的“自由文本理解 → 只追问问诊十问所缺字段 → 后台执行现有规则问诊 → 解释真实结果”仍未完成。PR #146 完成的是已有结构化问诊结果在成功持久化后自动解释，不是自然语言替代问诊十问。
- OPPO Find N2 E4B GPU/CPU、多轮、图片/语音、Activity/进程恢复、AI 数据清除后强停/重启不可恢复、端到端 TRACE，仍需设备记录；CI ARM64 APK/Native tests 不能替代真机运行。
- C 的知识资产临床审核不重复开展；仍缺的书目 locator、底本版本、卷页和原文身份属于来源治理，不得凭推测补齐。

### 31.5 后续推进顺序

1. 等待 merge SHA `8e44e0c7` 的 Flutter tests / Quality Gate 终态；若失败，只修复该 SHA 上实际失败的 job。
2. 继续逐项审计剩余 15 个 Page-only 工具，只在能复用原确定性代码、有清晰输入 schema 和来源的前提下实现一个最小 Headless 切片；不批量迁移。
3. B 维持 RELEASE BLOCKED，直到医学审核 detector 版本、审核记录、阈值/例外/处置文案和全入口覆盖证据齐备；期间不开放自由文本症状自动辨证。
4. 真机 A/E/F 按设备清单收集 Find N2 E4B、清理与 TRACE 证据；CI 结果不替代设备验收。


---

## 32. 2026-11-14 PR #151 小六壬 Headless 集成后增量复核

### 32.1 当前主线与能力分层

- 当前 master：`3915a404200ed8721fbc7715261c5b5e7ac592f0`。
- `AssistantToolRouter` 共 24 个定义：23 个常规页面工具入口和 1 个特殊内联确定性问诊流程 `structured_diagnosis`。
- 23 个页面入口中 9 项 Headless：`yunqi`、`almanac`、`bazi`、`xiaoliuren`、`meihua`、`chenggu`、`huangdi_siji`、`ziwei`、`solar_terms`；14 项仍 Page-only。Page builder 与 Headless executor 可并存，不能重复计数。
- `structured_diagnosis` 继续由原有 `TcmInterviewConversationController` / `DiagnosticEngine` 规则问诊控制器内联执行，不计入通用 Headless 数量。

### 32.2 PR #151 交付与边界

- PR #151 最终 head `eda34a85d917e58ac2afc8fe255d3f4349a8b4ac`，merge commit `3915a404200ed8721fbc7715261c5b5e7ac592f0`。
- 新增 `XiaoliurenToolExecutor`，复用现有 `LunarDate.fromSolar`、`computeXiaoliuren` 与 `xiaoliurenVerse`；没有复制或修改小六壬计算规则。
- 对话要求明确提供公历日期、单一地支时辰和算法口径 `common`（通行掌诀）或 `duoneng`（《多能鄙事》卷八）；不默认任何算法口径。农历、多个日期/时辰、冲突口径和非法参数均先澄清/拒绝执行。
- 缺参时在当前对话追问，已有参数跨轮持久化并可从历史恢复；支持取消。完整参数通过校验后由 App 原有纯函数执行，只有成功且 sourceIds/result contract 校验通过的真实结果才交给 AI 解释。
- 用户无需跳转小六壬页面；不新增数据库表，不改医学诊断、排盘或剂量计算。

### 32.3 自动化验收

- 分支验证 push run `43560093070` SUCCESS：Flutter 静态分析、changed tests 和 test pairing 全部通过。
- PR workflow `43560097611` SUCCESS：Flutter 全量回归 job `132341891873` SUCCESS；Android arm64/Native job `132342897892` SUCCESS。
- Android job 完成 arm64 Debug APK 构建、merged backup Manifest、ABI/SHA-256、Native unit tests、JUnit XML 与 evidence artifacts 上传。
- merge SHA `3915a404200ed8721fbc7715261c5b5e7ac592f0` 的 post-merge Flutter tests run `43560857686` 和 Flutter Quality Gate run `43560857654` 均已在相同 head SHA 上完成，终态均为 SUCCESS。
- PR/CI APK 不等于 OPPO Find N2 真机 E4B 推理、GPU/CPU、多媒体、Activity/进程恢复和真实 TRACE 验收。

### 32.4 未关闭问题及后续任务

- 自由文本问诊继续 PARTIAL / RELEASE BLOCKED：已审核医学知识库不重复审核；但自然语言红旗 detector 的正式医学审核记录、版本/阈值/例外/处置文案，以及全部生产模型入口调用前的 fail-closed 接入证据仍缺。不能自行编造词表，不能把 `REVIEW_REQUIRED/UNKNOWN` 当作 CLEAR。
- 用户要求的自然语言问诊完整闭环仍未完成：从用户自由描述中结构化理解已覆盖信息、只追问必要缺项、后台运行原确定性问诊规则、解释真实结果。当前结构化十问仍保留，PR #146 只负责完成结果自动解释。
- A/E/F 仍需 Find N2 真机证据：E4B GPU/CPU、多轮文字/图片/语音、Activity/进程中断恢复、清除 AI 数据后强停/重启不可恢复、端到端 TRACE。CI arm64 APK 不替代真机。
- C 不重复审核既有知识库；只补书目 locator、底本版本、卷页和原文身份缺失。
- D 下一项候选为 `yijing`：现有 `YiJingEngine` 支持数字、当前时间、手动选卦和铜钱四种确定性计算。需为每种模式建立参数与回放契约；App 负责铜钱随机生成并持久化真实投掷值，模型不能伪造。逐项适配，不批量迁移。

### 32.5 不变边界

- AI 负责理解、澄清、调度和解释；原有业务函数负责计算，规则和知识库内容不由模型改写。
- 只将已执行、经过输入/结果契约校验并具有 sourceIds 的 App 结果交给模型作为事实解释。
- 不修改 `DiagnosticEngine`、`DiagnosticRules`、排盘算法、剂量换算和已审核知识库内容。
- 不新增第二套 Orchestrator、Agent/DAG、云 API、向量数据库；不为追求工具数量批量迁移 Page-only。


---

## 33. 2026-11-14 PR #153：易经四种起卦模式 Headless 集成后增量审计

### 基线与实现

- 当前 master / merge SHA：`59ca2a746d8dc4d29abb06f52697d02ce52a26df`；PR #153 最终 head：`18e9cd6feb97d65c4c36f18a84a47358b3483c17`。
- `AssistantToolRouter` 有 24 个定义：23 个页面工具入口 + 1 个由确定性问诊控制器内联执行的 `structured_diagnosis`。其中 10 个页面工具入口具备 Headless executor，13 项仍 Page-only。
- 新增 `YiJingToolExecutor`，复用原 `YiJingEngine` 的数字、当前时间、手动选卦、铜钱六次投掷四种方法；未修改易经引擎计算逻辑、原页面或本地六十四卦资料。
- 参数缺失在统一助手对话中澄清和跨轮补充；时间由 App 注入，铜钱六次投掷由 App 生成并保存原始结果。模型不生成时间、随机值或卦象。
- 适配层按原引擎的单动爻/多动爻字段分别读取；执行成功并通过参数、结果、来源契约校验后才进入现有解释链，sourceIds 为 `local-engine:yijing` 与 `local-data:yijing-hexagrams`。
- 未改 `DiagnosticEngine`、`DiagnosticRules`、问诊十问、剂量换算或已审核医学知识库。

### 自动化验收

- Branch validation run `43563718624` SUCCESS。
- PR workflow `43563859567` SUCCESS：Flutter regression job `132353274615` 与 Android arm64 verification job `132354564040` 均 SUCCESS。Android job 包含 arm64 Debug APK、merged backup Manifest、ABI/SHA-256、Native unit tests、JUnit XML 与 evidence artifacts。
- post-merge master Flutter tests run `43564609205` 和 Flutter Quality Gate run `43564609235` 均以 master merge SHA `59ca2a746d8dc4d29abb06f52697d02ce52a26df` 为 head_sha，终态均为 SUCCESS；PR workflow 与 post-merge master CI 分别留档，互不替代。

### A-G 状态与剩余事项

- A Native 多轮/生命周期：PARTIAL / DEVICE UNKNOWN；Find N2 E4B GPU/CPU、多媒体、多轮、Activity/进程恢复与真实 TRACE 仍缺设备证据。
- B 红旗安全：PARTIAL / RELEASE BLOCKED；自然语言 detector 的医学审核版本、阈值/例外/处置文案及 Flutter/Native 全模型调用入口前置 fail-closed 证据仍缺。不得编造 detector；已审核医学知识库不重复审核。
- C 检索来源：PARTIAL；只补书目 locator、底本版本、卷页/原文身份缺口，不重新审核已审核医学知识内容。
- D Headless：10 项 Headless / 13 项 Page-only；剩余工具逐项建立确定性函数、输入 schema、来源和行为基线，不批量迁移。
- E 数据保护：PARTIAL / DEVICE UNKNOWN；Find N2 清除 AI 数据后强停/重启，核验 DB、附件、缩略图和孤儿文件不可恢复仍未完成。
- F TRACE：PARTIAL / DEVICE UNKNOWN；仍需真实设备场景贯穿输入、执行、sourceIds、持久化、解释和恢复。
- G 文档治理：本轮更新三份增量审计文档；规范性文件 `docs/ai-capability-audit.md` 保持不变。

用户要求的自由文本问诊闭环仍受 B 门禁阻塞：在自然语言红旗 detector 完成医学审核且覆盖全部生产模型入口前，不开放由模型直接把自由症状变成诊断输入。结构化问诊继续由 App 原规则引擎执行；AI 只解释已完成、已校验、有来源的业务结果。


---

## 34. 2026-11-14 PR #156：子午流注对话内 Headless 执行后增量复核

### 当前主线与合并结果

- master merge SHA：`aed6c4b0c3b7684a437b61253c16fd495e6ab717`。
- PR #156 最终 head：`86c7398cb5635c7387182c6582a3bbe638a0c410`；PR 已 squash merge。
- `AssistantToolRouter` 保持 24 个定义：23 个常规工具页面入口 + 1 个确定性问诊控制器内联 `structured_diagnosis`。
- 23 个常规页面入口中 12 项具备 Headless executor：`yunqi`、`almanac`、`bazi`、`xiaoliuren`、`meihua`、`chenggu`、`huangdi_siji`、`ziwei`、`solar_terms`、`yijing`、`dosage`、`ziwu_liuzhu`；11 项仍为 Page-only。
- `structured_diagnosis` 继续由 `TcmInterviewConversationController` / `DiagnosticEngine` 执行，不计入通用 Headless 数量。

### 实现和职责边界

- `ZiWuLiuZhuCalculationService` 收敛页面与助手共享计算/数据映射；`ZiWuLiuZhuToolExecutor` 复用既有子午流注引擎，不修改原算法。
- 用户在助手对话内完成子午流注参数澄清和调用；日期/时间槽位跨轮持久化，日期单独提供时追问时刻。未指定日期/时间时沿用原页面“设备当前本地时间”的透明语义；最终时间由 App 注入，不接受模型伪造时间。
- 结果包含 `local-engine:ziwuliuzhu` 与 `local-data:ziwuliuzhu-reference-tables`。执行、参数、结果和来源契约通过后才交给 AI 解释；结果明确说明默认经纬度、换日口径及非诊断/非处方边界。
- 没有修改 DiagnosticEngine、DiagnosticRules、问诊十问、剂量规则、排盘/民俗算法或已审核知识库。

### 自动化验收

- Branch validation run `43575671526` SUCCESS（head `86c7398`）。
- PR run `43575673793` SUCCESS：Flutter regression job `132389779409` SUCCESS；Android arm64 job `132390872014` SUCCESS。
- Android arm64 Debug APK、merged backup Manifest、ABI/SHA-256、Native unit tests、JUnit XML 及证据上传全部 SUCCESS。
- artifacts：`android-arm64-ci-debug-abi-evidence` id `14106526485`；`android-unit-test-reports` id `14106930205`。
- post-merge master Flutter tests `43576475144` 与 Flutter Quality Gate `43576475147` 在本次复核时仍 IN_PROGRESS；不得提前标记 master CI PASS。

### 未关闭目标

- B 红旗仍 RELEASE BLOCKED：自然语言 detector 缺正式医学审核版本/阈值/例外/处置文案与所有 Flutter/Native 模型入口调用前的 fail-closed 证据；先补 B2 注入式门禁接缝，不自行发明医学规则，也不重复审核知识库。
- 自由文本问诊未完成：当前结构化控制器仍按既定问题顺序推进；初始自由描述只进入上下文/transcript，没有映射成待确认字段、自动跳过已覆盖信息。完成 B 门禁后再做“结构化理解—确认—仅追问缺项—调用原规则引擎—解释真实结果”。
- D 还有 11 个 Page-only 工具；下一项低风险候选为本地梦境资料检索，但 keyword 存在大量多义，需要先澄清情节，不得取第一条命中。
- Find N2 真机 A/E/F 和 C 书目 locator 仍 PARTIAL/UNKNOWN；已审核知识库内容不重复审核。

### 不变边界

AI 是交互与理解中枢，不是业务规则和计算引擎；规则问诊、剂量、排盘、民俗计算继续由 App 确定性代码执行。只有经执行与契约校验且带来源的真实结果才交给 AI 解释。模型不能伪造结果、覆盖规则或将推断包装成医学诊断。


---

## 35. 2026-11-14 C：医案库来源账本页面加载链路增量复核

### 复核基线与问题

- 当前复核基线：`master @ f73d6743794b9e253752a372e3e0f19667e9c34f`；PR #160 squash merge：`f73d6743794b9e253752a372e3e0f19667e9c34f`。
- `MedicalCaseSourceLedger` 已将网页/原文核验状态与纸本/影印本书目定位状态分开；只有完整字段与显式状态匹配才允许 `VERIFIED`。
- 发现页面加载链路未使用已有来源账本：`MedicalCaseLibraryScreen._load()` 直接加载 `assets/medical_cases/cases_table.md` 后调用 `parseMedicalCaseTable(md)`，未传入 `sourceLedgers`，导致页面中所有病例都使用默认 `MedicalCaseSourceLedger.missing`。而数据层已有 `getAllMedicalCases()` 会加载 `source_ledger.json` 并按内部序号注入。
- 当前账本本身的状态（原始 JSON，不做内容更改）：1,256 条记录；10 条 `verificationStatus=VERIFIED` 且来源字段完整；1,246 条来源状态 `MISSING`；全部 1,256 条 `bibliographicLocatorStatus=MISSING`。没有任何记录完成纸本/影印本版本、卷次与页码定位核验。

### 最小修复

- 在 `lib/data/medical_case_data.dart` 抽出 `loadMedicalCasesFromAssets()`，统一完成 Markdown 主表加载、来源账本读取和主键关联。
- `MedicalCaseLibraryScreen._load()` 改为调用共享加载函数；`getAllMedicalCases()` 也复用该函数，保持缓存与页面加载的来源映射一致。
- 账本读取失败不会隐藏病例正文；没有来源账本的记录保持 `MISSING`。主 Markdown 加载失败继续抛给页面 FutureBuilder，保持原错误态。
- 新增 `medical_case_source_integrity_test.dart` 回归测试，验证真实资产加载路径、原文核验与纸本定位状态不互相升级、缺来源记录保持 `MISSING`。
- 不修改任何医案内容、source ledger 数据、医学知识结论或 DiagnosticEngine/DiagnosticRules；不重复进行已完成的医学审核。

### 验收与状态

- 独立分支：`work/medical-case-source-ledger-wiring-2026-11-14`。
- **状态：自动化验收通过。** PR run `43585625501`、分支验证 run `43585569847`、合并后 master Flutter tests run `43586347265`、master Quality Gate run `43586347314` 均为 SUCCESS；覆盖真实资产来源注入、Flutter 全量回归、Android arm64 Debug APK/Manifest/ABI、Native 单测及报告工件。此项仅修复现有来源账本的加载链路。
- 本项只修复已有来源证据的加载链路，不补齐纸本 locator。C 仍 PARTIAL，后续只接受可追溯原始来源材料，不得推测或填造卷页。

---

## 36. 2026-11-14 PR #161：工具结果知识追问链路复核

### 36.1 集成事实

- PR #161：https://github.com/just2512/nihaixia-app/pull/161。
- 独立分支：`work/ai-tool-result-knowledge-followup-2026-11-14`；PR head：`b33bff0ba6df94a7ca89e7abd2b1e3f294788e3c`。
- squash merge SHA / 当前 master：`a9052504e55bae29fccc980f88dab06836b4e9cb`。
- 4 个变更文件只涉及助手检索上下文、知识检索门禁及配套回归测试；规范性约束 `docs/ai-capability-audit.md` 未修改。

### 36.2 行为与边界复核

- 工具结果解释可按确定性门禁检索本地 TCM 知识，省略式追问可用最近用户原话与已验证 App 结果恢复指代；结果必须有 App 来源，不能使用 AI 自由文本伪装成事实。
- “那它的禁忌呢？”会以有限会话上下文补全检索 query；不重新调用已完成的工具、不把用户送到独立工具页面。
- 寒暄类输入不触发知识检索。医案记录不被无差别注入工具结果解释，缺失来源仍明确为 MISSING。
- 未修改医学规则、十问、确定性排盘/剂量业务、知识库内容、来源账本或 RedFlag detector。

### 36.3 验收证据

- 分支验证 run `43595221690` SUCCESS。
- PR run `43595241256` SUCCESS：Flutter regression 与 Android arm64 verification 全部成功，含 APK 构建、Manifest/ABI/SHA-256、Native tests、JUnit XML 与证据工件上传。
- PR artifacts：ABI evidence `14114860428`；Native reports `14114073681`；retrieval snapshot `14114195696`。
- post-merge master Flutter tests run `43595987567` 和 Quality Gate run `43595987556` 在本节记录时尚未结束；不得将 IN_PROGRESS 标为 SUCCESS。最终状态应在这两项结束后补记。

### 36.4 A-G 状态

- A/E/F：仍为 DEVICE UNKNOWN，等待 OPPO Find N2 真实设备、多轮、多媒体、进程恢复、清除数据和端到端 TRACE 证据。
- B：仍 `PARTIAL / RELEASE BLOCKED`；缺生产自然语言 detector 医学审核记录及所有模型入口 fail-closed 证明。自由文本自动辨证不得开放。
- C：仍 PARTIAL；来源定位缺口保持 MISSING，不重复审核已有审核内容。
- D：23 个常规工具入口中 13 个 Headless、10 个 Page-only；按独立场景逐项审计，不批量迁移。
- G：本次补充审计报告与执行台账；规范性约束文件保持不变。

### 36.5 下一步

- 先以 merge SHA `a9052504e55bae29fccc980f88dab06836b4e9cb` 核验 post-merge Flutter tests 和 Flutter Quality Gate 终态；两个都 SUCCESS 后将证据补入本节。
- 自由文本问诊不越过 B 门禁。等待医学审核资料和生产接入依据；不重复审核现有知识库。
- 对 Page-only 工具只审计与用户场景有明确关系的现有代码；没有必要的知识检索入口不重复建设。
