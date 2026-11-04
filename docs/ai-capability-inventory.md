# AI、问诊与全应用功能能力盘点

审计基线：`master` @ `fa586d52ddaa8bb7046b3ad1e0236b0c6ccd6fea`（2026-11-04）。
本文件只记录源码与测试能证明的现状；文档声明、静态布局测试和真实设备验收分开处理。状态采用 `EXISTS`、`PARTIAL`、`MISSING`、`UNKNOWN`，不以功能名称或 UI 文案代替验收。

## 1. 12 项计划落地矩阵

| # | 事项 | 状态 | 源码/测试证据 | 未关闭项 |
|---:|---|---|---|---|
| 1 | 合病规则可达性矩阵 | PARTIAL | `docs/combined-pattern-reachability-matrix.md`、`test/engine/combined_pattern_regression_test.dart` | 当前有效表 15 项，14 项有检测器路径；`threeYangBase` 仍为 UNREACHABLE。主规则、旧六经兜底、旧杂病兜底虽有回归，但旧杂病入口仍非穷举。还要区分代码可达与医学适用性。 |
| 2 | 合病调用链修复 | PARTIAL | `CombinedPatternCondition` 集中条件键；`DiagnosticEngine` 在最终结果传播合病字段；`ChatScreen` 在最终 diagnose 前调用 `getRequiredCombinedPatternFollowUpQuestions()` | 第32、34、163、256条关键门槛已收紧；需继续覆盖全部旧兜底组合，并复核 `formula`、`recommendedFormulas`、`pattern`、`prescription` 一致性和所有入口。 |
| 3 | 脉舌交叉验证 | EXISTS（自动化范围内） | `DiagnosticRules.canonicalPulse()`；`pulse_tongue_cross_validation_test.dart` | 已区分复合脉 canonical 值、单脉与主脉+兼脉；矛盾时追加饮水、小便、四肢等追问。仍需验证真实问诊界面完整路径、用户无法判断脉象时的输入和设备体验。 |
| 4 | 脏腑独立证据层 | EXISTS（证据层） | `models/zangfu_evidence.dart`、`engine/zangfu_evidence_builder.dart`、`zangfu_evidence_builder_test.dart` | 当前只保存原始问答、舌脉与来源，不生成脏腑映射、证型或方剂；`organMappingStatus=MISSING` 是预期安全边界。若要展示，应只展示证据和未知项。 |
| 5 | 经典条文、医案关联 | PARTIAL | `docs/classic-and-medical-case-source-audit.md`、`ClassicSearchService`、`AssistantKnowledgeContextBuilder` | 已对部分条文做在线交叉核验和分类纠错；李心机2022译注本逐页书影、赵开美具体馆藏/刻次、卷页、异文与本地 manifest 未完成。医案逐案原始定位缺失；1257 与来源统计 1337 的差异未核清，医案—经典自动关联保持 MISSING。 |
| 6 | Find N2 内外屏适配 | PARTIAL | `docs/find-n2-adaptive-layout.md`、`docs/find-n2-fold-aware-layout.md`；`adaptive_home_navigation_test.dart`、`adaptive_master_detail_test.dart`、`local_ai_adaptive_content_test.dart`、`fold_aware_routes_test.dart` | 已有窗口断点、导航双面板、折痕/铰链安全区和窄屏换行回归。Find N2（PGU110）外屏、内屏、半折叠、键盘、相机、文件选择器、模型导入的实机截图与窗口指标仍为 MISSING。 |
| 7 | 本地 AI 与辨证问诊统一 | PARTIAL | 首页默认入口为 `LocalAiInterviewScreen`；`AssistantConversationOrchestrator` 将个人症状导向问诊；`structured_diagnosis` 工具打开 `ChatScreen(returnResultOnComplete: true)` | 用户入口和会话编排已统一，但规则问诊仍是独立页面/独立问答 UI，通过工具路由进入并把结果带回助手；尚非同一消息流中的原生交互卡片。附件与规则问诊的确认/回传边界需继续验证。 |
| 8 | 本地 AI 调用知识库和工具 | PARTIAL（工具目录已补齐） | `services/assistant_knowledge_context.dart`；`services/assistant_conversation_orchestrator.dart`；`screens/assistant_tool_router.dart`；`test/assistant_conversation_orchestrator_test.dart` | 学习与问诊文本可检索 App 内方剂、本草、针灸、穴位、内经、古籍及（学习域）医案；结果带来源和 MISSING 标记。2026-11-04 新增注册 ToolsScreen 中此前未接入的诊断历史、闭门课重症、节气养生、玉匣灵兆、解梦、关煞、灵签、称骨、受生债、黄帝四季歌、命盘库；统一助手工具注册表现有 23 个入口，工具/玄学提示词从注册表动态生成。仍由本地关键词/动作词确定性路由，工具实际执行打开既有页面，不是模型任意调用 Dart 函数；部分页面没有结构化结果回传，只能返回“已打开”说明。 |
| 9 | 设置入口 | EXISTS | `HomeScreen` 根导航含独立“设置”目的地；`home_screen_entry_test.dart` 断言设置可从根导航进入 | 当前已不依赖问诊页面内部入口；后续可继续优化设置分类与可发现性，不应把设置重新塞回聊天页。 |
| 10 | 全应用功能盘点与 AI 融合 | PARTIAL | 本文件；`README.md`、`HomeScreen`、`AssistantToolRouter` | 本轮先盘点本计划相关功能；尚未逐页完成全量功能、数据源、入口、重复能力、权限、持久化和 AI 可调用性清单。不得据此宣称全 App 设计重构完成。 |
| 11 | 单一主入口与统一调度 | PARTIAL（目录覆盖扩展） | `HomeScreen` 默认 AI 一级入口；`AssistantMode`（automatic/consultation/learning/tools/metaphysics）；`AssistantConversationOrchestrator`；`AssistantToolRouter.all`；`assistant_conversation_orchestrator_test.dart` | 统一助手已覆盖 ToolsScreen 的 22 个页面/工具目的地，并包含独立结构化辨证入口，共 23 个注册工具；工具角色上下文动态读取注册表。路由仍是关键词/动作词确定性匹配，工具操作以卡片按钮启动既有页面，部分工具不回传机器可读结果；未具备语义参数抽取、表单缺参追问、跨轮工具任务状态和多工具计划，不能称为完整通用 Agent。 |
| 12 | 对话历史持久化、续聊、批量删除 | EXISTS（文本会话） | `AssistantConversationStore`、SQLite `assistant_conversations/assistant_messages`；`assistant_history_screen.dart`；`assistant_history_resume_test.dart`、`assistant_history_screen_test.dart` | 文本消息可持久化、选择历史继续并在原会话追加、批量删除。原始图片/录音附件不持久化，只保留附件说明；历史模型上下文受长度上限约束。 |

