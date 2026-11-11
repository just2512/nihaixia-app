# Find N2 AI 多轮 / 附件 / 恢复 / 清除真机验收方案

> 本文是执行方案，不是 PASS 报告。测试必须在用户本地 Find N2 上执行；CI、模拟器和静态代码均不能替代真实设备 TRACE。

## 0. 当前前置条件（必须先满足）

以 master `05f118e1d0b090cee7dbeaa37669c410dae0e876` 为基线：

- `AiTraceRecorder` 已有默认关闭的元数据记录器（`lib/services/ai_trace.dart`），但当前 master 尚无 `LocalAiTraceFileWriter`，也没有生产调用链的 trace_id 注入和显式 Debug 开关。
- 本分支只补本地有界 writer，不代表 writer 已接入生产链路。
- E 数据清除 PR #39 尚未安全集成；清除测试须等当前 master 上的 E 清除实现通过 CI 后执行。
- 因此，在 TRACE recorder + writer + 生产节点接线 + 显式本地审计开关均完成前，不得声称设备已能产生完整 TRACE，也不得用 adb 普通日志代替完整 TRACE。

## 1. 设备 / 构建信息

每次测试记录：

| 字段 | 实测值 |
|---|---|
| 设备型号 | OPPO Find N2，记录 `getprop ro.product.model` |
| Android / SDK / ColorOS | 设备实测 |
| App version / commit | 安装 APK 对应值 |
| APK SHA-256 | 本地计算值 |
| 模型文件版本 / SHA-256 | 本地核验值，不上传模型文件 |
| 实际 backend | 每次会话记录 Native 返回的 GPU 或 CPU；禁止按设置推断 |
| 屏幕姿态 | 外屏 / 内屏展开 / 半折叠（仅在影响场景时记录） |
| TRACE 开关 | 显式启用；默认必须关闭 |
| 测试数据 | 合成数据，不使用真实健康信息 |

## 2. TRACE 事件完整性

每个场景使用独立 `trace_id`；同一会话跨轮沿用同一会话关联关系，但每轮请求必须可区分。事件只保存 allowlist 元数据，不保存 prompt、response、症状正文、图片/音频内容、文件路径或身份信息。

至少检查以下阶段：

`INPUT → RED_FLAG → ROUTE → ENTITY_RESOLUTION → RETRIEVAL → CONTEXT_ASSEMBLY → MODEL_INPUT → MODEL_OUTPUT → TOOL_EXECUTION → ARGUMENT_VALIDATION → BUSINESS_EXECUTION → RESULT_VALIDATION → FINAL_RENDER → PERSISTED_STATE`

若场景包含工具，再增加 `TOOL_EXECUTION`。不适用节点写 `NOT_APPLICABLE`，不能静默缺失。

每个事件必须能关联：
- trace_id、stage、status、时间戳、duration_ms；
- conversation_id / message_id（可取得时）；
- route / mode / tool_id（适用时）；
- 实际 backend、model_version；
- source_ids（适用时）；
- error_code（失败时）。

关键节点缺失、trace_id 中途变化、backend 未记录或最终展示/持久化无法关联，场景不得 PASS。

## 3. GPU 多轮稳定性（G-01）

1. 新建空白会话，确认实际 backend 为 GPU。
2. 连续完成至少 20 轮文字交互；使用固定、无个人信息的测试脚本，覆盖简单问答、上下文追问、实体回指、一次检索命中、一次检索无命中、一次明确要求澄清。
3. 每轮记录发送、Native 返回、最终展示、消息持久化状态；不得把空字符串或旧回复计为成功。
4. 发生异常时保留原始 error code；记录是否触发 CPU fallback、Engine/Conversation 是否重建、transcript 是否回放。
5. 若发生 fallback，本轮标记实际 backend 变化，并检查历史回放前后的 Flutter transcript 与 Native context 一致。

通过条件：
- 至少 20 轮均有可关联 trace_id；无 state:7 未恢复、无空回复假成功、无重复消息、无历史串线。
- fallback 后明确记录 GPU 失败与 CPU 成功/失败，不把 CPU 回复标成 GPU。
- 失败轮状态为 FAILED/UNKNOWN，不盲目自动重放未知副作用请求。

## 4. CPU 多轮稳定性（C-01）

1. 新建独立会话，确认实际 backend 为 CPU（必须由 Native 实际状态证明）。
2. 连续完成至少 20 轮，输入脚本与 GPU 组保持一致。
3. 检查每轮耗时、输出是否为空、历史是否逐轮累积、会话切换是否隔离。

