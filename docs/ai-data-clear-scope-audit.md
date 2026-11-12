# AI 数据清除范围审计

- 审计基线：`master` @ `4dfff41049063925daa559830341053bd33c6528`
- 审计日期：2026-11-11
- 类型：静态代码与配置审计
- 结论：E = PARTIAL；尚不存在可证明完整的“清除全部 AI 数据”闭环。
- 本文只记录源码/配置事实；不把 CI、静态代码或 Find N2 既有 A-K 汇总当作清除后不可恢复证据。

## 1. 数据域清单

| 数据域 | 当前落点 / 证据 | 清除要求 | 当前状态 |
|---|---|---|---|
| 统一助手会话 | SQLite `assistant_conversations`，`DatabaseHelper._createDB()` | 删除全部会话行 | 有单会话删除；PR #51 新增全量数据库原语，待 Android CI |
| 统一助手消息 | SQLite `assistant_messages` | 删除全部消息行 | 同上 |
| 结构化问诊任务快照 | SQLite `tcm_interview_tasks` | 删除任务行及 JSON 快照 | 同上 |
| 旧版聊天历史 | SQLite `chat_history` | 作为旧对话数据一并删除 | PR #51 原语纳入事务 |
| 用户诊断历史 | SQLite `diagnosis_history` | 当前按非 AI 历史数据保留；除非产品明确扩大清除范围 | 保留，不得误删 |
| 收藏、收藏夹、医案收藏 | SQLite `bookmarks`、`bookmark_folders`、`medical_case_bookmarks` | 保留 | 不属于本次 AI 对话清除范围 |
| 用户设置、命盘 | SQLite `user_settings`、`user_charts` | 保留 | 不属于本次 AI 对话清除范围 |
| 图片附件 | Flutter `image_picker` 返回路径；`LocalAiInterviewScreen._deleteCachedAttachments()` 仅允许删除临时目录内指定路径 | 必须能枚举全部 AI 附件，不能清空整个共享临时目录 | 当前没有专用目录/持久化附件清单，完整清除 UNKNOWN |
| 语音附件 | `getTemporaryDirectory()/local_ai_<timestamp>.wav` | 删除 AI 专属录音文件及失败残留 | 有单次/已知路径清理；没有全量可枚举清理 |
| Native 推理缓存 | `cacheDir/litertlm`，`MainActivity.loadLocalModel()` 与恢复逻辑使用 | 先释放 Conversation/Engine，再删除该目录 | `releaseLocalModel()` 只释放对象和内存历史，没有删除目录 |
| Native 用户输入缓存 | `MainActivity.userReportedInputs`、`conversationHistoryTurns` | 清空内存状态 | `releaseLocalModel()` 已清空 |
| 模型文件 | `filesDir/ai_models/gemma-4-E4B-it.litertlm` | 按当前产品约定保留，不纳入 AI 数据清除 | 必须保留 |
| TRACE 文件 | Application Support 下 `ai_trace.jsonl` 与 `.tmp` | 清除 AI 数据时调用 writer 的 `clear()` | writer 已有自清理原语；尚未接入 E 编排 |
| 数据库备份 | 当前主 Manifest 未声明 `android:allowBackup`、`fullBackupContent` 或 `dataExtractionRules` | 必须明确 Android 备份/设备迁移行为 | 当前显式策略证据缺失 |

## 2. 关键代码事实

### SQLite

- 数据库文件为应用数据库 `nihaisha.db`，schema version 7。
- AI 会话由 `assistant_conversations`、`assistant_messages`、`tcm_interview_tasks` 三表组成。
- 外键关系是按会话 ID 关联；删除顺序必须先消息、再任务快照、最后会话。
- 旧 `chat_history` 仍在 schema 中，属于历史聊天内容，PR #51 将它纳入同一事务。
- `diagnosis_history`、收藏、设置和命盘与 AI 对话存储不同；不得为了清除 AI 对话而删除整个数据库文件。

### 附件与 Native 缓存

- 语音录音文件名带 `local_ai_` 前缀，但写在共享临时目录。
- 图片由 image_picker 返回临时文件路径；不能仅凭文件名推断为 AI 专属文件。
- 当前按“已知路径 + 临时目录边界”逐项删除，不存在全量附件索引。
- Native 只接受位于应用 `cacheDir` 下的附件路径；推理缓存目录是 `cacheDir/litertlm`。
- 模型文件位于 `filesDir/ai_models`，不得随清除动作删除。

