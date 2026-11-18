# AI 增值功能版权归属与授权审计

> 审计范围：仅限本仓库由 `just2512` 自主增加的 AI 功能代码。  
> 不审计、不收费、不改变原有知识库、经典资料、本草、医案、图片或其他内容的授权。  
> 审计基线：`master` @ `a886286de83116fef8193db3781a11dca6ff8ece`（2026-11-18）。

## 1. 审计结论

本仓库可以按“原有应用免费 + 自研 AI 增值功能商业授权”的方式进行分层商业化，但必须保留已经向外界授予的 Apache-2.0 权利。

本次审计确认了以下事实：

1. AI 本地推理、统一助手、工具调度和问诊界面等核心代码在本仓库有由 `just2512` 创建的 Git 提交记录。
2. 以下四个核心 AI 文件在上游 `jangviktor-web/nihaixia-app@main` 对应路径均返回 404；在本仓库提交历史中有明确的 `just2512` 创建记录：
   - `lib/services/local_ai_service.dart`
   - `lib/screens/local_ai_interview_screen.dart`
   - `lib/services/assistant_conversation_orchestrator.dart`
   - `lib/screens/assistant_tool_router.dart`
3. 本仓库当前根目录 `LICENSE` 仍为 Apache License 2.0；当前公开版本的 README 也声明项目按 Apache 2.0 发布。因此，不能把已经公开发布的 AI 源码描述成从未授予 Apache 权利，也不能追溯撤销接收者已取得的许可。
4. 维护者可以对自己拥有版权的代码另行提供商业许可；Apache 2.0 第 4 节允许版权持有人对其修改或衍生作品提供附加或不同的许可条件，但前提是继续遵守原作品的 Apache 条件。Apache 官方 FAQ 也明确说明，修改者可以销售自己的修改版本，但原始代码仍受 Apache 许可约束。

## 2. Git 提交证据

以下为本次复核到的代表性创建提交。GitHub 提交记录中的作者账号均为 `just2512`：

