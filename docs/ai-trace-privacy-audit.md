# F：端到端 TRACE 与隐私审计

审计基线：`master`，2026-11-10。只读审计；本分支不引入埋点、不改变模型调用和持久化行为。

## 1. 现状结论

<badge>FAIL — 未实现端到端 TRACE</badge>

在以下关键文件中检索 `traceId`、`trace_id`、`requestId`、`correlationId`、`spanId`，未发现贯穿一次请求的关联 ID：

- `lib/services/local_ai_service.dart`
- `lib/services/assistant_conversation_orchestrator.dart`
- `lib/screens/local_ai_interview_screen.dart`
- `lib/models/assistant_tool_result.dart`
- `lib/data/assistant_conversation_store.dart`
- `lib/data/database_helper.dart`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt`

当前仅有局部关联信息：
- `AssistantToolResult.sourceIds`：工具结果的来源引用，不是请求执行 trace ID。
- `assistant_conversations.id` / `assistant_messages.id`：会话/消息主键，不是跨阶段请求 ID。
- Native `aiExecutor` 串行化任务，但没有 request ID、执行状态和阶段关联。
- MethodChannel 请求没有传递 trace ID。
- 数据库 `assistant_messages.metadata` 是 JSON 扩展字段，没有统一 trace schema。

因此目前无法可靠地从某条用户输入追踪到路由、检索、模型调用、工具执行、结果回写、UI 展示和数据库持久化。

## 2. 当前日志与隐私

本次检查的 AI 关键路径中没有发现 `Log.d/i/w/e`、`print()` 或模型服务层的正文日志。Flutter UI 有少量 `debugPrint`，目前打印的是数据库写入/状态读取异常和 stack trace，没有直接拼接用户症状正文、图片/音频内容或生辰数据。

这只能证明所审计文件中没有发现直接正文日志；不能证明全仓库/第三方依赖/系统日志完全无敏感信息。发布前仍需全仓库日志扫描和 Android logcat 实测。

## 3. 缺失的链路节点

| 节点 | 当前证据 | 状态 |
|---|---|---|
| 用户输入创建 trace | 没有 trace ID | MISSING |
| 红旗 preflight | 尚未接入全入口 | MISSING |
| Orchestrator 决策 | 有 dispatch decision，无 trace ID | PARTIAL |
| 检索 query / hit IDs | 有 source IDs 和上下文构建，但无统一 trace | PARTIAL |
| Native MethodChannel | 无 requestId/traceId | MISSING |
| LiteRT Engine/Conversation | 无执行请求 ID、开始/完成状态 | MISSING |
| Headless/Page Tool 执行 | 只有部分结果对象；无统一执行状态链 | PARTIAL |
| 结果回流/展示 | UI 有消息对象和工具结果，无 trace ID | MISSING |
| SQLite 持久化 | conversation/message 主键和 metadata，无 trace schema | MISSING |
| 失败/超时/取消 | 异常有错误信息，但不能区分未启动、已执行、未知 | PARTIAL |

## 4. 建议的最小 TRACE 契约（尚未实现）

### Trace identity

- 每个用户输入/工具请求生成独立 `trace_id`；不复用 conversationId/messageId。
- 一个请求内的所有阶段复用该 ID；子阶段可选 `span_id` 和 `parent_span_id`。
- trace ID 使用随机 UUID/等价无语义标识，不编码用户身份、症状或时间。

### 事件字段（仅元数据）

- `trace_id`、`span_id`、`parent_span_id`
- `conversation_id`、`message_id`（仅本地关联）
- `stage`、`started_at`、`finished_at`、`duration_ms`
- `status`: NOT_STARTED / SUCCEEDED / FAILED / UNKNOWN
- `route`、`mode`、`tool_id`、`backend`、`model_version`
- `source_ids`、`result_kind`、`error_code`
- `trace_schema_version`

禁止写入：
- 原始用户文本、症状正文、问诊答案、模型完整 prompt/response；
- 图片、音频、OCR/ASR 原文、缩略图；
- 生辰、出生地、身份信息、联系方式；
- 任何能够直接复原上述敏感内容的摘要。

### 隐私与失败语义

- TRACE 默认关闭，必须由用户显式打开本地审计开关。
- 关闭时不得写 TRACE 文件/数据库，不得增加模型调用，不得改变路由、检索、工具调用顺序和业务结果。
- 开启时只写脱敏元数据；本地存储、有限保留期、可一键清除；不上传云端，不进入普通日志。
- TRACE 写入失败不得阻断模型/工具业务。
- 请求未派发为 NOT_STARTED；明确执行完成为 SUCCEEDED；确定性异常为 FAILED；超时、进程中断、取消但 Native 仍可能运行、响应丢失为 UNKNOWN。
- UNKNOWN 不得被 UI/日志改写为 FAILED 或 SUCCEEDED，也不得触发自动重放。

## 5. 建议实施顺序

1. 先定义 `AiTraceContext` 和 `AiTraceEvent` typed schema；不先引入复杂 tracing SDK。
2. Dart 用户输入创建 trace ID，显式传给 Orchestrator、检索和 MethodChannel。
3. Native 每次任务入口记录 NOT_STARTED，执行返回后写 SUCCEEDED/FAILED；Dart Future 超时但 Native 仍运行时写 UNKNOWN。
4. Tool/Page 执行结果带同一 trace ID，保留 sourceIds 与 arguments。
5. SQLite metadata 可选保存 trace_id；TRACE 关闭时字段为空且不产生额外写入。
6. 增加默认关闭、显式开启、关闭时结果一致、脱敏、写入失败不阻断、UNKNOWN 状态测试。
7. Android logcat/Find N2 实测，确认日志没有敏感正文，且 trace 关闭时性能/行为不变。

## 6. 当前状态

- 端到端 trace_id：MISSING。
- 默认关闭的审计开关：MISSING。
- 执行状态 NOT_STARTED/SUCCEEDED/FAILED/UNKNOWN：MISSING。
- AI 关键路径直接打印正文：本次所审计文件未发现；全仓库/真机日志仍 UNKNOWN。
- 不应将 `sourceIds`、conversationId 或 messageId 误标为端到端 TRACE。
