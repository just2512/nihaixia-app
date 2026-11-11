# F 工作流：本地 TRACE 有界写入器

基线：master `05f118e1d0b090cee7dbeaa37669c410dae0e876`  
分支：`work/ai-trace-writer-current-master`

## 本切片

- 新增 `LocalAiTraceFileWriter`，仅写入 `AiTraceEvent.toJson()` 的 allowlist 字段。
- 默认不接入生产调用路径；调用方必须显式启用 `AiTraceRecorder(enabled: true, writer: ...)`。
- 使用 App 私有 Application Support 目录，文件名固定为 `ai_trace.jsonl`。
- 保留最近 7 天且最多 500 条事件；并发写入串行化。
- 写入临时文件后替换目标文件；损坏行/过期行丢弃。
- `clear()` 仅删除本 writer 的 trace 文件和临时文件。

## 当前能力边界

- master 已有默认关闭的 `AiTraceRecorder`（`lib/services/ai_trace.dart`），但没有 writer 和生产调用点。
- 本 PR 只提供有界本地 writer 与单测，不添加 UI 开关，不注入生产 trace_id，不宣称已具备完整 TRACE。
- 真实设备验收步骤见 `docs/find-n2-ai-trace-acceptance-plan.md`。该方案要求先完成生产链路接线与显式本地审计开关，再执行设备测试。

## 隐私与故障隔离

- 不保存 prompt、response、症状正文、附件内容/路径、出生信息或身份信息。
- writer 的文件写入失败由 recorder best-effort 隔离，不得阻断 AI 业务。
- 文件系统与 SQLite 不构成单一事务；trace 缺失必须可识别，不能伪造完整链路。

## 测试

`test/ai_trace_store_test.dart` 覆盖 allowlist、7 天 TTL、最大条数、并发写入顺序和只清理自身文件。CI 通过只证明 writer 切片，不替代生产接入和 Find N2 TRACE。
