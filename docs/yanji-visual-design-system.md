# 研纪全局视觉设计系统

**状态：** Batch 1 颜色基础与自动化门禁
**品牌配色：** 冷白 #EBECEE · 银灰 #BCBBBF · 正红 #D71019
**Flutter 基线：** 3.47.0（与 .github/workflows/flutter-tests.yml 固定版本一致）

## 1. 品牌视觉原则

- 冷白负责浅色阅读底色。页面 Scaffold 使用冷白；卡片、输入区域和对话表面使用纯白，以明度差而不是阴影分隔。
- 银灰负责装饰。只用于纯装饰性分割线，不用于输入框边界、Chip 边界、未选中图标或其他需要被识别的控件。
- 正红负责品牌与交互。用于 Launcher 标志、主按钮和当前选中状态；不用于一般状态文字、错误文本或医药风险提示。
- 风险状态独立表达。必须同时具有语义色、图标、文字标签和边界容器；不得仅凭红/黄颜色传达禁忌或故障。
- 正文使用深炭灰；银灰不是次级正文色。

## 2. 基础色板（唯一原始色值来源）

源文件：lib/theme/yanji_palette.dart。

| Token | 色值 | 用途 |
|---|---|---|
| coldWhite | #EBECEE | 浅色 Scaffold 背景 |
| silverGray | #BCBBBF | 装饰分割线 |
| brandRed | #D71019 | 品牌主色、主要交互 |
| white | #FFFFFF | 卡片、输入框、红色按钮文字 |
| charcoal | #252629 | 主文字 |
| functionalGray | #808087 | 可识别的控件边界/功能图形 |
| textSecondaryLight | #64646B | 浅色次级文字 |
| redOnLight | #B30D15 | 浅色背景下的链接 |
| dangerLight | #A61B1B | 浅色错误/高风险语义 |
| warningLight | #815500 | 浅色警告语义 |
| darkBackground | #17181B | 深色 Scaffold 背景 |
| darkSurface | #202227 | 深色卡片、输入表面 |
| darkSurfaceContainer | #292B31 | 深色最高层常用容器 |
| darkPrimary | #FF5B62 | 深色主题品牌交互 |
| darkLink | #FF858A | 深色链接 |
| darkTextSecondary | #B6BAC4 | 深色次级文字 |
| darkOutline | #8A8E98 | 深色功能边界 |
| dangerDark | #FF7B72 | 深色错误/高风险语义 |
| warningDark | #FFD166 | 深色警告语义 |

浅色、深色 Material 3 容器、固定色角色、反色表面和系统透明度常量也集中在该文件中；业务 Widget 不得复制色值。

## 3. 语义层与主题接线

现有 AppColors 已经是项目使用的 ThemeExtension，且 context.colors 已经是便捷访问器。本次保留它作为语义层，不再新建第二套平行 ThemeExtension。

```dart
final scheme = Theme.of(context).colorScheme;
final semantic = context.colors;
```

| 语义角色 | 浅色 | 深色 | 说明 |
|---|---|---|---|
| primary / onPrimary | #D71019 / #FFFFFF | #FF5B62 / #1F0809 | 主操作与品牌状态 |
| link | #B30D15 | #FF858A | 链接文字，组件必须同时使用下划线或其他非颜色提示 |
| danger / onDanger | #A61B1B / #FFFFFF | #FF7B72 / #2B0B09 | 错误、禁忌和高风险 |
| warning / onWarning | #815500 / #FFFFFF | #FFD166 / #261900 | 需注意，但未达到危险级别 |
| onSurface | #252629 | #F0F1F3 | 主文字 |
| onSurfaceVariant | #64646B | #B6BAC4 | 次级文字 |
| outline | #808087 | #8A8E98 | 控件边界和功能图形 |
| outlineVariant | #BCBBBF | #454951 | 装饰性分割线 |

### Material 3 强制规则

- 使用 Flutter 3.47.0 的 ColorScheme 显式构造，不得使用 ColorScheme.fromSeed 推导品牌色。
- 所有 M3 角色（主/次/第三色、容器、Fixed 角色、错误容器、全部 surface container、inverse、shadow/scrim、surfaceTint）均显式传值，防止 SDK 版本中的回退角色误用 primary/secondary。
- ThemeData.scaffoldBackgroundColor 显式指向 AppColors.background；ColorScheme.surface 指向 AppColors.surface。两者不可互换。
- 浅色页面底色为冷白，卡片/输入填充为纯白；深色页面底色为 #17181B，卡片表面为 #202227。
- surfaceTint 设置为透明；卡片和对话框显式遵守该设置，避免 elevation tint 改变纯白表面。
- 输入框和 Chip 边界使用 colorScheme.outline；纯装饰分割线使用 colorScheme.outlineVariant。

