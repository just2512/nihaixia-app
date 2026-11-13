# 本地 AI 多轮稳定性与 Native 生命周期审计

- 审计基线：`master` @ `4dfff41049063925daa559830341053bd33c6528`
- 修复分支：`work/ai-transcript-restore-boundary-2026-11-11`
- 审计日期：2026-11-11
- 范围：Flutter MethodChannel、Native Engine/Conversation、成功轮次历史、GPU→CPU 恢复、历史恢复、SQLite 持久化和资源释放。
- 总结：A = PARTIAL。当前代码已有多轮失败后的保守恢复和显式 UNKNOWN 语义；本分支补上历史恢复截断与症状来源截断标记。真机 GPU/CPU 轮次 TRACE 和跨层持久化一致性仍未闭合。

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

- `conversationHistoryTurns` 当前是无显式轮数/字符预算的可变列表；Native CPU 恢复会重放其全部成功轮次。当前没有基于模型 token/context window 的实测预算。不得自行添加未经模型实测的 token 上限；需在 A 后续切片用设备数据确定。
- `runAiTask()` 和主要推理恢复分支捕获 `Exception`，不是所有 JVM `Throwable`。不能据此声称 JNI/Error 类故障全部会被恢复。是否扩大捕获范围需按 LiteRT-LM 实际异常类型审计，不能吞掉 OOM 等致命错误。
- `onDestroy()` 把资源释放任务排入单线程 executor 后调用 `shutdown()`，但没有等待释放完成，也没有把 teardown 结果写入 TRACE。代码顺序保证已提交任务不会因正常 shutdown 被取消，不等于已证明所有 Activity/进程终止竞态。
- 当前 Native 方法没有独立 request ID/idempotency key；串行 executor 与 Flutter `_sending` 控制降低并发重入，但不等于跨进程重试幂等。

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
