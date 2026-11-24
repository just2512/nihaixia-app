# 研纪 UI 主题颜色与视觉风格约束

> **文件属性：** 项目级强制约束（Normative）
> **约束编号：** YANJI-UI-THEME-001
> **版本：** v1.0
> **生效日期：** 2026-11-24
> **适用范围：** Flutter App 全局主题、共享组件、业务页面、Android Launcher 与品牌图形资源
> **执行状态：** 当前主题实现基线；页面级迁移按批次推进

## 0. 文件权威性与变更规则

本文件是研纪 UI 主题颜色、表面层级、状态色和品牌视觉方向的**唯一强制约束文件**。后续所有 UI 视觉改造、主题调整、组件重构、页面换肤、品牌资源变更和 PR 评审，必须先读取本文件，并按本文件验收。

文件职责边界：

- 本文件约束颜色 Token、Material 3 角色、浅深主题表面、颜色语义、对比度、状态表达、品牌图形色和相关 CI 门禁。
- 《研纪前端视觉规范与分批实施计划》（docs/yanji-editorial-frontend-design-plan.md）继续约束页面布局、信息密度、字体、排版、间距、圆角、折叠屏和页面实施批次；涉及颜色的内容以本文件为准。
- lib/theme/yanji_palette.dart 是基础色值的代码唯一来源；lib/theme/app_colors.dart 是应用语义颜色唯一映射层；lib/main.dart 是全局 ThemeData 和共享组件主题的统一接线入口。
- lib/theme/app_tokens.dart 继续管理非颜色 Token，不得在本文件之外复制或另建平行的字号、间距、圆角系统。
- test/theme/yanji_contrast_test.dart、test/theme/yanji_theme_wiring_test.dart、test/app_theme_color_scheme_test.dart 与 tool/audit_color_tokens.py 是本约束的自动化执行证据。

发生冲突时按以下顺序处理：

1. 本文件的强制规则优先于页面局部样式和临时设计稿。
2. 代码实现与本文件不一致时，不能默认代码正确；必须修正代码，或通过正式变更流程同步更新本文件和测试。
3. 单个 PR 不得只改颜色值而不更新对比度矩阵、语义说明和回归测试。
4. 未经记录的局部颜色、临时主题覆盖、页面自建 ColorScheme 或绕过 Token 的写法均视为规范偏离。

### 0.1 允许修改本规范的条件

只有在以下证据齐备后才允许改动已冻结的颜色 Token 或语义角色：

- 写明修改原因、涉及角色、旧值/新值、影响页面和预期视觉结果。
- 提交完整的前景色 × 背景表面对比度矩阵；透明状态层先合成到实际背景后再计算。
- 同步更新 YanjiPalette、AppColors、ColorScheme 映射、自动化测试和本文件。
- 提供浅色/深色页面截图；涉及高频阅读页面时，提供 OPPO Find N2 外屏、内屏和 200% 字号的真实设备验收记录。
- 不得以“看起来更好”“统一品牌色”或单张截图作为降低可访问性阈值的理由。

## 1. 品牌视觉定位

### 1.1 风格定义

**现代编辑型杂志风：内容优先、层级清晰、低饱和中性色、高信息密度、轻表面、克制的品牌红。**

研纪的界面服务于中医经典、方剂、本草、针灸、医案和相关知识的长时间阅读，也承载工具、问诊、学习与本地 AI 辅助流程。视觉系统应让内容和操作清晰，而不是以装饰抢占注意力。

### 1.2 必须坚持

- 浅色页面采用中性冷白，不采用大面积纯白作为页面底色，也不采用明显泛黄的宣纸色、仿古纸纹或米黄色大底。
- 页面背景与内容表面以明度差、细分隔线和排版层级分离；默认不依赖阴影建立层级。
- 品牌正红承担品牌识别和主要交互，不承担错误、禁忌、风险或普通正文文字语义。
- 银灰只做装饰性分割；功能灰承担控件识别和功能图形；链接红承担浅底链接文字。三者不得互相替代。
- 保留六经、五行、经络、方位、卦象和其他专业图谱的固定业务语义色，不因品牌统一而全部改为红色。
- 避免大面积高饱和色、厚重卡片、重复容器、强投影、无信息价值的渐变和装饰图案。
- 内容层级优先通过标题字号、字重、栏目编号、说明文字、细分隔线和适量间距体现。

### 1.3 明确禁止

