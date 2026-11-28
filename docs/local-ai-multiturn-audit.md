# 本地 AI 多轮稳定性与 Native 生命周期审计

- 历史审计基线：`master` @ `4dfff41049063925daa559830341053bd33c6528`（2026-11-11）
- 当前仓库主线复核点：`master@1d79bc2f628fde789c5b5602cee889f844972c23`（2026-11-27；Flutter tests run `45976217087`、Flutter Quality Gate run `45976217173`、Fork License run `45976217114` 均 SUCCESS）
- 当前 AI 多轮运行时集成点：`45144f6c3d140d259ac51f8cfbb886c19c10e0a3`（包含 #565/#575 后续集成、#585 跨层 E2E 所在主线）
- 历史修复分支：`work/ai-transcript-restore-boundary-2026-11-11`
- 首次审计日期：2026-11-11；当前复核日期：2026-11-27
- 范围：Flutter MethodChannel、Native Engine/Conversation、成功轮次历史、GPU→CPU 恢复、历史恢复、SQLite 持久化和资源释放。
- 历史总结：A = PARTIAL。**当前状态以第 10 节（2026-11-27 主线复核）为准**：SQLite 原子轮次持久化、Native transcript 截断策略、临时上下文逐轮清理、结构化推理请求状态账本和 UNKNOWN 不重放已有代码/自动化覆盖；Native KV Cache token 数与模型声明 maxContextTokens 已有只读观测，但 App 可用 Token/input budget 尚未配置；真机 GPU/CPU 轮次、state:7、Activity/进程恢复和设备实际观测值仍为 DEVICE UNKNOWN。

## 1. Native 状态与执行边界

### 1.1 Engine / Conversation 状态

源码：`android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt`

| 状态 | 代码证据 | 当前语义 |
|---|---|---|
| 未加载 | `aiEngine == null`、`aiConversation == null`、`activeBackend=not_loaded` | Native 不接受推理 |
| Engine 已初始化、Conversation 创建中 | `loadLocalModel()` 先初始化 Engine，再调用 `createConversationWithHistory()` | Conversation 创建失败时调用 `releaseLocalModel()`，不保留半初始化对象 |
| 可推理 | Engine 与 Conversation 均非 null | MethodChannel 任务通过单线程 `aiExecutor` 串行执行 |
| 多轮推理失败 | `sendWithFirstTurnGpuFallback()` | 当前请求执行状态未知；只恢复此前成功轮次，不自动重放当前请求 |
| CPU 恢复失败 | `recreateCpuEngineForRecovery()` | 旧对象先 detach；关闭失败则停止恢复；CPU 初始化或 Conversation 创建失败时不把失败对象挂回字段 |
| 重置 | `resetLocalConversation()` + `ConversationResetPolicy` | 先 detach 旧 Conversation；关闭/新建失败会关闭 Engine 并清空字段 |
| 释放 | `releaseLocalModel()` | 先清空引用和内存历史，再按 Conversation→Engine 顺序释放 |

### 1.2 GPU 首轮失败与多轮失败

- `FirstTurnGpuFallbackPolicy` 只允许“当前 backend 为 GPU、尚无成功轮次、异常链含已知 OpenCL library 缺失信息”时自动回退 CPU。
- 该策略不对已建立历史的会话自动重放，也不对 OOM 等无关异常扩大 fallback。
- `sendWithFirstTurnGpuFallback()` 只在回复非空且通过清理后，才把 user/model pair 追加到 `conversationHistoryTurns`。
- 非首轮失败时，先重建 CPU Engine，并通过 `LocalAiConversationHistoryPolicy.initialMessages()` 回放此前已成功轮次，然后抛出“当前请求执行状态未知、未自动重放”的错误。
- 这避免了模型可能已经消费当前请求、但响应丢失时的自动重复执行。用户确认后重新发送属于新的显式请求。

### 1.3 仍存在的边界

- 当前 Native 成功轮次恢复历史由 `LocalAiConversationHistory` 管理，按最多 12 个完整成功轮次与 10,000 UTF-16 code units 双重限制，逐条淘汰最旧完整轮次并记录省略计数；CPU 恢复只回放保留的完整成功轮次。此字符/轮数上限不是 Gemma 4 E4B 的 Token/context window 预算，实际可用 Token 预算仍须设备测量。
- `runAiTask()` 和主要推理恢复分支捕获 `Exception`，不是所有 JVM `Throwable`。不能据此声称 JNI/Error 类故障全部会被恢复。是否扩大捕获范围需按 LiteRT-LM 实际异常类型审计，不能吞掉 OOM 等致命错误。
- 当前 `onDestroy()` 通过 `LocalAiActivityTaskLifecycle.destroy()` 将 release 排入进程级单线程 executor，不再 shutdown 共享队列；新 Activity 的模型任务排在旧 release 后。release 失败会把进程健康状态标记为 unavailable，后续 Native 操作 fail-closed，需强停进程再启动。JVM 生命周期测试覆盖队列顺序和失败隔离，但不等同于 Find N2 真机资源释放/进程恢复验收。
- Core-3 主文本与媒体结构化 Native 入口现已携带 `request_id + conversation_id`，在 Native 建立 pending turn 并要求显式 `finalizeReasoningTurn` / `rejectReasoningTurn`；Dart/SQLite 的 `AssistantReasoningTurnLedger` 另行持久化请求生命周期。Native 的 MethodChannel finalize/reject acknowledgement ledger 仅为进程内有界缓存；旧 `sendMessage` 与辅助窄任务不应被推定为全部拥有相同跨进程幂等语义。跨进程恢复以 App SQLite Ledger 的 UNKNOWN/non-replayable 规则为准。

## 2. 历史恢复与上下文一致性

### 2.1 SQLite / Flutter / Native 的不同表示

- SQLite：`assistant_conversations`、`assistant_messages`、`tcm_interview_tasks` 保存会话、消息和结构化问诊快照。
- Flutter：`LocalAiInterviewScreen._openHistory()` 从 SQLite 读取 user/assistant 消息，恢复 UI 消息、模式、待处理工具状态和结构化问诊状态。
- Native：`restoreLocalConversation()` 将恢复后的 transcript 作为一个受约束的上下文 prompt 注入新 Conversation，而不是逐条重建原始 user/model message 对象。
- 附件原件不持久化；恢复 transcript 只包含“曾发送附件”的说明，不代表图片/语音二进制已恢复。
- Native 症状提取输入只收显式 user messages 与标记为待用户核对的音频转写；不把 assistant 回复或图片观察直接当作用户自述。

