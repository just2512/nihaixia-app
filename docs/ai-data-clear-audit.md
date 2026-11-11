# E：AI 数据清除范围审计

审计基线：`master`（2026-11-10）。本文件是数据清除实现前的只读盘点；不代表清除功能已实现或验收。

## 1. 当前持久化数据位置

### SQLite（`lib/data/database_helper.dart`）

数据库文件由 `DatabaseHelper._initDB('nihaisha.db')` 打开，当前 schema version 为 7。已确认表：

| 表 | 当前用途 | 清除策略 |
|---|---|---|
| `chat_history` | 旧版聊天记录 | 清除 |
| `assistant_conversations` | 统一助手会话元数据 | 清除 |
| `assistant_messages` | 统一助手用户/助手/系统/工具消息 | 清除 |
| `tcm_interview_tasks` | 会话关联的结构化问诊任务快照 | 清除 |
| `diagnosis_history` | 独立辨证历史 | 暂不清除；不是统一 AI 会话表，需单独确认范围 |
| `user_settings` | 应用设置 | 保留 |
| `bookmarks` / `bookmark_folders` | 用户收藏 | 保留 |
| `search_history` | 全局搜索记录 | 保留 |
| `medical_case_bookmarks` / `medical_case_recent` | 医案收藏/最近访问 | 保留 |
| `user_charts` | 用户自定义命盘资料 | 保留 |

当前已有 `clearChatHistory()` 只删除旧表 `chat_history`，不删除统一助手表。已有 `deleteAssistantConversations()` 会在 transaction 内先删除 `assistant_messages`、`tcm_interview_tasks`，再删除 `assistant_conversations`；但它是按会话 ID 删除，不提供全量清除。

**必须实现的数据库清除事务：** 删除 `assistant_messages`、`tcm_interview_tasks`、`assistant_conversations`、`chat_history`。不能删除整个 `nihaisha.db`，否则会误删收藏、用户设置、命盘和其他功能数据。

## 2. Android 应用私有文件

### 模型文件（非会话数据）

- Native 模型：`filesDir/ai_models/gemma-4-E4B-it.litertlm`。
- 导入中间文件：同目录 `.importing`。
- 替换回滚文件：同目录 `.previous`。
- `LocalAiModelImportRecovery.recover(modelFile)` 会在目标缺失时恢复旧模型，并清理残留中间文件。

本轮“清除全部 AI 数据”定义为清除会话/消息/问诊快照/附件/推理缓存，**保留已导入模型文件**，避免用户每次清除聊天都必须重新导入约 3.66 GB 模型。模型文件不是用户对话数据；如果将来需要卸载模型，应作为独立操作明确标识。

### LiteRT-LM 运行缓存

Native `loadLocalModel()` 使用 `File(cacheDir, "litertlm")` 作为 `EngineConfig.cacheDir`。当前 `releaseLocalModel()` 关闭 Conversation/Engine 并清理内存态，但不删除该目录。

清除流程必须先在 Native 单线程 executor 上释放 Engine/Conversation，再删除 `cacheDir/litertlm`。不得在 Engine 仍持有文件时直接递归删除。

## 3. 附件与临时文件

当前附件位置和生命周期：

- 语音录音：`getTemporaryDirectory()/local_ai_<timestamp>.wav`。
- 拍照：`ImagePicker.pickImage(source: camera)` 返回的临时文件路径；目前没有独立 AI 子目录。
- Native `validateCachedInput` 要求附件路径位于 Android `cacheDir` 下，并限制单文件不超过 15 MB。
- 发送成功后，Flutter `_send()` 调用 `_deleteCachedAttachments([imagePath, audioPath])`。
- 用户移除附件、发送失败后的组件销毁、模型释放/重置等路径也会尽力清理当前已知路径。
- `_deleteCachedAttachments` 只删除传入的当前路径；它不会扫描历史遗留文件或未知孤儿文件。
- 录音停止失败、Activity/widget teardown 也有清理分支，但属于 best-effort。

**已确认缺口：** 图片和语音当前没有统一的专属持久化目录。若进程在文件创建后、路径清理前异常退出，UI 已丢失该路径时无法可靠地枚举所有 AI 附件。不能为了清除 AI 附件而递归删除整个 `cacheDir`，因为其他功能可能共用该目录。

### 建议的最小安全改造

1. 新增专属目录 `cacheDir/local_ai_attachments/`。
2. 拍照 picker 返回文件后，复制到该目录，再删除 picker 原始临时文件；录音直接写入该目录。
3. Native 仍只接受 cacheDir 内的规范化路径，附件大小校验保持不变。
4. 发送完成、放弃、失败后重试、重置、释放、清除全部数据都只清理该专属目录中的文件。
5. 清除时兼容清理旧版已知语音文件名 `local_ai_*.wav`；对无法证明归属的共享 picker 缓存，不做全目录删除。
6. 在专属目录中创建文件后即使进程被杀，下一次启动/清除也可扫描并清除孤儿文件。

## 4. 当前 Native 接口缺口

当前 MethodChannel 已有：
`getModelStatus`、`importModel`、`loadModel`、`extractSymptoms`、`sendImage`、`sendAudio`、`sendMessage`、`restoreConversation`、`resetConversation`、`releaseModel`、`clearAiData`（本分支新增，待 CI 验收）。

