# AI 能力静态/动态审计报告

- 审计日期：2026-11-12
- 仓库：`just2512/nihaixia-app`
- 审计基线：`master @ eaa83b440ddb1299a7eac58b70067de38ad44ea2`
- 约束来源：`docs/ai-capability-audit.md`、`docs/ai-modernization-execution-ledger.md`
- 方法：读取当前 master 代码、专项测试、PR diff、GitHub Actions job/step/log、CI 生成的检索快照；未执行 Find N2 真机测试。

## 1. 审计结论

当前系统已具备统一助手主入口、确定性问诊规则引擎、本地知识检索、SQLite 会话持久化、基础工具路由、TRACE 事件记录骨架和 AI 数据清理编排。但“有代码/有页面/有测试”不等于端到端能力完成。

| 工作流 | 状态 | 关键结论 |
|---|---|---|
| A 多轮稳定性 | PARTIAL | Native 串行执行和未知请求不自动重放已存在；SQLite 成功轮次已有事务接口和 UI 持久化失败提示；Activity teardown 等待、真机 GPU/CPU 证据未闭环 |
| B 红旗安全 | PARTIAL / RELEASE BLOCKED | preflight 语义契约和 provenance 已实现；自然语言 detector、所有生产入口 fail-closed、医学审核均缺失 |
| C 检索基线 | PARTIAL | 桂枝汤/伤寒论黄金快照已版本化并通过 CI；快照暴露原始 query 0 命中、派生 query 扩展以及纸本定位全部 MISSING |
| D Headless Capability | PARTIAL | 24 项工具注册，23 项仍为页面 builder；没有统一 Headless 执行与 typed result 契约 |
| E 数据保护 | PARTIAL | 清理 coordinator 已存在；设置入口与生产附件归属迁移正在独立 PR 验收；旧共享临时文件和 Android 备份行为未闭环 |
| F TRACE | PARTIAL | writer/recorder 默认关闭，事件 schema 与生命周期协调存在；trace_id 未贯穿 Dart→Native→模型→工具→SQLite |
| G 文档治理 | PARTIAL | README 与 pubspec 版本一致；当前审计报告首次建立，需随后续 master 增量维护 |

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