- 重新引入松墨绿作为全局品牌主色，或将旧主题颜色与新品牌红混用。
- 将品牌正红直接用作错误、毒性、禁忌、授权损坏或医疗风险状态的唯一标记。
- 用颜色 alone 表达选中、错误、警告、成功、禁忌或授权状态。
- 因追求颜色统一而修改业务图表、六经图例、五行方位图等领域色的含义。
- 在页面 Widget 中新增裸色值、局部 fromSeed 色板或页面私有主题系统。
- 通过降低文字字号、缩小图标、裁剪文字、锁死容器高度或减少滚动区域来迁就配色布局。

## 2. 品牌基础色板（冻结）

基础色值只允许定义在 lib/theme/yanji_palette.dart。除该文件外，业务代码只能读取 ColorScheme 或 AppColors 语义角色。

| Token | 色值 | 唯一用途 |
|---|---|---|
| coldWhite | #EBECEE | 浅色 Scaffold 页面底色 |
| silverGray | #BCBBBF | 浅色装饰性分割线 |
| brandRed | #D71019 | 浅色品牌主色、主操作和品牌图形 |
| white | #FFFFFF | 浅色卡片/输入表面、品牌按钮前景 |
| charcoal | #252629 | 浅色主文字、容器前景 |
| functionalGray | #808087 | 浅色功能边界和非文本控件图形 |
| textSecondaryLight | #64646B | 浅色次级文字 |
| redOnLight | #B30D15 | 浅色背景链接文字 |
| dangerLight | #A61B1B | 浅色错误/高风险语义 |
| warningLight | #815500 | 浅色警告语义 |
| darkBackground | #17181B | 深色 Scaffold 页面底色 |
| darkSurface | #202227 | 深色卡片、AppBar 和主要内容表面 |
| darkSurfaceContainer | #292B31 | 深色最高层常用容器 |
| darkOnSurface | #F0F1F3 | 深色主文字 |
| darkTextSecondary | #B6BAC4 | 深色次级文字 |
| darkOutline | #8A8E98 | 深色功能边界 |
| darkDivider | #454951 | 深色装饰分割线 |
| darkPrimary | #FF5B62 | 深色品牌主色与主操作 |
| darkOnPrimary | #1F0809 | 深色品牌主色前景 |
| darkLink | #FF858A | 深色背景链接文字 |
| dangerDark | #FF7B72 | 深色错误/高风险语义 |
| onDangerDark | #2B0B09 | 深色实心 danger 前景 |
| warningDark | #FFD166 | 深色警告语义 |
| onWarningDark | #261900 | 深色实心 warning 前景 |

以上基础色板之外的 Material 3 容器色、固定色、反色表面色和透明度辅助值也必须集中在 yanji_palette.dart；不得在页面代码复制十六进制值。

## 3. Material 3 语义角色映射

### 3.1 单一语义入口

应用只保留一个颜色 ThemeExtension：AppColors。不得再创建 YanjiSemanticColors 等第二套平行扩展。

```dart
final scheme = Theme.of(context).colorScheme;
final semantic = context.colors;
```

- Material 标准组件颜色优先读取 Theme.of(context).colorScheme。
- Material 3 没有直接角色的业务语义色（link、warningContainer、六经色、工具分区色等）读取 context.colors。
- AppColors 的新增字段必须同步实现 const/构造约束、copyWith、lerp 和浅深主题实例。
- 对已由 ColorScheme 表达的角色，不得在 AppColors 里再创建一份独立且可漂移的同名语义值；必要的别名必须由测试验证映射一致。

### 3.2 浅色主题语义角色

