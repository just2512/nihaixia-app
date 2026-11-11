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
