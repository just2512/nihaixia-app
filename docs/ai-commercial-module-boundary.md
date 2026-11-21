# AI 增值模块边界清单

> 本清单只定义 AI 增值功能的候选代码边界，不改变当前任何文件的许可证。当前公开版本仍按根目录 Apache 2.0 执行。知识库及其内容明确不在本清单内。

## 1. 商业授权对象

商业授权对象是维护者自主增加的 AI 能力代码，包括：

- 本地 AI 模型接入、会话调用和运行状态管理；
- AI 对话界面、会话生命周期、历史恢复和本地附件管理；
- 助手意图识别、确定性编排、工具选择与参数校验；
- AI 对知识内容的本地检索编排、上下文组织、来源引用和结果解释；
- AI 与结构化问诊流程之间的衔接；
- AI 工具调用适配、结果回传及 TRACE 调试能力。

AI 读取或引用知识库，不意味着知识库、古籍、讲稿、医案、本草或穴位内容成为商业授权对象。

## 2. 首批核心文件

| 文件 | AI 功能 | 边界状态 |
|---|---|---|
| `lib/services/local_ai_service.dart` | 本地模型接入与会话调用 | 候选：独立 AI 服务文件 |
| `lib/services/assistant_conversation_orchestrator.dart` | 助手意图分流与流程编排 | 候选：独立 AI 编排文件 |
| `lib/screens/assistant_tool_router.dart` | AI 工具注册、选择与路由 | 候选：AI 调度层；被调用的工具本体不因此收费 |
| `lib/screens/local_ai_interview_screen.dart` | 本地 AI 对话、问诊交互和会话 UI | **混合文件**：不得将整文件直接列为商业专有；需先拆分 AI 专属逻辑或按可识别增量处理 |

## 3. AI 支撑模块候选范围

以下是功能候选路径，不等于这些文件当前已全部通过版权归属审查，也不代表整文件自动转为商业许可。每次商业发行必须结合对应版本的 Git diff 复核。

### 会话、数据结构与本地存储

- `lib/data/assistant_conversation_store.dart`
- `lib/models/assistant_message_metadata.dart`
- `lib/models/assistant_tool_result.dart`
- `lib/models/ai_context_ref.dart`
- `lib/models/tcm_interview_message.dart`
- `lib/models/tcm_interview_task_state.dart`

### 上下文、检索编排与结果解释

- `lib/services/assistant_knowledge_context.dart`
- `lib/services/ai_context_prompt_builder.dart`
- `lib/services/ai_context_resolver.dart`
- `lib/services/ai_tool_result_snapshot.dart`
- `lib/services/assistant_chart_result_formatter.dart`
- `lib/services/bazi_context_snapshot.dart`

这里只能把维护者编写的检索调度、上下文拼装、引用定位及结果解释逻辑作为 AI 候选代码。知识条目、文献原文、讲稿、医案及索引内容本身均不纳入。

### TRACE、附件与本地运行管理

- `lib/services/ai_trace.dart`
- `lib/services/ai_trace_runtime.dart`
- `lib/services/ai_trace_store.dart`
- `lib/services/local_ai_attachment_store.dart`
- `lib/services/local_ai_data_clear_coordinator.dart`

### 结构化问诊与 AI 交接

- `lib/services/tcm_interview_adapter.dart`
- `lib/services/tcm_interview_conversation_controller.dart`

只限 AI 与学习问诊流程之间的交互适配，不包括确定性辨证规则、诊断引擎和既有问诊数据。

### AI 界面与设置组件

- `lib/screens/assistant_history_screen.dart`
- `lib/widgets/contextual_ai_sheet.dart`
- `lib/widgets/local_ai_backend_settings_tile.dart`
- `lib/widgets/local_ai_data_clear_tile.dart`
- `lib/widgets/local_ai_trace_debug_tile.dart`

## 4. 工具适配器的特别边界

AI 助手的工具适配代码可以作为 AI 增值功能的一部分，但只能覆盖：

- 从 AI 请求中解析和校验工具参数；
- 将已确认参数交给原有确定性工具；
- 接收原有工具的结构化结果；
- 将结果组织为 AI 会话可解释、可引用的上下文。

以下内容仍属于免费基础功能，不因 AI 调用而收费：

- 排盘、历法、五运六气、剂量换算及其他确定性计算算法；
- 既有独立工具页面和用户直接调用这些工具的路径；
- 这些工具依赖的原始数据表、规则表和知识内容。

因此，诸如 `*_tool_executor.dart` 的文件只有在逐段确认其全部内容均为维护者新增的 AI 适配代码后，才可考虑整文件纳入；否则只标记 AI 适配增量，不能把整个执行器或底层算法列入商业清单。

## 5. 混合宿主文件

首页、知识详情页、方剂/本草/医案页面、排盘页、原有问诊页和 Android `MainActivity.kt` 可能承载 AI 入口或桥接逻辑。这些文件同时包含免费原有功能，处理规则如下：

1. 不把整个宿主文件列为商业专有代码。
2. 只考虑维护者新增且可识别的 AI 入口、上下文传递和本地调用桥接代码。
3. 优先把 AI 逻辑抽取到独立文件或模块，宿主只保留免费调用接口。
4. Android 原生 AI 类可单独评估；`MainActivity.kt` 不得整体纳入商业范围。

## 6. 明确排除

- 上游 Fork 原有代码及原有免费功能；
- `lib/engine/**` 中的确定性辨证、诊断、排盘及其他业务算法；
- `assets/**` 中的知识库、经典资料、本草、穴位、医案、讲稿、索引及其他内容；
- 第三方模型权重、Gemma/LiteRT-LM 运行库和其他依赖；
- 用户自己的本地数据；
- 与 AI 增值能力无关的普通 UI、测试和构建工具。

## 7. 纳入规则

新增 AI 功能只有同时满足以下条件，才能进入未来商业版本 manifest：

- 代码权利归属可核对，且授权方有权进行商业授权；
- 不含未经许可的上游或第三方代码；
- 不把知识内容、确定性业务引擎或原有免费功能纳入；
- 混合文件已拆分，或能精确标识仅适用于维护者新增部分；
- 对应文件有明确许可标识；
- manifest 记录路径、版本、commit SHA、许可类型及排除说明。

本清单是候选边界，不是已生效的商业许可文件清单。不得使用目录通配符自动扩大授权范围。