| Material 3 角色 | 色值 | 说明 |
|---|---|---|
| primary / onPrimary | #D71019 / #FFFFFF | 品牌主色和其前景 |
| primaryContainer / onPrimaryContainer | #F8DADC / #4D1117 | 浅红选中容器和前景 |
| secondary / onSecondary | #64646B / #FFFFFF | 深中性次级角色，不使用功能灰 #808087 承载文字 |
| secondaryContainer / onSecondaryContainer | #E4E4E7 / #252629 | 中性次级容器 |
| tertiary / onTertiary | #64646B / #FFFFFF | 中性第三色角色 |
| tertiaryContainer / onTertiaryContainer | #EBEBED / #252629 | 中性第三色容器 |
| error / onError | #A61B1B / #FFFFFF | 实心错误色及其前景 |
| errorContainer / onErrorContainer | #F6DAD7 / #410E0B | 错误容器及专用前景 |
| surface / onSurface | #FFFFFF / #252629 | 卡片表面及主文字 |
| surfaceDim | #E3E4E6 | 次级表面明度角色 |
| surfaceBright | #FFFFFF | 最亮内容表面 |
| surfaceContainerLowest | #FFFFFF | 最低层表面 |
| surfaceContainerLow | #FAFAFB | 低层容器 |
| surfaceContainer | #F7F7F8 | 标准容器 |
| surfaceContainerHigh | #F4F4F5 | 高层容器 |
| surfaceContainerHighest | #F0F1F2 | 最高层容器 |
| onSurfaceVariant | #64646B | 次级文字 |
| outline / outlineVariant | #808087 / #BCBBBF | 功能边界 / 装饰分割线 |
| inverseSurface / onInverseSurface | #252629 / #FFFFFF | 反色表面及前景 |
| inversePrimary | #FFB3B6 | 反色场景的主色 |
| shadow / scrim / surfaceTint | #000000 / #80000000 / transparent | 框架角色；surfaceTint 必须透明 |

### 3.3 深色主题语义角色

| Material 3 角色 | 色值 | 说明 |
|---|---|---|
| primary / onPrimary | #FF5B62 / #1F0809 | 深色品牌主色和前景 |
| primaryContainer / onPrimaryContainer | #6A252B / #FFE0E2 | 深红选中容器和前景 |
| secondary / onSecondary | #454951 / #F0F1F3 | 深色中性次级角色 |
| secondaryContainer / onSecondaryContainer | #363841 / #F0F1F3 | 深色次级容器 |
| tertiary / onTertiary | #454951 / #F0F1F3 | 深色中性第三色角色 |
| tertiaryContainer / onTertiaryContainer | #3B3D44 / #F0F1F3 | 深色第三色容器 |
| error / onError | #FF7B72 / #2B0B09 | 实心错误色及其前景 |
| errorContainer / onErrorContainer | #7A2220 / #FFE0DC | 深色错误容器及专用前景 |
| surface / onSurface | #202227 / #F0F1F3 | 卡片表面及主文字 |
| surfaceDim | #17181B | 深色低层背景 |
| surfaceBright | #292B31 | 深色最亮表面 |
| surfaceContainerLowest | #17181B | 最低层表面 |
| surfaceContainerLow | #1D2025 | 低层容器 |
| surfaceContainer | #202227 | 标准容器 |
| surfaceContainerHigh | #25282E | 高层容器 |
| surfaceContainerHighest | #292B31 | 最高层容器 |
| onSurfaceVariant | #B6BAC4 | 次级文字 |
| outline / outlineVariant | #8A8E98 / #454951 | 功能边界 / 装饰分割线 |
| inverseSurface / onInverseSurface | #F0F1F3 / #252629 | 反色表面及前景 |
| inversePrimary | #B30D15 | 反色场景的主色 |
| shadow / scrim / surfaceTint | #000000 / #80000000 / transparent | 框架角色；surfaceTint 必须透明 |

### 3.4 Material 3 Fixed 角色（两种亮度保持一致）

| 角色 | 色值 |
|---|---|
| primaryFixed / primaryFixedDim | #FADADD / #F2B7BC |
| onPrimaryFixed / onPrimaryFixedVariant | #3F0B10 / #6B1720 |
| secondaryFixed / secondaryFixedDim | #E4E4E7 / #C8C8CC |
| onSecondaryFixed / onSecondaryFixedVariant | #1F2024 / #4B4C54 |
| tertiaryFixed / tertiaryFixedDim | #EBEBED / #D3D3D8 |
| onTertiaryFixed / onTertiaryFixedVariant | #202126 / #4A4B52 |

### 3.6 浅色/深色主题入口

当前项目已经具备三种主题模式，不属于待设计功能：

- SettingsScreen 的“外观 → 暗黑模式”提供“跟随系统 / 浅色 / 深色”三项选择。
- SettingsRepository 使用 theme_mode 持久化当前选择，默认值为 ThemeMode.system。
- MaterialApp 通过 settings.themeMode 接线，并分别提供 theme: _buildTheme(Brightness.light) 与 darkTheme: _buildTheme(Brightness.dark)。

强制约束：

