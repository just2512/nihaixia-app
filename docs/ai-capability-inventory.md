# AI、问诊与全应用功能能力盘点

审计基线：`master` @ `fa586d52ddaa8bb7046b3ad1e0236b0c6ccd6fea`（2026-11-04）；增量复核至 `08da70cd5d728418f3ec511bd8ed51f2a68c9ed8`（2026-11-05）。
本文件只记录源码与测试能证明的现状；文档声明、静态布局测试和真实设备验收分开处理。状态采用 `EXISTS`、`PARTIAL`、`MISSING`、`UNKNOWN`，不以功能名称或 UI 文案代替验收。

## 1. 12 项计划落地矩阵

| # | 事项 | 状态 | 源码/测试证据 | 未关闭项 |
|---:|---|---|---|---|
| 1 | 合病规则可达性矩阵 | PARTIAL | `docs/combined-pattern-reachability-matrix.md`、`test/engine/combined_pattern_reachability_matrix_test.dart`、`test/engine/diagnostic_engine_test.dart` | 当前有效表 12 项；参数化矩阵对12项分别覆盖结构化主路径和旧兜底路径，`threeYangBase` 保持 UNREACHABLE。旧杂病兜底另发现小陷胸汤布尔优先级错误：单独滑脉曾可绕过胸痛门槛，已修正并新增正反向回归。仍需逐条补齐未满足/满足/未知/冲突四态与旧杂病入口穷举，并区分代码可达与医学适用性。 |
| 2 | 合病调用链修复 | PARTIAL | `CombinedPatternCondition` 集中 canonical 条件键；`DiagnosticEngine` 统一最终结果传播；`ChatScreen` 与 `TcmInterviewAdapter` 调用 `getRequiredCombinedPatternFollowUpQuestions()` | 第32、33、36、146、147、163、172、256条关键前提已有门槛或回归覆盖；追问与最终检测共用少阳/太阳/阳明/太阴证据计算；第172条有正向、阴性及未知回归；旧杂病胸痛/脉象条件已修复运算优先级。仍需补齐全部旧兜底组合及所有入口的一致性验证。 |
| 3 | 脉舌交叉验证 | EXISTS（自动化范围内） | `DiagnosticRules.canonicalPulse()`；`test/engine/pulse_tongue_cross_validation_test.dart`；`test/engine/combined_pattern_negative_reachability_test.dart`、`ChatScreen._showTonguePulseDialog()` | 已区分复合脉 canonical 值、单脉与主脉+兼脉；矛盾时追加饮水、小便、四肢等追问。第256条新增单脉拒绝、滑数/数滑双顺序回归；界面禁止无主脉或与主脉重复的兼脉选择，切换/清空主脉时清理失效兼脉。仍需验证真实问诊界面完整路径、用户无法判断脉象时的输入和设备体验。 |
| 4 | 脏腑独立证据层 | EXISTS（证据采集与展示） | `models/zangfu_evidence.dart`、`engine/zangfu_evidence_builder.dart`、`ChatScreen._showResult()`、`zangfu_evidence_builder_test.dart` | 结果页已展示原始问答、舌脉、来源及未知/未作答状态；不生成脏腑映射、证型或方剂。`organMappingStatus=MISSING` 是预期安全边界；后续只补可追溯证据，不自动诊断。 |
| 5 | 经典条文、医案关联 | PARTIAL | `docs/classic-and-medical-case-source-audit.md`、`ClassicSearchService`、`AssistantKnowledgeContextBuilder` | 已对部分条文做在线交叉核验和分类纠错；李心机2022译注本逐页书影、赵开美具体馆藏/刻次、卷页、异文与本地 manifest 未完成。医案逐案原始定位缺失；1257 与来源统计 1337 的差异未核清，医案—经典自动关联保持 MISSING。 |
| 6 | Find N2 内外屏适配 | PARTIAL | `docs/find-n2-adaptive-layout.md`、`docs/find-n2-fold-aware-layout.md`；`adaptive_home_navigation_test.dart`、`adaptive_master_detail_test.dart`、`local_ai_adaptive_content_test.dart`、`fold_aware_routes_test.dart` | 已有窗口断点、导航双面板、折痕/铰链安全区和窄屏换行回归。Find N2（PUG110）外屏、内屏、半折叠、键盘、相机、文件选择器、模型导入的实机截图与窗口指标仍为 MISSING。 |
| 7 | 本地 AI 与辨证问诊统一 | PARTIAL | 首页默认入口为 `LocalAiInterviewScreen`；`AssistantConversationOrchestrator` 将个人症状导向问诊；`structured_diagnosis` 工具打开 `ChatScreen(returnResultOnComplete: true)` | 用户入口和会话编排已统一，但规则问诊仍是独立页面/独立问答 UI，通过工具路由进入并把结果带回助手；尚非同一消息流中的原生交互卡片。附件与规则问诊的确认/回传边界需继续验证。 |
| 8 | 本地 AI 调用知识库和工具 | PARTIAL（知识检索与计算工具回传已接通部分路径） | `services/assistant_knowledge_context.dart`；`services/assistant_conversation_orchestrator.dart`；`screens/assistant_tool_router.dart`；`test/assistant_conversation_orchestrator_test.dart` | 学习与问诊文本可检索 App 内方剂、本草、针灸、穴位、内经、古籍及（学习域）医案；结果带来源和 MISSING 标记。统一助手工具注册表现有 23 个入口；五运六气、紫微、八字、易经、小六壬、梅花、剂量换算、时辰开穴、黄历等计算页配置 `returnResultOnComplete`，返回内容会追加到同一对话并重建本地模型上下文。只读资料页或未实现结构化回传的页面仍无法机器读取结果；工具调用仍是注册表匹配后打开既有页面，不是模型任意调用 Dart 函数。 |
| 9 | 设置入口 | EXISTS | `HomeScreen` 根导航含独立“设置”目的地；`home_screen_entry_test.dart` 断言设置可从根导航进入 | 当前已不依赖问诊页面内部入口；后续可继续优化设置分类与可发现性，不应把设置重新塞回聊天页。 |
| 10 | 全应用功能盘点与 AI 融合 | PARTIAL | 本文件；`README.md`、`HomeScreen`、`AssistantToolRouter` | 本轮先盘点本计划相关功能；尚未逐页完成全量功能、数据源、入口、重复能力、权限、持久化和 AI 可调用性清单。不得据此宣称全 App 设计重构完成。 |
| 11 | 单一主入口与统一调度 | PARTIAL（澄清后续路由已补） | `HomeScreen` 默认 AI 一级入口；`AssistantMode`（automatic/consultation/learning/tools/metaphysics）；`AssistantConversationOrchestrator`；`AssistantToolRouter.all`；`assistant_conversation_orchestrator_test.dart` | 统一助手覆盖 ToolsScreen 的 22 个页面/工具目的地，并包含独立结构化辨证入口，共 23 个注册工具；工具角色上下文动态读取注册表。已补排盘/起卦澄清后的短答案路由，例如用户回答“紫微斗数”可直接打开紫微工具；多个工具名同时出现时继续澄清，不随意选一个；学习语境优先于工具启动。路由仍是关键词/别名/动作词确定性匹配，未具备模型语义参数抽取、表单缺参追问、跨轮工具任务状态和多工具计划，不能称为完整通用 Agent。 |
| 12 | 对话历史持久化、续聊、批量删除 | PARTIAL（文本续聊完成；结构化任务快照已接入） | `AssistantConversationStore`、SQLite `assistant_conversations/assistant_messages/tcm_interview_tasks`；`assistant_history_screen.dart`；`assistant_history_resume_test.dart`；`test/models/tcm_interview_task_state_test.dart`；`test/chat_screen_task_resume_test.dart`；`.github/workflows/flutter-tests.yml` | 文本消息可持久化、选择历史继续并在原会话追加、批量删除。结构化问诊现可逐题保存引擎快照、题面与选项，并从历史入口恢复当前题；新增恢复/下一题保存 widget 回归，并加入 CI 独立门禁。仍未把每条结构化问答气泡逐条写入助手消息表，未实现单一对话气泡内的结构化任务卡；原始图片/录音附件不持久化；最新 CI 尚未取得可核验结果。 |

