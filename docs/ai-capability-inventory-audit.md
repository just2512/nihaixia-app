# D：统一助手能力目录审计（Page / Executed / Headless）

审计基线：`master`，仅做只读代码审计；不抽适配器、不修改计算逻辑。

## 1. 当前真实架构

### 路由注册表不是 Headless Capability Registry

`lib/screens/assistant_tool_router.dart` 中 `AssistantToolDefinition` 的执行载体是：

- `Widget Function() builder`
- 可选 `Widget Function(AssistantToolArguments) builderWithArguments`
- 参数声明 `parameters`
- 模式、别名、动作词

注册表共 24 个 `AssistantToolDefinition`。没有 `Future<AssistantToolResult> execute(...)` 或无 UI 的 capability handler。它目前是“意图匹配 → 页面构建”的路由表，不是可供模型/自动化直接调用的 headless 执行层。

### Orchestrator 只做决策，不执行

`lib/services/assistant_conversation_orchestrator.dart` 的 `resolve()`：
- 根据显式模式、学习提示、工具别名/动作词、症状/个人语境 cue 生成 `AssistantDispatchDecision`；
- 多工具命中时要求澄清；
- 只有一个明确工具命中才设置 `tool`；
- 不执行计算，不访问页面，不产生工具结果。

### 执行发生在统一会话页面

`LocalAiInterviewScreen._openTool()`：
1. 校验 `AssistantToolArguments`；
2. 通过 `Navigator.push` 打开 `_AssistantToolRouteGuard` 包裹的页面；
3. 页面内部由用户完成输入/操作/计算；
4. 页面返回 `AssistantToolResult`、旧版字符串或 null；
5. 统一规范化为 `AssistantToolResult`，校验 toolId/参数后写回会话。

因此“Page”与“Executed”不是同义词：页面打开不代表能力已执行；用户完成页面操作并返回有效结果才是 executed。

## 2. 24 项能力当前分类

| toolId | 目标页面/流程 | 当前类别 | 证据/限制 |
|---|---|---|---|
| `structured_diagnosis` | LocalAiInterviewScreen 内联结构化问诊 | Page + Executed（内联） | `_buildStructuredDiagnosis` 故意抛 StateError；`_openTool` 特殊路由到 `_startInlineTcmInterview` |
| `yunqi` | 五运六气 | Page + Executed | builder 设置 `returnResultOnComplete: true`；支持日期参数 |
| `ziwei` | 紫微斗数 | Page + Executed | builder 设置 `returnResultOnComplete: true` |
| `bazi` | 八字排盘 | Page + Executed | builder 设置 `returnResultOnComplete: true` |
| `yijing` | 易经起卦 | Page + Executed | builder 设置 `returnResultOnComplete: true` |
| `xiaoliuren` | 小六壬 | Page + Executed | builder 设置 `returnResultOnComplete: true` |
| `meihua` | 梅花易数 | Page + Executed | builder 设置 `returnResultOnComplete: true` |
| `dosage` | 经方剂量换算 | Page + Executed | builder 设置 `returnResultOnComplete: true` |
| `ziwu_liuzhu` | 时辰开穴 | Page + Executed | builder 设置 `returnResultOnComplete: true` |
| `guji_library` | 古籍原文库 | Page only | 页面浏览；没有通用 Headless handler |
| `knowledge_hub` | 中医知识库浏览 | Page only | 具体问答仍留在统一会话检索流程 |
| `medical_cases` | 医案库 | Page only | 打开检索页面；当前没有统一执行结果 handler |
| `almanac` | 每日黄历 | Page + Executed | builder 设置 `returnResultOnComplete: true` |
| `diagnosis_history` | 辨证历史趋势 | Page only | 查看历史页面；不产生新的诊断计算结果 |
| `critical_illness` | 重症课程资料 | Page only | 资料浏览，不是个体治疗执行 |
| `solar_terms` | 节气养生 | Page only | 资料浏览 |
| `yuxiaji_omen` | 玉匣灵兆 | Page only | 页面查询；未注册 Headless handler |
| `dream` | 周公解梦 | Page only | 页面查询；未注册 Headless handler |
| `guansha` | 小儿关煞 | Page only | 页面查询；未注册 Headless handler |
| `sanshan_lingqian` | 三山灵签 | Page only | 页面查询；未注册 Headless handler |
| `chenggu` | 袁天罡称骨 | Page only | 页面查询；未注册 Headless handler |
| `shousheng_debt` | 受生债 | Page only | 页面查询；未注册 Headless handler |
| `huangdi_siji` | 黄帝四季歌 | Page only | 页面查询；未注册 Headless handler |
| `saved_charts` | 已保存命盘 | Page only | 管理/查看历史数据，不是新计算 |