### 2.2 本分支修复的两个确定性问题

**问题一：Native 二次截断会丢失 transcript 尾部。**

Flutter 历史恢复先在超过 10,000 UTF-16 code units 时添加“较早历史已省略”标记，并截取最近 10,000 个字符；加上标记后总长度超过 10,000。旧 Native 代码再执行 `transcript.take(10000)`，会从末尾截掉最近内容，而不是继续删除更早内容。

本分支新增 `LocalAiTranscriptRestorePolicy.boundTranscript()`：
- 统一以 UTF-16 code units 计数；
- 超长 transcript 保留显式省略标记和最新尾部；
- 已带标记时不重复添加；
- 截断边界不从 UTF-16 surrogate pair 的 low surrogate 开始；
- MainActivity 使用该 policy，不再直接 `take(10000)`。

**问题二：症状提取历史最多保留 60 条，但旧代码没有标记被省略。**

旧代码 `userMessages.takeLast(60)` 静默丢弃较早用户消息，且没有将 `userReportedInputsTruncated` 设为 true。后续症状草稿可能把保留的 60 条误当作完整来源。

本分支改为：
- 由 `LocalAiTranscriptRestorePolicy.recentUserMessages()` 统一保留最近 60 条；
- 当原始 userMessages 超过 60 条时，先将 `userReportedInputsTruncated` 设为 true；
- `extractSymptoms()` 将 `sourceTruncated=true` 返回给 Dart，并要求模型把无法从保留记录确认的信息列入 unknowns。

新增 Kotlin 单测覆盖短 transcript、超长 transcript 保留尾部、已有省略标记、surrogate 边界、最近 60 条和省略标记传播。

## 3. 成功轮次与症状来源

- Native `LocalAiConversationHistoryPolicy` 只接受非空 user/model pair；空回复不会被记录为成功轮次。
- `UserReportedInputPolicy` 限制 100 条、单条 2,000 UTF-16 code units、总计 16,000；任何裁剪通过 `truncated` 标记传递。
- 图片观察和 assistant 回复不直接进入用户症状来源；音频转写作为“模型生成、尚待用户核对”的来源单独标记。
- 附件在 Native Conversation 历史中使用占位说明和 prompt，不保存临时文件路径；原始附件文件在当前成功/失败清理路径中由 Flutter 删除或保留供用户重试。

## 4. SQLite 持久化风险（未在本分支修复）

源码：`LocalAiInterviewScreen._persistSuccessfulTurn()` 与 `DatabaseHelper.saveAssistantMessage()`。

- Flutter 先调用一次 `saveAssistantMessage(user)`，再调用一次 `saveAssistantMessage(assistant)`；两条消息不是同一个 SQLite transaction。
- `_persistSuccessfulTurn()` 捕获异常后只 `debugPrint`，没有把“本轮回复未完整持久化”明确显示给用户。
- 若 user 消息写入成功、assistant 消息写入失败，会留下单边消息；若两次都失败，UI 和 Native 已有成功轮次，但 SQLite 历史缺失。
- 这会使当前 Flutter/Native 会话与重启后 SQLite transcript 不一致。应在独立 A 切片增加原子 `saveAssistantTurn` 契约，并让 UI 对持久化失败给出明确状态；不能在本审计中把这类失败当作已解决。

## 5. 当前测试覆盖与未覆盖

| 范围 | 已有测试/代码 | 状态 |
|---|---|---|
| 成功轮次追加、顺序和 snapshot | `LocalAiConversationHistoryPolicyTest` | TEST |
| 空 user/空 model 不进入成功历史 | `LocalAiConversationHistoryPolicyTest` | TEST |
| 仅首轮已知 OpenCL 错误允许 GPU→CPU 自动 fallback | `FirstTurnGpuFallbackPolicyTest` | TEST |
| Conversation 先于 Engine 释放，首项失败仍尝试释放另一项 | `ConversationResourceReleasePolicyTest` | TEST |
| reset 失败时释放 Engine，不保留半初始化引用 | `ConversationResetPolicyTest` | TEST |
| user-reported inputs 条目/字符预算和 truncated 状态 | `UserReportedInputPolicyTest` | TEST |
| transcript 尾部保留、marker、surrogate 边界 | `LocalAiTranscriptRestorePolicyTest`（本分支新增） | 等待本分支 CI |
| 超过 60 条用户消息时传播 sourceTruncated | `LocalAiTranscriptRestorePolicyTest`（本分支新增） | 等待本分支 CI |
| 真正 LiteRT-LM GPU/CPU 连续推理、state:7 复现和恢复 | Find N2 设备 | UNKNOWN，尚无本轮逐轮 TRACE |
| Activity destroy 与 Native executor 正在运行的竞态 | 设备/集成测试 | UNKNOWN |
| SQLite user+assistant 原子持久化与失败注入 | 当前无对应原子接口 | MISSING |
| SQLite transcript、Flutter UI、Native context 三方逐轮对照 | 设备 TRACE | UNKNOWN |

## 6. 本分支改动与验收边界

- 新增 `LocalAiTranscriptRestorePolicy.kt` 与对应 JUnit 测试。
- 修改 `MainActivity.restoreLocalConversation()`：保留最新 transcript 尾部，并在用户消息被截断时设置来源不完整标记。
- 不改 GPU/CPU backend 选择、不扩大异常捕获、不自动重放未知请求、不改模型文件和推理参数。
- 本分支 CI 通过后，只能把两个历史恢复缺陷标记为代码/单测修复；A 整体仍 PARTIAL。
- Find N2 GPU 至少 20 轮、CPU 至少 20 轮、图片/语音附件、强制终止/重启和 SQLite/Flutter/Native 三方对照仍需真实设备 TRACE。没有设备证据不标 PASS。

## 7. 下一项 A 工作

