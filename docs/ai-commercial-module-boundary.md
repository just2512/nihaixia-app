# AI 增值模块边界清单

> 本清单只界定由 `just2512` 自主增加的 AI 功能代码。它不是对整个文件夹、整个页面或整个仓库的版权主张。  
> 当前清单基于 `master` @ `a886286de83116fef8193db3781a11dca6ff8ece`。

## 1. 商业功能边界

纳入增值功能的，是 AI 提供的本地理解、会话、问诊衔接、助手编排、工具调度、上下文检索组织、来源引用、结果解释及相关本地运行控制能力。

收费对象是 AI 增值功能，不是中医知识库，也不是底层确定性辨证引擎。

## 2. 首批核心独立模块

以下四个文件在上游 `jangviktor-web/nihaixia-app@main` 不存在，在本仓库均有维护者创建记录：

| 文件 | 功能 | 边界 |
|---|---|---|
| `lib/services/local_ai_service.dart` | 本地模型推理服务封装 | AI 本地推理接入与会话调用逻辑，不包含第三方模型权重和运行库 |
| `lib/screens/local_ai_interview_screen.dart` | 本地 AI 助手/问诊交互 | AI 对话和交互流程，不代表页面中引用的原有规则引擎归商业模块 |
| `lib/services/assistant_conversation_orchestrator.dart` | 助手意图理解与确定性流程编排 | 只包括助手编排与路由逻辑；具体业务工具仍归原功能所属模块 |
| `lib/screens/assistant_tool_router.dart` | 工具注册、选择和执行路由 | 只包括 AI 助手工具调度逻辑，不把工具的原始数据或确定性计算算法纳入 |

## 3. AI 支撑模块清单

以下路径属于 AI 增值能力的实现支撑范围。若文件本身含有既有代码，授权只作用于维护者新增并可识别的代码，不扩大到文件中的上游或第三方内容。

### 会话、数据结构和本地持久化

- `lib/data/assistant_conversation_store.dart`
- `lib/models/assistant_message_metadata.dart`
- `lib/models/assistant_tool_result.dart`
- `lib/models/ai_context_ref.dart`
- `lib/models/tcm_interview_message.dart`
- `lib/models/tcm_interview_task_state.dart`

### 上下文、检索编排和结果解释

- `lib/services/assistant_knowledge_context.dart`
- `lib/services/ai_context_prompt_builder.dart`
- `lib/services/ai_context_resolver.dart`
- `lib/services/ai_tool_result_snapshot.dart`
- `lib/services/assistant_chart_result_formatter.dart`
- `lib/services/bazi_context_snapshot.dart`

**重要区分：** `assistant_knowledge_context.dart` 中由维护者编写的检索调度、上下文拼装、引用定位和结果解释逻辑可以列入 AI 功能范围；它读取的知识库内容、文献文本、医案文本、药物/穴位资料及其文件不因此变成商业授权内容。

### TRACE、附件与本地运行管理

- `lib/services/ai_trace.dart`
- `lib/services/ai_trace_runtime.dart`
- `lib/services/ai_trace_store.dart`
- `lib/services/local_ai_attachment_store.dart`
- `lib/services/local_ai_data_clear_coordinator.dart`

### 结构化问诊与 AI 交接

- `lib/services/tcm_interview_adapter.dart`
- `lib/services/tcm_interview_conversation_controller.dart`

### AI 界面与设置组件

- `lib/screens/assistant_history_screen.dart`
- `lib/widgets/contextual_ai_sheet.dart`
- `lib/widgets/local_ai_backend_settings_tile.dart`
- `lib/widgets/local_ai_data_clear_tile.dart`
- `lib/widgets/local_ai_trace_debug_tile.dart`

### Android 本地 AI 原生适配

- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAi*.kt` 中由维护者新建的 AI 策略、生命周期和输入校验类。

`MainActivity.kt` 是上游已有文件，不能作为整体商业专有文件；仅可识别和授权维护者新增的本地 AI 调用桥接代码。

## 4. 仅作为 AI 接入宿主的混合文件

主入口、首页、知识详情页、排盘页和原有问诊页可能增加了“向 AI 提问”、情境上下文传递或结果解释入口。这些页面仍然承担原有免费功能。

处理规则：

1. 不将整个宿主文件列为商业专有代码。
2. 只把维护者提交新增的 AI 入口、上下文引用和调用适配代码纳入 AI 功能增量。
3. 如果后续需要对这些代码单独商业授权，优先把 AI 逻辑抽取到独立模块，宿主页面只保留必要接口。

## 5. 明确不纳入商业授权

以下项目继续按原许可证执行：

- 原 Fork 代码及原有免费功能。
- `lib/engine/**` 中的确定性诊断/辨证引擎和其他原有确定性业务逻辑。
- `assets/**` 中的知识库、经典资料、讲稿、医案、穴位、本草及其他内容。
- 任何原始知识条目、文献文本、知识库索引内容和用户本地数据。
- 第三方模型权重、Gemma/LiteRT-LM 运行库及其他依赖。
- 不属于 AI 增值功能的普通界面、测试代码和工程工具。

## 6. 新增 AI 代码的纳入规则

后续新增 AI 能力时，必须同时满足：

- 提交作者和实际版权权利来源可核对；
- 没有未经许可复制上游或第三方代码；
- 不把知识内容或确定性核心规则伪装成 AI 专有代码；
- 优先落在独立 AI 模块中；
- 更新本文件并在代码文件头标记适用授权；
- 同一文件若含有上游或原有代码，先拆分或明确仅授权新增部分。

本清单应随实际合并的 AI 功能提交更新，不以目录通配符自动扩大授权范围。
