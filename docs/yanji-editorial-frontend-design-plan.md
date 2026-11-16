# 研纪前端视觉规范与分批实施计划

> 版本：v1.0  
> 建立日期：2026-11-16  
> 执行原则：保留现有杂志式风格，以最小改动完成统一；本文件是后续前端视觉改造的执行基线。  
> 当前阶段：设计规范已固化；页面分批实施尚未全部完成。未完成的真机项目必须标记为 `MISSING`，不得以模拟器或 CI 结果替代。

## 1. 改造目标

在保留项目现有现代杂志式视觉基础上，形成稳定、克制、适合长时间阅读的界面系统：

- 降低浅色主题近白背景带来的视觉刺激，避免纯白大面积铺底。
- 保留现有标题、正文、栏目、列表和卡片的编辑式层级，不把页面改成后台管理面板。
- 保持较高有效信息密度，避免过度留白、厚重卡片、重复容器和装饰性大区块。
- 让浅色与深色主题属于同一套品牌系统。
- 通过颜色 Token 和全局 Theme 控制大多数页面；只对确有视觉问题的页面做局部修正。
- 不为追求统一而改变内容结构、操作流程或业务行为。

## 2. 当前代码基线

当前仓库已有设计系统，不从零重建：

- `lib/theme/app_colors.dart`：`AppColors` 是颜色 Token 唯一来源，并通过 `ThemeExtension` 和 `context.colors` 访问。
- `lib/theme/app_tokens.dart`：已集中管理间距、圆角、字号、字体族和全局文字缩放。
- `lib/main.dart`：已集中定义 AppBar、Card、NavigationBar、NavigationRail、ListTile、Chip、Divider、输入框和按钮主题。
- 全局文字缩放由 `AppPreferenceTextScaler` 包裹整个 Navigator；最大值为 200%。
- 首页根导航使用 `AdaptiveHomeNavigation` 和 `IndexedStack`。当前顺序为 AI、工具、知识、收藏、设置，默认入口为 AI。

### 基线保护

在没有单独产品决策前，以下行为保持不变：

1. 首页默认入口仍为 AI；不擅自改为知识库首页。
2. 根导航顺序、名称和五个入口不变。
3. 页面 Tab 顺序、默认选中项、KeepAlive、检索筛选和详情跳转行为不变。
4. 不修改诊断、问诊、排盘、方剂、本草、针灸、医案等业务逻辑和内容。
5. 不改变本地数据库、持久化键、路由语义、数据来源或模型调用流程。

## 3. 视觉方向与设计原则

### 3.1 风格定义

**现代编辑型杂志风：内容优先、层级清晰、低饱和、轻表面、高信息密度。**

它不是仿古书房、宣纸古籍、传统诊所界面，也不是大卡片堆叠的仪表盘。

### 3.2 必须遵守

- 页面底色使用低亮度中性灰绿，不使用纯白或明显泛黄的纸张色作为大面积底色。
- 内容表面与页面背景保持细微但可辨识的层次差，不靠厚阴影和高饱和色制造层级。
- 主要层级通过标题字号、字重、栏目编号、短说明、细分隔线和适量间距表达。
- 卡片只用于确实需要分组或承载交互的内容；连续阅读内容优先使用平面布局、列表和轻边界。
- 保留现有衬线标题气质，但正文、说明、表单和长内容保持系统无衬线字体的可读性。
- 朱砂、金色、紫色等仅作为有明确语义的局部强调，不承担全局主色。
- 六经颜色、状态颜色和领域分区色属于语义色，不为视觉统一而全部染成品牌绿。
- 不增加水墨背景、卷轴、八卦纹、渐变大底、浮夸插画或无信息价值的装饰。
- 不为追求整齐而裁切文字、缩小字体、锁死高度或破坏滚动。

### 3.3 最小改动原则

优先级按以下顺序执行：

1. 修正全局 Theme / Token 映射。
2. 修正共享组件的主题继承和表面层级。
3. 只修复实际偏离规范的页面局部样式。
4. 只有在布局本身确实妨碍阅读或操作时，才做局部布局调整。

不得借视觉改造之名重做页面信息架构或批量重写业务页面。