1. 为 user+assistant 成功轮次提供原子持久化接口；故障注入验证不会只留下半轮。
2. 给持久化失败增加明确 UI 状态，禁止 UI/Native 成功但历史无提示地缺失。
3. 为 Native 成功轮次历史定义可测量的上下文预算与裁剪策略；必须显式标记 truncation，不以猜测 token 数设硬阈值。
4. 对 Activity destroy、请求执行中离开页面、release/reset 排队和重复请求做状态矩阵与可注入测试。
5. 完成设备 TRACE 对照；设备侧实测缺失前 A 不得转 PASS。


---

## 8. 2026-11-13 增量复核：SQLite 原子持久化、TRACE 分离与 Activity 释放失败隔离

> 本节以 `master @ 849ec817f6e11f154ea662316b32b2fbfa230ffc` 为当前代码基线，覆盖前文尚未更新的持久化和 Activity 生命周期结论。前文第 4、5、7 节保留为 2026-11-11 历史审计记录；与本节冲突的旧结论不再代表当前 master。

### 8.1 已关闭的确定性代码问题

| 原审计问题 | 当前实现 | 当前证据 | 结论 |
|---|---|---|---|
| 普通 user + assistant 成功轮次分两次 SQLite insert，可能只保存一半 | `DatabaseHelper.saveAssistantTurn()` 将两条 `AssistantMessageDraft` 交给 `saveAssistantMessagesAtomically()`，同一 SQLite transaction 写消息与 conversation metadata | PR #117；`test/assistant_history_persistence_test.dart` 的事务成功及 trigger 故障回滚测试 | CODE + TEST + CI PASS |
| `_persistSuccessfulTurn()` 保存失败只写 debug log，UI 无明确告警 | `_persistSuccessfulTurn()` 捕获异常后在 UI 显示“本轮回复已生成，但保存到历史记录失败”；返回 false | 当前 `local_ai_interview_screen.dart`；PR #117 Flutter regression | CODE + TEST + CI PASS |
| 结构化问诊一轮新增多条 transcript 逐条写入，后续失败可能留半轮 | `_appendTcmInterviewMessages()` 将新增消息组装成有序批次，通过 `saveAssistantMessagesAtomically()` 一次提交；事务失败时不保留部分消息 | PR #117；SQLite trigger 回滚测试；`test/local_ai_interview_screen_test.dart` 批次失败回归 | CODE + TEST + CI PASS |
| transcript 消息写入失败和问诊任务快照失败使用同一 `persistence` 结果，可能错报 | `_TcmInterviewMessagePersistenceResult` 分离 transcript applicability/commit；`AiTraceStage.persistence` 只记录 transcript batch，`AiTraceStage.persistedState` 只记录任务快照 | PR #119；反向故障注入断言 message SUCCESS + task snapshot FAILED | CODE + TEST + CI PASS |
| task snapshot 失败时诊断历史索引/自动复制后续动作可能越过原有依赖 | `_persistDiagnosisHistoryOnce()` 和自动复制处方只在 `taskStatePersisted` 时执行；失败时保留独立错误提示 | PR #119 最新 head `94964cb653ec1400a7944e7f25d23c83a8259588` 的全量 Flutter/Android CI | CODE + TEST + CI PASS |

**当前持久化语义：**
- 普通助手成功轮次：user + assistant 消息成对事务提交；失败后显示历史保存失败，不把 SQLite 成功状态假装为成功。
- 结构化问诊 transcript：本次新增的多条消息在一个 transaction 内提交；任意 insert 或 preview/title 更新失败时整批回滚。
- 结构化问诊任务快照：与 transcript 分开保存、分开记录 TRACE。以下两种状态都允许且有独立测试：
  - transcript `FAILED` + task snapshot `SUCCEEDED`；
  - transcript `SUCCEEDED` + task snapshot `FAILED`。
- SQLite transaction 保证的是数据库消息批次一致性；不代表 Native Conversation 内存历史、Flutter 页面状态与 SQLite 在设备进程崩溃后的所有时刻都已完成三方一致性验收。

### 8.2 Activity destroy / process-wide Native executor 当前实现