## 2. 当前统一助手的数据流

```text
HomeScreen（默认 AI 一级入口）
  -> LocalAiInterviewScreen（唯一常驻对话与会话历史）
     -> AssistantConversationOrchestrator.resolve()
        -> consultation：E4B 澄清 + 本地知识检索（参考上下文）
        -> learning：E4B 学习解释 + 本地知识检索
        -> tools/metaphysics：AssistantToolRouter 精确注册表
           -> 打开既有 App 工具页面
           -> 返回结果写入当前会话并恢复模型上下文
        -> structured_diagnosis：打开 ChatScreen 规则问诊
           -> DiagnosticEngine / DiagnosticRules
           -> 返回规则结果给助手对话
     -> AssistantConversationStore（SQLite 历史）
     -> SettingsScreen（根导航独立入口）
```

必须保持的职责边界：

1. E4B 负责自然语言理解、澄清、摘要和知识解释；不能直接给出自动六经诊断、处方或药量。
2. DiagnosticEngine 是结构化辨证结果的唯一计算来源；模型摘要不得自动回写问诊答案。
3. 知识库检索结果是引用上下文，不是个体诊断证据。每条内容应携带来源类型、内部定位和版本状态；缺失字段明确显示 MISSING。
4. 术数工具只由 App 内置确定性计算页面执行。模型不得编造排盘结果，也不得将民俗推算包装为科学预测。
5. 未确认的用户信息、模型推断、未知回答不能转成阳性/阴性证据；写入诊断输入必须经过用户确认。

## 2A. 统一助手与实用工具目录核对（2026-11-04）

ToolsScreen 中原有的业务目的地已纳入 `AssistantToolRouter` 注册表，且 `quickActions(mode)` 与工具/玄学角色提示词均读取同一注册表，避免提示词列出的工具和可执行路由出现两份手工清单。

