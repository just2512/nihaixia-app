# AI、问诊与全应用功能能力盘点

审计基线：`master` @ `fa586d52ddaa8bb7046b3ad1e0236b0c6ccd6fea`（2026-11-04）；增量复核至 `08da70cd5d728418f3ec511bd8ed51f2a68c9ed8`（2026-11-05）。
本文件只记录源码与测试能证明的现状；文档声明、静态布局测试和真实设备验收分开处理。状态采用 `EXISTS`、`PARTIAL`、`MISSING`、`UNKNOWN`，不以功能名称或 UI 文案代替验收。

## 1. 12 项计划落地矩阵

| # | 事项 | 状态 | 源码/测试证据 | 未关闭项 |
|---:|---|---|---|---|
| 1 | 合病规则可达性矩阵 | PARTIAL | `docs/combined-pattern-reachability-matrix.md`、`test/engine/combined_pattern_reachability_matrix_test.dart`、`test/engine/diagnostic_engine_test.dart`、`test/engine/three_yang_clause268_gate_test.dart` | 当前有效表 12 项；参数化矩阵对12项分别覆盖结构化主路径和旧兜底路径，`threeYangBase` 保持 UNREACHABLE。旧杂病兜底小陷胸汤布尔优先级已修正；第268条已增加浮+大组合脉及专业人员确认“上关上”的严格门槛，缺失/未知不标记三阳合病。仍需补齐未满足/满足/未知/冲突四态与旧杂病入口穷举，并区分代码可达与医学适用性。 |
| 2 | 合病调用链修复 | PARTIAL | `CombinedPatternCondition` 集中 canonical 条件键；`DiagnosticEngine` 统一最终结果传播；`ChatScreen` 与 `TcmInterviewAdapter` 调用 `getRequiredCombinedPatternFollowUpQuestions()` | 第32、33、36、146、147、163、172、256条关键前提已有门槛或回归覆盖；追问与最终检测共用证据计算；第172条有正向、阴性及未知回归；第268条新增脉象位置确认追问，三阳证据分支优先于重叠的两经追问；旧杂病胸痛/脉象条件已修复运算优先级。仍需补齐全部旧兜底组合及所有入口的一致性验证。 |
| 3 | 脉舌交叉验证 | EXISTS（自动化范围内） | `DiagnosticRules.canonicalPulse()`；`test/engine/pulse_tongue_cross_validation_test.dart`；`test/engine/combined_pattern_negative_reachability_test.dart`、`ChatScreen._showTonguePulseDialog()` | 已区分复合脉 canonical 值、单脉与主脉+兼脉；矛盾时追加饮水、小便、四肢等追问。第256条新增单脉拒绝、滑数/数滑双顺序回归；界面禁止无主脉或与主脉重复的兼脉选择，切换/清空主脉时清理失效兼脉。仍需验证真实问诊界面完整路径、用户无法判断脉象时的输入和设备体验。 |
| 4 | 脏腑独立证据层 | EXISTS（证据采集与展示） | `models/zangfu_evidence.dart`、`engine/zangfu_evidence_builder.dart`、`ChatScreen._showResult()`、`zangfu_evidence_builder_test.dart` | 结果页已展示原始问答、舌脉、来源及未知/未作答状态；不生成脏腑映射、证型或方剂。`organMappingStatus=MISSING` 是预期安全边界；后续只补可追溯证据，不自动诊断。 |
| 5 | 经典条文、医案关联 | PARTIAL | `docs/classic-and-medical-case-source-audit.md`、`ClassicSearchService`、`AssistantKnowledgeContextBuilder` | 已对部分条文做在线交叉核验和分类纠错；李心机2022译注本逐页书影、赵开美具体馆藏/刻次、卷页、异文与本地 manifest 未完成。医案逐案原始定位缺失；1257 与来源统计 1337 的差异未核清，医案—经典自动关联保持 MISSING。 |
| 6 | Find N2 内外屏适配 | PARTIAL（首批排盘表单已响应式调整） | `docs/find-n2-adaptive-layout.md`、`docs/find-n2-fold-aware-layout.md`；`adaptive_home_navigation_test.dart`、`adaptive_master_detail_test.dart`、`local_ai_adaptive_content_test.dart`、`fold_aware_routes_test.dart`；`test/bazi_foldable_layout_test.dart` | 已有窗口断点、导航双面板、折痕/铰链安全区和窄屏换行回归；八字排盘的生辰输入卡与地点行现采用 720dp 最大内容宽度，外屏占满可用宽度、内屏居中限宽，并新增 402dp/840dp widget 测试。其他排盘/知识页面仍需逐页布局审计；Find N2（PUG110）外屏、内屏、半折叠、键盘、相机、文件选择器、模型导入的实机截图与窗口指标仍为 MISSING。 |
| 7 | 本地 AI 与辨证问诊统一 | PARTIAL（统一消息时间线主路径已实现） | `LocalAiInterviewScreen._requestTool()` / `_openTool()` 对 `structured_diagnosis` 拦截并调用 `_startInlineTcmInterview()`；`_appendTcmInterviewMessages()` 将题目、选项、用户回答和结果写入共用 `_messages` 与 SQLite `assistant_messages`；`TcmInterviewConversationController` 使用 `DiagnosticEngine` | 常规结构化问诊已在本地 AI 主对话内联进行，不再跳转独立 ChatScreen；规则计算仍由确定性引擎负责。仍需清理注册表旧 ChatScreen builder 兼容残留，并补齐跨重启/跨会话恢复一致性、完成态回看与附件生命周期。 |
| 8 | 本地 AI 调用知识库和工具 | PARTIAL（知识检索已接入；工具仍以页面适配器执行） | `AssistantKnowledgeContextBuilder.buildAsync()`；`AssistantToolRouter` 23 项注册表；`LocalAiInterviewScreen._openTool()` 接收返回字符串并追加到当前消息流、重建模型上下文 | 中医知识以检索上下文注入，不等于结构化诊断证据；医案来源不明时标记 MISSING。工具尚无统一 typed args/result schema、参数抽取与缺参追问、可取消执行器、统一错误/状态协议；模型不能任意直接调用 Dart 函数。 |
| 9 | 设置入口 | EXISTS | `HomeScreen` 根导航含独立“设置”目的地；`home_screen_entry_test.dart` 断言设置可从根导航进入 | 当前已不依赖问诊页面内部入口；后续可继续优化设置分类与可发现性，不应把设置重新塞回聊天页。 |
| 10 | 全应用功能盘点与 AI 融合 | PARTIAL | 本文件；`README.md`、`HomeScreen`、`AssistantToolRouter` | 本轮先盘点本计划相关功能；尚未逐页完成全量功能、数据源、入口、重复能力、权限、持久化和 AI 可调用性清单。不得据此宣称全 App 设计重构完成。 |
| 11 | 单一主入口与统一调度 | PARTIAL（澄清状态可持久化） | `HomeScreen` 默认 AI 一级入口；`AssistantMode`（automatic/consultation/learning/tools/metaphysics）；`AssistantConversationOrchestrator`；`AssistantToolRouter.all`；`assistant_conversation_orchestrator_test.dart` | 统一助手覆盖 ToolsScreen 的 22 个页面/工具目的地，并包含独立结构化辨证入口，共 23 个注册工具；工具角色上下文动态读取注册表。已补排盘/起卦澄清后的短答案路由，并显式保存 `tool_choice=true` 状态，只有处于待选工具澄清时才允许别名启动工具；该状态随历史消息恢复，取消、学习问题和个人症状可结束待选状态；多个工具名同时出现时继续澄清。路由仍是关键词/别名/动作词确定性匹配，未具备模型语义参数抽取、表单缺参追问、跨轮工具任务状态和多工具计划，不能称为完整通用 Agent。 |
| 12 | 对话历史持久化、续聊、批量删除 | PARTIAL（普通与结构化问诊消息均写入历史；附件原件未持久化） | `AssistantConversationStore`、SQLite `assistant_conversations/assistant_messages/tcm_interview_tasks`；`_appendTcmInterviewMessages()` 同时写入逐题消息与 `TcmInterviewTaskState`；`_openHistory()` 恢复消息和任务快照 | 结构化问诊题目、选项、回答和结果已作为普通 user/assistant 消息写入统一历史，并另存引擎快照恢复待答状态。仍需验证跨重启/跨会话恢复、消息与快照一致性及完成任务回看；图片/录音附件原件未持久化。 |

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
- CI：当前 `master` HEAD 为 `c83993b17749f3380b7164882a88b86175a63fca`。2026-11-06 对应的 Flutter tests run `42153999654` 与 Flutter Quality Gate run `42153999821` 均已完成并为 `success`。Flutter regression tests、Android debug APK、Dart 静态分析、完整 Dart suite、Android native unit tests 和 arm64 Debug APK 构建均通过。CI 结果仅证明该 SHA 的自动化检查通过，不等于 OPPO Find N2 真机验收。
- 当前 `master` 分支 HEAD 与最新两条工作流的 `head_sha` 一致；旧 SHA 的取消/失败运行不覆盖当前 SHA 的成功结果。
- Fork 与上游分支关系已更新为 781 ahead / 29 behind；未执行 Sync fork 或合并。完整潜在冲突清单仍需基于完整三方 diff 穷举，不能把 compare API 的截断文件列表当作最终结果。
- 其余未完成事项仍保持 `PARTIAL` / `MISSING`：经典与医案逐条来源校勘、Find N2 真机验收、工具统一参数/执行协议、问诊完全内联到同一聊天消息流、全 App 逐页功能盘点及附件原件持久化。

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


