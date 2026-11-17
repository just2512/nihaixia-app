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

**当前主线基线（2026-11-17）**：`3f8f4bee141b6c1614e479d66cac4749b50346f3`。后续每一批仍须以执行时最新 `master` 为基线；本节 SHA 是本次文档更新时的状态快照，不是永久基线。旧 Phase 1 分支 `work/yanji-editorial-phase1` 已分叉，不得继续作为实施基线。

**已合并批次**

- **Phase 3.1：收藏、设置与历史对话**。PR #214 已合并，集成 SHA `7d1dfec8cb4dcfa831177a86082fbc165e01d205`；全量 Flutter、Android arm64 和专项测试通过。保留收藏筛选/移动/删除/导出、设置持久化、历史会话恢复与批量删除。
- **Phase 3.2：命盘库与诊断历史**。PR #217 已合并，集成 SHA `68b2b2d8869daf4f9f6a60e61a3c50cbd624c915`；全量 Flutter、Android arm64 和专项测试通过。保留排盘入口、出生数据、左滑删除、六经趋势与历史记录。
- **Phase 3.3：闭门课重症临床列表**。PR #219 已合并，集成 SHA `e58d6035fb29843ca419069191683198a17aa3f4`。移除连续列表中不必要的高 elevation Card，保留七条内容、Markdown 原文、药材精确匹配优先于方剂匹配的跳转。
- **Phase 3.5：农历节日与神诞检索**。PR #220 已合并，集成 SHA `5d9326c30707fee7503adaaafdbb1f094852eb53`。使用轻分隔线替代重复 Card，元数据自然换行；保留双来源合并、农历月日排序、名称过滤和公历换算。
- **Phase 3.6：工具入口大字号布局**。PR #226 已合并，集成 SHA `45a11103406a6912452b861c2bd45bb75216eb57`。工具标题和摘要改为自然换行；对应测试覆盖 402/775dp、浅深主题、200% 字号，并保留入口顺序与原有详情路由。工具入口表面原本已是单层主题 `Material + InkWell`，没有进行整体重绘。
- **Phase 3.6：易经六十四卦布局**。PR #227 已合并，集成 SHA `2219b29949b1a8aabfdfe4651c821fdf929075db`。移除起卦方法区不必要的 Card 阴影；保留 Tab、起卦方法、讲义入口与卦象内容。对应测试覆盖 402/775dp、浅深主题、200% 字号及窄屏网格单元格增高。
- **Phase 3.6：紫微排盘布局**。PR #240 已合并，集成 SHA `3dc7fb793848fcd92f11c21ba970e7b1837d8126`。修正 200% 字号下摘要、宫名/徽标和大限条目换行，并覆盖外屏/内屏/物理 hinge 的布局边界；不改变排盘计算。
- **Phase 3.7：五运六气图表标签对比度**。PR #247 已合并，集成 SHA `baa74865650f8bba0835051ada224df6941cf374`。按实际对比度生成图表文字前景色，自动测试浅深主题 × 木火土金水组合至少达到 4.5:1；不改五行底色、运算数据与绘图几何。
- **Phase 3.7：五运六气页面标题 200%/半折叠换行**。PR #248 已合并，集成 SHA `f1fb3afdf80b241548d524ba9746ff108acd223f`。修正 `_KeyValueCard` 标题 Row 的弹性约束，解决 402dp 深色主题 200% 和半折叠窄面板的真实 RenderFlex overflow；不改 132dp 标签列、五运六气算法、数据和路由。

**当前独立批次**

- **五运六气三张图的 CustomPainter 字号适配**。PR #255 已合并，集成 SHA `3f8f4bee141b6c1614e479d66cac4749b50346f3`。分支 `work/yanji-yunqi-chart-text-scale-20261117` 的最终 HEAD 为 `01c1ed57469bfb4cc764e85a806552b87a9cd54e`，合并前基线为 `f1fb3afdf80b241548d524ba9746ff108acd223f`。根因由测试复现：系统 TextScaler 从 100% 改为 200% 时，五行图、五运图、六气图三个 painter 原先均未请求重绘。修复将系统 TextScaler 传到 painter、TextPainter 和字号宽度测量，并纳入 shouldRepaint。合并前 Push branch validation Run `44060140912`、PR Flutter 全量回归 Run `44060482065`、Android arm64 APK/ABI/native unit tests 均 SUCCESS。该批证明图表绘制层能接收系统缩放并触发重绘；尚未证明 200% 下各标签完全无重叠或边缘裁切，后续仍需独立做图表空间适配及真实设备阅读验收。
- **其余工具详情页逐页审计**。继续对尚未有专项证据的工具详情页检查 Card 是否承担参数/结果分组、固定高度、固定字号、标签省略和内容滚动。按实际缺陷逐页 test-first；不得仅因存在 Card 或固定字号就批量删除/放大。
- 收藏、设置、历史页面已完成；除新发现可复现缺陷外不重复改造。
- `tools_screen.dart` 入口标题/摘要自然换行已由 PR #226 完成，不再列为待修复项。

**实施与合并门槛**

