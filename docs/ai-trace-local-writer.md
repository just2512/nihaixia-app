# F 工作流：本地 TRACE 有界写入器

基线：master `c7a12ed32140fb2e8e97ea406e5fdc6504216907`  
分支：`work/ai-trace-local-writer`

## 本切片

- 新增 `LocalAiTraceFileWriter`，仅写入 `AiTraceEvent.toJson()` 的 allowlist 字段。
- 默认不接入生产调用路径；只有调用方显式启用 `AiTraceRecorder(enabled: true, writer: ...)` 才会写入。
- 使用 App 私有 Application Support 目录，文件名固定为 `ai_trace.jsonl`。
- 保留最近 7 天且最多 500 条事件；每次写入按队列串行化。
- 写入临时文件后替换目标文件；损坏行/过期行丢弃。
- `clear()` 仅删除 trace 文件和自己的临时文件，不触碰其他数据。

## 风险边界

- 本切片没有 UI 设置开关，没有生产调用点，没有 Native trace_id 贯穿。
- 默认关闭仍由 `AiTraceRecorder` 保证；本 writer 的存在本身不会生成文件。
- 当前保留期限/条数是本地实现默认值，后续可在隐私审计中调整；不记录任何原始用户文本。
- 文件系统无法与 SQLite 形成单一事务；写入失败由 recorder 隔离，不阻断业务。

## 测试

`test/ai_trace_store_test.dart` 覆盖 allowlist、7 天 TTL、最大条数、并发写入顺序和只清理自身文件。全量 CI 与后续生产接入测试仍待通过。
