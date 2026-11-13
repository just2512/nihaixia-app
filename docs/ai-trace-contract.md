# Local AI TRACE 端到端契约

- 状态：F 部分落地；普通文本/图片/语音常规助手轮次已有 per-turn trace_id、Native bridge correlation 和 SQLite metadata；Debug-only 本地显式开关已纳入实现分支；结构化问诊/澄清/工具等其余分支、完整阶段覆盖及 Find N2 真实 TRACE 仍未闭环
- 最近复核主线：`master @ 14784fa2b93a3746419ea02de8290bf69876ed4b`；PR #127 新增 Debug-only 开关，待当前 PR CI 完成后集成
- 约束：TRACE 默认关闭；Release/Profile 不提供启用入口；只记录 allowlisted metadata；写入失败不得影响 AI 业务；不创建新的 conversation table。

## 1. 核心不变量

1. 一个用户轮次最多一个 `trace_id`；该轮所有 Dart、Native、检索、工具、展示、SQLite 事件复用同一 ID。
2. 只有 `AiTraceRecorder.isEnabled == true` 时才生成 ID。关闭时不生成、不传递、不写入，SQLite metadata 不包含 trace_id。
3. ID 格式为 16 bytes secure-random 的 32 位小写十六进制字符串：`^[0-9a-f]{32}$`。
4. Native 必须原样回传收到的 trace_id；Dart 收到缺失或不匹配 ID 时将 Native 结果标记为 UNKNOWN/TRACE_ID_MISMATCH，不得静默归入其他轮次。
5. TRACE writer/Native instrumentation 失败是可观测性失败，不改变模型调用、工具执行或用户可见结果；状态应记录为 UNKNOWN（若写入仍可用）。
6. 同一轮 user/assistant 消息的 SQLite metadata 必须携带相同 trace_id；写入仍复用 `saveAssistantTurn` 的单事务，不增加 conversation/message 表。
7. 禁止记录用户原文、模型 prompt/response、症状文本、舌象/OCR、语音/ASR、附件路径、图片字节、出生信息、姓名、手机号或其他身份信息。

## 2. ID 生命周期与传播

### 2.1 生成

- 轮次入口：`LocalAiInterviewScreen._send()` 在完成空输入/忙碌状态等纯 UI 校验后、进入 TCM 结构化答案分支或 `AssistantConversationOrchestrator.resolve` 前，调用 `AiTraceRuntime.recorder.start(stage: AiTraceStage.input, route: ..., mode: ...)`。
- 当 recorder 关闭时返回 `AiTraceContext.disabled()`，不生成 ID。
- 不能在每个 Native 方法中重新生成 ID；不能按 messageId/conversationId 重新推导 trace_id。

### 2.2 Flutter 内部

`AiTraceContext` 必须显式传递到以下分支，不使用全局“当前 trace”可变变量，以免并发轮次串线：

- 活动结构化问诊答案与规则引擎执行；
- `AssistantConversationOrchestrator.resolve` 与 `_requestTool` 工具分发；
- `_sendTextWithKnowledgeContext` 的普通文本和知识检索；
- `LocalAiService.sendImage`、`sendAudio`；
- `LocalAiService.extractSymptoms`；
- `_persistSuccessfulTurn` 与 `DatabaseHelper.saveAssistantTurn`；
- 最终 UI 结果展示/错误展示。

同一轮中若工具执行或规则问诊不调用 Native，仍需记录对应阶段，并在 SQLite 的 user/assistant metadata 中保存相同 ID。

### 2.3 MethodChannel 契约

对以下 Native 调用增加可选参数 `trace_id`：

| Dart API | MethodChannel method | 必须携带 |
|---|---|---|
| `sendMessage` | `sendMessage` | trace_id、现有 text/context |
| `sendImage` | `sendImage` | trace_id、现有 path/prompt |
| `sendAudio` | `sendAudio` | trace_id、现有 path/prompt |
| `extractSymptoms` | `extractSymptoms` | trace_id |