## 6A. 统一问诊消息流源码复核（2026-11-06）

本节按当前 `master` 源码纠正第 7、12 项的过时描述，不能继续把结构化问诊说成仍完全独立于助手对话：

- `LocalAiInterviewScreen._requestTool()` 对 `structured_diagnosis` 有专门分支，直接调用 `_startInlineTcmInterview()`；`_openTool()` 也有同样拦截。因此主入口不是通过注册表 builder 跳转到 `ChatScreen`。
- `_appendTcmInterviewMessages()` 把问诊中的用户回答、助手题目、选项和结果追加到与本地 AI 共用的 `_messages` 时间线；待答选项由同一消息气泡的交互选项承载。
- 每次追加的问诊消息会写入 SQLite `assistant_messages`；同时另存 `TcmInterviewTaskState`，保存 DiagnosticEngine 快照、待答题目、选项和 transcript，以便恢复确定性问诊状态。
- `AssistantToolRouter` 中仍保留 `structured_diagnosis` 的旧 `ChatScreen` builder，但主入口分支会先拦截它。它是兼容残留，不代表当前主流程；后续应删除或明确隔离，防止未来调用绕过统一消息流。
- 因此，第 7 项已完成“同一入口、同一消息时间线、同一确定性辨证引擎”的主路径，整体仍标记 PARTIAL：任务恢复一致性、完成态回看、附件原件生命周期和旧入口清理尚未闭合。
- 第 12 项的旧描述“结构化 transcript 目前存于任务快照而非 assistant_messages”不准确：当前逐条问诊消息也已写入 `assistant_messages`。仍需验证消息表与任务快照跨重启的一致性；图片/录音附件原件尚未持久化。
- 第 8、11 项仍为 PARTIAL：知识库以检索上下文方式注入，不等同于结构化证据；工具注册表虽有 23 个目的地，但尚无统一 typed args/result schema、参数抽取与缺参追问、可取消执行器及统一错误协议。关键词匹配不能称为完整 Agent。