当前源码：
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiActivityTaskLifecycle.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt`
- `android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiActivityTaskLifecycleTest.kt`

当前行为：
1. `LocalAiProcessExecutor.executor` 是进程级单线程队列；Activity 的 Native AI 操作和 teardown 进入同一队列。
2. `LocalAiActivityTaskLifecycle.destroy()` 使用原子标记，防止重复 release；已开始的任务先结束，queued-but-not-started 的旧 Activity 操作被拒绝；旧 Activity 的 `releaseLocalModel()` 排在已运行任务之后。
3. 新 Activity 通过同一进程级队列提交模型加载/推理任务，因此在 release 正常完成时，其操作排在旧 Activity release 之后。
4. `LocalAiProcessHealth` 记录第一次 release failure。release 失败后：
   - 进程健康状态保持 unavailable；
   - 新任务在提交前检查一次，在队列执行时再检查一次，覆盖“新 Activity 已入队，旧 Activity release 随后失败”的竞态；
   - 新模型操作/导入返回 `LOCAL_AI_RUNTIME_RELEASE_FAILED`，不会在同一进程继续创建另一套 Engine；
   - Activity teardown 记录 Native release error；用户提示通过系统设置强行停止 App 进程后再重新打开。
5. 该保护是进程级 fail-closed 状态，不是自动恢复机制。当前进程不会通过重新创建 Activity 清除 poisoned 状态；必须结束 App 进程后重新启动。

**新增测试：**
- `LocalAiActivityTaskLifecycleTest.releaseFailureBlocksWorkQueuedByARecreatedActivity` 使用 latch 让旧 release 保持阻塞，确认新 Activity 任务已经入队后再让旧 release 抛错；断言新任务没有执行、收到 unavailable 回调、进程健康状态保留原始失败，后续提交立即拒绝。
- 既有 `oldActivityTeardownRunsBeforeNextActivityTasks` 和 `destroyReleasesExactlyOnceAndRejectsLaterWork` 继续覆盖正常 teardown 顺序和 exactly-once 行为。
- 这一组是 executor/lifecycle 协调层 Kotlin 单元测试；不是 OPPO Find N2 上 LiteRT-LM Engine/Conversation 实例确实释放的实机证据。

### 8.3 PR 与 CI 证据

| 交付 | 主线提交 | PR/CI 证据 | 状态 |
|---|---|---|---|
| #117 SQLite transcript 原子批量持久化 | `872a715a3817a57c8b4dd708a33f6b3a13c428c0` | PR run `43238225000` Flutter + Android arm64/Native SUCCESS；post-merge runs `43239874217`、`43239874208` SUCCESS | MERGED / PASS |
| #118 执行台账和 B2 当前入口调用图 | `2ddbd43b14f4c90d3a328eb53108e2d90d894d03` | PR run `43240664441` Flutter regression + Android arm64/manifest/ABI/Native SUCCESS；post-merge runs `43242258923`、`43242259297` SUCCESS | MERGED / PASS |
| #119 transcript / task snapshot TRACE 分离 | `5d73161b49fd3f38ffada31c0da1b06e7d24bec0` | PR run `43242639810` Flutter regression + Android arm64/Native SUCCESS；post-merge runs `43339881225`、`43339881116` SUCCESS | MERGED / PASS |
| #120 Native release failure fail-closed | `849ec817f6e11f154ea662316b32b2fbfa230ffc` | PR run `43342006102`：Flutter job `131612308210` SUCCESS；Android job `131614130546` SUCCESS（APK/ABI、Native unit tests、XML 报告和证据上传）；post-merge runs `43343151516` 和 `43343151619` 在本节更新时为 IN_PROGRESS | MERGED / PR CI PASS；post-merge CI PENDING |

PR #120 早期 head `43ebdb5931111ae75631a4a2942514f65e32371f` 的一次 CI 曾因 Kotlin constructor 参数顺序不兼容而在 `compileDebugUnitTestKotlin` 失败；已将可选 `processHealth` 参数放到最后一个 `release` 函数参数之前，保持历史尾随 lambda 调用兼容。该失败 head 不作为最新 head `9ed99aa66f2047b985682ff4df9dd425647600b5` 的验收结果。

### 8.4 A 当前状态和剩余 UNKNOWN

| 场景 | 当前结论 | 仍需的证据 |
|---|---|---|
| 普通 user + assistant SQLite 半轮持久化 | 对应代码缺陷已修复 | 真机连续轮次后 SQLite / UI / Native transcript 三方逐轮对照 |
| 结构化问诊 transcript 半批次写入 | 对应代码缺陷已修复 | Find N2 实际连续问诊、Activity recreation、进程终止恢复 TRACE |
| task snapshot / transcript TRACE 错误归属 | 对应状态分类缺陷已修复 | 真实设备故障/恢复场景及持久化 trace 对照 |
| Activity release success 后新 Activity 串行加载 | executor 单元测试覆盖 | Find N2 实际 Activity recreation、模型 release/load、GPU/CPU backend 日志 |
| Activity release failure 后新 Activity fail-closed | 新 Kotlin 并发回归通过 | Find N2 注入或可复现的 Native release failure 实机记录；当前进程强行停止/重新启动后可恢复加载 |
| `state:7` 根因 | UNKNOWN | 必须取得设备 logcat、LiteRT-LM backend、App SHA 和逐轮 trace；不能用 executor 测试推断 |
| GPU 连续推理 / CPU 连续推理 | UNKNOWN | Find N2 GPU 至少 20 轮、CPU 至少 20 轮；不能用 arm64 APK 构建或 JVM tests 代替 |
| 图片/语音附件连续输入和中断恢复 | UNKNOWN | 真实附件、转写状态、临时文件生命周期和每轮 trace |
| 历史恢复后 Native context / Flutter UI / SQLite 一致性 | PARTIAL / DEVICE UNKNOWN | 真实恢复前后 transcript、成功轮次、任务快照及 trace_id 对照 |
| `conversationHistoryTurns` context budget | UNKNOWN | 基于 Gemma 4 E4B 实际上下文行为测量，不按猜测 token 数增加裁剪阈值 |

**A 继续保持 `PARTIAL`。** #117/#119/#120 关闭了可通过代码和自动化精确复现的问题，但没有完成设备验收。本轮没有更改 GPU/CPU fallback 条件，没有对未知执行状态自动重放当前请求，也没有猜测模型上下文窗口并添加 token 上限。

### 8.5 下一项 A 工作

1. **设备 TRACE**：Find N2 GPU 至少 20 轮、CPU 至少 20 轮，覆盖文字、图片、语音；记录设备型号、Android 版本、App SHA、模型 SHA/版本、backend、轮次和 trace_id。
2. **生命周期实机**：真实执行 Activity recreation、请求中离开页面、进程强行停止/重启；核对 release failure 时新 Engine 是否被阻断、进程重启后能否重新加载。
3. **三方历史一致性**：逐轮对照 SQLite transcript、Flutter UI 和 Native successful-turn history；历史恢复后核对任务快照、来源截断标记和上下文恢复结果。
4. **上下文预算**：只记录设备测量数据；没有模型实测前不擅自为 `conversationHistoryTurns` 设置 token 硬限制。
5. **数据清除与备份副本**：沿 E 工作流继续核对共享 SQLite 的备份边界、旧共享附件和外部副本；本节 lifecycle 修复不代表清除后重启不可恢复已完成。

### 8.6 执行边界

- PR/主线 Android arm64 APK 是 build/ABI 证据，不是 OPPO Find N2 实机运行证据。
- JVM lifecycle test 验证的是进程级串行队列与失败传播，不证明 LiteRT-LM Native 资源在真机所有异常类型下都一定可释放。
- release failure 后的策略是 fail-closed：宁可要求用户强停并重启进程，也不在资源释放状态未知时继续初始化另一套模型对象。
- 没有设备 logcat、backend 及 trace_id 的场景继续标 `UNKNOWN`；不得以 CI 绿灯冒充真机 PASS。


## 9. 2026-11-13 主线核验：transcript restore policy 已集成

本节是对上文第 5/8 节“LocalAiTranscriptRestorePolicy 新增后等待本分支 CI”的后续状态更新；旧段落保留为历史记录，不再代表当前主线状态。

### 9.1 当前主线调用链

- 当前 master 集成基线：`04de8e52abdc88d3c6f99d4b0db836721564acf4`。
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiTranscriptRestorePolicy.kt` 已在 master；`MainActivity.restoreLocalConversation()` 调用：
  - `boundTranscript(transcript)`：限制恢复 transcript 到 10,000 个 UTF-16 code units，保留明确的“较早历史已省略”标记和最新尾部，避免在代理项对中间切断。
  - `hasOmittedUserMessages(userMessages)`：在超过 60 条用户文字输入时，先设置 `userReportedInputsTruncated=true`。
  - `recentUserMessages(userMessages)`：仅将最近 60 条显式用户文字自述交给 `recordUserInput`；助手回复和附件占位不作为症状来源。
