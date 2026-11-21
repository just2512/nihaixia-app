# 情境问 AI 全仓库覆盖审计

- 审计日期：2026-11-21
- 仓库：just2512/nihaixia-app
- 代码基线：86dbac6c3714f593cffdb31400a25d74e581f8e7（PR #374 合并后）
- 审计范围：docs/contextual-ask-ai-spec.md 第 2–12 节；阅读入口、工具结果/字段入口、统一助手锚点/metadata、数据清除、自动化证据。
- 方法：递归 Git tree、相关 screen/service/test 源码静态检查、现有测试与 PR/CI 记录核对。不是 Find N2 设备测试。
- 状态约定：CODE + TEST 表示云端代码与自动化证据存在；IN_PROGRESS 表示由活动 PR 承接；UNKNOWN / LOCAL ONLY 表示必须留待设备验收。

## 1. 统一上下文基础设施

| 协议要求 | 代码证据 | 自动化证据 | 云端结论 |
|---|---|---|---|
| 受控引用类型、锚点与版本 | lib/models/ai_context_ref.dart：闭合枚举；classic / formula / herb / case / toolResult / field；toolResult/field 要求 snapshotId、ruleVersion 和 anchorVersion 一致 | test/ai_context_prompt_builder_test.dart：无效 metadata、版本/快照差异、字段路径拒绝 | CODE + TEST |
| Resolver 与 PromptBuilder 分层 | lib/services/ai_context_resolver.dart、lib/services/ai_context_prompt_builder.dart | test/ai_context_prompt_builder_test.dart 及各模块 contextual-entry tests | CODE + TEST |
| 复用现有助手面板 | lib/widgets/contextual_ai_sheet.dart 创建既有 LocalAiInterviewScreen，注入归一化 contextRef，不建第二套会话/模型链路 | test/contextual_ai_panel_layout_test.dart、各页面 widget tests | CODE + TEST |
| 窄屏弹层/宽屏侧栏 | 基于可用窗口宽度 720dp 分界；窄屏使用 DraggableScrollableSheet（0.55–0.95），宽屏侧栏宽度受边界约束 | test/contextual_ai_panel_layout_test.dart 和各页面 402/775dp 覆盖 | CODE + TEST；折叠铰链/键盘实机仍 UNKNOWN |
| explanation-only 不重入工具路由 | lib/screens/local_ai_interview_screen.dart 对 contextualExplanationOnly 使用解释专用路由 | test/local_ai_interview_screen_test.dart：同锚点续问不进入工具意图分发 | CODE + TEST |

## 2. 已有结果/知识入口目录

### 2.1 工具结果入口

| 页面/领域 | 结果入口 / Resolver | 主要自动化证据 | 云端状态 |
|---|---|---|---|
| 每日黄历 | daily_almanac_screen.dart / buildAlmanacResultContextRef | almanac_contextual_result_entry_test.dart | CODE + TEST |
| 八字及字段 | bazi_paipan_screen.dart / Bazi result + field resolver | bazi_contextual_result_entry_test.dart | CODE + TEST |
| 袁天罡称骨 | chenggu_bone_screen.dart / Chenggu snapshot | chenggu_contextual_result_entry_test.dart | CODE + TEST |
| 经方度量衡 | dosage_converter_screen.dart / dosage snapshot | dosage_contextual_result_entry_test.dart | CODE + TEST |
| 周公解梦 | dream_screen.dart / 用户明确选择单条 DreamEntry ID | dream_contextual_result_entry_test.dart | CODE + TEST |
| 小儿关煞 | guansha_screen.dart / Headless 结果快照 | guansha_contextual_result_entry_test.dart | CODE + TEST |
| 黄帝四季歌 | huangdi_siji_screen.dart / 四季歌结果 | huangdi_siji_contextual_result_entry_test.dart | CODE + TEST |
| 梅花易数及字段 | meihua_screen.dart / 整体 + 字段路径 | meihua_contextual_result_entry_test.dart、meihua_contextual_field_entry_test.dart | CODE + TEST |
| 三山国王灵签 | sanshan_lingqian_screen.dart / 确定签号快照 | sanshan_lingqian_contextual_result_entry_test.dart | CODE + TEST |
| 受生债 | shousheng_debt_screen.dart / 两套口径结果 | shousheng_debt_contextual_result_entry_test.dart | CODE + TEST |
| 节气 | solar_term_section_screen.dart / 所选节气 | solar_term_contextual_result_entry_test.dart | CODE + TEST |
| 小六壬 | xiaoliuren_screen.dart / 明确起课口径和结果 | xiaoliuren_contextual_result_entry_test.dart | CODE + TEST |
| 易经及字段 | yijing_result_screen.dart / 整体 + 字段 | yijing_contextual_result_entry_test.dart | CODE + TEST |
| 五运六气整体结果 | yunqi_screen.dart / 年度结果 | yunqi_contextual_result_entry_test.dart | CODE + TEST |
| 五运六气三张图字段 | yunqi_screen.dart / chart.wuxing、chart.wuyun、chart.liuqi | yunqi_contextual_chart_field_entry_test.dart | PR #375：最新 head ee728b9cb6658c02cf4dcd3447bc49c9f69a3b77；Fork license boundary SUCCESS，Flutter regression run 44899694651 尚在执行，Android arm64 待该 run 终态后确认 |
| 玉匣灵兆 | yuxiaji_omen_screen.dart / 当前设备本地时间文本 | yuxiaji_omen_contextual_result_entry_test.dart | CODE + TEST |
| 紫微斗数及宫位字段 | ziwei_chart_screen.dart / 排盘快照 + 宫位星曜 | ziwei_contextual_result_entry_test.dart | CODE + TEST |
| 子午流注 | ziwuliuzhu_screen.dart / 时辰开穴结果 | ziwuliuzhu_contextual_result_entry_test.dart | CODE + TEST |