- 后续颜色改造必须同时验证 light、dark 两套 ThemeData；不得只修浅色主题而破坏深色主题。
- 不得删除、隐藏或改变现有三种模式的语义和持久化行为。
- 不得在 MaterialApp 中将 themeMode 写死为 ThemeMode.light 或 ThemeMode.dark。
- 新增配色、容器、状态和图标资源必须在“跟随系统、手动浅色、手动深色”三种入口下保持一致。
- 本次 Batch 1 只冻结主题色值和视觉规则，不重做主题模式设置交互。

### 3.5 Material 3 接线强制要求

- 使用 Flutter 3.47.0 基线下的 ColorScheme 显式构造；禁止 ColorScheme.fromSeed 自动生成项目主色和组件容器角色。
- ColorScheme 的所有当前 SDK 角色必须显式赋值，包括 primary/secondary/tertiary、所有 on/container/fixed 角色、error、全部 surfaceContainer、outline、inverse、shadow、scrim、surfaceTint。
- 浅色 ThemeData.scaffoldBackgroundColor 必须为 #EBECEE；ColorScheme.surface 必须为 #FFFFFF。二者是不同语义，不得互换。
- 深色 ThemeData.scaffoldBackgroundColor 必须为 #17181B；ColorScheme.surface 必须为 #202227。
- Card、Dialog、BottomSheet 等内容组件不得通过默认 elevation tint 改变指定表面；surfaceTintColor 必须跟随透明 surfaceTint Token。
- 输入框、Chip 等交互控件的可识别边界使用 colorScheme.outline；纯装饰性 Divider 使用 colorScheme.outlineVariant。
- NavigationBar 和 NavigationRail 显式使用 colorScheme.primaryContainer 作为选中指示器，选中图标使用 onPrimaryContainer；不得依赖 Material 默认 secondaryContainer。
- 当前 AppBar、Card、输入框、Chip、Divider 和导航等共享主题只在 lib/main.dart 统一定义。页面不得再创建第二套全局主题。

## 4. 页面底色、内容表面与层级

### 4.1 浅色模式

- Scaffold / 页面大背景：coldWhite #EBECEE。
- Card / AppBar / 主要阅读表面 / 输入框填充：white #FFFFFF。
- 低层次分组：lightSurfaceContainerLow #FAFAFB。
- 普通容器：lightSurfaceContainer #F7F7F8。
- 较高层容器：lightSurfaceContainerHigh #F4F4F5。
- 最高层容器：lightSurfaceContainerHighest #F0F1F2。
- 表面层级主要依赖冷白与容器明度差，不增加厚阴影或大面积描边。

### 4.2 深色模式

- Scaffold / 页面大背景：darkBackground #17181B。
- Card / AppBar / 主要阅读表面：darkSurface #202227。
- 低层容器：darkSurfaceContainerLow #1D2025。
- 普通内容表面：darkSurface #202227。
- 高层容器：darkSurfaceContainerHigh #25282E。
- 最高层容器：darkSurfaceContainer #292B31。
- 深色模式不将页面简单反转为纯黑；应维持背景、表面和内容容器之间的细微可辨识层次。

### 4.3 分层原则

- 页面底色承担整体背景，不承载大面积正文区域。
- 内容表面承载可阅读内容或主要交互；卡片只用于确实需要分组的内容，不将所有段落都包进卡片。
- 输入框填充应可与页面底色识别，边界不能仅靠银灰装饰线承担。
- 分割线保持轻量；没有信息分组意义时不添加额外边框。
- elevation 默认保持 0 或最低限度；除非有明确浮层层级需求，不用阴影替代颜色 Token。

## 5. 颜色语义与组件表达

### 5.1 品牌主色 primary

- 浅色主色 #D71019；深色主色 #FF5B62。
- 用于品牌识别、主操作、主按钮背景、当前选中图形和导航指示。
- 品牌红不用于普通正文、次级说明、错误文字、禁忌文字、毒性文字和授权异常文字。
- 浅色 brandRed 在 coldWhite 上约为 4.47:1，低于普通文字 4.5:1；因此不能将其用于普通小字号文字。小字链接使用 redOnLight。
- 品牌按钮前景分别使用 onPrimary；按钮文字对比度必须单独测试。

### 5.2 链接 link

- 浅色链接：#B30D15；深色链接：#FF858A。
- 链接必须有下划线或其他非颜色交互提示；不可只靠红色让用户判断可点击。
- 链接色不得被拿来充当错误或危险状态文字。