## 4. 设计 Token 规范

以下颜色是当前候选基线，来自主题 Token 分支。通过自动对比度测试不等于通过真实屏幕阅读验收；实机确认前不得称为最终定稿。

### 4.1 颜色 Token

| 语义 | 浅色主题 | 深色主题 | 用途 |
|---|---|---|---|
| `primary` | `#43594D` | `#A7B8AA` | 品牌主操作、选中态 |
| `onPrimary` | `#FFFFFF` | `#1F3026` | 主色上的文字/图标 |
| `primaryContainer` | `#DFE6DF` | `#34483C` | 选中背景、主色弱强调 |
| `onPrimaryContainer` | `#20342A` | `#DDE8DE` | 主色容器上的内容 |
| `background` | `#E7E9E4` | `#181E1B` | 页面底色 |
| `surface` | `#EFF0EB` | `#202823` | AppBar、卡片和主要内容表面 |
| `surfaceContainerLow` | `#E1E4DE` | `#252F29` | 次级分组、轻量区域 |
| `surfaceContainerHighest` | `#D9DDD6` | `#303B34` | 输入容器、强调分组等 |
| `onSurface` | `#262C28` | `#E4EAE4` | 正文和主要标题 |
| `onSurfaceVariant` | `#59635C` | `#B7C1B8` | 辅助说明、次级标签 |
| `outline` | `#747E76` | `#879388` | 需要清楚可见的控件边界 |
| `outlineVariant` | `#C8CEC6` | `#465149` | 细分隔线、弱边界 |

### 4.2 语义色保留规则

- `danger`、`success`、`info` 及其 container 沿用既有语义定义；只有在对比度测试证明存在问题时才单独调整。
- `warning` 浅色值当前为 `#896000`，用于在新浅色底上保持文字识别度。
- 六经颜色与六经容器颜色保留其领域语义；容器底色可随主题 surface 调整。
- `tcmZone` 和 `metaphysicsZone` 保留现有分区含义。
- 业务状态、诊断结果或领域颜色不得被用于纯装饰，也不得因品牌色调整而改变含义。

### 4.3 非颜色 Token

本轮不重新发明间距、圆角和字号体系；以现有 `app_tokens.dart` 为准：

| Token 组 | 当前值 | 执行约束 |
|---|---|---|
| `AppSpacing` | xs 4 / sm 8 / md 12 / lg 16 / xl 24 / xxl 32 | 保持现值；只在局部确有拥挤或浪费时调整 |
| `AppRadius` | xs 4 / sm 8 / md 12 / lg 16 / xl 24 | 保持现值；不把所有元素统一做成大圆角 |
| `AppType` | display 24 / headline 20 / subhead 18 / title 16 / body 14 / caption 12 / micro 11 | 保持现值；页面不得为适配窄屏而低于可读字号 |
| `AppFonts` | display = serif，正文系统默认字体 | 衬线仅承担标题/编辑感，不扩展到长正文和表单 |
| `AppTextScale` | min 0.8 / max 2.0 / default 1.0 / step 0.05 | 保持最大 200% 和持久化行为 |

### 4.4 全局组件基线

沿用 `main.dart` 中的 Material 3 主题约定：AppBar 无投影、Card 低表面/零 elevation、统一的中等圆角、细分隔线、主题化输入框和按钮。后续页面不另造一套局部组件皮肤；只有主题无法表达的领域语义样式才允许局部覆盖。

## 5. 页面实施批次

每批使用独立工作分支和独立验收，不跨批混入业务逻辑。某页面若已符合规范，应记录检查结论，不为制造改动而改动。

### Phase 0：设计规范与全局 Token 基线

**范围**
- 本文档。
- `lib/theme/app_colors.dart`。
- `test/app_theme_color_scheme_test.dart`。

**完成情况**
- 低饱和灰绿 / 墨灰绿浅深主题 Token 与主题对比度断言已纳入 PR #211，并随 Phase 1 合并进入 `master`。
- PR #208 已关闭，明确由 PR #211 取代；它不是仍待合并的有效 PR。
- Find N2 真实屏幕阅读测试仍为 `MISSING`；颜色仍是候选基线，不能据自动化结果宣称实机最终定稿。