- 保留工具参数、计算结果、领域语义色、诊断/排盘业务逻辑、数据库及导航路由。
- 200% 字号不截断重要标题、摘要、表单标签或操作；文字自然换行，操作仍可触达。
- 按页面覆盖 402dp、775dp、浅深主题；涉及折叠布局的页面继续覆盖 840dp、物理 hinge、零宽 fold 和半折叠场景。
- CustomPainter 图表除了验证 TextScaler 变化能触发重绘，还要检查 200% 下标签的空间适配；单独的 shouldRepaint 断言不足以证明文字没有相互覆盖。
- 先定向测试与静态分析，再完整 Flutter regression、Android arm64；CI 未完成或失败不合并。
- 每批从最新主线建立独立分支，合并时保留依赖关系；旧 HEAD CI 不继承到新 HEAD；未取得真机证据不得声称 Find N2 实机通过。

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
- 大字号文字：至少## 9. 当前执行记录

| 项目 | 状态 | 证据 / 说明 |
|---|---|---|
| 设计规范与浅深主题 Token | `PASS`（自动化） | PR #211 已合并；浅深主题 Token 和自动对比度回归进入 master。 |
| Phase 1：首页、根导航与 AI 首屏 | `PASS`（自动化） | PR #211 合并 SHA `ceb4c54c5ee8440b8fa0578058b2434d7fe046c4`；原记录的 Flutter regression Run `43839568819` 与 Android arm64 job `133207359364` success。首页入口/hinge、根导航 200% 与 fold、AI 首屏外屏/内屏 200% 和半折叠 hinge 有自动化覆盖。Find N2 实机阅读另记为 MISSING。 |
| Phase 2：知识浏览、经典和核心详情 | `PASS`（自动化） | PR #212 合并 SHA `7681d6584d3a3667a5f54a19fac0f675774fd749`；原记录的 Flutter regression Run `43851588625` success，合并后 master Flutter / Android arm64 / Quality Gate 有成功记录。 |
| Phase 2 补充：古籍原文库 | `PASS`（自动化） | PR #222 合并 SHA `68896b3179b49271522957a7877d08268c8cbdbd`；使用测试专用内存 AssetBundle，避免测试直接重复读取大型真实古籍资产。合并后 master Flutter Run `43901866825`、Android arm64 与 Quality Gate 有成功记录。 |
| Phase 3.1：收藏、设置、历史对话 | `PASS`（已合并） | PR #214，集成 SHA `7d1dfec8cb4dcfa831177a86082fbc165e01d205`；全量 Flutter、Android arm64、专项布局/行为测试有成功记录。 |
| Phase 3.2：命盘库、诊断历史 | `PASS`（已合并） | PR #217，集成 SHA `68b2b2d8869daf4f9f6a60e61a3c50cbd624c915`；全量 Flutter、Android arm64、专项测试有成功记录。 |
| Phase 3.3：闭门课重症临床列表 | `PASS`（已合并） | PR #219，集成 SHA `e58d6035fb29843ca419069191683198a17aa3f4`；保留列表内容、Markdown 和原有药材/方剂关联跳转。 |
| Phase 3.5：农历节日与神诞 | `PASS`（已合并） | PR #220，集成 SHA `5d9326c30707fee7503adaaafdbb1f094852eb53`；保留双来源、排序、筛选与公历换算。 |
| Phase 3.6：工具入口 200% 字号换行 | `PASS`（已合并） | PR #226，集成 SHA `45a11103406a6912452b861c2bd45bb75216eb57`；`tools_screen.dart` 标题/摘要自然换行，专项测试覆盖 402/775dp、浅深主题、200% 字号和古籍详情路由。 |
| Phase 3.6：易经六十四卦布局 | `PASS`（已合并） | PR #227，集成 SHA `2219b29949b1a8aabfdfe4651c821fdf929075db`；专项测试覆盖方法区轻表面、Tab 切换与六十四卦窄屏大字号网格。 |
| Phase 3.6：紫微排盘布局 | `PASS`（已合并） | PR #240，集成 SHA `3dc7fb793848fcd92f11c21ba970e7b1837d8126`；专项测试覆盖 200% 字号和外屏/内屏/物理 hinge 布局。 |
| Phase 3.7：五运六气图表文字对比度 | `PASS`（自动化） | PR #247，集成 SHA `baa74865650f8bba0835051ada224df6941cf374`；浅深主题 × 五行五色自动对比度达到正文 AA 门槛。 |
| Phase 3.7：五运六气页面标题换行 | `PASS`（已合并） | PR #248，集成 SHA `f1fb3afdf80b241548d524ba9746ff108acd223f`；402dp 深色主题 200% 和半折叠窄面板的标题溢出有针对性回归测试。 |
| 五运六气 CustomPainter 200% 字号适配 | `PASS`（缩放传递与重绘自动化） | PR #255 已合并，集成 SHA `3f8f4bee141b6c1614e479d66cac4749b50346f3`；最终 HEAD `01c1ed57469bfb4cc764e85a806552b87a9cd54e`。Push branch validation Run `44060140912`、PR Flutter 全量 regression Run `44060482065`、Android arm64 APK/ABI/native unit tests 均 SUCCESS。当前证据证明 TextScaler 传入三张图并在 100%→200% 时触发重绘；标签空间是否完全无重叠/裁切仍需后续专测。 |
| 全局自动对比度 | `PASS`（已有组合） | PR #211 对主题 Token 建立自动对比度断言；PR #247 补充五运六气实际语义底色组合。跨页面实际组合仍应随新组件/页面增量扩展。 |
| Find N2 外屏/内屏/半折叠真实阅读 | `MISSING` | 需要真实设备截图、系统版本、实际窗口 dp、字号档位和阅读记录；CI/Widget 不替代真机。 |