### 5.3 功能灰与装饰银灰

- functionalGray #808087（浅色）和 darkOutline #8A8E98（深色）用于控件边界、非文本控件图形和必要的交互结构。
- 功能灰不是正文色，不用于小字号辅助说明；其对比度必须按实际承载的表面验收。
- silverGray #BCBBBF（浅色）和 darkDivider #454951（深色）用于纯装饰分割线，不用于输入框边界、未选中图标或可操作控件边缘。
- 浅色功能灰相对 coldWhite 的项目内部门槛为 3.3:1，不得仅满足 3.0:1 后再以四舍五入宣称通过。

### 5.4 danger 与 warning

- danger/error 用于真实错误、高风险和禁忌；浅色 #A61B1B，深色 #FF7B72。
- warning 用于需要注意、慎用、资料缺失或可恢复异常；浅色 #815500，深色 #FFD166。
- success 只表达已完成或已激活；info 只表达中性信息，不得与 danger/warning 混用。
- brandRed 和 danger 即使视觉接近，也必须通过标签、图标、边框和文案结构区分，不得仅靠色相让用户辨认。

### 5.5 风险提示的非颜色冗余

十八反、十九畏、妊娠禁忌、有毒本草、剂量风险等必须同时具有：

1. 明确图标（例如 warning_amber 或项目约定的风险图标）。
2. 文字标签（例如【禁忌】【有毒】【慎用】【注意】）。
3. 说明文字，清楚描述风险来源和适用范围。
4. 与状态语义一致的边界容器。

不得只把药名、剂量或一段文字涂成红色。

errorContainer 内的正文和图标使用 colorScheme.onErrorContainer；不得直接使用 dangerDark 作为深色 errorContainer 的正文前景。warningContainer 内的文字/图标使用 semantic.warning；onWarning 仅用于实心 warning 色背景上的前景。

### 5.6 专业版授权和门禁状态

| 状态 | 视觉语义 | 呈现约束 |
|---|---|---|
| checking / temporarilyUnavailable | neutral | 中性进度或说明，不显示错误红条 |
| unlicensed | neutral | 未授权是可预期产品状态，不等同于程序故障 |
| keyMissing / deviceMismatch / storeCorrupt | warning | 可恢复问题，给出明确的重新申请/恢复操作 |
| signatureInvalid / issuerUnknown | danger | 明确错误图标、状态码、说明和处理边界 |
| 已激活 | success | 勾选图标和【已激活】标签；不得只依赖品牌红 |

具体授权业务状态的映射必须服从专业版授权协议；本表只约束用户可见表达，不改变授权判定逻辑。

### 5.7 导航、Tab 和选中态

- 选中态必须同时具有颜色和结构线索；例如浅红 primaryContainer 指示器、onPrimaryContainer 实心图标、加粗文字或 2dp 指示条。
- 当前 NavigationBar / NavigationRail 已将 indicatorColor 显式绑定 primaryContainer；不要把 secondaryContainer 误当成导航选中色。
- 未选中状态以 onSurfaceVariant 和 outline 等中性色表达；不得通过全红导航造成持续视觉噪声。
- 页面 Tab、栏目、筛选 chip 的颜色变化不能成为唯一的选中提示，应有下划线、形状、字重或明确的指示器。

### 5.8 领域专用色与受控豁免

以下专用色允许保留独立业务含义：六经、五行、八卦方位、经络流注、卦象、云气图表、术数盘面、工具分区和资料来源图例。

豁免条件：

- 仅对承担明确领域分类或数据可视化含义的颜色开放，不包括普通页面背景、按钮、文本、边框或导航。
- 在 tool/color_token_audit_allowlist.json 中逐文件登记用途和理由；禁止整目录或整模块无理由豁免。
- 该颜色必须同时有浅色与深色搭配规则；当承担文字或有意义图形时，必须进入相应对比度测试。
- 领域色不得伪装成品牌色、危险状态或授权状态；如语义冲突，以明确标签和组件结构优先纠正。
- 业务图谱的原始数据和含义不得因配色重构而改变。

## 6. 对比度与可访问性硬门槛

### 6.1 阈值