以上 CODE + TEST 仅指云端源码和自动化证据，不代表已取得 Find N2 TRACE。

### 2.2 知识阅读入口

| 页面/领域 | 入口行为 | 主要自动化证据 | 云端状态 |
|---|---|---|---|
| 方剂详情 | 通过准确方剂记录建立知识上下文 | formula_contextual_entry_test.dart | CODE + TEST |
| 本草详情 | 通过本地药物准确名称/记录解析 | herb_contextual_entry_test.dart | CODE + TEST |
| 医案详情 | 通过内部医案记录 ID 和来源账本解析 | medical_case_contextual_entry_test.dart | CODE + TEST |
| 内经结构化条目 | 通过准确条目 ID / 资料版本解析 | neijing_contextual_entry_test.dart | CODE + TEST |
| 经典划词 | 当前只在明确接入的《伤寒论》单条文块提供菜单操作；依赖唯一 blockquote 和源身份，不把 Markdown 可选中文字误当作已接入 | markdown_doc_contextual_selection_test.dart | 首批样板 CODE + TEST；其余经典/讲稿页尚未逐页接入，不宣称已全量接入 |

### 2.3 未建立列表级或空壳入口的页面

- 我的命盘库是保存记录列表；打开后进入已有八字/紫微结果页。没有为列表页额外创建重复的 Ask AI 入口。
- 助手历史、诊断历史和危急提示不是独立确定性工具结果页。历史会话通过现有会话/消息 metadata 恢复；不因覆盖率数量而添加空壳入口。
- 普通知识目录、针灸目录/穴位索引等页面没有被认定为已存在情境 Ask AI；必须先明确单条知识实体、来源身份及回链后才可接入。

## 3. 已确认的非合规入口缺口：六经详情页

- 文件：lib/screens/meridian_detail_screen.dart，基线 blob cb5c1e88bedef1a397ee93f85fa598f995eea4c2。
- 直接入口位于 AppBar 聊天按钮（约第 37–50 行）：直接 push LocalAiInterviewScreen(initialPrompt: ...)，没有 AiContextRef、Resolver、来源锚点、内容版本或会话 metadata 锚定。
- 同页展示内容来自 DiagnosticRules.meridianDetails[meridian]、DiagnosticRules.meridianHealingTime 和 FormulaRepository.getByMeridian(meridian)；数据包含核心脉证、症状、传入/传出、经典条文文字、倪师整理内容和关联方剂。
- 当前按钮会预填泛化问题，但 initialPrompt 不等于情境会话，违反协议 §3、§6.1 和 §8 对稳定锚点/会话绑定的要求。
- 当前目录没有 test/meridian_detail_screen_test.dart；test/meridian_detail_editorial_layout_test.dart 只覆盖 402/775dp、浅深主题和 200% 字号，不覆盖情境入口或来源。
- 缺口状态：MISSING（对这个页面的真实情境上下文接入）；页面本身和原阅读内容继续保留。下一小切片应在最新 master 上增加准确六经记录 Resolver/Prompt、将按钮切换为 explanation-only 面板，并覆盖有效/非法六经、错源/错误版本、真实页面调用链和 402/775dp。不得把《伤寒论》条文文字本身标记为经版本/卷页已核验；现有规则数据只证明 App 本地整理文本存在。