当前 HEAD `83e4cfdcbee2aca3fcced3787e8086dabfaf4bc7` 对应的 Flutter regression tests + Android debug APK（run `42166190983`）和 Flutter Quality Gate（run `42166197546`）均已 SUCCESS。自动化通过不替代 Find N2 真机折叠屏验收，也不替代古籍版本及医案逐案来源校勘。

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
- 结构化问诊的角色、文本和结果标记现随任务快照保存为 transcript，恢复后可查看此前问答；该 transcript 仍独立于 assistant_messages，不是同一聊天流内的原生消息卡。
- 自动化测试和远端 CI 尚待本次提交触发后确认；在此之前标记为实现已提交、验证待完成，不标记为 PASS。


---

## 7. 2026-11-10 全局 AI 调用链复核（基线更新）

> 本节是 2026-11-10 对当前 master 的重新读取，优先于上文 2026-11-04 至 11-06 的历史状态描述。审计基线：`1a1b30cb751bd9a2f332d99f89ca633e2398e801`；`pubspec.yaml` 版本 `1.11.30+8039`。本节只对明确读取的文件作结论；未逐页检查的底层算法仍标 UNKNOWN。

### 7.1 核心调用链结论

| 阶段 | 当前状态 | 最新源码证据与判断 |
|---|---|---|
| S1 输入 | PARTIAL | 文字/图片/音频通过统一 LocalAiInterviewScreen 和 MainActivity MethodChannel 接入；详情页可传 initialPrompt。见 `local_ai_interview_screen.dart:119-168,245-259`、`MainActivity.kt:82-126`。附件输入主要是音频转写/图片可见特征描述，不等于完整的跨模态任务规划。 |
| S2 安全前置 | PARTIAL；确定性红旗拦截 MISSING | 红旗仅在 systemInstruction 中要求模型处理，见 `MainActivity.kt:42-66`。Orchestrator 和 `_send()` 前置路径未见确定性红旗检查，见 `assistant_conversation_orchestrator.dart:121-203,206-340`、`local_ai_interview_screen.dart:2096-2215`。 |
| S3 意图理解 | PARTIAL | 当前 Orchestrator 是固定 cue/alias/actionWords 匹配；没有模型语义规划。见 `assistant_conversation_orchestrator.dart:24-31,32-119,121-203,206-340`。参数提取目前仅对 yunqi 日期做正则处理，见 102-119 行。 |
| S4 任务规划 | MISSING（通用任务）；问诊专用状态 EXISTS | 有 `TcmInterviewTaskState` 和 `TcmInterviewConversationController`，但仅服务规则问诊；未发现通用 TaskPlan/ActiveTaskFrame。见 `tcm_interview_task_state.dart:41-83`、`tcm_interview_conversation_controller.dart:9-105`、`database_helper.dart:176-184`。 |
| S5 业务调用 | PARTIAL | ToolRouter 24 项注册，其中 structured_diagnosis 在对话页内联执行；其余 23 项均注册为 Widget builder。见 `assistant_tool_router.dart:155-435,489-526`。目前没有统一 Headless execute 接口。 |
| S6 结果验证 | PARTIAL | 工具参数校验、AssistantToolResult 校验和来源反查已经存在；但不是所有能力都有统一 typed result/provenance。见 `assistant_tool_router.dart:67-126`、`local_ai_interview_screen.dart:1665-1719`、`assistant_knowledge_context.dart:16-45,81-170`。 |
| S7 模型综合 | PARTIAL | 模型在当前主链主要接收 prompt/context 后生成文本；学习/问诊/自动模式注入检索上下文，工具/玄学模式仅注入工具清单和页面执行说明。见 `local_ai_interview_screen.dart:771-880`。未发现模型结构化规划或原生工具调用。 |
| S8 结果呈现 | PARTIAL | 工具页返回结果可进入消息流；来源 ID 可深链到部分知识详情页；部分经典章节仍只能打开书库。见 `local_ai_interview_screen.dart:1493-1610,1628-1758`。缺少所有业务能力共用的结果卡片协议。 |
| S9 状态/安全 | PARTIAL | SQLite v7 有会话、消息和问诊任务；消息正文存储于 assistant_messages.content。见 `database_helper.dart:25-42,149-184,384-432`。本轮未见 SQLCipher 依赖；Android Keystore/备份排除/附件缓存全量清除仍需专项审计。 |