### TRACE

- PR #50 已集成 `LocalAiTraceFileWriter`，默认不启用。
- writer 的 `clear()` 只删除 `ai_trace.jsonl` 与其临时替换文件，不触碰其他 Application Support 数据。
- 清除编排应在 Native runtime 释放和数据库/附件清除中明确报告 TRACE 文件清除状态；不能将 writer 文件缺失误报为整个清除闭环成功。

## 3. Android 备份边界

当前主 Manifest 未显式声明备份控制属性；本轮读取的常见 XML 路径 `res/xml/backup_rules.xml`、`res/xml/data_extraction_rules.xml` 不存在。

数据库中 AI 会话和非 AI 数据共用 `nihaisha.db`。Android XML 备份规则不能按 SQLite 表/行选择性排除，因此：

- 仅排除整个数据库文件会同时影响收藏、设置、诊断历史等非 AI 数据的备份/迁移。
- `android:allowBackup=false` 会扩大到整个应用私有数据，不应作为“只保护 AI 对话”的无影响改动。
- 在没有明确产品决策和 Android merged manifest/build 证据前，不得合并全应用禁用备份的改动，也不得声称已实现 AI-only backup exclusion。
- 本轮低成本方案优先依赖应用内明确的全量 AI 数据清除；备份策略的剩余风险必须单独列明。

## 4. 分阶段实施与硬门槛

1. **E-01 SQLite 原语**：单事务删除四张对话表；故障注入证明任何一步失败均回滚。PR #51 当前负责此切片。
2. **E-02 附件归属**：后续改为 AI 专属附件目录或建立可验证清单；不得递归清空共享临时目录。
3. **E-03 Native runtime**：在同一 Native executor 上先释放 Conversation/Engine、清空内存状态，再删除 `cacheDir/litertlm`；任何失败必须返回部分失败，不得假成功。
4. **E-04 TRACE**：调用 `LocalAiTraceFileWriter.clear()`，仅清理其拥有的文件。
5. **E-05 UI 编排**：提供二次确认；执行中禁止发消息、恢复历史或加载模型；结果按数据库/附件/Native cache/TRACE 分项显示。
6. **E-06 Android backup**：单独核验 merged manifest 与实际构建；不把全应用禁用备份包装成 AI-only 策略。
7. **E-07 真机验证**：准备合成数据，执行清除、强制停止、重启、再次检查；同时验证收藏/设置/诊断历史和模型文件保留。

**E 的 PASS 条件**：数据库、附件原件、转写、Native runtime cache、TRACE 全部清除；任一部分失败均可见；App 强制停止并重启后 AI 数据不可恢复；非 AI 数据与模型文件保持不变。未完成 Find N2 重启验证时，整体不得标记 PASS。

## 5. 当前缺口

- 没有统一清除服务协调 SQLite、附件、Native runtime 与 TRACE。
- 没有 UI 二次确认与分项结果。
- 共享临时目录内的图片文件缺少可靠全量枚举机制。
- Native 推理缓存尚无清除动作。
- Android 备份策略尚未核验 merged manifest。
- Find N2 清除后重启不可恢复的实测 TRACE 尚未提供。
- SQLCipher 不在本轮范围内；不得宣称数据库已加密。


---

## 6. 2026-11-12 增量复核（master `eefa56e9cf159c5533de1c35556f82aa4c873a4f`）

本节覆盖前文 2026-11-11 的旧状态；历史章节保留为当时的审计记录。

### 6.1 当前已落地的数据清除链