| AI 功能代码 | 首个可核对的创建提交 | 记录时间（UTC） | 说明 |
|---|---|---|---|
| 本地 E4B 推理服务 `local_ai_service.dart` | [`5670526cb2`](https://github.com/just2512/nihaixia-app/commit/5670526cb2393ddba2e156a035fac94e05f722df) | 2026-10-31 | 新增离线 Gemma 4 推理服务 |
| 助手工具路由 `assistant_tool_router.dart` | [`85da0093c7`](https://github.com/just2512/nihaixia-app/commit/85da0093c736f8abe0c25c96c7bfc03ae1fa05bc) | 2026-11-03 | 新增确定性工具路由注册表 |
| 统一助手编排器 `assistant_conversation_orchestrator.dart` | [`f9c357e005`](https://github.com/just2512/nihaixia-app/commit/f9c357e005ff085e7a1920071d545492a31f5f8c) | 2026-11-03 | 新增统一助手确定性编排器 |
| AI 知识检索编排 `assistant_knowledge_context.dart` | [`0199d7e956`](https://github.com/just2512/nihaixia-app/commit/0199d7e9568edbd3a42b9bf844688ebce780ed22) | 2026-11-03 | 新增本地知识检索接入逻辑；不包含知识内容本身 |
| 本地 AI TRACE `ai_trace.dart` | [`c7a12ed321`](https://github.com/just2512/nihaixia-app/commit/c7a12ed32140fb2e8e97ea406e5fdc6504216907) | 2026-11-11 | 新增默认关闭、隐私约束的 TRACE 契约 |
| 情境 AI 引用模型 `ai_context_ref.dart` | [`bd0dad172a`](https://github.com/just2512/nihaixia-app/commit/bd0dad172a4f627c6ec0fef740b2a4d242ff1d4f) | 2026-11-17 | 新增情境上下文锚点 |

`local_ai_interview_screen.dart`、`assistant_tool_router.dart` 等文件之后持续有多个 AI 功能和修复提交。当前提交历史可以证明账号提交轨迹，但 Git 作者字段本身不是完整的法律权属证明；版权归属仍以实际创作、雇佣/委托关系、第三方代码来源和权利协议为准。

## 3. 文件归属分级

### A. 独立 AI 功能文件：可纳入 AI 商业授权候选范围

首批核心文件：

- `lib/services/local_ai_service.dart`
- `lib/screens/local_ai_interview_screen.dart`
- `lib/services/assistant_conversation_orchestrator.dart`
- `lib/screens/assistant_tool_router.dart`

这些路径在上游对应位置不存在，且本仓库有维护者创建记录。可以作为 AI 增值功能的首批独立代码边界。

### B. AI 支撑模块：纳入功能范围，但要按实际新增代码确定权属

包括本地会话、上下文引用、知识检索编排、工具结果快照、TRACE、附件生命周期、问诊会话衔接等 AI 支撑代码。当前主线中可见的代表路径：

- `lib/data/assistant_conversation_store.dart`
- `lib/models/ai_context_ref.dart`
- `lib/models/assistant_message_metadata.dart`
- `lib/models/assistant_tool_result.dart`
- `lib/models/tcm_interview_message.dart`
- `lib/models/tcm_interview_task_state.dart`
- `lib/services/assistant_knowledge_context.dart`
- `lib/services/ai_context_prompt_builder.dart`
- `lib/services/ai_context_resolver.dart`
- `lib/services/ai_tool_result_snapshot.dart`
- `lib/services/ai_trace.dart`
- `lib/services/ai_trace_runtime.dart`
- `lib/services/ai_trace_store.dart`
- `lib/services/assistant_chart_result_formatter.dart`
- `lib/services/bazi_context_snapshot.dart`
- `lib/services/local_ai_attachment_store.dart`
- `lib/services/local_ai_data_clear_coordinator.dart`
- `lib/services/tcm_interview_adapter.dart`
- `lib/services/tcm_interview_conversation_controller.dart`
- `lib/screens/assistant_history_screen.dart`
- `lib/widgets/contextual_ai_sheet.dart`
- `lib/widgets/local_ai_backend_settings_tile.dart`
- `lib/widgets/local_ai_data_clear_tile.dart`
- `lib/widgets/local_ai_trace_debug_tile.dart`

其中 `assistant_knowledge_context.dart` 的商业授权对象仅是维护者新增的检索、上下文组织、来源引用和结果解释代码；知识库条目、古籍文本、医案内容及其他资料本身明确排除在本次商业授权之外。

### B2. AI 工具执行适配层

主线当前有以下 18 个由 `just2512` 的提交记录引入的助手工具执行适配文件：

- `lib/services/almanac_tool_executor.dart`
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

这些文件纳入 AI 商业功能候选范围的部分，仅限助手侧的参数接收/校验、任务执行适配、调用既有业务能力和结果交接。它们调用的既有排盘、历法、剂量换算、择时等确定性算法及原始数据不因此转为商业专有模块。若某个适配文件中包含独立于 AI 的可复用业务算法，应按代码差异单独拆分或标注，不能把算法整体打包进 AI 授权范围。

### C. 与上游或原有页面混合的文件：不得把整个文件认定为独占代码

例如：

- `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt`
- `lib/main.dart`
- 原有首页、诊断页面、排盘页面和知识详情页面中增加的 AI 入口/上下文传递代码

其中可能同时包含上游原代码、原有业务逻辑和维护者新增的 AI 适配代码。商业归属只按维护者实际新增的可分离代码或提交差异确定，不把整个文件、整个页面或整个原有模块纳入商业专有范围。

## 4. 明确排除范围

下列内容继续按原有许可证或各自原授权执行，不纳入 AI 商业授权：

- 原 Fork 继承的功能和上游代码。
- 确定性中医辨证、排盘、计算等原有业务引擎，尤其是 `lib/engine/**`。
- 知识库、经典、本草、穴位、医案、讲稿及其他知识内容，包括 `assets/**` 中的内容。
- 普通数据文件、与 AI 功能无关的界面和基础设施。
- Gemma 模型文件、LiteRT-LM 等第三方运行库及其他第三方依赖；其权利仍由各自权利人和许可证决定。
- 测试代码和本次授权说明文档本身。

## 5. 商业授权落地结论

- 原有应用及上述排除内容继续免费使用，根目录 `LICENSE` 不在本次修改。
- 对已经公开发布的 AI 源码，保留发布时已经授予的 Apache-2.0 权利；不要求下载者购买、不向既有下载者追收费用。
- 未来官方发行版可以针对维护者有权授权的 AI 增值功能建立独立商业授权，但必须由具体版本的 release manifest、文件级许可标识及根目录许可例外共同落实。当前公开 master 的 AI 源码仍按现行 Apache 2.0 执行。
- 若未来需要让新开发的 AI 源文件本身采用商业专有许可，应先把新逻辑拆入独立文件并逐文件标注许可；不得仅凭目录名或本清单把混合文件整体改成专有许可。

## 6. 本轮状态

| 项目 | 状态 |
|---|---|
| 当前主线及许可证基线核对 | PASS |
| 核心 AI 文件的提交归属证据 | PASS（Git 历史层面） |
| 四个核心文件与上游路径对照 | PASS（上游对应路径 404） |
| 混合文件与非 AI 内容排除边界 | PASS（已列明原则和代表路径） |
| 已公开 AI 源码的既有 Apache 权利处理 | PASS（不追溯撤销） |
| 当前 master 的 AI 源码许可证状态 | Apache 2.0（尚未切换） |
| 未来商业版本的逐文件许可例外与 release manifest | PENDING |
| AI 源文件未来专有许可的逐文件切分与标注 | PENDING；须在指定未来版本实施，不是本次提交的变更 |
| 版权法律意见 | 未委托律师出具；本文件是仓库证据审计，不是法律意见 |

## 参考依据

- [Apache License 2.0 正文，尤其第 2、4、5 节](https://www.apache.org/licenses/LICENSE-2.0.html)
- [Apache Software Foundation：Apache Licensing and Distribution FAQ](https://www.apache.org/foundation/license-faq.html)
- [本仓库当前 LICENSE](../LICENSE)
- [AI 增值模块范围](ai-commercial-module-boundary.md)
- [AI 商业授权政策](ai-commercial-licensing-policy.md)