### 7.2 五种模式当前真实行为

| 模式 | 实际链路 | 当前能力判断 |
|---|---|---|
| 自动调度 | L0 cue/alias/actionWords 识别；单工具命中后产生“打开工具”操作；多工具命中要求用户选一个；其他情况进入知识检索/文本生成 | PARTIAL：不是语义 Agent，不会把复合需求拆成多个任务并自动执行 |
| 问诊助手 | E4B 负责自由文本澄清；用户明确启动结构化问诊后，转入确定性 TcmInterviewConversationController/DiagnosticEngine | PARTIAL：规则问诊真实存在；自由文本不会自动写成规则答案，当前没有通用症状槽位追问器 |
| 学习助手 | 当前输入触发本地检索，检索文本和来源状态注入 E4B prompt，再输出文本 | PARTIAL：检索已实现，教学规划、主动测验、学习进度管理未发现 |
| 工具助手 | E4B 只收到已注册工具名称和“实际计算由 App 页面执行”的提示；用户点击按钮后打开页面；页面返回结果后写入会话 | PARTIAL：有人工触发的页面执行与结果回传；无模型自动调用 Headless 能力 |
| 玄学大师 | E4B 收到工具清单和禁止编造排盘的提示；命中工具后由用户点击进入排盘/起卦页面；部分页面可回传结构化结果 | PARTIAL：真实算法页面存在，但模型没有直接读取/调用算法结果的统一执行接口，缺参收集也不完整 |

