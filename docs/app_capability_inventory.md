# App 功能与 AI 融合盘点

> 盘点基线：Fork `master`，提交 `74a58b3b228a6413454ae0d6a957c5b54d58cc70`。
> 本文是代码结构与现有入口盘点，不等于真机验收，也不把文件存在视为功能完整。

## 1. 当前代码规模

| 范围 | 数量 |
|---|---:|
| `lib/screens/` 页面文件 | 58 |
| `lib/services/` 服务文件 | 19 |
| `lib/data/` 数据/仓储文件 | 39 |
| `lib/models/` 模型文件 | 12 |
| `lib/widgets/` 组件文件 | 23 |
| `test/` 测试文件 | 157 |
| `assets/` 资源文件 | 1,278 |

## 2. 一级入口与信息架构

`HomeScreen` 是根页面，当前五个一级入口：

1. **AI**：`LocalAiInterviewScreen`，默认打开；问诊、学习、工具和术数任务的统一对话入口。
2. **知识**：七个知识分区——六经、方剂、本草、针灸、内经、伤寒金匮、搜索。
3. **工具**：中医计算与资料入口、术数排盘与民俗工具。
4. **收藏**：收藏内容入口。
5. **设置**：主题、字号、默认问诊性别等配置。

根导航由 `AdaptiveHomeNavigation` 根据窗口宽度和折叠特征切换导航形态；不能仅根据设备型号判断内外屏，应以实际窗口约束和 display features 为准。

## 3. 功能域清单

### 3.1 中医知识与诊疗资料

- 六经与经络：六经知识、经络详情、穴位详情、经络图。
- 方剂：方剂列表、方剂详情、口述提示与组成药味关联。
- 本草：药材列表、药材详情、异名归一、讲义/关联入口。
- 针灸：针灸资料、穴位库、针灸讲稿。
- 经典：古籍阅读、内经知识/条目/搜索、伤寒金匮条文库。
- 医案：医案列表、详情、洞察；另有闭门课重症资料。
- 其他：节气养生、经方剂量换算、诊断历史趋势。

核心仓储/服务包括 `FormulaRepository`、`HerbRepository`、`AcupunctureRepository`、`AcupointRepository`、`ClassicSearchService`、`AssistantKnowledgeContextBuilder`。

### 3.2 术数与民俗工具

代码中可见的页面/能力包括：

- 紫微斗数排盘、命盘保存与回看、紫微案例/参考/文档。
- 八字排盘、出生地选择、八字规则与关系计算。
- 易经起卦、卦象结果、详情与讲解。
- 小六壬、梅花易数。
- 五运六气、子午流注/灵龟八法/纳子纳甲。
- 每日黄历、周公解梦、小儿关煞、玉匣灵兆、三山国王灵签、称骨、受生债、轩辕黄帝四季歌。

以上术数与民俗内容应标注传统文化参考边界，不得作为科学预测，也不得替代医疗、法律或投资判断。

## 4. 统一 AI 入口现状

### 4.1 已有实现

- `HomeScreen` 默认一级入口就是 AI 对话。
- `AssistantConversationOrchestrator` 先进行显式工具匹配，再区分问诊、学习、工具/术数任务；歧义时澄清，不静默选择第一个工具。
- `AssistantToolRouter` 当前注册 23 个定义，包含结构化辨证问诊、五运六气、紫微、八字、易经、小六壬、梅花、剂量换算、子午流注、古籍、医案、黄历等。
- `AssistantKnowledgeContextBuilder` 已接入方剂、本草、针灸、穴位、内经/古籍全文索引及受限医案检索；上下文有长度上限，并保留来源标签与出处缺失边界。
- 结构化问诊由 `TcmInterviewConversationController` 与规则引擎执行；本地模型承担对话、澄清、整理，不应自行生成辨证结论、方剂或剂量。
- 对话历史与问诊任务快照已有持久化/恢复测试。
- 五运六气已开始采用 `AssistantToolResult` 结构化结果；对话端同时兼容旧 String 返回，属于迁移中的第一条垂直切片。

### 4.2 仍未闭合的接口

| 接口层 | 当前状态 | 尚缺内容 |
|---|---|---|
| 意图识别 | PARTIAL | 主要是规则/关键词匹配；尚无统一、可校验的模型结构化意图协议 |
| 工具参数 | MISSING | 没有覆盖全部工具的 typed args、必填/可选参数、参数校验、缺参追问协议 |
| 工具执行 | PARTIAL | 多数工具仍以页面导航为执行边界；未形成统一的可取消任务与错误状态协议 |
| 工具结果 | PARTIAL | 五运六气接入 typed result，其余工具仍需迁移；结果来源、字段状态、定位信息尚未统一 |
| 多轮任务 | PARTIAL | 有问诊任务快照和工具选择澄清；通用多工具计划、跨轮参数槽位和任务恢复尚未统一 |
| 结果展示 | PARTIAL | 结构化结果目前转为对话文本；尚无统一结果卡、来源展开和再次调用动作 |
| 知识引用 | PARTIAL | 有来源标签和内部路径；稳定条目 ID、版本/页码/段落定位并未全覆盖 |

### 4.3 应固定的职责边界