- Native `extractSymptoms()` 使用 `userReportedInputsTruncated` 传播 `sourceTruncated=true`，避免把保留的 60 条误当作完整历史来源。

### 9.2 当前测试与验收证据

- 对应 Kotlin 测试：`android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiTranscriptRestorePolicyTest.kt`，覆盖短 transcript 原样保留、长 transcript marker/最新尾部、已有 marker、surrogate 边界、最近 60 条和省略状态传播。
- PR #139 Android arm64 CI job `131912798580` 已通过 Native unit tests 与 JUnit XML 校验；这条 CI 的测试运行包含当前 master 的 Kotlin 测试源。
- 这关闭的是“策略/单测仍在分支等待”的代码状态；并不等于 Find N2 真机恢复后的 Native/Flutter/SQLite 三方 transcript 已完成逐轮一致性验证。

### 9.3 A 项剩余状态

- Transcript 裁剪和 sourceTruncated 传播：CODE + TEST + PR Android Native CI PASS。
- Find N2 GPU 至少 20 轮、CPU 至少 20 轮、图片/语音、多轮、Activity/进程恢复以及恢复后 SQLite/Flutter/Native 三方历史一致性：继续 DEVICE UNKNOWN。
- `state:7` 等 Native 推理根因仍须设备 logcat、backend 和 trace_id；不使用 JVM lifecycle test 推断真机根因。

---

## 10. 2026-11-27 历史主线复核：Native 多轮记忆边界与请求生命周期已形成云端闭环

> 本节保留 `master@1d79bc2f628fde789c5b5602cee889f844972c23` 时的主线状态快照，历史实现过程不回写；最新运行时代码复核与 CI 状态以第 11 节 `master@04eb5bec9321b3d00eb85fdea7c0bd31b6fdc40f` 为准。AI 多轮/五层运行时集成点为 `45144f6c3d140d259ac51f8cfbb886c19c10e0a3`。

### 10.1 当前已落地的 Native / Memory 治理

| 事项 | 当前主线实现 | 当前结论与边界 |
|---|---|---|
| Native 成功轮次历史 | `LocalAiConversationHistory` / `LocalAiConversationHistoryPolicy` | 最多保留 12 个完整 user/model 成功轮次，且累计不超过 10,000 UTF-16 code units；按完整最旧轮次淘汰，保留 omitted turn/character 计数与完整成功轮次总数。不是 Token 预算，不能据此声称满足 E4B context window。 |
| Native Token/context 只读观测 | `MainActivity.observeConversationTokenCount()` / `Conversation.getTokenCount()`；`MainActivity.inspectModelContextLimit()` / `ModelInfo.maxContextTokens()`；`LocalAiModelStatus` | 主线已暴露当前 Conversation KV Cache token 数与模型文件声明的最大上下文长度，并分别提供观察状态；读取失败/状态重置时回到 UNKNOWN。`conversationKvCacheBudgetStatus` 固定为 `NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`，未形成 App 可用输入预算、输出预留、动态预算阈值、安全裁剪或自动压缩。源码与 parser 单测证明接线/解析合同，不替代 Find N2 对实际数值和长会话行为的 TRACE。 |
| SQLite 成功轮次原子保存 | PR #117 的 `DatabaseHelper.saveAssistantTurn()` / `saveAssistantMessagesAtomically()` | user + assistant 消息同一 SQLite transaction；故障注入验证不留半轮；持久化失败由 UI 显示，不伪装为成功保存。结构化问诊 transcript 批次也原子提交；任务快照与 transcript 的 TRACE 分离由 #119 完成。 |
| Native transcript 恢复 | `LocalAiTranscriptRestorePolicy`、`MainActivity.restoreLocalConversation()` | 以 UTF-16 字符限制保留最新尾部和显式省略 marker；最近 60 条用户文字输入会传播来源截断状态。只恢复用户/模型成功文本与附件占位说明；不恢复附件原始二进制。 |
| 请求级临时上下文隔离 | PR #565，merge `da63bafec6e2a38784ba1d7b8a16d36d6b3a5a18` | 跟踪活动 LiteRT Conversation KV cache 是否含 RAG、SessionState、reasoning metadata 或多媒体输入；下一个请求前只在 dirty 时从有界成功 transcript 重建 Conversation。普通纯文本连续轮次不做不必要 rebuild；失败/GPU→CPU retry 保留 dirty 标记。临时 RAG 正文、SessionState 正文、reasoning envelope 和真实附件 payload 不写入恢复 transcript。 |
| 结构化推理请求生命周期 | PR #575，merge `700d6e87e6e86d25c6e75ab3d602e3fbb0897720` | SQLite 隐藏 Ledger 持久化 PENDING/FINALIZED/REJECTED/UNKNOWN/SUPERSEDED；打开会话时未终结请求降为 UNKNOWN、禁止自动重放；已 FINALIZED 但 transcript 原子保存中断时，从 App 已验证答案重建 user/assistant 对。请求按 conversation/request identity 隔离。 |
| Native 两阶段提交 | `sendReasoningMessage`、`sendReasoningAttachmentMessage`、`finalizeReasoningTurn` / `rejectReasoningTurn` | 主文本和媒体结构化入口均绑定 requestId 与 conversationId；Native 在解析前不把 raw JSON 当作成功轮次，Dart 校验后 finalize，失败则 reject。Native 的 finalize/reject ack ledger 为进程内缓存；跨进程 UNKNOWN/non-replayable 语义由 SQLite ReasoningTurnLedger 保证。 |
| Activity / process 生命周期 | PR #120 的 `LocalAiProcessExecutor` / `LocalAiActivityTaskLifecycle` | Native 推理与 teardown 共享进程级单线程队列；新 Activity 排在旧 release 后。release 失败会 poison 当前进程并 fail-closed，须用户强停 App 进程后重新打开；不在释放结果未知时重建第二套 Engine。JVM 测试覆盖队列顺序与失败隔离，不替代真机资源释放证据。 |
| 多轮 E2E | PR #585 的 20 轮 widget regression | Flutter 侧验证同一 conversation owner、requestId 唯一、SessionState 只含允许的用户/模型消息、排除隐藏 Native/工具 Ledger、一次显式确认工具执行和只读结果回流。使用测试 Native service / fake executor；不证明真实 E4B/GPU/CPU 连续推理。 |