模式 prompt 位置：`assistant_tool_router.dart:27-44`。实际模式 context 构造位置：`local_ai_interview_screen.dart:771-880`。路由位置：`assistant_conversation_orchestrator.dart:121-340`。

### 7.3 ToolRouter 24 项登记清单

以下是当前 `AssistantToolRouter._all` 的完整登记项（24 项），不是“24 个 Headless 能力”。`structured_diagnosis` 由对话页特殊处理；其余均通过页面 builder。工具定义行号见 `lib/screens/assistant_tool_router.dart:155-435`，builder 行号见 489-526。

| ID | 名称 | 当前入口形态 | Headless 结论 |
|---|---|---|---|
| structured_diagnosis | 结构化辨证问诊 | 对话页内联 TcmInterviewConversationController | NEEDS_ADAPTER：已有纯业务 Controller/Adapter，但必须维持用户确认和 DiagnosticEngine 边界 |
| yunqi | 五运六气推算 | YunQiScreen，日期参数可传入，页面可回传结果 | NEEDS_ADAPTER：已有 YunqiEngine，尚未完成调用契约审计 |
| ziwei | 紫微斗数排盘 | ZiweiChartScreen，页面可回传结果 | NEEDS_ADAPTER：已有 ZiweiEngine，尚未完成输入输出契约审计 |
| bazi | 八字排盘 | BaZiPaipanScreen，页面可回传结果 | NEEDS_ADAPTER：已有 BaziService/bazi_core，尚未完成调用契约审计 |
| yijing | 易经起卦 | YiJingScreen，页面可回传结果 | UNKNOWN：页面底层计算边界待审 |
| xiaoliuren | 小六壬起课 | XiaoliurenScreen，页面可回传结果 | UNKNOWN：页面底层计算边界待审 |
| meihua | 梅花易数起卦 | MeihuaScreen，页面可回传结果 | UNKNOWN：页面底层计算边界待审 |
| dosage | 经方剂量换算 | DosageConverterScreen，页面可回传结果 | UNKNOWN：需检查计算是否已抽成纯 Dart 服务 |
| ziwu_liuzhu | 时辰开穴计算 | ZiWuLiuZhuScreen，页面可回传结果 | NEEDS_ADAPTER：已有 ZiwuliuzhuEngine，尚未完成调用契约审计 |
| guji_library | 古籍原文 | GujiLibraryScreen | NEEDS_ADAPTER：已有 GujiRepository/ClassicSearchService，可复用但需统一结果结构 |
| knowledge_hub | 中医知识库浏览 | KnowledgeScreen | NEEDS_ADAPTER：已有知识 Repository，不能用打开浏览页代替 AI 检索 |
| medical_cases | 医案库检索 | MedicalCaseLibraryScreen | NEEDS_ADAPTER：已有医案数据服务，需核对来源字段和查询边界 |
| almanac | 每日黄历 | DailyAlmanacScreen，页面可回传结果 | NEEDS_ADAPTER：已有 LunarAlmanacService，需核对纯函数接口 |
| diagnosis_history | 诊断历史趋势 | DiagnosisHistoryScreen | BLOCKED：个人健康数据需单独授权和最小化读取 |
| critical_illness | 闭门课重症资料 | CriticalIllnessListScreen | NEEDS_ADAPTER：只读资料能力；不得生成个体治疗建议 |
| solar_terms | 节气养生 | SolarTermSectionScreen | NEEDS_ADAPTER：需抽取结构化查询能力 |
| yuxiaji_omen | 玉匣灵兆 | YuxiajiOmenScreen | UNKNOWN：底层数据/算法边界待审 |
| dream | 周公解梦 | DreamScreen | NEEDS_ADAPTER：已有 dream_data，需核对检索实现 |
| guansha | 小儿关煞 | GuanshaScreen | UNKNOWN：底层算法边界待审 |
| sanshan_lingqian | 三山国王灵签 | SanshanLingqianScreen | UNKNOWN：抽签状态与数据边界待审 |
| chenggu | 袁天罡称骨 | ChengguBoneScreen | NEEDS_ADAPTER：已有 chenggu_data，需核对计算边界 |
| shousheng_debt | 受生债查询 | ShoushengDebtScreen | NEEDS_ADAPTER：已有 shousheng_data，需核对计算边界 |
| huangdi_siji | 轩辕黄帝四季歌 | HuangdiSijiScreen | NEEDS_ADAPTER：已有数据资产，需抽取查询接口 |
| saved_charts | 我的命盘库 | SavedChartsScreen | BLOCKED：生辰资料属于个人数据，需显式授权后开放 |

