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


## 6. 2026-11-12 当前主线增量复核（master @ aadd7df0c8ffc1579d91ad425737ac5a70d2c656）

> 本节修正上文中已过期的附件与清理编排结论。以下为静态源码复核；未执行 Find N2 清除后重启验收。

### 6.1 已确认的实现变化

- `DatabaseHelper.clearAllAiConversationData()` 已在同一 SQLite transaction 中删除 `assistant_messages`、`tcm_interview_tasks`、`assistant_conversations`、旧 `chat_history`。数据库文件仍为 `nihaisha.db`，schema version 7；诊断历史、收藏、设置、命盘等非 AI 数据保留。
- `test/ai_data_clear_database_test.dart` 覆盖四类 AI 对话数据清空、非 AI sentinel 数据保留，以及删除中途失败时事务回滚。
- `LocalAiRuntimeCacheClearPolicy` 已先调用 Native runtime release，再删除 `cacheDir/litertlm`；模型文件位于 `filesDir/ai_models`，不属于清理目标。Native `releaseLocalModel()` 清空 Engine/Conversation 引用、`userReportedInputs` 与 `conversationHistoryTurns`。
- `LocalAiAttachmentStore` 已有独立目录和定向删除单测，但它目前没有被 `LocalAiInterviewScreen` 调用；“有附件存储类”不能证明生产附件已经迁移到专属目录。
- `LocalAiDataClearCoordinator` 已有分域编排与故障注入测试；但当前 `settings_screen.dart` 和 `local_ai_interview_screen.dart` 未发现该协调器的生产调用，也未发现“清除全部 AI 数据”设置入口。工厂方法存在不等于用户可以执行清除。
- TRACE writer 已有只删除自身 `ai_trace.jsonl` 与 `.tmp` 的能力；统一 recorder/runtime 生命周期仍由 PR #69 处理，且当前主线尚未集成 #69。

### 6.2 附件归属的当前真实情况

- 图片仍由 ImagePicker 返回临时路径，`LocalAiInterviewScreen._deleteCachedAttachments()` 仅按已知路径删除，并通过路径规范化限制在系统临时目录内。
- 语音录音仍写入 `getTemporaryDirectory()/local_ai_<timestamp>.wav`。
- 该屏幕没有使用 `LocalAiAttachmentStore`；因此图片/语音附件缺少可靠的全量枚举和进程重启后孤儿文件清理机制。
- 单次发送/页面销毁时按当前已知路径清理，只能证明局部清理，不足以证明“清除全部 AI 数据”。

### 6.3 Android 备份边界仍未解决

- 当前 `android/app/src/main/AndroidManifest.xml` 未声明 `android:allowBackup`、`android:fullBackupContent` 或 `android:dataExtractionRules`。
- 当前树中未发现 `backup_rules.xml` 或 `data_extraction_rules.xml`。
- AI 对话表与收藏、设置、诊断历史共用 `nihaisha.db`。Android XML 备份规则只能按文件/目录域排除，不能按 SQLite 表或行排除。
- 因此“只排除 AI 对话而保留同库非 AI 数据”不能仅靠现有 XML 规则实现。全应用 `allowBackup=false` 会扩大影响面，必须单独作产品决策，不作为默认修复。

### 6.4 更新后的 E 状态

| 子项 | 状态 | 证据 | 剩余缺口 |
|---|---|---|---|
| SQLite AI 对话原语 | PARTIAL（代码/测试存在） | `database_helper.dart` / `ai_data_clear_database_test.dart` | 尚未接入生产清除 UI；设备重启后不可恢复未验证 |
| Native runtime/cache | PARTIAL（代码/Native 单测存在） | `MainActivity.kt` / `LocalAiRuntimeCacheClearPolicy.kt` | 必须经生产协调器调用；设备端释放与缓存删除未实测 |
| AI 附件归属 | PARTIAL | `LocalAiAttachmentStore` 单测通过，但生产 screen 仍使用共享临时目录 | 迁移生产读写路径、清理历史遗留文件；不误删共享临时文件 |
| TRACE | PARTIAL | writer/recorder 基础存在；#69 待集成 | 必须统一 writer/recorder 实例并纳入清理编排 |
| UI/用户确认 | MISSING | 当前 Settings 与 AI screen 未发现清除入口/协调器调用 | 增加二次确认、执行期间互斥和逐域结果 |
| Android backup | UNKNOWN / 产品决策阻塞 | Manifest 无显式策略；无规则 XML；同库混存 | 先评估备份影响与数据隔离替代方案，不擅自全局关闭 |
| Find N2 重启验证 | UNKNOWN | 无本轮设备 TRACE | 合成数据清理、强制停止、重启、再次检查 |

### 6.5 下一步（按依赖顺序）

1. #69 合并后，确认 coordinator 使用进程级同一 recorder/writer，并保持默认关闭状态。
2. 将生产附件写入迁移到 AI 专属目录；保留对历史共享临时路径的有限清理兼容，不能递归删除整个 temp 目录。
3. 在设置页增加“清除全部 AI 对话数据”二次确认；调用 coordinator，执行期间禁止发送、恢复历史、加载/重置模型；逐项展示数据库、附件、Native cache、TRACE 清理状态和失败域。
4. 为 coordinator 增加生产 wiring/widget 测试与并发互斥测试；确保部分失败不显示“全部清除成功”。
5. Android backup 单独提交影响评估与 merged manifest/build 证据；在用户决策前不合并全应用禁用备份。
6. Find N2 以合成数据执行清理、强制停止、重启、数据不可恢复及非 AI 数据/模型文件保留验证；未取得 TRACE 前 E 保持 PARTIAL。

