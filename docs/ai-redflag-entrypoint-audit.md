# 全模式红旗门禁入口审计

- 审计类型：只读静态审计
- 基线：`master` @ `60011c4d237cd8d80659038beb6a3a7257228e01`
- 范围：统一助手文本、附件、结构化问诊、工具路由、症状提取与 Native 模型入口
- 结论限制：本报告确认的是代码入口和现有保护形式；正式医学词表/阈值尚未由医学背景人员审核。

## 1. 当前已有保护

`MainActivity.kt` 的 `systemInstruction` 含急症提示（约第 55-66 行）：胸痛、呼吸困难、意识障碍、突发偏瘫/言语障碍、大量出血、自伤风险时，要求先建议寻求当地急救，不继续普通问诊。

这属于模型提示词约束，不是模型调用前的确定性安全门禁。模型可能忽略、误解或未收到该提示；因此不能作为全模式安全放行条件。

## 2. 已核对入口

| 入口 | 源码位置 | 当前路径 | 门禁结论 |
|---|---|---|---|
| 统一助手纯文本 | `local_ai_interview_screen.dart` `_send()` 约 2110-2240；`assistant_conversation_orchestrator.dart` `resolve()` 121 起 | 先处理结构化问诊分支，再进行自动/手动模式路由，最后发给 Native | 未发现前置红旗规则 |
| 自动模式 | `_send()` 调用 `AssistantConversationOrchestrator.resolve` | 通过 cue 识别领域后调用工具或模型 | resolve 负责领域/工具选择，不承担急症识别 |
| 学习/工具/玄学模式 | `AssistantConversationOrchestrator.resolve()` | 手动模式下先做工具别名匹配与澄清 | 未发现统一红旗门禁；工具路由可能先于模型 |
| 结构化中医问诊选项 | `local_ai_interview_screen.dart` `_send()` 中 `activeTcmTask?.canAnswer` 分支 | 直接进入 `_handleTcmInterviewOption`，不经过普通 orchestrator | 业务规则入口绕过普通文本路由；需在业务处理前纳入安全前置检查 |
| 图片附件 | `MainActivity.kt` `sendImage` / `sendLocalImage` 约 90-97、587 起 | MethodChannel 直接进入 Native 模型 | 未发现模型调用前的红旗检查 |
| 语音附件 | `MainActivity.kt` `sendAudio` / `sendLocalAudio` 约 99-106、611 起 | MethodChannel 直接进入 Native 模型 | 未发现模型调用前的红旗检查 |
| 症状提取 | `MainActivity.kt` `extractSymptoms` 约 86、约 650 起；Dart `_extractSymptoms()` | 单独 Native Conversation 抽取用户自述 | 未发现前置红旗检查 |
| 历史续聊/恢复 | `restoreConversation` Dart/Native 双端入口 | transcript 回放到新 Conversation | 未发现恢复内容的安全重检；历史文本不能直接当作当前本人症状 |
| Native 文本接口 | `MainActivity.kt` `sendMessage` 分支 107-113 | 直接 `runAiTask { sendLocalMessage }` | Native 不具备独立的确定性红旗校验 |

以上说明：现有提示词有红旗条目，但全模式前置门禁目前属于 `MISSING`，而不是已实现。

## 3. 当前路由的误判风险

`AssistantConversationOrchestrator.resolve()` 在 121 行起首先 trim 输入，之后对非自动模式执行学习 cue、工具 alias/action 匹配；没有在入口第一步调用安全预检。

症状 cue 和学习 cue 是领域分类词表，不是医疗红旗词表。简单把二者拼接也不能满足安全门禁要求。

若只在纯文本 orchestrator 前增加 contains 检查，仍会漏掉：
- 图片/语音附件直接调用 Native 的路径；
- 结构化问诊控制器先处理选项的路径；
- 症状提取和历史恢复路径；
- 未来其他直接调用 `LocalAiService` / MethodChannel 的路径。

## 4. 实施建议：一个共享策略、多个边界强制执行

建议建立纯 Dart 的 `RedFlagPreflight`（具体文件名可在实现时按现有目录规范确定），采用输入 schema：
- 原始文本；
- 输入来源（当前文本/附件转写/历史恢复/结构化选项/工具参数）；
- 语义主体（本人/他人/知识讨论/未知）；
- 时间属性（当前/既往/假设/未知）；
- 当前会话领域。

输出必须是显式状态：
- `CLEAR`：未识别到当前本人明确红旗；
- `BLOCK_URGENT`：明确高危信号，阻断普通模型/业务流程并显示急救提示；
- `CLARIFY`：主体、时间、否定或语义不明确，先澄清；
- `REVIEW_REQUIRED`：规则版本未审核或输入不在规则覆盖范围，不能默认为 CLEAR。

同一策略至少在以下两个边界执行：
1. Flutter 所有入口路由前：覆盖普通文本、结构化问诊、工具路由、附件、症状提取和历史续聊。
2. Native MethodChannel 的模型调用边界：作为纵深防御，防止未来绕过 Flutter 路由直接调用模型。Native 规则实现可通过共享协议/参数传递保持语义一致，但不得依赖提示词。

附件需先取得可信转写/用户描述；不能对图片文件路径或二进制内容做关键词判断。附件模型结果不能反向覆盖用户本人症状主体判断。

## 5. 必须覆盖的测试矩阵

每个红旗词条至少测试以下语义变体：
- 本人当前：明确表达本人正在出现症状；
- 他人当前：明确是家人/朋友/他人；
- 知识讨论：询问某症状的定义、病理或经典记载；
- 否定：明确表示没有该症状；
- 既往史：过去发生、现在已结束；
- 假设/引用：假设句、书籍原文、转述他人原话；
- 主体未知：未说明是谁；
- 时间未知：未说明是否当前；
- 多信号组合：多个红旗信号同时出现；
- 附件/语音转写：转写后重新走相同预检。

必须证明：
- 明确本人当前红旗在模型调用和业务路由之前阻断；
- 他人/知识/否定/既往描述不会错误地作为本人当前急症；
- 主体或时间不明时进入 CLARIFY，不默认为 CLEAR；
- 安全规则不可被用户 prompt 或模式切换覆盖；
- 规则异常/版本缺失时 fail-closed，不静默放行。

## 6. 医学审核与发布条件

- 当前 systemInstruction 中的急症列表不能直接视为完整词表。
- 正式词表、语义规则、阈值、急救文案必须由具备医学背景的人员审核；保存审核人角色、规则版本、审核日期和变更记录。
- 本审计不自行增加医疗阈值，也不将中医术语映射成未经审核的现代医学诊断。
- 在医学审核记录和全入口回归测试完成前，门禁状态只能标记 `PARTIAL`，不得标记 `PASS`。

## 7. 结论

| 项目 | 状态 |
|---|---|
| systemInstruction 急症提示 | `IMPLEMENTED`（仅提示词约束） |
| 纯文本统一入口前置门禁 | `MISSING` |
| 自动/学习/工具/玄学全模式覆盖 | `MISSING` |
| 结构化问诊入口覆盖 | `MISSING` |
| 图片/语音 Native 入口覆盖 | `MISSING` |
| 症状提取/历史恢复覆盖 | `MISSING` |
| 否定/他人/知识/既往语义处理 | `UNKNOWN`（未见独立规则实现） |
| 医学词表审核 | `MISSING` |
| 全入口测试矩阵 | `MISSING` |

本报告为静态入口审计，未修改业务代码，未进行医学审核或设备测试。