**重要限定：** NEEDS_ADAPTER 表示已有可复用的业务数据/服务线索，但尚未证明当前已具备符合统一契约的 Headless 接口；UNKNOWN 表示没有逐页检查底层实现。不得将以上估计写成已完成的底层代码审计。ToolRouter 本身没有 `execute(args)` 或等价 Headless executor。

### 7.4 多轮异常恢复：源码与文档存在不一致

- `MainActivity.sendLocalMessage()` 在空回复时尝试重建 CPU Engine/Conversation，再发送同一个本轮 `modelInput`：`MainActivity.kt:400-427`。
- `sendWithFirstTurnGpuFallback()` 对非首轮异常也尝试重建 CPU Engine；重建成功后只对新 Conversation 发送当前 `send` 闭包内容：`MainActivity.kt:430-479`。
- `recreateCpuEngineAfterFirstTurnOpenClFailure()` 先 detach/关闭旧 Conversation 与 Engine，再创建全新的 CPU Engine/Conversation：`MainActivity.kt:490-558`。
- 新 Conversation 只初始化 systemInstruction；该恢复路径没有接收或回填 Flutter transcript。因此多轮异常后会丢失模型内部历史，而 UI/SQLite 仍保留历史。
- CPU 重试失败时当前代码抛出原始异常，CPU retry 错误作为局部变量没有成为最终主错误，诊断信息可能不完整：`MainActivity.kt:466-479`。
- 以上代码行为与 `docs/local-ai-e4b.md:48-50,85-86,96` 所述“仅首轮 OpenCL 错误回退；多轮故障不自动重放”不一致。应以当前代码为准，修正文档或代码策略，不可只改文档掩盖实际行为。
- 真机 state:7、空回复、CPU 重建、连续轮次是否稳定：UNKNOWN。自动化策略测试不能替代 Find N2 实测。

### 7.5 关键文件与测试覆盖

已确认存在的相关测试：
- 路由：`test/assistant_conversation_orchestrator_test.dart`、`test/assistant_tool_router_test.dart`、`test/assistant_tool_registry_build_test.dart`。
- 工具结果回传：`test/assistant_tool_result_test.dart`、`test/assistant_tool_result_handoff_test.dart`。
- 知识检索与溯源：`test/assistant_knowledge_context_test.dart`、`test/assistant_provenance_integration_test.dart`、`test/classic_search_backlink_test.dart`。
- 本地模型 UI/服务：`test/local_ai_interview_screen_test.dart`、`test/local_ai_service_test.dart`。
- 规则问诊：`test/services/tcm_interview_conversation_controller_test.dart`、`test/tcm_interview_adapter_test.dart`、`test/models/tcm_interview_task_state_test.dart`。
- 原生模型策略：`android/app/src/test/kotlin/com/nihaisha/nihaisha_app/FirstTurnGpuFallbackPolicyTest.kt` 等。

测试文件存在不等于每一项端到端行为已覆盖；需逐项核对断言和执行记录。当前审计时 master 最新 commit 的 GitHub combined status 为 `pending`，statuses 为空；本轮不能宣称 CI PASS。

### 7.6 必须修正的审计口径

