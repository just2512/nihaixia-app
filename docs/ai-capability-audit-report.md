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
| F TRACE | PARTIAL | 已覆盖普通文本/图片/语音、检索/上下文、Orchestrator/Headless、结构化问诊阶段；PR #111 补 Headless 结果契约失败终态，但该失败分支缺直接负向测试，恢复/失败关联与真机 TRACE 未闭环 |
| G 文档治理 | 版本源子目标 IMPLEMENTED | README/pubspec/Flutter CI/Android CI/Release tag 版本一致性 guard 已合并；本次主线 post-merge CI 两条 run 均 SUCCESS |

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

## 2026-11-12 PR #111 合并后增量复核

- 当前复核主线：`8a80b9e71c61cecdf9d36d6a6013225185912f63`。
- 主线 Flutter tests run `43211557732`：SUCCESS；Flutter regression、AI contract、SQLite persistence/reopen、Android arm64 APK/ABI、Native unit tests 均成功。
- 主线 Flutter Quality Gate run `43211557461`：SUCCESS；static analysis、Dart tests、Android Native tests、Find N2 arm64 debug APK 均成功。
- `saveAssistantTurn` 已通过单一 SQLite transaction 原子保存 user/assistant 消息；PR #77 已用真实 SQLite FFI trigger 测试验证 assistant insert 失败时 user insert 回滚。该项不是当前待修复缺陷。
- PR #111 已为 Headless 结果契约失败补齐 TRACE 终态，但尚无直接构造无效结果的负向测试。当前只需补该分支测试，避免重复成功路径测试。
- A/E 的 Find N2 真机多轮、媒体、Activity/进程恢复与清理后不可恢复证据仍 UNKNOWN；B 仍 RELEASE BLOCKED（医学审核 detector 和生产入口门禁缺失）；C 来源 locator 仍待人工底本核验；D 保持 2 项 Headless/Executed；G 版本源 guard 已完成。