- trace_id 是 metadata，不得拼接到 prompt/context。
- Native 对 ID 做格式校验；无效 ID 返回明确错误，不得替换生成新 ID。
- 上述调用的结果 map 增加 `trace_id`（TRACE 关闭时可省略）。
- Dart 验证返回 ID 与请求 ID 一致；不一致时保留业务结果状态 UNKNOWN，不伪造成功的跨层关联。
- `restoreConversation` 是历史上下文恢复，不是新的用户轮次；恢复历史时保留每条消息原 metadata，不生成新的 trace_id。

## 3. SQLite 持久化

当前 `assistant_messages` 已有 `metadata TEXT` 字段，优先复用，不新增表或列：

- user message metadata：`{"trace_id":"..."}`（可与已有安全 metadata 合并）。
- assistant message metadata：同一个 `trace_id`，并保留已有 mode/sourceIds/knowledgeStatus 等非敏感字段。
- TRACE 关闭时 metadata 不增加 trace_id。
- `saveAssistantTurn` 仍在一个 SQLite transaction 内写入 user/assistant pair；故障注入必须证明任一方失败时整轮回滚。
- 历史查询不得把 trace_id 展示成对话正文或用户可见内容。

## 4. 事件阶段与状态

复用现有 `AiTraceStage`，不另造重复枚举：

`INPUT → PREFLIGHT → RED_FLAG → DISPATCH → ROUTE → ENTITY_RESOLUTION → RETRIEVAL → CONTEXT_ASSEMBLY → MODEL_INPUT → NATIVE_INFERENCE → MODEL_OUTPUT → TOOL_EXECUTION → ARGUMENT_VALIDATION → BUSINESS_EXECUTION → RESULT_VALIDATION → PERSISTENCE → PERSISTED_STATE → PRESENTATION → FINAL_RENDER`

不适用的阶段写 `NOT_APPLICABLE`；尚未开始写 `NOT_STARTED`；明确完成写 `SUCCEEDED`；明确失败写 `FAILED`；超时、进程中断、Native Future 未完成或跨层 ID 不匹配写 `UNKNOWN`。不得把 UNKNOWN 映射为 FAILED 或 SUCCEEDED。

事件字段沿用 `AiTraceEvent`：schema_version、trace_id、stage、status、occurred_at、duration_ms、conversation_id、message_id、route、mode、tool_id、backend、model_version、source_ids、error_code。error_code 必须是稳定枚举/allowlist，不能写入异常原文。

## 5. 隐私与存储

- 复用 `AiTraceEvent.toJson()` 的字段 allowlist；禁止扩展为任意 map 或附带原始请求对象。
- 不记录用户输入、模型输出、系统 prompt、知识正文、症状摘要、附件路径、ASR/OCR 内容。
- source_ids 仅记录稳定来源 ID，不记录来源正文。
- 现有 writer 上限：500 events、7 days；如需变更必须独立说明存储成本和隐私影响。
- writer 默认关闭；用户显式启用后才开始生成 trace_id。
- 清理时沿用 `LocalAiDataClearCoordinator`：disableAndFlush → clear writer file → 恢复原先启用状态；清理失败必须显示失败域。

## 6. 自动验收矩阵

| 层 | 必须覆盖的断言 |
|---|---|
| Recorder | disabled 不生成 ID、不写入；enabled 每轮只生成一个 ID；ID 格式正确；writer 失败不传播 |
| Flutter 路由 | 自动/问诊/学习/工具、结构化问诊、澄清分支和附件分支使用同一个 turn context，不跨轮串线 |
| Retrieval/tool | 有结果、无结果、失败、部分命中和 NOT_APPLICABLE 都有明确状态；source_ids/tool_id 对应真实执行 |
| MethodChannel | sendMessage/sendImage/sendAudio/extractSymptoms 收到同一 trace_id；Native 原样回传；缺失/错配标记 UNKNOWN |
| Native | GPU/CPU、模型加载失败、推理超时、进程 teardown 的终态不伪造 |
| SQLite | user/assistant metadata 使用同一 trace_id；TRACE disabled 时无 trace_id；事务失败整轮回滚 |
| Privacy | JSONL 与 SQLite metadata 中不存在原文、prompt、response、症状、附件路径、ASR/OCR、身份数据 |
| Clear | stop/flush/clear/resume 顺序正确；并发清理互斥；失败域可见；默认关闭状态不被意外开启 |