### Phase 1：首页与根导航

**主要文件**
- `lib/screens/home_screen.dart`
- `lib/widgets/adaptive_home_navigation.dart`
- `lib/screens/local_ai_interview_screen.dart`
- `test/home_screen_entry_test.dart`
- `test/adaptive_home_navigation_test.dart`

**实施重点**
- 检查根导航、默认 AI 首屏、AppBar、主要输入区、消息/内容表面是否正确继承新 Token。
- 以栏目层级、细边界、内容间距和低对比表面修正实际偏离项。
- 保留 AI 对话的阅读顺序、输入区、附件、语音、工具调用和状态展示。
- 保留现有导航顺序、默认 AI 入口、IndexedStack、选中状态和页面 State。
- 只在有明确布局缺陷时改局部布局，不重构 AI 交互。

**完成门槛**
- 外屏窄宽度、内屏宽度、半折叠 hinge/fold 和 200% 字号下无溢出、无遮挡。
- 切换内外屏、导航 Tab 和主题后，不丢失当前会话/输入草稿/选中 Tab/滚动状态。
- 既有首页导航和 AI 入口测试通过。

### Phase 2：知识浏览与核心详情

**主要文件**
- 知识入口：`lib/screens/knowledge_screen.dart`、`lib/screens/search_tab.dart`。
- 经典阅读：`lib/screens/classic_library_screen.dart`、`lib/screens/shanghan_jingui_screen.dart`、`lib/screens/neijing_knowledge_screen.dart`。
- 核心详情：`lib/screens/formula_detail_screen.dart`、`lib/screens/herb_detail_screen.dart`、`lib/screens/acupoint_detail_screen.dart`、`lib/screens/meridian_detail_screen.dart`、`lib/screens/medical_case_detail_screen.dart`。
- 共享布局：`lib/widgets/adaptive_master_detail.dart`（仅在发现与主题或阅读布局直接相关的问题时修改）。

**实施重点**
- 统一标题、条目摘要、来源/出处、正文、关联内容和操作区的编辑层级。
- 减少不必要的嵌套 Card；连续原文优先使用正文排版、分段标题和细分隔线。
- 详情内容保持可读行宽；宽屏可利用主从布局，但不跨物理 hinge 放置文字列或主要操作。
- 保留原典、讲授、整理、研究等来源性质及其出处定位；不改知识内容和关联关系。
- 保留现有七个知识 Tab、Tab 状态、筛选、检索、收藏和详情导航。

**完成门槛**
- 覆盖外屏单列、内屏主从模式、半折叠物理面板和无折痕窗口。
- 200% 字号时长标题、原文、表格/列表、按钮可访问且不横向溢出。
- 知识入口、主从预览、核心详情与来源展示相关回归测试通过。

### Phase 3：工具、收藏、设置与辅助页面

**当前执行分支**：`work/yanji-editorial-phase3-auxiliary`，父基线 `68b2b2d8869daf4f9f6a60e61a3c50cbd624c915`（Phase 3.2 合并提交）。

**Phase 3.1 已合并：收藏、设置与历史对话**
- 收藏页列表改为平面 `ListTile + Divider`；文件夹/分类筛选使用自然高度横向滚动；保留文件夹创建/删除、分类筛选、移动、删除确认、导出、详情打开与 `AdaptiveMasterDetail`。
- 设置页章节标题和间距对齐 `AppType` / `AppSpacing`；保留全部设置项、实时监听和 `SettingsRepository` 持久化。
- 历史对话标题和摘要自然换行，时间作为次级信息；保留会话 ID、多选和删除逻辑。
- PR #214 已合并，集成 SHA `7d1dfec8cb4dcfa831177a86082fbc165e01d205`；PR 全量 Flutter、Android arm64、分支定向测试及合并后主线 CI 已通过。