1. 当前 ToolRouter 有 **24 个注册项**，不是 23 个；其中 1 个结构化问诊特殊处理、23 个页面 builder。
2. 工具结果并非完全不能回到对话：页面结果可校验、保存、恢复模型上下文；缺口是必须由用户手动点击页面执行，模型没有 Headless 直接调用权。
3. 不可仅凭 Widget builder 断言底层算法全部写在 Widget State；必须检查 Screen 调用的 Service/Repository/Engine。
4. 原 Headless readiness 四类状态不足以表达未检查项，必须允许 UNKNOWN。
5. “每轮最多一次模型调用”只能作为端侧性能目标，不能作为绝对硬约束。确定性路由/模板任务可以 0 次模型规划调用；复杂语义任务可用一次结构化规划；需要解释时再调用一次综合生成。必须根据 E4B 实测耗时、token/context 限制和错误率决定是否合并阶段。
6. `ActiveTaskFrame` 不应把未经确认的原始症状、生辰、个人资料直接作为任意字符串长期持久化。敏感槽位要有来源、确认状态、用途权限、保留期限和删除策略；审计日志不得存症状原文。
7. 任何工具重试都要区分“确定未执行”“执行结果未知”“已执行但返回失败”。不能把未知执行状态当作安全可重放；写操作必须幂等或要求重新确认。

### 7.7 本轮结论与未关闭范围

**已确认的核心病因：** 当前系统有多模式 prompt、确定性 L0 路由、知识检索、规则问诊和页面工具；缺少统一的语义任务规划、跨模式任务帧、Headless 能力注册/执行器和跨结果综合闭环。这是五种模式普遍表现为“有入口但不够聪明”的架构原因。

**下一步不应立即创建 ActiveTaskFrame 或批量抽取 24 个工具。** 先完成每个工具页面与底层服务的逐项可调用性审计；同时优先修复 MainActivity 多轮恢复上下文丢失，并建立一条跨两项只读能力的最小复合任务端到端测试。所有未知项继续标记 UNKNOWN，不能提前写成 READY。


## 6B. Page / Executed / Headless 增量审计（2026-11-10）

本节纠正旧版目录中“23 个注册目的地”的历史统计，按当前审计基线重新核对：

- 审计基线：`master` @ `3d982e8129a2659547df1cd21143a825c8c5f8fb`。
- `AssistantToolRouter`：24 个唯一 `toolId`。
- `ToolsScreen`：22 个 `_ToolCard` 页面入口；`structured_diagnosis` 是会话内联流程，`knowledge_hub` 由独立知识入口承载。
- Page + Executed：1 个内联结构化问诊 + 9 个有页面结果回传设计的工具。
- Page only：14 个。
- Headless Capability：0 个。注册表执行载体仍是 Widget builder，没有无 UI 的 typed executor。

**重要区分：** `returnResultOnComplete: true` 只是页面结果回传设计，不等于每条执行路径已经产生可验证结果。页面被打开不算 Executed；模型在 prompt 中提到工具名不算 Executed；只有业务函数实际执行、参数验证、结果校验、来源 ID 和结果回流证据完整，才可记为 Executed。

Orchestrator 当前只负责决策；`LocalAiInterviewScreen._openTool()` 负责导航与结果规范化；业务计算仍发生在具体页面内部。旧版字符串结果兼容路径仍可能把结构化字段降级为单一“结果”文本。

详细逐项分类、参数/结果契约和下一步：[ai-capability-inventory-audit.md](ai-capability-inventory-audit.md)。

## 6C. 统一 TRACE 与隐私审计状态（2026-11-10）

端到端 TRACE 当前仍为 MISSING：未发现贯穿输入、preflight、orchestrator、检索、MethodChannel、Native 推理、工具、结果回流和 SQLite 持久化的 `trace_id`。`AssistantToolResult.sourceIds` 是来源引用，不是请求执行 trace ID；conversationId/messageId 也不能替代 trace ID。

详细证据与建议契约：[ai-trace-privacy-audit.md](ai-trace-privacy-audit.md)。

## 6D. 文档版本一致性（2026-11-10）

- `pubspec.yaml` 是唯一版本来源，当前为 `1.11.30+8039`。
- README 当前版本行已同步为 `1.11.30+8039`。
- 新增 `test/readme_version_consistency_test.dart`，防止 README 与 pubspec 再次漂移。
- 当前分支的测试与 CI 结果尚待回归；未通过前保持 IN_PROGRESS。