### 10.2 精确 PR HEAD 自动验收证据

| 变更 | 精确 PR HEAD | Flutter / Native 相关 CI | Fork License | 说明 |
|---|---|---|---|---|
| #565 Native dirty-KV flush | `9f5adea9b0b2cc1391665e469bf038c881350baa` | run `45801957065` SUCCESS | run `45801957063` SUCCESS | PR 事件返回的工作流包含 Flutter tests 和许可证检查；不将其解释为实机推理结果 |
| #575 持久化 reasoning turn ledger | `9fe364df135e42be122259043c408485b78779b7` | run `45839888161` SUCCESS | run `45839888050` SUCCESS | Android arm64/JVM 的当前主线自动验证在之后的 master runs 完成；不以此表中未列出的 PR job 声称单独通过 |
| #585 20 轮 / 单次工具 E2E | `6d9bb0549bed768d66cb2fe6b6fcdeecb6ef369d` | run `45943407178` SUCCESS，Android arm64/JVM job `140324524005` SUCCESS | run `45943407188` SUCCESS | fake executor 的 Flutter widget 合同测试，不是 E4B 真模型 |

### 10.3 当前仍为 DEVICE UNKNOWN 的验收项

1. Find N2 上 GPU 实际 backend 连续至少 20 轮；记录每轮成功/空回复/异常、backend、trace_id。
2. Find N2 上 CPU 实际 backend 连续至少 20 轮；GPU 自动 fallback 的轮次不得计为 GPU 成功。
3. 真实图片/语音多轮输入、附件临时文件清理/保留与用户核对状态；确认结构化 Response、finalize/reject 和 Native dirty-KV flush 在实际 E4B 下行为正确。
4. Activity recreation、请求中离开页面、App force-stop / process restart；确认旧 Native 资源释放与新 Activity 初始化顺序、SQLite transcript、Flutter UI 和 Native recovered history 三方一致。
5. state:7 的实际根因；必须有 Find N2 logcat、实际 backend、App SHA、模型 SHA/版本和逐轮 trace_id，不能从 JVM test 推断。
6. Gemma 4 E4B 在 Find N2 上的实际 KV Cache token 数、模型声明 maxContextTokens 与长会话行为。当前已接入只读 `Conversation.getTokenCount()` 和 `ModelInfo.maxContextTokens()`，但 App budget status 仍为 `NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`；实测可用输入预算、输出预留、预算策略/安全裁剪和自动压缩仍 UNKNOWN。现有 12 轮、10,000 transcript 字符、16,000 SessionState 字符、24,000 reasoning context 字符均为字符/轮次数边界，不是可用 Token 预算，也不能直接相加推定预算。
7. AI 数据清理后 Native/SQLite/附件/备份副本的不可恢复状态，按唯一设备交接文件执行。

**当前判定：** Native 多轮的云端确定性代码治理已形成闭环：原子 transcript 持久化、临时 KV 上下文逐轮隔离、结构化请求终态和非 replayable 恢复、Activity executor 失败隔离均有主线实现和自动化证据。A 仍是 **PARTIAL / DEVICE UNKNOWN**，因为真实 Find N2 GPU/CPU、state:7、媒体、Activity/进程恢复、三方 transcript 对照、实际观测值及长会话行为尚未有设备 TRACE；App 可用 Token 预算与自动压缩也尚未配置。设备验收按唯一 `docs/local-real-device-acceptance-handoff.md` 放在所有云端工作之后，不阻塞云端代码、文档和 CI。



### 10.4 2026-11-27 历史主线 CI 状态同步

- 当时 master HEAD：`1d79bc2f628fde789c5b5602cee889f844972c23`（该次仅文档同步）。
- 同一 SHA 对应的 Flutter tests run `45976217087`、Flutter Quality Gate run `45976217173`、Fork License run `45976217114` 均为 SUCCESS。
- PR #594 已将 LocalAiService 旧非结构化包装方法退役；Native 旧 `sendMessage` 保留为 fail-closed 路由，不调用模型。该 Core-3 变更不改变本节 Core-1 的恢复边界。
- 当前主线已有 KV Cache token 数与模型声明 maxContextTokens 的只读观测；`conversationKvCacheBudgetStatus` 仍为 `NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`，因此实测可用 Token/input budget、预算控制/自动压缩并未完成。
- 本次只同步当前主线核验点、CI 证据和 Token 观测/预算边界，未修改 Native 多轮运行时代码。真实 Find N2 GPU/CPU、state:7、媒体、Activity/process restart、实际 token/context 值与长会话行为仍按第 10.3 节和唯一设备交接文件执行，继续保持 DEVICE UNKNOWN / NOT RUN。


## 11. 2026-11-27 PR #598 后 Native 多轮云端状态复核