## 1A. 2026-11-05 增量复核与代码落地

本节记录 2026-11-04 审计基线之后的增量，不将尚未通过最新 CI 的改动标为 PASS。

- `master` 增量提交（最新源码提交 `08da70cd`；第256条测试提交 `2eab5d97`）：
  - `2a1a00e6`：补齐第172条追问路径使用的少阳证据分值。
  - `d52923bf`：将太阳、阳明、少阳、太阴四组证据分值抽为 `DiagnosticEngine` 共享 getter，追问资格判断与最终合病检测复用同一计算，消除重复实现漂移。
  - `1e0ea459`：新增 `test/engine/combined_pattern_followup_score_test.dart`，覆盖少阳证据达到门槛、单独恶心不足阈值，以及明确无下利/未知不得命中第172条呕吐方。
  - `422e182d`：新增 `test/engine/combined_pattern_negative_reachability_test.dart`，12项有效条件分别在结构化主路径与旧兜底路径覆盖相反证据和未知证据。
  - `2eab5d97`：补充第256条滑数脉边界，单滑、单数、重复同脉和未知脉象均拒绝命中；滑数/数滑两种录入顺序均覆盖。
  - `08da70cd`：问诊舌脉选择 UI 禁止无主脉、重复主兼脉，并在主脉变化时清理失效兼脉。
  - `e90cdaac` / `9c7758a5`：新增 `test/models/tcm_interview_task_state_test.dart`，覆盖结构化问诊快照的完整序列化往返、待回答问题与选项恢复字段、schema 版本拒绝及损坏数据拒绝。该测试只验证持久化模型契约，不代表 `ChatScreen` 已接入自动保存/恢复。
  - `a42fdff3`、`ee9ca969`：修正测试用例记录字段完整性，并将追问门槛注释放回对应方法。