Native 清除入口由主线程门禁 + 单线程 `aiExecutor` 执行：
- 若文件选择器仍等待用户选择（`pendingModelImportResult != null`），立即拒绝；
- 清除排队/执行期间设置 `aiDataClearPending`，阻止新 `importModel` 请求；
- 已经在 executor 排队的导入任务按队列顺序先完成，再执行清除；
- 释放当前 Conversation/Engine，并清空 Native 内存中的 userReportedInputs 和 transcript；
- 仅删除 `cacheDir/litertlm`、`cacheDir/local_ai_attachments` 和符合 `local_ai_<timestamp>.wav` 的旧录音；
- 保留模型文件和其他 cache 内容；
- 返回每类删除数量；任何删除失败通过 MethodChannel error 返回，不能伪报成功。


## 5. 清除事务与失败语义

跨 SQLite 与文件系统无法使用单一事务。推荐按可重试、幂等方式编排：

1. UI 二次确认，发送/录音/模型控制/附件操作期间禁用清除。
2. 等待当前会话创建与问诊任务写入完成，避免清除后异步写入重新创建空会话。
3. Native 先在 aiExecutor 串行释放 Engine/Conversation，再清理 runtime cache、AI 附件目录和旧录音。
4. Dart 再清理当前附件路径与专属附件目录，并在单个 SQLite transaction 中删除四张 AI 会话表。
5. 任一步失败都显示未全部清除；已完成的步骤可幂等重试。若 Native 已释放模型但后续 SQLite 失败，UI 必须同步模型状态为 not_ready，保留数据库历史供重试。
6. 全部成功后清空 UI 消息、当前会话 ID、结构化问诊控制器、待恢复 transcript 和附件状态。
7. 设备重启验收：数据库无会话/消息/问诊任务，AI 附件目录和 Native runtime cache 不存在；模型文件仍在，不要求重新导入。
8. 不删除整个数据库，不删除全局用户设置、收藏、命盘和医案数据。

## 6. 自动化验收

- 数据库测试：四张 AI 表有样本记录，清除后行数为 0；其他表样本行数不变。
- 事务测试：人为制造删除失败，确认事务回滚，不出现部分表已删、部分未删。
- 附件测试：专属目录中的照片/录音/孤儿文件全部删除；cacheDir 中非 AI 文件保持不变。
- Native 测试：Engine/Conversation 已关闭后才删除 runtime cache；未完成模型导入时拒绝清除；删除失败返回失败状态。
- UI 测试：清除后消息列表/当前会话/问诊任务/待恢复上下文/附件状态全部重置；清除进行中禁止再次发送。
- 重启验收：进程重启后 SQLite 无会话/消息/问诊任务，附件目录为空，Native runtime cache 不存在；重新导入模型不是清除会话的必要条件。
- 真机：Find N2 实测模型已加载时执行清除，验证 Engine 释放、cache 删除、UI 重置和重启后不可恢复。

## 当前实现进度（2026-11-11）

已在独立分支加入以下实现，但尚未集成、不得标记为完整 PASS：

- `DatabaseHelper.clearAiConversationData()`：单个 SQLite transaction 清理四张 AI 会话表；保留其他业务表。
- `LocalAiAttachmentStorage`：将 picker 图片复制到 `local_ai_attachments/`，录音直接创建在该目录；拒绝附件根目录符号链接，清理递归不跟随链接；提供旧版 `local_ai_<timestamp>.wav` 兼容清理。
- `LocalAiService.clearAiData()`：Dart MethodChannel 调用契约已添加。
- `LocalAiInterviewScreen`：新增二次确认入口；清理后重置当前消息、会话 ID、问诊控制器和附件状态；下一次成功写入时延迟创建新会话，避免清除后留下空会话行。
- `LocalAiDataCleanup.kt`：提供仅删除 AI 专属目录/旧版录音的 Native 文件清理 helper，包含目录越界和符号链接防护；Kotlin 测试新增根目录 symlink 越界拒绝用例。
- `MainActivity.kt`：新增 `clearAiData` MethodChannel handler；清除期间拒绝新模型导入，Engine/Conversation 释放成功后删除 `litertlm`、`local_ai_attachments` 与旧版录音；保留模型文件和其他 cache。
- Dart `LocalAiModelStatus`：新增 Native 清理数量字段；UI 清理顺序调整为 Native runtime → 附件 → SQLite，失败时刷新/标记 runtime 状态，避免数据库先删而 Native 失败。
- 新增 Dart 数据库/附件/服务/UI 测试和 Kotlin 文件清理测试。

**当前剩余硬阻断：** Native `clearAiData` handler 已接入 `MainActivity.kt`，并设置主线程 `aiDataClearPending` 门禁；Engine/Conversation 释放后才删除 runtime cache，删除失败会向 Dart 返回错误。当前代码尚未通过本分支最新 CI，且没有 Find N2 真机测试，因此仍不得标记完整 PASS。

验收仍需：
- C 分支的 CI 改进合并后重新跑本分支 changed tests（包括 Linux SQLite host asset prewarm）；
- Native handler 与 Android unit tests；
- PR 全量 Flutter regression + Android arm64 build/unit tests；
- Find N2 真机清除前已加载 Engine、附件缓存、重启不可恢复验收。

## 7. 明确不在本切片内

- 不删除 `filesDir/ai_models/gemma-4-E4B-it.litertlm`。
- 不删除整个 SQLite 数据库。
- 不删除全局 `cacheDir` 或所有 `getTemporaryDirectory()` 内容。
- 不实施 SQLCipher 或数据库密钥迁移。
- 不清除独立 `diagnosis_history`、`user_settings`、收藏、命盘和医案数据；如产品定义将它们纳入 AI 清除，需独立更新范围与确认文案。