- **复核运行时代码基线：** `master@04eb5bec9321b3d00eb85fdea7c0bd31b6fdc40f`。PR #598 改动属于 Core-3 旧 Native 媒体 helper 清理，不改变 Core-1 会话历史、请求 Ledger、SessionState owner 或 dirty-KV 隔离路径。
- **精确 SHA 自动化：** Flutter tests `45993861676`、Flutter Quality Gate `45993861611`、Fork License `45993861643` 均 SUCCESS；Android arm64/JVM job `140491798547` 与 `140488210528` 均 SUCCESS。Branch validation `140488213234` 是 SKIPPED，不计 PASS。
- **云端确定性部分：** 有界成功 transcript、临时 RAG/SessionState/reasoning/media 上下文隔离、请求终态 Ledger、UNKNOWN/non-replayable 恢复、Native 串行队列与失败隔离维持现有代码和自动化覆盖；本轮不改这些运行时逻辑。
- **Token 观察边界：** `Conversation.getTokenCount()` 和 `ModelInfo.maxContextTokens()` 是 Native 运行时只读观察；`conversationKvCacheBudgetStatus=NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`。它们不代表 App 可用输入 Token 预算、剩余空间、输出预留或安全截断阈值。没有 Find N2 实测数据前，不添加推测性 token budget 或自动压缩。
- **设备未决项：** GPU/CPU 各至少 20 轮、state:7、图片/语音、多轮上下文行为、Activity/process restart、SQLite/Flutter/Native transcript 三方对照、真实 KV Cache 数值、长会话边界仍为 `DEVICE UNKNOWN / LOCAL ONLY / NOT RUN`。不得用 Android CI build、JVM、Widget 或 fake executor 改写为设备 PASS。
- **交接路径：** 设备所有执行状态和本地证据只回填 `docs/local-real-device-acceptance-handoff.md` §7.1；本审计文档保留 Native 多轮技术边界与代码审计，不另开设备进度表。


## 12. 2026-11-28 Native restore 用户自述载荷跨进程前限界

- **基线：** PR #609 合并后 `master@85f9a23acb07341af3fbfdd38275831f2a2f4c48`。
- **问题：** 历史恢复此前把全部历史 user messages 传入 Native，再在 Native 侧取最近 60 条并由 `UserReportedInputPolicy` 裁剪；这只能证明接收后有上限，不能证明跨 MethodChannel 的载荷有限。
- **云端修复：** Flutter 在遍历持久化历史时以增量 Builder 保留最近 60 条非空用户输入；按每条附加固定来源标签 `用户文字自述：` 后不超过 2,000 UTF-16、聚合不超过 16,000 UTF-16 计算边界。截断不拆分 surrogate pair，数量/单条/总量裁剪通过必需 `user_messages_truncated` Boolean 传入 Native。
- **Native 复核：** `parsePayload` 对 Boolean 类型、条目数、每条及聚合格式化长度进行第二次校验；不合法载荷在当前 Native Conversation reset 前拒绝。成功恢复后，Native 使用显式截断状态初始化症状来源完整性标记，不再在收到无界列表后静默丢弃旧条目。
- **数据边界：** 该投影只用于症状整理的用户自述输入，不提升为 Native 成功轮次、SessionState 事实或可重放工具动作。成功 transcript 仍最多 12 个完整轮次/10,000 UTF-16；KV Cache 不持久化，App Token budget 仍 `NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`。
- **设备状态：** 真实 E4B 症状整理效果、Find N2 GPU/CPU 多轮、Activity/process restart 和 SQLite/Flutter/Native 三方历史一致性继续 MISSING / UNKNOWN / LOCAL ONLY；CI 不替代设备 PASS。


## 13. 2026-11-28 PR #610 / #618 / #622 后跨层记忆边界与当前主线复核

> 本节追加更新，不改写 §10–§12 的历史快照。Native transcript 恢复、症状整理用户自述投影、Dart/SQLite SessionState 快照是三个相关但不同的边界；不得合并为一个“历史恢复”状态。

### 13.1 当前基线与职责分界

- **当前仓库 master：** `57f6fbef193d28fc6c3493c8740d672038fdd52c`（PR #623 文档收尾合并）。当前 AI 运行时代码基线仍为 `805f006ed502c5cbf10dba4ad30428ee9761eb42`（PR #622 合并）；PR #623 只修改架构、执行台账和唯一设备交接文档，没有运行时代码变化。
- **Native 成功轮次 transcript：** `LocalAiConversationHistory` / `LocalAiConversationHistoryPolicy` 只保留最多 12 个完整成功 user/model 轮次和 10,000 UTF-16 code units；未完成或失败请求不提升为成功轮次。它服务 Native Conversation 重建，不等同 SQLite UI 全历史。
- **症状整理用户自述投影：** `LocalAiUserMessageRestoreProjectionBuilder` 只为症状整理保留最近 60 条非空 user 输入；每条含来源标签后最多 2,000 UTF-16，合计最多 16,000 UTF-16；数量、单条或总量裁剪都必须通过 `user_messages_truncated=true` 显式传播。它不是成功 transcript、SessionState 事实或工具动作恢复记录。
- **SessionState：** PR #622 新增的 SQLite 专用读取只为本轮结构化记忆构造提供有界数据；它不替换完整 UI/history API，也不改变 Native 成功 transcript。三者的 owner、截断状态和可重放资格必须继续分开。

### 13.2 PR #610：跨 MethodChannel 用户自述载荷限界

- **合并证据：** PR #610 最终 HEAD `39e841917139bb2b9036d615cb7bacb30031b75f`，squash merge `bcfa2e36440689d7d5cd12abfd80cf191c6d66dc`。
- **Dart：** `lib/services/local_ai_transcript_restore_policy.dart` 中的 `LocalAiUserMessageRestoreProjectionBuilder` 增量遍历历史，只保留最近 60 条；按附加 `用户文字自述：` 后的最终 Native 格式核算 2,000 / 16,000 UTF-16 边界，并在裁剪时避免拆开 surrogate pair。两条恢复调用路径均传入有界列表与必需截断 Boolean。
- **Native：** `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiTranscriptRestorePolicy.kt` 的 `parsePayload` 严格验证列表、必需 Boolean、条数、每条格式化长度与聚合长度。无效载荷返回 `INVALID_RESTORE_PAYLOAD`；`MainActivity` 在恢复路径先解析/验证载荷，再进入会话状态更换流程。
- **测试：** `test/local_ai_transcript_restore_policy_test.dart`、`test/local_ai_transcript_restore_architecture_test.dart`、`test/local_ai_interview_screen_test.dart`、`test/assistant_history_resume_test.dart`、`android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiTranscriptRestorePolicyTest.kt` 覆盖边界、截断传播、错误 envelope、surrogate pair 和恢复调用路径。
- **精确 HEAD CI：** Flutter regression job `140802809044` SUCCESS；Android arm64/JVM job `140805368611` SUCCESS；Fork License run `46088245573` SUCCESS。Branch validation job `140802810165` 为 SKIPPED，不计 PASS。