| 项目 | 最低阈值 | 项目执行规则 |
|---|---:|---|
| 普通正文、辅助文字、链接、按钮文字 | 4.5:1 | 对每一种实际出现的表面分别验证 |
| 大字号文字 | 3.0:1 | 只有符合 WCAG 大字定义时才可用该阈值；不得擅自把普通标题归入大字 |
| 控件边界、状态图形和有意义非文本信息 | 3.0:1 | 对实际表面分别验证 |
| 浅色 functionalGray #808087 | 3.0:1 | 项目内部提高至 coldWhite 上 ≥3.3:1 |
| 装饰性分割线 | 不强制达到 3.0:1 | 仅限无交互、无需辨认的装饰用途 |

### 6.2 必须覆盖的表面矩阵

浅色主题至少覆盖：

- coldWhite 页面背景 #EBECEE。
- white 卡片和输入框填充 #FFFFFF。
- lightSurfaceContainerLow #FAFAFB。
- lightSurfaceContainer #F7F7F8。
- lightSurfaceContainerHigh #F4F4F5。
- lightSurfaceContainerHighest #F0F1F2。
- 实际存在的 primaryContainer、secondaryContainer、tertiaryContainer、errorContainer、warningContainer。
- 悬停、按下、焦点、禁用等状态层与其背景合成后的结果。

深色主题至少覆盖：

- darkBackground #17181B。
- darkSurfaceContainerLow #1D2025。
- darkSurface #202227。
- darkSurfaceContainerHigh #25282E。
- darkSurfaceContainer #292B31。
- 实际存在的 primaryContainer、secondaryContainer、tertiaryContainer、errorContainer、warningContainer。
- 悬停、按下、焦点、禁用等状态层与其背景合成后的结果。

### 6.3 计算规则

- 使用 WCAG 相对亮度公式；sRGB 线性化分段阈值采用 0.04045。
- 测试比较未四舍五入的原始 double 值；输出日志可以格式化显示，但不得用显示值代替门槛判断。
- alpha 颜色必须先用实际 opacity 与具体背景进行合成，再计算前景色与合成背景的对比度。
- withOpacity、withValues、Color.fromARGB、Color.fromRGBO 和状态层均属于审计范围。
- 测试不得只验证页面背景；同一语义色可能同时出现在卡片、输入框、弹层或容器上。
- 组合不满足阈值时，应更换前景/背景语义配对或改变组件结构，不得降低阈值掩盖问题。

### 6.4 自动化证据

- test/theme/yanji_contrast_test.dart：浅深主题多表面文字、链接、错误、警告、控件边界、状态层合成、容器前景及 Material 3 Fixed 角色。
- test/theme/yanji_theme_wiring_test.dart：Scaffold/surface 分离、surfaceTint、控件边界和导航选中指示器。
- test/app_theme_color_scheme_test.dart：AppColors 与 ColorScheme 语义映射。
- test/editorial_semantic_contrast_test.dart：既有编辑型组件和领域色回归。
- test/yanji_android_icon_resource_test.dart：品牌图标资源与基础色板一致性。

CI PASS 只代表自动化检查通过，不代表 OPPO Find N2 实机视觉验收已经完成。

## 7. 颜色静态审计与 CI 门禁

工具：tool/audit_color_tokens.py；白名单：tool/color_token_audit_allowlist.json。

审计覆盖 lib/**/*.dart 中的：

- Color(0x...)。
- Color.fromARGB(...)。
- Color.fromRGBO(...)。
- Colors.* 及 Colors[...]。
- withOpacity(...) 和 withValues(...)。
- 页面或组件内新建 ThemeData(...)。

运行模式：

- --inventory：输出历史遗留颜色用法基线，供分批迁移。当前阶段不因历史债务一次性失败。
- --changed-only --base-ref <ref>：仅审查相对基线新增的 Dart 行；新增页面级颜色字面量或局部 ThemeData 默认拒绝。
- 新增颜色必须放入 yanji_palette.dart / AppColors，或对具有真实业务语义的专用色提出逐文件白名单申请。

白名单必须包含具体文件路径和非空理由，并接受浅深主题对比度验证；不得将白名单用作绕过通用 UI 约束的渠道。

现有历史硬编码颜色被 inventory 记录，不表示它们自动合规。后续页面迁移应逐批将其替换为语义 Token；不得借批量替换破坏领域语义或测试。

## 8. 后续 UI 执行流程与合并门槛

### 8.1 每批执行步骤