## 4. 共通会话、来源与生命周期审计

| 协议要求 | 现有证据 | 云端结论 |
|---|---|---|
| 同锚点会话复用 | LocalAiInterviewScreen._initializeContextualConversation 遍历会话消息，只有全部非空 user/assistant message 的 contextRef 都严格匹配才复用 | CODE + TEST |
| 不同 snapshot / 不同选中文字隔离 | test/local_ai_interview_screen_test.dart 覆盖 snapshot-a/b 与同 passage 不同 selectedText | CODE + TEST |
| 每轮 user/assistant metadata 写入相同 contextRef | _persistSuccessfulTurn 两条 message metadata 均写 _activeContextRef；AssistantMessageMetadata schemaVersion 1 持久化 contextRef | CODE + TEST；assistant_message_metadata_test.dart 覆盖序列化/恢复 |
| 历史不跨上下文污染 | 历史恢复会恢复 metadata 中最后已验证上下文；上下文初始化时要求 transcript 全部引用同一锚点 | CODE + TEST |
| token 预算 | PromptBuilder 当前在没有模型 tokenizer 时明确输出 UNKNOWN，不把字符数冒充 token | CODE + TEST；真实 tokenizer 预算 UNKNOWN |
| AI 数据清除 | LocalAiDataClearCoordinator、SQLite/附件/Native cache/TRACE 分域清除均已有自动化 | CODE + TEST；整体仍 PARTIAL，见下节 |
| 安全和领域隔离 | explanation-only route 不进入工具 dispatch；AssistantConversationOrchestrator 对问诊/学习/玄学域有确定性边界和受限工具候选 | CODE + TEST；真实设备/端侧模型跨轮 TRACE 留待最终本地 |

## 5. AI 数据清除现状（不得误报 PASS）

docs/ai-data-clear-scope-audit.md 第 7 节为 2026-11-13 最新有效增量：
- SQLite 对话/消息/问诊任务/旧 chat_history 在单一事务内清除；测试覆盖 AI 数据删除、非 AI 数据保留及失败回滚。
- 新 AI 附件放在专属目录；旧版本 image_picker 共享临时图片归属仍 UNKNOWN，不删除共享目录中的任意图片。
- Native cache 清除先释放运行时再删除 cache；模型文件按产品约定保留。
- TRACE stop/flush/clear、UI 二次确认和分项失败结果已有测试。
- 系统备份规则无法只排除混合 SQLite 数据库中的 AI 行；当前 nihaisha.db 中 AI 与非 AI 数据共存。不得擅自排除整个数据库或全局禁用备份；这需要产品层备份决策。
- Find N2 强制停止、进程重启后不可恢复的证据未提供。

因此 AI 数据清除整体状态仍是 PARTIAL；上面 CODE + TEST 不等同于最终端到端 PASS。

## 6. 风险与下一步

1. 先完成 PR #375 最新 HEAD 的 Flutter regression 和 Android arm64，确认同一 HEAD 的 Fork license boundary，然后合并并核验 master post-merge CI。
2. 紧接着修复本审计 §3 的 Meridian detail 原始 initialPrompt 入口：使用六经本地数据建立稳定引用、精确 Resolver 和 PromptBuilder，确保页面当前内容和送入 AI 的快照一致。
3. 将 #375 与六经修复合并后，再复核全仓库相关页面的调用链；如有新发现，按单一共享文件所有权串行推进。
4. 云端完成后输出 Find N2 最终验收清单，集中测试外屏/内屏/半折叠/分屏/键盘、E4B 多轮和数据清除强停重启。
5. 未取得设备 TRACE 的功能持续标记 UNKNOWN / LOCAL ONLY；不以设备验收为由阻塞上述云端实现、测试、台账和 CI。

## 7. 回滚

六经详情修复应限定在详情页 Ask AI 入口、Resolver/Prompt 适配和新增测试。回滚时撤回该入口与适配，不删除六经原有数据、规则问诊或方剂链接。