## 7. 实施顺序

1. 先实现 Flutter turn context 与事件阶段，不改变模型请求内容。
2. 扩展 LocalAiService 的可选 trace_id 参数和 MethodChannel payload。
3. 扩展 Kotlin handler/result map 的 trace_id 校验与原样回传；不记录原始 prompt。
4. 将 trace_id 合并进现有 assistant_messages.metadata，并保持 saveAssistantTurn 单事务。
5. 增加 Flutter、Native、SQLite 故障注入与隐私扫描测试。
6. CI 通过后再用 Find N2 真机验证 GPU/CPU、图片/语音、多轮、清理/重启；没有真实 TRACE 不得标记 IMPLEMENTED。



## 8. 2026-11-12 F1 Native bridge correlation implementation

- PR #84 已合并到 master `b786f84df0452b9771e341c818e0d06a12451ef3`。
- 保留旧方法签名并增加显式 traced API：`sendMessageWithTrace`、`sendMessageWithContextAndTrace`、`sendImageWithTrace`、`sendAudioWithTrace`、`extractSymptomsWithTrace`。
- MethodChannel 字段统一为 `trace_id`；只接受 32 位小写十六进制标识。Native 在推理成功响应中原样回显；Dart 不匹配时抛出 `TRACE_ID_MISMATCH`。
- 未提供 ID 时不添加 payload 字段；服务层不自行生成 ID。TRACE recorder 默认关闭时，旧调用行为不变。
- 不将 prompt、模型输出、症状正文、附件路径或身份信息写入 ID 或 Native 日志。

### F1 证据边界

该实现证明了显式 ID 能跨越 Dart → MethodChannel → Native inference response；尚无统一聊天 UI 的生产调用者。因此它不是 per-turn trace，也没有证明 SQLite 持久化和后续阶段关联。

### F2 下一切片

1. 在统一聊天 UI 每轮开始时从默认关闭的 recorder 获取可选 trace context。
2. 将同一 ID 传入上述 traced API，并为 retrieval/model/persistence/presentation 记录状态。
3. 通过既有 assistant message metadata 的 `trace_id` 关联 user/assistant message，不新建会话表。
4. 证明 TRACE 关闭时 metadata 不增加 ID，TRACE 开启时不记录敏感正文；清理入口必须一并清除 trace 文件与消息 metadata。


## 9. 2026-11-12 F2 per-turn UI correlation（PR #87 验收中）

- `LocalAiInterviewScreen` 在正常模型轮次创建可选 `AiTraceContext`；ID 只由默认关闭的 `AiTraceRecorder` 生成，TRACE 关闭时不生成。
- 普通文本按有无 context 选择既有 traced API；图片、语音调用对应 traced API。Native 响应仍由 `LocalAiService` 校验相同 ID。
- 同一 ID 写入现有 `assistant_messages.metadata` 的 user/assistant 两条消息；不新增表/列，历史 metadata 解码保持向后兼容。
- 已记录 input、native_inference、model_output、persistence、final_render 阶段；持久化事件只有在 `saveAssistantTurn` 成功后才记为 SUCCEEDED。
- 持久化失败记为 FAILED；Native 响应 ID 缺失/错配或推理调用异常记为 UNKNOWN，使用稳定错误码，不记录异常正文。
- 新增可注入 recorder 的测试 seam，验证一个 ID 贯穿 traced Native API 与 user/assistant metadata，且事件阶段完整。
- 独立症状提取入口也已按 recorder 开关调用 traced API，并记录 Native 成功/UNKNOWN；该草稿尚未持久化到消息 metadata。
- 本切片仍未覆盖结构化问诊分支、澄清/工具执行分支、检索阶段细分、Native 失败轮次的持久化关联及真实 Find N2 TRACE；整体 F 仍为 PARTIAL。

---

## 10. 2026-11-13 Debug-only 开关与当前实现边界

### 10.1 已有基础设施与普通轮次接线