通过条件：
- 至少 20 轮均可关联；无状态污染、空回复假成功、跨会话串线。
- 记录 GPU 与 CPU 的实际 backend，不允许只记录“请求使用 CPU”。

## 5. 附件输入（ATT-01）

分别验证图片与语音，使用专门准备的非敏感测试文件：

- 图片：选择相册图片 → 附件落入 AI 专用目录 → Native 接收 → 模型输出 → Flutter 展示 → 消息持久化。
- 语音：录音 → 文件落入 AI 专用目录 → Native 转写/问诊处理 → 回复展示 → transcript 持久化。
- 每类附件至少执行一次正常路径和一次取消/无权限路径；检查取消不生成伪成功消息。
- 检查附件引用只在对应会话可见；退出/切换会话后不串用旧附件。

通过条件：
- TRACE 能关联附件输入事件与最终消息，但不记录真实路径或附件内容。
- 附件不存在、解码失败、权限取消均有明确失败状态；不留下孤儿文件或伪造成功记录。
- 用户正文/图片/音频内容不进入 TRACE JSONL、logcat 或 CI 日志。

## 6. 进程中断与恢复（REC-01）

1. 在同一会话完成至少 5 轮，其中包含一次上下文检索和一次附件输入。
2. 记录中断前最后一条成功 user/assistant 消息 ID、conversation_id 与 trace_id。
3. 使用 `adb shell am force-stop com.nihaisha.nihaisha_app` 终止进程；重新启动 App 并恢复原会话。
4. 比较 SQLite transcript、Flutter UI messages、Native 重建后的 model context；发送一条依赖第 1 轮实体的追问。
5. 再执行一次系统回收/进程重启路径（若无法稳定触发，明确标 BLOCKED，不伪造结果）。

通过条件：
- 恢复后的消息顺序、角色、内容摘要和 ID 一致；Native context 不缺失、不重复、不跨会话。
- 新一轮能正确回指早期实体；若历史无法安全恢复，必须明确停止并要求用户显式重试。
- 中断时未完成的 user-only 轮次不得伪装为已成功 assistant 回复。

## 7. 清除全部 AI 数据后重启（CLR-01）

前置：当前 master 已集成经 CI 验证的 E 清除实现；本地安装包 SHA 与清除实现 commit 对应。

1. 准备至少两个 AI 会话，包含文字消息、问诊任务状态、图片附件、音频附件及缓存。
2. 同时准备非 AI 数据哨兵：收藏、诊断历史、命盘、主题设置；清除前核对均存在。
3. 在 App 设置/助手入口执行“清除全部 AI 数据”并确认。
4. 记录清除结果中的数据库行数、附件数、旧录音数、Native runtime cache 删除数及失败状态。
5. 先强制停止并重启 App；确认 AI 会话、消息、问诊快照、附件与缓存不可见/不存在，模型安装文件按当前产品约定保留。
6. 再执行设备重启后复核一次；若设备重启不在本轮范围，明确标记 NOT_RUN。
7. 检查非 AI 数据哨兵仍存在；检查没有把数据库部分失败误报成整体成功。

通过条件：
- AI 数据在 App 重启后不可恢复；若执行设备重启，设备重启后仍不可恢复。
- 非 AI 数据保持不变；已安装模型文件按当前清除契约保留。
- 任一数据库/附件/Native cache 删除失败均返回可见失败，不得显示清除成功。
- 不允许用只清 UI 列表、只删 SQLite、或只删缓存替代全范围验收。

## 8. 证据包与判定

每个场景单独保存：

```text
output/find-n2-ai/<run-id>/
  device-metadata.json
  app-build.json
  model-metadata.json
  trace/ai_trace.jsonl
  logcat-redacted.txt
  scenario-results.md
  screenshots/
```

提交前脱敏；不得包含模型文件、密钥、数据库原件、真实问诊正文、出生信息、图片或音频。

`scenario-results.md` 每行至少包含：
- scenario_id、trace_id、backend、轮次；
- expected / observed；
- PASS / FAIL / BLOCKED / UNKNOWN；
- failure_class（理解/检索/上下文/执行/模型上限/安全/UNKNOWN）；
- 缺失节点、error_code、耗时；
- 对应 TRACE 行范围和截图编号。

最终统计必须按实际执行场景计算：PASS、FAIL、BLOCKED、UNKNOWN 分开列；未执行项不得计入分母或写成 PASS。