- 变更范围：诊断引擎共享证据计算、两组新增合病回归测试及审计文档；未改数据库、依赖、Android 配置或诊断规则表。
- CI：`.github/workflows/flutter-tests.yml` 配置了 `push` 到 `master` 自动执行。此前可核验的 2026-11-04 两条工作流（run `41794913815`、`41794913787`）均已完成且成功，但它们对应旧审计基线 `fa586d52`，不能替代本次增量提交的 CI 结果。本次新提交的全量 Flutter/Android CI 状态暂记 `PENDING_VERIFICATION`，不提前标记通过。

- 当前 `master` 最新提交为 `3102db63`，包含第256条单脉拒绝与组合脉顺序测试，以及对应审计文档更新。GitHub App 当前可用的提交状态接口未返回 Actions run/check 数据；因此本轮新增测试尚未取得远端执行证据。不能用 2026-11-04 的历史成功结果替代本轮 CI。
- 其余 3—12 项仍沿用本文件所列状态；特别是统一助手仍通过独立页面启动结构化辨证/部分工具，附件原件仍未持久化，Find N2 真机验收仍缺少外屏/内屏/半折叠实测记录。

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


## 6. 结构化问诊快照接入（2026-11-06）

本轮将此前仅存在于模型/数据库层的任务快照接入 ChatScreen 与统一助手历史：

- ChatScreen 支持接收进行中的 TcmInterviewTaskState，恢复引擎输入快照及待回答问题。
- 对寒热辨经、舌脉输入、十问、寒热真假线索和引擎追问保存当前 prompt ID、原始题干与可见选项。
- 每次进入下一道题后向父页面回传快照；统一助手通过串行 SQLite 写入队列保存，避免较慢的旧写入覆盖新状态。
- 从历史记录选择会话时读取关联任务；存在 in_progress 任务且待回答问题可用时，显示“继续结构化问诊”入口。
- 任务完成时写入 completed，历史页不再把它作为待恢复任务。
- 无法重建题目的旧快照不会自动重置或覆盖原数据。

本轮实现边界：
- 这仍是从统一对话历史中打开的结构化问诊任务页，并非结构化问诊已完全变成同一聊天气泡内的交互卡片。
- 结构化问诊每题的原始消息气泡尚未逐条写入助手消息表；引擎答案本身保存在快照中，恢复时从待回答问题继续。
- 自动化测试和远端 CI 尚待本次提交触发后确认；在此之前标记为实现已提交、验证待完成，不标记为 PASS。
