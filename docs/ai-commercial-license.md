# AI 功能商业授权清单

AI 功能属于本 Fork 自有修改层，**现有 AI 实现和未来 AI 实现统一采用 `LICENSE-FORK-COMMERCIAL.md`**。不以写入时间区分，也不将知识库内容纳入该授权。

## 1. 功能范围

| 功能域 | 商业授权覆盖的 Fork 自有实现 |
|---|---|
| 本地模型运行时 | 模型导入、完整性校验、加载/释放、GPU/CPU backend、Native bridge、Activity/Conversation 生命周期 |
| 统一助手 | 会话、消息、模式路由、意图识别、参数提取、澄清、任务状态、历史恢复 |
| 知识上下文 | 本地知识检索接入、Prompt、来源引用、上下文解析、快照校验、AI 结果解释 |
| 工具能力 | AssistantToolRouter、Headless executor、参数/结果校验、工具结果回流和解释 |
| 情境提问 | 经典、本草、方剂、医案、内经、八字、紫微、易经、梅花、五运六气、黄历等页面中的 Fork 新增 AI 提问入口与上下文接入 |
| 数据与安全 | AI 附件、AI 数据清理、TRACE、模型调用安全边界、AI 设置与调试 UI |

上表只覆盖 Fork 新增/修改的 AI 代码，不改变被调用的上游代码、确定性原始引擎、知识数据或第三方组件各自的许可证。

## 2. AI 专属核心文件

以下路径在当前 Fork 中构成 AI 核心实现或 AI 工具适配器：

### 2.1 对话、上下文、检索和模型服务

- `lib/data/assistant_conversation_store.dart`
- `lib/models/ai_context_ref.dart`
- `lib/models/assistant_message_metadata.dart`
- `lib/models/assistant_tool_result.dart`
- `lib/models/tcm_interview_message.dart`
- `lib/models/tcm_interview_task_state.dart`
- `lib/screens/assistant_history_screen.dart`
- `lib/screens/assistant_tool_router.dart`
- `lib/screens/local_ai_interview_screen.dart`
- `lib/services/ai_context_prompt_builder.dart`
- `lib/services/ai_context_resolver.dart`
- `lib/services/ai_tool_result_snapshot.dart`
- `lib/services/ai_trace.dart`
- `lib/services/ai_trace_runtime.dart`
- `lib/services/ai_trace_store.dart`
- `lib/services/assistant_chart_result_formatter.dart`
- `lib/services/assistant_conversation_orchestrator.dart`
- `lib/services/assistant_knowledge_context.dart`
- `lib/services/local_ai_attachment_store.dart`
- `lib/services/local_ai_data_clear_coordinator.dart`
- `lib/services/local_ai_service.dart`
- `lib/services/tcm_interview_adapter.dart`
- `lib/services/tcm_interview_conversation_controller.dart`
- `lib/widgets/contextual_ai_sheet.dart`
- `lib/widgets/local_ai_backend_settings_tile.dart`
- `lib/widgets/local_ai_data_clear_tile.dart`
- `lib/widgets/local_ai_trace_debug_tile.dart`

### 2.2 Assistant 工具适配器

这些文件是 AI 工具调用与结果回流适配，不把其调用的底层数据和上游确定性代码一并改许可：

- `lib/services/almanac_tool_executor.dart`
- `lib/services/bazi_context_snapshot.dart`
- `lib/services/bazi_tool_executor.dart`
- `lib/services/chenggu_tool_executor.dart`
- `lib/services/dosage_tool_executor.dart`
- `lib/services/dream_tool_executor.dart`
- `lib/services/guansha_tool_executor.dart`
- `lib/services/huangdi_siji_tool_executor.dart`
- `lib/services/meihua_tool_executor.dart`
- `lib/services/sanshan_lingqian_tool_executor.dart`
- `lib/services/saved_chart_tool_executor.dart`
- `lib/services/shousheng_debt_tool_executor.dart`
- `lib/services/solar_term_tool_executor.dart`
- `lib/services/xiaoliuren_tool_executor.dart`
- `lib/services/yijing_tool_executor.dart`
- `lib/services/yunqi_tool_executor.dart`
- `lib/services/yuxiaji_omen_tool_executor.dart`
- `lib/services/ziwei_tool_executor.dart`
- `lib/services/ziwuliuzhu_tool_executor.dart`

### 2.3 Android Native AI 生命周期、模型和安全策略

- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/ConversationResetPolicy.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/ConversationResourceReleasePolicy.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/FirstTurnGpuFallbackPolicy.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiActivityTaskLifecycle.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiAttachmentPolicy.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiBackendSelectionPolicy.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiConversationHistoryPolicy.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiImagePolicy.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiModelImportRecovery.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiModelIntegrityPolicy.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiRuntimeCacheClearPolicy.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiTraceIdPolicy.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiTranscriptRestorePolicy.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiWavPolicy.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/NativeRedFlagExecutionBoundary.kt`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/UserReportedInputPolicy.kt`

## 3. 页面中的 AI 功能接入

以下既有页面属于混合文件。页面原有功能和上游内容仍按其原许可；Fork 新增的 AI 提问按钮、上下文适配、快照绑定、Prompt 构造和 AI 会话接入属于商业授权修改：

- `lib/screens/classic_library_screen.dart`
- `lib/screens/markdown_doc_screen.dart`
- `lib/screens/ziwei_chart_screen.dart`
- `lib/screens/formula_detail_screen.dart`
- `lib/screens/herb_detail_screen.dart`
- `lib/screens/neijing_entries_screen.dart`
- `lib/screens/meihua_screen.dart`
- `lib/screens/bazi_paipan_screen.dart`
- `lib/widgets/bazi_paipan_widgets.dart`
- `lib/screens/yunqi_screen.dart`
- `lib/screens/medical_case_detail_screen.dart`
- `lib/screens/daily_almanac_screen.dart`
- `lib/screens/yijing_result_screen.dart`
- `lib/screens/yijing_screen.dart`
- `lib/screens/yuxiaji_omen_screen.dart`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt`

未来任何页面增加 AI 提问入口，自动按同一功能边界纳入，不需要改变知识库或页面原功能的许可证。

## 4. 测试及工程证明

对上述功能的 AI 单元测试、Widget/集成测试、Native policy tests、工具执行契约测试，以及对应的 AI 实施文档，属于同一 Fork 自有修改层。测试夹具中的知识库原文或第三方样本仍按其原许可证处理。

## 5. 明确排除项

- `assets/**` 中的经典、讲义、医案、本草、方剂、穴位、针灸、易学等知识内容和原始资料；
- 知识库条目、资料正文、原始数据及其来源文件，继续按各自原有许可证、来源声明或授权条件；
- 上游未修改的 AI/非 AI 代码以及混合文件中的上游原始部分；
- 被 AI 工具适配器调用的上游确定性代码，除非该代码本身包含本 Fork 自有修改；
- Flutter/Dart/Android、LiteRT-LM、模型权重、第三方依赖和外部服务。

原有上游 AI 代码（若在后续同步时重新引入）仍按上游许可证；本 Fork 对其所作的原创扩展和替换实现按商业授权。



## 6. 全仓库边界与清单

AI 文件不是独立于全仓库清单之外的第二套授权。现有及未来 AI 代码均按 Fork 自有实现统一进入商业授权；AI 代码所在的混合页面仅对 Fork 原创修改部分适用商业许可。全量文件级分类以 [Fork 修改文件清单](fork-license-file-inventory.md) 和机器可读 JSON 为准。