**Headless：0 项。** 当前没有证据表明上述 24 项中存在不打开 UI、直接返回结构化结果的独立能力执行器。

说明：`returnResultOnComplete: true` 证明页面具备回传设计，不等于每条页面路径都已完成真实执行/结果来源验收。实际是否返回有效值仍需逐项测试。

## 3. 参数与结果契约

### 参数

`AssistantToolArguments.validateAgainst()` 当前校验：
- toolId 一致；
- 不接受未声明参数；
- 必填参数非空；
- date 必须规范化为 `YYYY-MM-DD`；
- integer 可解析；
- choice 必须属于允许选项；
- text 类型没有长度/字符集/领域格式限制。

当前 `_argumentsFor()` 只为 `yunqi` 自动抽取日期；其余工具没有统一的自然语言参数抽取契约。快速入口如果不带参数，也会经过同一校验；因此不能绕过必填参数校验。

### 结果

`AssistantToolResult` 提供：
- `toolId`、`title`、`values`；
- `status`: SUCCEEDED / NO_RESULT / FAILED / CANCELLED；
- `arguments`：实际执行参数；
- `sourceIds`：来源标识；
- `disclaimer`：说明。

`validateFor()` 校验工具 ID、标题、成功结果是否有 values、sourceIds 和参数名是否为空；`validateArgumentsMatch()` 检查实际返回参数是否与调用参数完全一致。

缺口：
- `SUCCEEDED` 的 values 目前不保证每个工具都有明确字段 schema；
- sourceIds 为空可以通过校验，最终只显示 MISSING；
- 页面返回旧版字符串时会被包装成 `{'结果': ...}`，丢失结构化字段/来源；
- null 结果被归为 NO_RESULT，文案已明确说明无法区分取消与旧页面未实现回传；
- 参数 schema 不支持数值范围、互斥条件、依赖参数和来源约束。

## 4. ToolsScreen 与 AssistantToolRouter 的重复维护

`lib/screens/tools_screen.dart` 仍独立维护工具页面入口和标题/副标题/导航代码；`AssistantToolRouter` 又维护 24 项别名、动作词、模式和 builder。两处存在能力清单与导航元数据漂移风险。

不能直接让 ToolsScreen 完全依赖 AssistantToolRouter：部分工具是资料浏览、部分工具需要参数/返回结果，且两处当前有不同展示语义。应先建立单一元数据 manifest，再由两个 UI 消费。

## 5. Headless 抽取前必须补齐的证据

每个候选能力需要独立记录：
- toolId 与页面入口；
- 纯计算/查询函数及输入输出类型；
- 是否有副作用（写数据库、改偏好、保存命盘、文件/网络访问）；
- 结果来源/数据版本/时间戳；
- Page 路径与拟抽取 Headless 路径的输出对照；
- 参数缺失、边界、异常、取消、无结果测试；
- UI 结果回写和历史恢复兼容性。

只允许优先抽取纯函数、无 UI 依赖、无隐式副作用的确定性计算。资料浏览页面、用户确认型操作、写数据库操作不能仅因为“可自动化”就抽为 Headless。

## 6. 建议下一步（尚未执行）

1. 建立 `AssistantCapabilityManifest` 的只读清单测试，先覆盖 toolId 唯一性、ToolsScreen 入口覆盖、参数 schema 完整性。
2. 为 9 个 Page+Executed 页面逐一建立真实结果回传测试，检查 values/sourceIds/arguments/status。
3. 先抽一个纯函数候选（如剂量换算的单位换算核心）做 Page 与 Headless 双路径同输入输出对照；不改 UI 行为。
4. 其余能力按副作用与来源证据分类；没有行为基线不做大规模适配器抽取。

本审计不建议现在把 24 个页面统一重构为 Headless。当前最重要的是避免把“打开页面”误记为“能力已执行”，并防止工具目录/参数/结果契约继续漂移。