| 工具域 | 已注册目的地 |
|---|---|
| 问诊/记录 | 结构化辨证问诊、诊断历史趋势 |
| 中医知识 | 五运六气、经方剂量换算、时辰开穴、古籍原文、医案库、闭门课重症资料、节气养生 |
| 术数/民俗 | 紫微斗数、八字、易经、小六壬、梅花易数、每日黄历、玉匣灵兆、周公解梦、小儿关煞、三山国王灵签、称骨、受生债、黄帝四季歌 |
| 资料管理 | 我的命盘库 |

测试新增：
- 注册工具 ID 唯一性与完整目录覆盖。
- 11 个此前未接入助手的工具意图路由。
- 玄学工具与医学问诊角色边界。

限制：工具目录覆盖不等于工具计算已经嵌入对话气泡。当前通过统一助手卡片打开既有页面；能返回字符串的工具回传结果，其他页面回到对话时只能记录页面已打开。下一阶段需给可计算工具定义统一输入 schema、结果 schema 和取消/失败状态，并逐个接入结构化回传。

## 3. 当前 CI 验收状态

最新提交 `fa586d52ddaa8bb7046b3ad1e0236b0c6ccd6fea` 对应：

- [Flutter tests](https://github.com/just2512/nihaixia-app/actions/runs/41794913815)：**SUCCESS**。Dart/Flutter 静态分析、local AI contract、录音/照片生命周期、模型状态与串行控制、历史续聊、全量回归均通过；独立 Android debug APK 构建、ABI/SHA-256 校验、Android local unit tests 和 APK 上传均通过。
- [Flutter Quality Gate #243](https://github.com/just2512/nihaixia-app/actions/runs/41794913787)：静态分析 PASS；历史续聊回归 PASS；Dart 全量测试 PASS；Android native unit tests 步骤仍显示 `in_progress`，该 run 的更新时间停留在 2026-11-04 07:50:24Z；Find N2 arm64 Debug APK 步骤尚未开始。

因此，独立 Flutter tests 工作流已完整通过，且独立 Android APK 与 native tests 已通过；Quality Gate #243 仍未给出最终结论。以上均为 CI 自动化结果，不等于 OPPO Find N2 真机验收。

## 4. 下一步执行顺序与硬门槛

1. 完成两条当前 CI 的最终结果；若失败，先定位具体失败步骤，区分代码失败与 runner/依赖基础设施失败。
2. 合病矩阵逐条转为可执行参数化测试：每个条件至少覆盖“未满足/满足/未知/冲突”，并明确 RuleEngine 主路径、旧六经兜底、旧杂病兜底；`threeYangBase` 保持 UNREACHABLE，除非补足经典依据和用户可回答的必要条件。
3. 把“合病/并病/兼证/关联方证/来源待核”变成显式来源分类；不得因代码命中而把关联方证升级为仲景原文明确合病。
4. 将结构化辨证逐题流程改造成统一助手会话中的可交互任务卡/步骤状态；完成前保留现有独立页面作为受控工具，不做破坏性删除。
5. 对 AssistantToolRouter 建立完整工具能力清单、实体参数 schema、缺参追问、确认边界、执行结果结构和失败回退；当前关键词匹配只作为第一层路由，不作为最终 Agent 能力。
6. 补齐知识检索的可追溯来源字段和分域策略；医案没有稳定原始来源 ID 时继续排除自动证据引用。
7. 全应用功能盘点覆盖所有一级入口、二级页面、设置、搜索、收藏、历史、工具、权限、存储和 AI 调用能力，并标记重复入口与无入口能力。
8. Find N2 实机验收必须提供外屏/内屏/半折叠的真实截图、dp 尺寸、displayFeatures、键盘/相机/文件选择器/模型导入记录。Widget 测试不能替代真机验收。

## 5. 验收状态原则

- `PASS`：有对应源码、自动化测试或真实设备记录，且测试确实执行成功。
- `PARTIAL`：主路径存在，但覆盖、来源、设备或交互边界仍缺失。
- `MISSING`：没有可核验实现或证据。
- `UNKNOWN`：现有接口/工具无法确认，不能按通过处理。

本文件是审计基线，不是对未完成事项的豁免。任何状态变更都必须附对应代码路径、测试名称/结果或设备验收记录。