| 数据域 | 当前实现 | 当前结论 |
|---|---|---|
| AI 会话/消息/结构化问诊快照/旧 chat_history | `DatabaseHelper.clearAllAiConversationData()` 单事务删除四张表；`test/local_ai_data_clear_database_boundary_test.dart` 验证重开 DB 后 AI 表为空、收藏/诊断历史/搜索历史/设置保留，并注入失败验证回滚 | CODE + TEST PRESENT |
| AI 附件 | `LocalAiAttachmentStore` 将新附件复制/录音写入专属 `local_ai_attachments` 目录；clearAll 删除该目录直接子项，并按精确 `local_ai_[0-9]+.wav` 规则清理旧版录音 | CODE + TEST PRESENT；旧共享图片归属 UNKNOWN |
| Native runtime cache | `MainActivity.clearRuntimeCache` 经 `aiTasks` executor 调用 `LocalAiRuntimeCacheClearPolicy`；先 `releaseLocalModel()`，再删除 `cacheDir/litertlm`；失败时保留缓存；模型文件在 `filesDir/ai_models` | CODE + Native unit tests PRESENT |
| Native 内存会话 | `releaseLocalModel()` 先清空 Engine/Conversation 引用，再关闭资源，同时清空 `userReportedInputs`、截断标记、`conversationHistoryTurns` | CODE PRESENT |
| TRACE | `LocalAiDataClearCoordinator.forApp()` 先调用 `AiTraceRecorder.disableAndFlush`，再调用 writer.clear() 删除 `ai_trace.jsonl` 和 `.tmp`；结束后按之前开关状态恢复 | CODE + tests PRESENT |
| UI | `SettingsScreen` 数据管理区已挂载 `LocalAiDataClearTile`；二次确认、清理中状态、分域结果和部分失败提示均存在 | CODE + widget tests PRESENT |
| Android backup | Manifest 显式引用 `backup_rules.xml` 与 `data_extraction_rules.xml`；两者仅排除 `ai_models/`、`ai_trace.jsonl`、`ai_trace.jsonl.tmp` | 模型/TRACE 排除有配置证据；混合 SQLite 仍在备份范围内 |

### 6.2 数据库备份边界（仍未解决）

- AI 对话与非 AI 数据共用 `nihaisha.db`。
- 两套 Android 规则没有排除 `domain="database"`，因此 AI 会话行可能随数据库备份/设备迁移保留。
- 不能通过 XML 按 SQLite 表/行选择性排除 AI 数据；排除整个数据库会连带影响 bookmarks、diagnosis_history、user_settings、user_charts 等非 AI 数据。
- 当前清除动作删除的是设备本地数据库中的 AI 行，不会证明此前生成的云备份/设备迁移副本同步删除。
- 可行的长期隔离方向是将 AI 会话数据迁入独立数据库文件，或采用应用层可撤销密钥/数据加密设计；两者均涉及迁移、恢复与产品行为，不在本轮擅自实施。

### 6.3 当前剩余缺口

1. **旧共享图片**：历史版本的 image_picker 临时文件没有完整所有权清单；不得扫描并删除共享临时目录中的任意图片。当前结论 UNKNOWN。
2. **外部副本**：用户手动导出、系统备份、设备迁移副本不在本地 coordinator 控制范围。
3. **进程重启**：数据库边界测试验证了关闭/重开 SQLite 连接后的行状态；尚未证明 Find N2 上强制停止/进程重启后不可恢复。UI 明确要求完全退出并重启后复查，但这不是已完成的真机证据。
4. **真机清理**：尚无 Find N2 实测 TRACE，覆盖 Native 模型运行中、附件存在、TRACE 开关开启/关闭、清理失败和进程重启。
5. **Native 任务并发**：Native cache 清除通过串行 `aiTasks` executor 执行；仍需真机验证清理触发时正在进行的模型调用、Activity teardown 与清理结果交付顺序。

### 6.4 当前结论

- SQLite、AI 专属附件、Native runtime cache、TRACE 和设置 UI 的清除代码已落地，并有单元/组件测试。
- 模型文件按产品约定保留；非 AI 数据在数据库边界测试中得到保留证明。
- **E = PARTIAL，不是 PASS。** 混合 SQLite 备份副本、旧共享图片和 Find N2 强制停止/重启后的不可恢复证据仍缺失。
- 不得全局禁用 Android backup；不得删除整个 `nihaisha.db`；不得清空共享 temp 目录；不得把关闭/重开数据库连接等同于真实进程重启。

### 6.5 下一步

1. 为 Android backup 风险建立独立决策记录：保留现状并接受 AI 数据进入备份，或评估 AI 独立数据库迁移；不以全局关闭备份替代分析。
2. 为旧版图片建立可验证归属证据；没有证据时继续保留并在 UI/文档披露。
3. 在 Find N2 做合成数据清理验收：模型运行中/空闲、附件存在、TRACE 开关两种状态、清理成功/部分失败、强制停止、重启后重新检查；同时确认模型文件和非 AI 数据保留。
4. 把设备结果记录为每个数据域的 CLEAR / RETAINED / UNKNOWN，附设备型号、Android 版本、构建 SHA、步骤和重启后复查结果。