**Phase 3.2 已合并：命盘库与诊断历史**
- 命盘库移除重复 `Card(elevation: 2)`，改用主题表面与分隔线；Token 化字号、间距和圆角；保留出生信息、紫微/八字排盘入口和左滑删除。
- 诊断历史统一字号/间距/圆角 Token；趋势图高度随字号变化；日期移至次级信息行，避免窄屏挤压正文；保留六经趋势、语义色和历史数据。
- PR #217 已合并，集成 SHA `68b2b2d8869daf4f9f6a60e61a3c50cbd624c915`；PR 全量 Flutter、Android arm64 和分支定向测试均通过；合并后 master CI 正在执行。

**Phase 3.3 当前批次：闭门课重症临床列表**
- 七条列表项移除重复高 elevation Card，改为主题表面、轻分隔线与点击反馈；标题/摘要/标签字号及间距使用共享 Token。
- 保留七条原文内容、资产路径、原文 Markdown 路由、方剂/本草标签精确导航和非医疗建议 footer；不改数据、辨证与用药逻辑。
- 新增测试覆盖 402/775dp、浅/深主题、200% 字号、七条滚动可读性、Markdown 原文路由，以及方剂/药材详情跳转。

**Phase 3.1 实施前只读审计（历史基线：Phase 2 master）**

- `tools_screen.dart` 已使用 `ZoneSection`、`AppSpacing`、`AppRadius`、`AppType`；工具入口卡片是带边界的 `Material + InkWell`，不是堆叠的 `Card`。不为统一而重写；需继续验证各工具入口与路由覆盖。
- `bookmarks_screen.dart` 已使用 `AdaptiveMasterDetail` 和部分 `AppType`，列表项目前由 `Card + ListTile` 承载；预览区仍有多处间距字面值。现有测试覆盖新建文件夹弹窗，但未发现完整收藏列表、筛选/移动/删除/主从布局的页面级回归测试，Phase 3 应先补这些行为测试再调整表面。
- `settings_screen.dart` 通过 `SettingsRepository` 与 `ColorScheme` 维护现有设置；仍有局部字号/间距字面值，且未发现设置页整体的页面级测试。改动必须保留设置持久化及开关双向同步。
- `assistant_history_screen.dart` 采用列表和 `outlineVariant` 分隔线；已有列表、多选删除、恢复和持久化相关测试。尚缺少该页的折叠窗口与 200% 字号视觉覆盖。
- `tool_foldable_layout_test.dart` 已覆盖注册工具的展开内屏零宽 fold 与半折叠物理 hinge 路由边界；不得删除或缩小现有覆盖范围。

该只读审计是 Phase 3.1 的历史基线检查，不代表当前所有辅助页都需要重做。Phase 3.1、3.2 已完成合并；Phase 3.3 按页面独立分支和小批次推进。不得把“已有共享组件/局部 Token”误报为需要重做。

**主要文件族**
- `lib/screens/tools_screen.dart` 及其实际存在的工具页面。
- `lib/screens/bookmarks_screen.dart`。
- `lib/screens/settings_screen.dart`。
- `lib/screens/assistant_history_screen.dart`。
- 其他经典、易学、医案和辅助详情页面。

**实施重点**
- 先核对共享 Theme 是否已覆盖；只修正直接写死且与主题冲突的局部颜色/表面。
- 工具页面保留各领域语义色与参数关系，不把不同工具做成同一种大卡片。
- 收藏、设置和历史记录保留现有管理流程、筛选、导出、恢复和设置持久化行为。
- 对复杂表单优先保证标签、输入控件、错误提示、键盘和大字号下可用，不追求装饰统一。

**完成门槛**
- 工具页面既有单侧面板与折痕测试通过；收藏主从布局和设置功能测试通过。
- 200% 字号下，表单项可换行、操作可触达，不通过裁切隐藏选项。
- 不发生功能入口丢失、筛选状态重置或持久化回归。

### Phase 4：跨页面一致性与最终验收

- 审查实际改动页面是否存在旧色值、纯白大面积表面、过重阴影或重复容器。
- 仅修复有证据的偏差，不开启无边界的全仓 UI 重写。
- 汇总对比度自动测试、CI、模拟窗口测试和 Find N2 实机报告。
- 分开记录自动化 `PASS`、实机 `PASS`、`REJECT`、`MISSING`、`UNKNOWN`；不以平均分掩盖单项失败。

## 6. Find N2 与大字号不可退化项