当前 lib/main.dart 已经显式设置 scaffoldBackgroundColor: tokens.background；此次保留这一行为，并修正 InputBorder/Chip 边界误用装饰性 outlineVariant 的问题。

## 4. 可访问性与状态呈现

### 对比度门槛

- 普通文字、次级文字、链接、错误/警告文本、按钮文字：至少 4.5:1。
- 控件边界和有意义的非文本图形：至少 3:1；项目对基础功能灰提高内部门槛为 3.3:1。
- 银灰装饰分割线低于 3:1 是有意设计，但不得承担控件识别任务。
- 透明色层必须先与背景合成，再对合成结果计算对比度；禁止直接对 alpha 色值做比率计算。
- 对比度计算使用 WCAG 相对亮度公式的 0.04045 分段阈值，测试比较原始 double 数值，不四舍五入。

### 交互状态

- 选中态需同时表达颜色和结构变化（实心图标/字重/指示条或明确形状），不能只变色。
- 正红色调的 hover/pressed 状态层先与具体表面合成；状态层上的文字优先使用炭灰，链接使用加深红并保留下划线。
- 不要在红色调的选中/悬停容器上继续放置低对比度功能灰图标；该区域使用品牌图形色，其他非选中图标才使用功能灰。

### 中医风险与专业版授权

| 场景/状态 | 语义 | 呈现约束 |
|---|---|---|
| 十八反、十九畏、妊娠禁忌、有毒本草 | danger | 警示图标 + 【禁忌】/【有毒】标签 + 说明文字 + danger 边界容器 |
| 一般慎用、注意事项 | warning | 注意图标 + 【慎用】/【注意】标签 + warning 容器 |
| checking、temporarilyUnavailable | neutral | 中性进度/信息状态，不用品牌红制造故障感 |
| unlicensed | neutral | 未授权是正常产品状态，不用错误色表达 |
| keyMissing、deviceMismatch、storeCorrupt | warning | 可恢复的材料缺失或存储问题用 warning 与恢复动作 |
| signatureInvalid、issuerUnknown | danger | 明确错误图标、状态码/说明和修复边界 |
| 已激活 | success / primary action | 勾选图标与【已激活】，不能只靠品牌红色条 |

品牌红只承担识别与交互，不作为故障/危险状态文字；链接必须有下划线或其他非颜色提示，避免与风险状态混淆。

## 5. 旧颜色审计与 CI 门禁

tool/audit_color_tokens.py 分两种模式：

- --inventory：扫描 lib/**/*.dart 中的 Color(0x...)、Color.fromARGB、Color.fromRGBO、Colors.*、withOpacity/withValues 和局部 ThemeData，输出历史基线数量及主要文件。此阶段不因历史遗留一次性失败。
- --changed-only --base-ref <ref>：扫描相对于基线新增的 Dart 行；除 yanji_palette.dart、app_colors.dart 和有明确理由的受控白名单外，新增页面级硬编码颜色或局部 ThemeData 会使 CI 失败。

受控业务颜色白名单位于 tool/color_token_audit_allowlist.json。五行、六经、经络图、方位图等业务图例可保留专用色，但每个豁免必须写明文件路径和用途，并纳入对应浅/深表面对比度测试；不允许无理由豁免整类目录。

自动化文件：
- test/theme/yanji_contrast_test.dart：多表面、浅深主题、按钮/警示语义、状态层合成矩阵。
- test/app_theme_color_scheme_test.dart：Material 3 ThemeExtension / ColorScheme 映射。
- test/editorial_semantic_contrast_test.dart：状态容器和六经图例的既有对比度回归。

## 6. 其他视觉规范（分批确认，不在 Batch 1 擅自重排）

仓库已存在 lib/theme/app_tokens.dart，现有排版/间距基础为：
- 字号：24 / 20 / 18 / 16 / 14 / 12 / 11 dp。
- 间距：4 / 8 / 12 / 16 / 24 / 32 dp。
- 圆角：4 / 8 / 12 / 16 / 24 dp。
- 标题字体族当前为系统衬线（serif），正文使用系统默认字体。
- 当前主主题卡片 elevation 为 0，表面层级优先由底色明度差建立。

以上是现有代码基线记录，不代表字号、中文长文行高、段距、图标线宽/尺寸、风险提示组件、折叠屏不同姿态和深色主题入口已经完成全量 UI 验收。上述项目进入后续批次逐一审计和实机验收；Batch 1 不做无依据的全局排版改动。
