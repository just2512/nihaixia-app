# 研纪前端视觉规范与分批实施计划

> 版本：v1.0  
> 建立日期：2026-11-16  
> 执行原则：保留现有杂志式风格，以最小改动完成统一；本文件是后续前端视觉改造的执行基线。  
> 当前阶段：Phase 1–4 自动化验收已完成并合并；OPPO Find N2 真实设备阅读仍为 `MISSING`，不得以模拟器、Widget 或 CI 结果替代。

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

**集成补充（PR #272）**

- PR [#272](https://github.com/just2512/nihaixia-app/pull/272) 已普通 merge，集成 SHA：`5bb248f94d3e7a94bb827c78ad12ed461c828af6`；PR HEAD：`70925814f63d96cda50a0bdc227669db51401e95`。仅修改 `test/home_screen_entry_test.dart`，新增 92 行集成测试，不改生产代码。
- 补齐完整 `HomeScreen`（AI 内容 + 根导航）在 402/775dp、浅/深主题、200% 字号下的组合覆盖，以及半折叠物理 hinge × 浅/深主题 × 200% 覆盖。
- PR #272 当前 HEAD Flutter regression Run `44210565030`：`SUCCESS`；Android arm64 job `134489972009`：`SUCCESS`。完整 Flutter 回归报告为 1,725 passed、15 skipped。
- 15 项 skipped 均来自 `test/yunqi_engine_test.dart` 对外部 `D:\tools\yunqi_ref.json` 的依赖；仓库未包含该文件，CI 未设置 `YUNQI_REF_PATH`。这些对拍断言保持 `MISSING`，不计为 PASS，也未删除或降低测试。Branch validation 按 workflow 条件 skipped，不计 PASS/失败。

### Phase 2：知识浏览与核心详情

**主要文件**
- 知识入口：`lib/screens/knowledge_screen.dart`、`lib/screens/search_tab.dart`。
- 经典阅读：`lib/screens/classic_library_screen.dart`、`lib/screens/shanghan_jingui_screen.dart`、`lib/screens/neijing_knowledge_screen.dart`。
- 核心详情：`lib/screens/formula_detail_screen.dart`、`lib/screens/herb_detail_screen.dart`、`lib/screens/acupoint_detail_screen.dart`、`lib/screens/meridian_detail_screen.dart`、`lib/screens/medical_case_detail_screen.dart`。
- 针灸浏览与详情入口：`lib/screens/acupuncture_screen.dart`、`lib/screens/acupoint_detail_screen.dart`。
- 相关回归：`test/acupuncture_editorial_typography_test.dart`、`test/acupuncture_half_fold_root_navigation_test.dart`。
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

**集成补充（PR #304 / #306）**

- **针灸排版与窄屏换行**：PR [#304](https://github.com/just2512/nihaixia-app/pull/304) 已合并，merge SHA `be0db216d277ff755eb0f0d5f02541a0c7f6f921`。针灸页字号改用 `AppType` Token；窄屏条目标题与来源操作区改用可换行布局；保留针灸资料、搜索筛选、讲稿入口、经络图入口和详情路由。
- **真实根导航半折叠验收**：PR [#306](https://github.com/just2512/nihaixia-app/pull/306) 已合并，merge SHA `4b0e12e7ab159ef6e2a70963dc793dfb0a27ce88`。新增 `test/acupuncture_half_fold_root_navigation_test.dart`，通过真实 `HomeScreen → AdaptiveHomeNavigation → KnowledgeScreen → 针灸 Tab` 进入页面；覆盖浅/深主题、200% 字号、800×900 dp 与 x=388..412 dp 物理 hinge，检查知识页和针灸内容不越过 388 dp 安全面板，并实际进入穴位详情检查详情页边界及字号继承。
- **针灸四 Tab 专项矩阵**：PR #304 同时加入 `test/acupuncture_editorial_typography_test.dart`，覆盖 402/775 dp、浅/深主题、200% 字号、四个子 Tab 和可展开内容；针灸半折叠集成测试补充覆盖真实根导航和穴位详情，不以独立挂载页面替代导航链路验收。

### Phase 3：工具、收藏、设置与辅助页面

**当前主线复核基线**：`69c2b3d191e12f6cf2916650f673afcf8e5ffc2a`（2026-11-19，PR #337 合并后）。本阶段既定页面批次与半折叠路由验收均已落地；后续只处理有明确复现证据的问题，不为制造改动而重做页面。

**已合并批次与边界**

- **收藏、设置、历史对话**：PR #214，集成 SHA `7d1dfec8cb4dcfa831177a86082fbc165e01d205`。保留收藏筛选/移动/删除/导出、设置持久化、历史会话恢复与批量删除。
- **命盘库、诊断历史**：PR #217，集成 SHA `68b2b2d8869daf4f9f6a60e61a3c50cbd624c915`。保留排盘入口、出生数据、左滑删除、六经趋势和历史记录。
- **闭门课重症列表**：PR #219，集成 SHA `e58d6035fb29843ca419069191683198a17aa3f4`。压平连续列表中的不必要 Card，保留七条内容、Markdown 原文和药材/方剂精确匹配跳转。
- **农历节日与神诞**：PR #220，集成 SHA `5d9326c30707fee7503adaaafdbb1f094852eb53`。用轻分隔线替代重复 Card，保留双来源合并、农历排序、名称过滤和公历换算。
- **工具入口大字号**：PR #226，集成 SHA `45a11103406a6912452b861c2bd45bb75216eb57`。修复标题/摘要在 200% 字号下的信息截断，保留入口顺序、分区与路由。
- **易经工具卡片**：PR #227，集成 SHA `2219b29949b1a8aabfdfe4651c821fdf929075db`。移除不必要的卡片阴影，不改变工具内容和操作。
- **紫微斗数折叠布局**：PR #240，集成 SHA `3dc7fb793848fcd92f11c21ba970e7b1837d8126`。补充 200% 字号与折叠窗口布局覆盖。
- **五运六气**：PR #247、#248、#255、#264 分别以 SHA `baa74865650f8bba0835051ada224df6941cf374`、`f1fb3afdf80b241548d524ba9746ff108acd223f`、`3f8f4bee141b6c1614e479d66cac4749b50346f3`、`4136bc616fa382cc7196e277c99f67f7f3e23007` 合并。覆盖图表文字对比度、标题换行、CustomPainter 的 TextScaler，以及五行徽章背景随实际文字高度增长；未降低字号或裁切文字。
- **剂量换算器**：PR #262，集成 SHA `65849447e99e3349e58c62db1639ee18d2789cbd`，补充 200% 字号布局回归。
- **浅深主题补充覆盖**：PR #266，集成 SHA `21dbee152e4df941a80bc0467ccfcb3edcadac9e`，为收藏、诊断历史、设置等页面补齐深色主题与 200% 字号测试。
- **命盘库深色主题**：PR #267，集成 SHA `ead5a676aa508d54f5a392f3545625dce76b7622`，补齐 775dp expanded、深色主题、200% 字号、长命盘名称/出生地点和排盘入口可达性测试。

**阶段结论**

- 上述 Phase 3 批次均已合并，PR #267 的 Flutter regression 与 Android arm64 均为 success。
- 工具入口、收藏、设置、历史、命盘库、诊断历史、易经、紫微、五运六气和辅助列表不再有本阶段待合并项。
- 保留所有工具参数、计算结果、领域语义色、诊断/排盘业务逻辑、数据库、持久化键与导航路由。
- 后续发现问题时按页面独立建分支、先复现再最小修复；不开展全仓 UI 重写。

### Phase 4：跨页面一致性与最终验收

**自动化状态**：`PASS`。**真实 Find N2 阅读验收**：`MISSING`。

- 原有 PR #211 已对主题主文字、辅助文字在背景/表面层级，以及主色/主色容器建立自动对比度断言。
- PR #265 已合并，集成 SHA `6103dfba234f0b4a5477632f2b4c6b400ab829eb`；PR HEAD 为 `f903bb15a9da98f84c2673bcc03b30b26d93f83d`，仅新增 `test/editorial_semantic_contrast_test.dart`，不修改颜色 Token 或生产页面。
- PR #265 覆盖浅/深主题下 danger、warning、success、info 对页面背景，onDanger 对 danger，onSurface 对四类状态容器，以及六经前景色对各自语义容器；正常文字阈值为 4.5:1。
- PR #265 Flutter regression Run `44103235167` success；Android arm64 job `134112303183` success。Branch validation 为条件性 skipped，不计作通过或失败。
- PR #265 合并前，基线 `ead5a676aa508d54f5a392f3545625dce76b7622` 的 Flutter regression Run `44103069300` 与 Android arm64 job `134112172642` 均 success。
- PR #265 合并后的 master `6103dfba234f0b4a5477632f2b4c6b400ab829eb` 已复核：Flutter regression Run `44105085769` 与 Quality Gate Run `44105085816` 均 `SUCCESS`。
- 自动化 `PASS`、实机 `PASS`、`REJECT`、`MISSING`、`UNKNOWN` 分开记录；不以平均分掩盖单项失败。
- PR #272 合并后的最新 master 为 `5bb248f94d3e7a94bb827c78ad12ed461c828af6`；合并后 Flutter tests Run `44211890081`、Android arm64 job `134493862255`、Flutter Quality Gate Run `44211890175` 均 `SUCCESS`。
- Find N2 的外屏/内屏/半折叠、浅深主题、100%/150%/200% 字号及连续阅读检查，按第 7.2 节执行。未取得真实设备截图、系统版本、窗口 dp、字号档位及连续阅读记录前，保持 `MISSING`。
- 2026-11-19 PR #337 合并后：master HEAD `69c2b3d191e12f6cf2916650f673afcf8e5ffc2a`；Flutter regression Run `44491439429` 与 Android arm64 job `135450312683` 均 `SUCCESS`。Flutter Quality Gate Run `44491439602` 仍在进行 Android native unit tests / Find N2 arm64 Debug APK 阶段，终态尚未确认；不得将其提前记为 `PASS`。
- 2026-11-19 主线最新复核：HEAD `82d38c9d77ccac55555d18a943e204e9a6886531`；Flutter regression Run `44470735725` 为 `SUCCESS`，Android arm64 CI job `135381277649` 为 `SUCCESS`，Flutter Quality Gate Run `44470735746`（job `135379277558`）为 `SUCCESS`。这组结果覆盖 PR #304/#306 合并后的当前主线，不使用旧 SHA 的 CI 结果替代。

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
| 设计规范与浅深主题 Token | `PASS`（自动化） | PR #211 已合并；主题 Token、主文字/辅助文字与表面层级、主色和主色容器的自动对比度断言进入 master。 |
| Phase 1：首页、根导航与 AI 首屏 | `PASS`（自动化） | PR #211/#272 的首页与主题基础验收继续有效；PR #282 在最新主线补齐真实 `HomeScreen` 根导航、AI 首屏、402/775dp、浅深主题、200% 字号及半折叠铰链集成验证，合并 SHA `f25d96f03d8ac6c2a80521baf1edc71384fc0482`。PR #282 HEAD Flutter regression Run `44236524275` 与 Android arm64 均 success；合并后 master HEAD `e9658c9f98ee0651c170a784fcaa154bdca4057b` 的 Flutter Run `44242753459`、Quality Gate Run `44242753430` 均 success。Phase 1 云端自动化验收收口；Find N2 实机阅读仍单独保持 `MISSING`。 |
| 五运六气外部对拍夹具 | `MISSING` | PR #272 完整 Flutter regression 中 15 项 `test/yunqi_engine_test.dart` 测试因外部 `D:\tools\yunqi_ref.json` 不在仓库且 CI 未设置 `YUNQI_REF_PATH` 而按原测试逻辑 skipped；未删除、跳过代码或降低断言。 |
| Phase 2：知识浏览、经典和核心详情 | `PASS`（自动化） | PR #212 合并 SHA `7681d6584d3a3667a5f54a19fac0f675774fd749`；PR Flutter regression Run `43851588625` success，合并后主线 Flutter / Android arm64 / Quality Gate success。 |
| Phase 2 补充：古籍原文库 | `PASS`（自动化） | PR #222 合并 SHA `68896b3179b49271522957a7877d08268c8cbdbd`；最终 HEAD `7974d16f1e64b25b8bce9b5ac5d9cfd47e2c87de`。测试改用测试专用内存 AssetBundle，避免重复读取大型真实古籍资产；合并后 master Flutter Run `43901866825`、Android arm64 与 Quality Gate Run `43901867004` success。 |
| Phase 2 补充：针灸排版与半折叠详情 | `PASS`（自动化） | PR #304 合并 SHA `be0db216d277ff755eb0f0d5f02541a0c7f6f921`，以 AppType Token 统一针灸字号并修复窄屏换行；PR #306 合并 SHA `4b0e12e7ab159ef6e2a70963dc793dfb0a27ce88`，新增真实根导航下半折叠针灸四 Tab/穴位详情验收，覆盖浅深主题和 200% 字号。 |
| Phase 2 补充：六经、经典正文与医案半折叠详情 | `PASS`（自动化） | PR #337 合并 SHA `69c2b3d191e12f6cf2916650f673afcf8e5ffc2a`；新增 `test/phase2_remaining_half_fold_routes_test.dart`，从真实根导航进入六经详情、伤寒论篇目正文、倪师医案详情；覆盖 800×900 dp、x=388..412 dp 物理 hinge、浅深主题、200% 字号及 SQLite FFI 异步收尾。分支静态分析与定向 Flutter 测试 2/2 SUCCESS，PR 全量 Flutter regression 与 Android arm64 CI 均 SUCCESS。 |
| 当前主线 Flutter / Android CI | `PASS` | HEAD `69c2b3d191e12f6cf2916650f673afcf8e5ffc2a`；合并后 Flutter regression Run `44491439429` 为 `SUCCESS`；同一 run 的 Android arm64 job `135450312683` 为 `SUCCESS`，包含 arm64 APK 构建、Manifest/ABI/SHA-256 校验与 Android local unit tests。 |
| Phase 3：工具、收藏、设置、历史与辅助页面 | `PASS`（自动化） | PR #214/#217/#219/#220/#226/#227/#240/#247/#248/#255/#262/#264/#266/#267 均已合并；集成 SHA 见第 5 节。覆盖列表减阴影/细分隔、工具标签 200% 换行、紫微折叠布局、五运六气对比度/文本缩放/徽章高度、剂量换算器 200%，以及收藏/设置/历史/命盘库浅深主题。 |
| 五行徽章文字与背景高度 | `PASS` | PR #264 合并 SHA `4136bc616fa382cc7196e277c99f67f7f3e23007`；背景高度改为依据实际 TextPainter.height 计算，200% 几何断言进入 master。 |
| Phase 4：跨页面语义色对比度 | `PASS`（自动化） | PR #265 合并 SHA `6103dfba234f0b4a5477632f2b4c6b400ab829eb`；当前 HEAD Flutter regression Run `44103235167` success、Android arm64 job `134112303183` success。覆盖浅深主题状态色、容器和六经文字/容器配对。 |
| PR #265 合并后的主线 CI | `PASS` | master HEAD `6103dfba234f0b4a5477632f2b4c6b400ab829eb`；Flutter regression Run `44105085769` 与 Quality Gate Run `44105085816` 均 success。 |
| Find N2 外屏/内屏/半折叠真实阅读 | `MISSING` | 仍需 OPPO Find N2 真实设备截图、系统版本、实际窗口 dp、字号档位及浅深主题连续阅读记录。CI/Widget/模拟器不替代实机。 |