以 `docs/find-n2-adaptive-layout.md` 和现有折叠布局测试为设备适配依据。视觉改造不得改变已有响应式决策：

- 不识别设备型号来写死布局；继续使用运行时窗口约束和 `MediaQuery.displayFeatures`。
- 小于 600 dp 使用底部导航；600–839 dp 使用侧边导航；840 dp 及以上使用扩展导航。
- 正确处理物理 hinge 与零宽 fold；半折叠物理铰链区域不得放置正文列或重要控件。
- 不在 MaterialApp 最外层强制把所有页面限制到单个子屏幕。
- 保留内外屏切换时的当前 Tab、输入内容、滚动位置、筛选状态、会话和页面 State。
- 保留 100%、150%、200% 字号档位；文字允许自然换行和容器增高，不锁高、不裁字、不缩字号。
- 所有局部滚动区、弹窗、键盘和安全区必须在对应窗口宽度下可操作。

### 自动化窗口矩阵

每批至少按改动涉及的页面执行：

| 场景 | 最低检查要求 |
|---|---|
| 402 dp 左右 compact | 单列、底部导航、可滚动、无横向溢出 |
| 775 dp 左右 expanded | 侧边导航、内容行宽合理、主从内容可读 |
| 840 dp 及以上 | 扩展导航和宽屏约束正常 |
| 纵向物理 hinge | 内容只占安全物理面板；不能跨铰链放置关键控件 |
| 零宽 flat fold | 作为连续画布，不无故损失半屏 |
| 200% 字号 | 标题/正文/操作完整可见，按钮可点击，布局可滚动 |

窗口测试只能证明 Flutter 布局逻辑，不能替代 Find N2 真机验收。

## 7. 配色对比度与真实屏幕阅读验收

### 7.1 自动对比度

- 正常正文、辅助文字和小字号标签：与其实际背景组合至少 4.5:1。
- 大字号文字：至少 3:1；若字号或字重不明确，按 4.5:1 执行。
- 主要控件边界、选中状态和非文本图形：在确实承担识别功能时至少 3:1。
- 不只检查 `onSurface` 与页面底色；必须覆盖实际使用到的 surface、container、主色按钮、Chip、状态标签和领域容器组合。
- 禁止以降低字号、改成更淡的文字或遮盖背景的方式绕过失败断言。

### 7.2 Find N2 实机阅读

在 OPPO Find N2 上分别检查：

1. 外屏折叠状态：首页、知识列表、详情、工具、收藏、设置。
2. 内屏展开状态：同一组页面及列表/详情主从布局。
3. 半折叠状态：文本、表单、按钮避开物理铰链。
4. 浅色与深色主题。
5. 100%、150%、200% 字号。
6. 常用室内阅读光线下的连续阅读体验；每种主题至少连续阅读 15 分钟，记录背景是否刺眼、正文是否清楚、辅助文字是否过淡、分隔线是否过强，以及是否出现卡片过重或信息密度下降。
7. 保存每个关键状态的真实设备截图、系统版本、实际窗口 dp、系统字号档位和异常记录。

实机阅读是主观体验与真实显示条件的联合验收。未取得设备记录前统一为 `MISSING`；不得宣称“护眼”“不伤眼”或“已通过实机”。

## 8. 每批执行流程与合并门槛

1. 从最新已确认的父分支创建独立工作分支；提交前确认 ahead/behind。
2. 改动限制在本批文件，不夹带业务逻辑、上游同步或无关文档清理。
3. 先完成代码审查和针对性测试，再运行完整相关回归。
4. CI 未完成或失败时不合并；失败测试不得删除、跳过或降低验收门槛。
5. 每批提交后记录文件清单、Commit、PR、测试结果和剩余 `MISSING`。
6. 当前批次未完成，不将下一批标为已交付；允许在独立分支推进不依赖前批的只读审计，但集成必须遵守依赖顺序。

### 状态定义

- `PASS`：有可复核的自动化结果或真实设备证据。
- `REJECT`：实际结果不符合明确门槛。
- `MISSING`：需要的测试或证据尚未提供/尚未执行。
- `UNKNOWN`：证据不足，无法判断。
- 不使用主观评分、完成率或未经测量的“成功概率”代替验收结论。