- `AiTraceRecorder` 默认 `enabled=false`；没有可用 writer 时也不能启用。TRACE 关闭时不生成 ID、不写事件、不向 Native 传 ID、不向消息 metadata 写 `trace_id`。
- `LocalAiTraceFileWriter` 写入 App 私有 Application Support 目录中的 `ai_trace.jsonl`，最多 500 条、保留 7 天；只持久化 `AiTraceEvent.toJson()` allowlist 字段。
- `AiTraceRuntime` 是进程级 recorder/writer 单例。`LocalAiInterviewScreen` 普通文本、知识检索、图片、语音、结构化问诊启动/选项/舌脉输入、澄清路由、Headless/Page 工具和症状整理均已有不同程度的事件记录调用点；普通助手轮次已有可选 turn context、Native bridge correlation 和 user/assistant message metadata。当前代码对 retrieval/context assembly/model input/native inference/model output/argument validation/tool execution/business execution/result validation/persistence/persisted state/presentation/final render 等阶段有明确调用点，但不能据此推断所有路径的事件链已完整。
- 上述接线不代表所有路径和所有阶段都已覆盖。当前静态核对未发现生产代码记录 `AiTraceStage.preflight` 或 `AiTraceStage.redFlag` 的调用点；B 项自然语言 detector 与全入口 Gate 仍缺经医学审核的生产接入，因此这两个阶段保持 MISSING/UNKNOWN。失败/取消/未完成轮次及部分跨层终态仍需在设备上按场景核对；不得根据文件存在或某条正常路径的 JSONL 推断全链路完成。

### 10.2 显式开关的产品与生命周期约束

- Debug 设置页加入 `LocalAiTraceDebugTile`，仅在 `kDebugMode` 下显示；Release/Profile 构建不显示该入口。
- 打开开关时调用进程级 `AiTraceRuntime.recorder.enable()`；关闭时调用 `disableAndFlush()`，等待已排队写入完成后再报告关闭。
- 开关仅在当前进程内生效，不持久化用户偏好；App 进程重启后 recorder 重新按默认 `enabled=false` 创建。不得把开关状态同步到云端或长期偏好设置。
- UI 文案必须说明只记录脱敏流程元数据，明确 500 条/7 天保留边界，不记录聊天正文、prompt、模型回复、症状、附件内容或身份信息。

### 10.3 清除协调与隐私边界

- `LocalAiDataClearCoordinator.forApp()` 与生产采集共享同一 `AiTraceRuntime` 单例：`disableAndFlush → Native runtime release → clear AI-owned attachments / ai_trace.jsonl + .tmp / AI conversation rows → restore previous recorder state`。
- Native release 未确认时不删除仍可能被推理占用的附件；各数据域失败必须单独返回。应用内清除代码与自动化测试已落地，但它不证明混合数据库的系统备份/设备迁移副本、旧共享图片或外部导出副本被删除。
- 不允许通过清除操作删除整个 `nihaisha.db`、任意共享临时图片或已安装模型；Android backup policy 维持当前状态，除非产品另行决策。

### 10.4 尚未通过的验收

- `AiTraceStage` 规范阶段以本文件第 4 节为准。真机记录必须核对每个场景实际适用的阶段；真正不适用才记 `NOT_APPLICABLE`。应有事件却未接线/未写出时记缺失或 `UNKNOWN`，不得伪造补齐。
- Debug-only 开关和本地 JSONL writer 只解决“如何显式开启并本地留存”；它们不补齐所有路由节点、失败节点、Native 生命周期节点，也不证明某次模型请求一定由预期 backend 完成。
- Find N2 GPU 至少 20 轮、CPU 至少 20 轮，图片/语音、进程中断/恢复、模型/Activity 生命周期，以及 AI 数据清除后强停/重启的真实验收仍未执行；未提供设备 TRACE 的项目保持 `UNKNOWN`。红旗相关场景还必须先解决 B 的医学审核与生产 fail-closed Gate，不能用关闭 TRACE 或跳过红旗阶段换取验收通过。
- 因此 F 整体保持 `PARTIAL / DEVICE UNKNOWN`，不能标 `IMPLEMENTED` 或 RELEASE READY。CI、静态审计和 Widget 测试不能替代真实设备 TRACE。