1. **先审计：** 列出页面/组件的现有颜色、背景层级和状态表达；区分通用界面、领域图例和第三方资源。
2. **再映射：** 为每种颜色指定唯一语义角色和实际背景；不得直接按色相批量替换。
3. **最小改动：** 先修全局 Theme 和共享组件，再修实际偏离规范的页面局部；不为制造改动而改动已合规页面。
4. **自动验收：** 跑颜色对比度、Theme 接线、静态审计、受影响 Widget/Golden 测试和全量回归。
5. **视觉验收：** 浅色/深色、窄屏/展开屏、默认字号/200% 字号均检查文本换行、层级和滚动。
6. **实机验收：** 涉及阅读体验、系统图标或窗口姿态时，记录 OPPO Find N2 实际设备的外屏、内屏/半折叠场景；无法测试必须标记 MISSING。
7. **更新约束：** 新增 Token、例外或角色映射必须先更新本文件和对应测试，再合并实现。

### 8.2 PR 必须回答

- 哪些 Token 或语义角色发生变化？为什么？
- 涉及哪些表面和状态层？完整对比度矩阵在哪里？
- 是否引入新颜色或局部 ThemeData？静态审计结果是什么？
- 是否保留六经、五行、经络、方位和图谱等业务语义？
- 是否改变页面信息结构、导航顺序、业务行为、数据库或模型流程？若是，必须拆出独立需求和验收。
- 浅深主题与 200% 字号是否通过？哪些真实设备证据仍为 MISSING？

### 8.3 禁止合并的情况

- 任一文字/控件对比度未通过。
- 品牌红与风险状态仍只靠颜色区分。
- 页面新增未登记的颜色字面量或局部主题。
- Material 3 角色依赖 SDK 默认回退或 fromSeed 自动推导。
- 只更新文档但代码/测试不一致，或只更新代码但本文件未更新。
- 用 CI、模拟器或 Widget 测试冒充 Find N2 实机验收。
- 以主题改造名义改变诊断、问诊、排盘、数据库、路由、模型调用或授权判定逻辑。

## 9. 与既有设计系统的边界

本文件不重新定义以下内容，后续执行沿用 docs/yanji-editorial-frontend-design-plan.md 与 lib/theme/app_tokens.dart：

- 字体族、字号阶梯、中文长文行高、段距和标题层级。
- AppSpacing、AppRadius、AppType、AppFonts 和 AppTextScale。
- 首页信息架构、根导航顺序、Tab 顺序、KeepAlive、检索、详情跳转和折叠屏路由。
- 页面具体布局和内容密度。

执行这些内容时，只要涉及颜色、表面、状态和品牌图形，仍必须遵守本文件。

## 10. 当前落地状态

| 项目 | 当前状态 | 证据/边界 |
|---|---|---|
| 基础色板 YanjiPalette | 已落地 | lib/theme/yanji_palette.dart |
| AppColors 语义映射 | 已落地 | lib/theme/app_colors.dart；保留现有单一 ThemeExtension |
| Material 3 完整显式角色 | 已落地 | AppColors.colorSchemeFor；不使用 fromSeed |
| Scaffold / surface 分离 | 已落地 | lib/main.dart 显式 scaffoldBackgroundColor |
| 控件 outline / 装饰 divider 分离 | 已落地 | 全局 InputBorder / Chip / Divider 主题 |
| NavigationBar / Rail 选中背景 | 已落地 | primaryContainer + onPrimaryContainer |
| 多表面对比度测试 | 已落地 | test/theme/yanji_contrast_test.dart |
| 主题接线测试 | 已落地 | test/theme/yanji_theme_wiring_test.dart |
| 新增硬编码颜色审计 | 已接入 CI | tool/audit_color_tokens.py；历史存量仍需分批迁移 |
| 风险提示页面/授权页面全量组件改造 | 待后续批次 | 本文件先锁定组件语义与验收规则 |
| 所有业务页面旧颜色迁移 | 待后续批次 | 不做无差别一键替换 |
| OPPO Find N2 真实设备阅读验收 | MISSING | CI/模拟器不能替代实机 |

## 11. 版本记录

- v1.0（2026-11-24）：冻结研纪正红品牌主色、冷白/深色表面、Material 3 角色、链接/功能灰/危险色/警告色分离、对比度矩阵、状态表达和静态审计要求；后续 UI 执行以本文件作为颜色与主题强制约束。

**最终执行口径：** 先读取本文件，再修改主题或页面。颜色不按感觉临时决定，状态不靠颜色单独表达，业务图谱不为统一而改义，任何例外必须可追溯、可测试、可验收。