## 9. 当前执行记录

| 项目 | 状态 | 证据 / 说明 |
|---|---|---|
| 设计规范初版 | `PASS` | 本文档已写入仓库分支 |
| 浅色/深色主题 Token | `PASS`（分支内） | `lib/theme/app_colors.dart` |
| Token 对比度自动测试 | `PASS`（CI） | PR #211 的 Flutter regression 与 Android arm64 CI success；Run `43839568819`，Android job `133207359364` |
| Token 已进入 master | `PASS` | PR #211 已合并，集成提交 `ceb4c54c5ee8440b8fa0578058b2434d7fe046c4` |
| Phase 1 首页主题一致性 | `PASS` | PR #211 合并；Run `43839560908` 静态分析/改动测试 success，Run `43839568819` Flutter regression 与 Android arm64 success；合并 SHA `ceb4c54c5ee8440b8fa0578058b2434d7fe046c4` |
| Phase 2 知识与详情改造 | `PASS`（代码与自动化门禁） | PR #212，最终 HEAD `8f997362eb9574d02ab2b541a75a526428e45b66`；Flutter 全量回归 Run `43851588625` success；push 分支校验 Run `43851581819` success |
| Phase 2 集成状态 | `PASS` | PR #212 已于 2026-11-16 squash 合并；master 集成 SHA `7681d6584d3a3667a5f54a19fac0f675774fd749` |
| Phase 2 合并后主线 CI | `PASS` | master SHA `7681d6584d3a3667a5f54a19fac0f675774fd749`：Flutter tests Run `43855518336` success；Android arm64 job `133261664292` success；Flutter Quality Gate Run `43855518261` success |
| Phase 3.1 收藏/设置/历史改造 | `PASS`（代码与自动化门禁） | PR #214；HEAD `b29b09b3fb6d61cad11d99dd52f6cc6a607678f3`；Flutter 全量回归 Run `43864106649` success；Android arm64 job `133290336254` success；分支静态分析及 6 个 Widget tests Run `43863636922` success |

| Phase 3.1 集成状态 | `PASS` | PR #214 于 2026-11-16 squash 合并；master 集成 SHA `7d1dfec8cb4dcfa831177a86082fbc165e01d205` |
| Phase 3.1 合并后主线 CI | `PASS` | master SHA `7d1dfec8cb4dcfa831177a86082fbc165e01d205`：Flutter tests Run `43865416982` success；Android arm64 job `133294922898` success；Flutter Quality Gate Run `43865416976` success |
| Phase 3.2 命盘库与诊断历史 | `PASS`（代码与自动化门禁） | PR #217；HEAD `12b3859a05d4bfcf28ff51605d48107a77218e4a`；分支 Run `43865969348` success；Flutter 全量回归 Run `43866032021` success；Android arm64 job `133296754178` success |
| Phase 3.2 集成状态 | `PASS` | PR #217 于 2026-11-16 squash 合并；master 集成 SHA `68b2b2d8869daf4f9f6a60e61a3c50cbd624c915` |
| Phase 3.2 合并后主线 CI | `UNKNOWN`（运行中） | master SHA `68b2b2d8869daf4f9f6a60e61a3c50cbd624c915`：Flutter tests Run `43868280609` 与 Flutter Quality Gate Run `43868280610` 正在执行；Android arm64 job 待主线 workflow 报告 |
| Phase 3.3 闭门课重症临床列表 | `IN_PROGRESS`（分支定向测试待验收） | 分支 `work/yanji-editorial-phase3-auxiliary`，基线 master SHA `68b2b2d8869daf4f9f6a60e61a3c50cbd624c915`；最新测试 HEAD `ea178de5cbf76033d9693fc3f3f688030f97779a`；push Run `43868608311` 进行中 |
| Phase 3.3 集成状态 | `MISSING` | 尚未建立 PR；须先通过分支静态分析与定向测试，再通过 PR 全量 Flutter 与 Android arm64 门禁 |
| Find N2 实机阅读 | `MISSING` | 需要 OPPO Find N2 真实设备截图、系统/窗口参数和连续阅读记录 |