1. **问诊助手**：采集和澄清用户自述、整理症状；规则引擎独立产生辨证证据。模型不得代替规则引擎作诊断。
2. **学习助手**：先检索本地资料，再基于检索结果解释；没有可定位来源就明确标记 MISSING。
3. **工具助手**：模型识别工具和收集参数；确定性服务计算；模型只能解释服务返回结果，不得猜算。
4. **术数助手**：调用本地确定性排盘/起课服务，并明确传统文化参考边界。
5. **统一会话**：同一对话时间线承载问诊、学习、工具结果与澄清；模式是任务角色，不应再变成多个互不相通的聊天入口。

## 5. 折叠屏布局盘点

已有基础设施：

- `AdaptiveHomeNavigation`：按窗口断点切换导航。
- `AdaptiveSinglePane`：整页限制在一个物理面板。
- `AdaptiveMasterDetail`：适合列表+详情的双栏页面。
- `FoldAwareMaterialPageRoute`：根据发起控件位置选择路由面板。
- AI 对话、知识主从列表、八字表单等已有窗口/折痕测试。

当前缺口：测试覆盖的是模拟窗口尺寸和 display features，不等于 OPPO Find N2 真机验收。仍需逐页核对外屏、展开内屏、半折叠、键盘弹出、横竖屏切换、相机/文件选择器回跳和模型导入流程。不能把“有断点”当作“布局合理”。

## 6. 数据来源与经典条文风险

- 方剂、本草、穴位等结构化数据已有本地仓储。
- 经典全文索引已能进入 AI 上下文，但索引命中不自动证明条文版本、底本和出处已经校勘。
- 医案检索必须保留原始出处缺失标记；内部表格序号不能冒充原始医案编号。
- 经典条文需要分别记录：仲景/经典原文、底本版本、异文、倪师讲授、后世注家、App 编号映射。讲授解释不得伪装成经典原文。
- 适用条件必须与规则引擎中的实际问项和命中路径对应；仅有相似症状或文本相似度不能建立诊断关联。

## 7. 更新隔离

Fork 已删除上游自动更新服务、更新公告弹窗和 Gitee 自动同步工作流；启动链没有联网检查上游版本的调用。Fork 自己的构建与 Release 保留。该隔离策略已有专门测试覆盖。后续同步上游只能走人工审查后的选择性变更，不得恢复自动跟随上游的行为。

## 8. 下一阶段实施顺序（可并行）

- **A. 经典与医案来源**：建立条文/医案稳定 ID、版本与出处 manifest；优先完成条号映射和原文引用审计，未核验项目维持 MISSING。
- **B. Find N2 页面重构**：按页面清单建立外屏/内屏/半折叠布局验收矩阵；先重构 AI 对话与知识主从页，再覆盖工具表单和结果页。
- **C. 统一问诊**：清除旧页面回流；AI 对话承载自由问诊，结构化问诊控制器作为同一会话内的确定性子流程。
- **D. 工具协议**：先定义 typed args/result、来源、免责声明、MISSING、校验错误、取消和失败状态；按工具逐个迁移，保留旧 String 兼容直到迁移完成。
- **E. 全 App 能力映射**：为每个页面登记入口、服务、数据、权限、持久化、AI 可调用方式和错误状态；不允许只因页面已注册就标记 AI 已集成。

## 9. 页面文件索引

以下是当前 `lib/screens/` 的页面文件基线，后续盘点以实际代码为准：

- 核心入口与会话：`home_screen.dart`、`local_ai_interview_screen.dart`、`assistant_history_screen.dart`、`assistant_tool_router.dart`、`chat_screen.dart`、`knowledge_screen.dart`、`tools_screen.dart`、`bookmarks_screen.dart`、`settings_screen.dart`。
- 经典与中医知识：`classic_library_screen.dart`、`shanghan_jingui_screen.dart`、`neijing_knowledge_screen.dart`、`neijing_entries_screen.dart`、`neijing_library_screen.dart`、`neijing_search_screen.dart`、`guji_library_screen.dart`、`markdown_doc_screen.dart`、`acupuncture_screen.dart`、`acupoint_detail_screen.dart`、`zhenjiu_library_screen.dart`、`meridian_detail_screen.dart`、`formula_detail_screen.dart`、`herb_detail_screen.dart`、`herb_related_screens.dart`。
- 医案与诊疗辅助：`medical_case_library_screen.dart`、`medical_case_detail_screen.dart`、`medical_case_insights_screen.dart`、`critical_illness_list_screen.dart`、`diagnosis_history_screen.dart`、`dosage_converter_screen.dart`、`solar_term_section_screen.dart`。
- 术数与民俗：`ziwei_chart_screen.dart`、`ziwei_cases_list_screen.dart`、`ziwei_doc_screen.dart`、`ziwei_reference_screen.dart`、`bazi_paipan_screen.dart`、`yijing_screen.dart`、`yijing_result_screen.dart`、`yijing_detail_screen.dart`、`xiaoliuren_screen.dart`、`meihua_screen.dart`、`yunqi_screen.dart`、`yunqi_charts.dart`、`ziwuliuzhu_screen.dart`、`daily_almanac_screen.dart`、`dream_screen.dart`、`guansha_screen.dart`、`yuxiaji_omen_screen.dart`、`sanshan_lingqian_screen.dart`、`chenggu_bone_screen.dart`、`shousheng_debt_screen.dart`、`huangdi_siji_screen.dart`、`minggua_calculator_screen.dart`、`minggua_library_screen.dart`、`festival_lookup_screen.dart`、`saved_charts_screen.dart`。
- 辅助页面：`app_dialogs.dart`。