### 13.3 PR #618：GPU→CPU fallback 原因的生命周期可观测

- **合并证据：** PR #618 最终 HEAD `0b2aff6963e6fe79dabe788b05a529a273840567`，squash merge `73a79b9ac36879b22db60c8be9c1cd25ef31037a`。
- **源码：** `MainActivity.backendFallbackReason` 只在 GPU 初始化失败且 CPU fallback 成功时保留 GPU 原因；`modelStatus()` 将其投影为 `backendFallbackReason`，Dart `LocalAiModelStatus` 与设置页展示。GPU 初始化成功、用户明确选 CPU、Native runtime/model release 时清除旧原因，避免 `backend=not_loaded` 仍展示过期 fallback 原因。
- **测试：** `test/local_ai_service_test.dart` 覆盖状态字段读取；`test/local_ai_backend_settings_tile_test.dart` 覆盖设置页展示。该变更只提升失败可观测性，不改变 fallback 策略。
- **精确 HEAD CI：** Branch validation job `140844538153`、Flutter regression job `140844538488`、Android arm64/JVM job `140846198464`、PR required gate job `140847230585`、Fork License run `46101434294` 均 SUCCESS。
- **设备限制：** 以上测试不能证明 Find N2 的 GPU 初始化失败、CPU 实际 fallback、后端切换或长时间推理稳定性。

### 13.4 PR #622：SessionState SQLite 有界读取（Dart/SQLite，不是 Native transcript）

- **合并证据：** PR #622 最终 HEAD `1bd334ba64d46488a7008a49647bf83860f652cb`，squash merge / 代码 master `805f006ed502c5cbf10dba4ad30428ee9761eb42`。
- **读取路径：** `AssistantConversationStore.getAssistantMessagesForSessionState` / `DatabaseHelper.getAssistantMessagesForSessionState` 只查询当前 conversation 的 user/assistant 行，SQL 硬限制最多 129 行；隐藏 tool/system 行排除，assistant 正文不投影，结果按消息 ID 正序返回。原 `getAssistantMessages` 全历史接口不变。
- **投影限制：** Builder 最多处理最近 128 条；129 条读取用于识别是否存在更早前缀，存在则返回 PARTIAL。SQL 将 user 正文投影限制到 1,201 Unicode code points、metadata 限制到 16,001 code points；Dart 在 replayability JSON 解码前按 16,000 UTF-16 上限拒绝超限 metadata。证据引用最多 64 条，超限显式标记 PARTIAL。
- **测试：** `test/session_state_snapshot_builder_test.dart` 覆盖 owner、tool ledger 排除、历史省略 PARTIAL、64 条 evidence 上限、metadata 超限与非 replayable 请求；`test/assistant_conversation_storage_test.dart`、`test/local_ai_interview_screen_test.dart` 等覆盖存储与调用端合同。
- **精确 HEAD CI：** Branch validation job `140903069854`、Flutter regression job `140903070020`、Android arm64/JVM job `140905099227`、PR required gate job `140905913256`、Fork License job `140903069713` 均 SUCCESS，全部绑定 PR 最终 HEAD。
- **职责边界：** 此改动只限制 SessionState 快照读取/投影，不截断完整 UI 历史，不改变 Native KV cache 生命周期，不把隐藏 reasoning/tool ledger 提升为用户记忆。

### 13.5 PR #623 合并后的主线 Push CI

- PR #623 最终 HEAD `aa5d33362cd2fc3eba9fde9ea2e2add627429b87` 的 Branch validation job `140907641647`、Flutter regression job `140907641905`、Android arm64/JVM job `140909537273`、PR required gate job `140910317781`、Fork License job `140907596176` 均 SUCCESS。
- 合并后 `master@57f6fbef193d28fc6c3493c8740d672038fdd52c` 的 Flutter regression job `140910480679`、Android arm64/JVM job `140912271947`、Fork License job `140910480437` 均 SUCCESS。Push 事件的 Branch validation job `140910481473` 与 PR required gate job `140913307538` 为 SKIPPED；它们不属于 Push 事件门禁，也不计 PASS。
- 以上是仓库/自动化证据，不是 Find N2 TRACE。

### 13.6 当前结论与剩余事项

- **云端确定性治理：** transcript 成功轮次边界、跨 MethodChannel 用户自述载荷限界、SessionState owner/provenance 与 SQLite 有界读取、临时 RAG/媒体上下文隔离、Reasoning Ledger 终态和 UNKNOWN 不重放、Activity teardown 串行释放均已有主线源码与自动化锚点。本次交叉复核没有发现新的、可仅凭仓库源码/CI 稳定复现的 Native 多轮缺陷；不为形式收尾新增运行时代码分支。
- **Token 边界：** 12 轮/10,000 transcript、60 条/16,000 user-reported projection、128 条 SessionState 快照、16,000 SessionState context 和 24,000 reasoning supplement 都是轮数/字符/code-unit 限制，不是模型可用 Token 预算，不能相加推导。Native token count 与模型声明 maxContextTokens 仅只读观测；`conversationKvCacheBudgetStatus=NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED` 继续不变。未取得设备校准前，不实现猜测性的安全阈值、输出预留、动态裁剪或自动压缩。
- **Find N2：** GPU/CPU 各至少 20 轮、真实 E4B 推理、state:7 根因、图片/语音多轮、Activity/process restart、SQLite/Flutter/Native 三方 transcript 一致性、真实 KV Cache/context 数值及 AI 数据清理后不可恢复性继续 MISSING / UNKNOWN / LOCAL ONLY；只在唯一 `docs/local-real-device-acceptance-handoff.md` §7.1 记录真实证据。
- **下一步：** 云端本轮主线 CI 与文档映射已完成；若没有新的代码/测试可稳定复现的问题，不新增 Core-1 运行时代码或重复 Core-0～Core-5 抽象。云端收尾完成后统一交付 Find N2 本地 TRACE，设备未测不阻塞云端、也不得改写为 PASS。
