# Find N2 折痕与铰链感知布局

本文记录根导航、AdaptiveMasterDetail 与 AdaptiveSinglePane 的折叠屏落地范围：根导航把 NavigationRail 放左面板、当前业务页放右面板；主从布局把列表/详情分置；单列页面（含 AppBar）放入较宽的安全面板。所有复用组件将窗口坐标的 displayFeature.bounds 减去自身 RenderBox 的窗口起点，避免嵌套在单侧面板时误判铰链。

## 根导航双面板

- `AdaptiveHomeNavigation` 在识别到纵向 hinge/fold 时，左物理面板承载铺满面板宽度的应用导航面板（品牌区、全宽导航项、当前工作区标识），右物理面板承载 IndexedStack 当前 Tab；两面板之间按实际 hinge bounds 留空，零宽 fold 两侧各留 12 dp。导航不再只绘制窄 NavigationRail 后留下大块黑色空白。
- 左面板不足 260 dp 或右面板不足 300 dp 时，退化为较宽单侧面板内的底部 NavigationBar + 页面，不让 Tab 内容横跨铰链。
- 没有上报 displayFeatures 时，保留既有 600/840 dp 宽度断点与普通 NavigationRail/NavigationBar 行为。

## 本次实现

- 运行时读取 MediaQuery.displayFeatures，不按 Find N2 型号或固定像素坐标判断。
- 识别纵向贯穿窗口的 DisplayFeatureType.hinge 和 DisplayFeatureType.fold，将主列表限制在左侧面板、详情限制在右侧面板。
- 对零宽度折痕预留总计 24 dp 的安全间隔，避免分隔线、文字和可交互控件压在折痕上。
- 当两侧面板分别至少容纳 248 dp 主列表和 300 dp 详情时使用双栏；条件不满足时，只在较宽的单侧面板显示主列表，不把控件绘制到铰链或折痕上。
- 外屏小于 600 dp 时继续使用单栏流程；未上报折叠特征的普通窗口继续使用既有列表/详情布局。

## 单列页面适配

- 新增 AdaptiveSinglePane，普通窗口保持原有完整宽度；识别纵向 hinge/fold 后，将完整子页面约束在较宽的一侧物理面板。
- 本地 AI 问诊的 Scaffold（包括顶部操作栏、模型信息、消息流、附件预览和输入区）统一放在安全面板，避免 640 dp 居中内容跨过中央折痕。
- 零宽度折痕两侧各预留 12 dp；实际遮挡型 hinge 则按其物理 bounds 完整留空。

自动化回归：`test/adaptive_home_navigation_test.dart` 覆盖纵向 hinge 双面板、零宽 fold 留白和窄面板单侧回退，同时保留外屏/内屏窗口尺寸变化后的 Tab 状态测试。

## 自动化回归

test/adaptive_master_detail_test.dart 覆盖：
- 402 dp 紧凑窗口仍显示全宽单栏主列表。
- 普通宽屏仍使用列表/详情双栏。
- 800 dp 窗口中存在 24 dp 纵向铰链时，两栏分别落在左右物理面板。
- 零宽度纵向折痕仍保留 24 dp 安全间隔。
- 两个物理面板空间不足时退化为单栏，主列表不跨越铰链。

## 当前边界

AdaptiveHomeNavigation 已接入根导航双面板：左物理屏承载导航栏，当前 Tab 完整显示在右物理屏。AdaptiveMasterDetail 已用于收藏与知识库方剂/本草列表/预览；但在当前 Find N2 根导航结构中，Tab 视口约为右屏宽度，低于 600 dp，因此这些页面按紧凑单栏列表交互，点击条目进入详情，不会在两块物理屏间显示列表/预览。只有宿主视口本身横跨折痕且宽度足够时，AdaptiveMasterDetail 才会把列表与详情分置左右屏。AdaptiveSinglePane 已用于本地 AI 问诊完整页面。工具首页 ZoneSection 在当前右屏视口内使用单列；只有当宿主视口本身横跨折痕时才按 bounds 分成左右卡片列。嵌套在已分配面板中的 ZoneSection / AdaptiveMasterDetail 会识别铰链是否与自身局部区域相交，避免把另一侧铰链误当成内部折痕。普通页面路由弹窗已统一迁移到 `showFoldAwareDialog`：通过调用方 BuildContext 对应 RenderBox 的窗口坐标中心设置 `DialogRoute.anchorPoint`，并将原始 MediaQuery 传入弹窗内的 `AdaptiveSinglePane`；日期/时间选择器和模态底部弹层均设置 `foldAwareRouteAnchorPoint(context)`。当前对 `lib/screens/` 与 `lib/widgets/` 的 78 个 Dart 文件完成静态调用扫描，未发现残留直接 `showDialog`，扫描到的日期/时间选择器和模态底部弹层均已提供锚点参数。相机拍摄与 Android 系统文件选择器属于平台 UI，Flutter 页面锚点不能决定其系统窗口位置；仍需在 Find N2 真机分别验证内屏、外屏与半折叠状态下的系统返回、结果回传和窗口呈现。

test/local_ai_adaptive_content_test.dart 覆盖单列页面在 24 dp hinge 与零宽 fold 下不跨面板；test/zone_section_responsive_test.dart 覆盖工具卡片双物理面板分栏、折痕留白及嵌套右面板坐标；test/adaptive_master_detail_test.dart 覆盖主从布局嵌套右面板时不误识别边界外的铰链。

## 当前 UI 边界

当前根导航采用左侧全宽导航面板 + 右侧当前 Tab 的双面板模式。当前 Tab 内的本地 AI 问诊页面继续在右侧单屏内布局；工具卡片在右侧单屏内采用单列。ZoneSection 的跨折痕双列能力保留给宿主视口横跨两屏的场景，不会穿过根导航占用的左屏。

## Find N2 真机验收仍为 MISSING

模拟窗口和 displayFeatures 的 Widget 测试只验证 Flutter 布局逻辑，不等同于 OPPO Find N2（PGU110）实机报告。实机仍需分别检查外屏、内屏、半折叠姿态、100%/150%/200% 字号、键盘、附件选择与模型导入，并记录实际窗口 dp 尺寸、系统版本、displayFeatures 和截图。未执行前不得标为 PASS。

参考：
- https://api.flutter.dev/flutter/widgets/MediaQueryData/displayFeatures.html
- https://api.flutter.dev/flutter/widgets/DisplayFeatureSubScreen-class.html
- https://docs.flutter.dev/ui/adaptive-responsive/large-screens


## Debug 实机窗口诊断日志

Debug 构建会在 Flutter 窗口指标变化后输出一条 `[WINDOW_METRICS]` 日志，字段包括逻辑窗口尺寸（dp）、按 DPR 推算的物理像素尺寸、DPR、折痕/铰链类型与姿态、窗口坐标 bounds、键盘 `viewInsets`、系统 `viewPadding` 和文字缩放比例。日志不包含页面文字、问诊内容或模型输入；Release 构建不会输出该诊断。

在 Find N2 上采集步骤：

1. 安装本轮 Debug APK，打开应用并保持 USB 调试连接。
2. 在仓库根目录用 PowerShell 执行 `./tool/capture_find_n2_metrics.ps1`。脚本会检查已连接设备与应用包名，保存设备型号、Android 版本、屏幕尺寸/密度和系统字号。
3. 脚本只将包含 `[WINDOW_METRICS]` 的 Flutter 日志行写入 `output/find-n2/<时间戳>/window-metrics.log`，不会把其他 Flutter 日志、问诊内容或模型输出保存到文件。
4. 保持采集运行，依次切换外屏、展开内屏、半折叠，并分别弹出键盘、打开附件选择器；按 Ctrl+C 结束。
5. 每种姿态至少留一张系统截图，并将日志中的 `sizeDp`、`dpr`、`displayFeatures`、`viewInsets` 与截图对应记录。

**验收规则：** 日志只能证明 Flutter 在该时刻接收到的窗口参数；仍需结合实机截图检查导航栏、当前 Tab、弹窗、键盘和系统文件选择器的位置。没有设备日志和截图时，内外屏及半折叠实机项目继续标记为 MISSING。


## 普通全屏页面路由的来源面板约束

普通的 `MaterialPageRoute` 不会根据来源控件自动选择折叠屏物理面板。全屏详情页、工具页、设置页和列表详情跳转统一使用 `FoldAwareMaterialPageRoute`，并传入创建跳转的当前 `BuildContext`：

```dart
Navigator.of(context).push(
  FoldAwareMaterialPageRoute(
    sourceContext: context,
    builder: (_) => const SomeDetailScreen(),
  ),
);
```

路由在构建页面内容时读取来源控件的窗口坐标，并通过 `AdaptiveSinglePane` 将整个页面（包含 AppBar、滚动区和底部操作区）限制在来源控件所在的物理面板。没有上报铰链/折痕时保持普通全宽页面行为。弹窗仍使用 `showFoldAwareDialog`，不应改成页面路由。

当前已将 `lib/screens/` 中盘点到的普通全屏页面跳转统一迁移到该路由，包括知识/工具/收藏、规则问诊、医案、经方本草、针灸、内经、易经、紫微排盘和文档互链。规则问诊的本地 AI 专用子路由保留独立锚点参数（`preferredAnchorPoint`），同样会被约束到来源物理屏。继续新增页面时，必须使用 `FoldAwareMaterialPageRoute`，不要直接使用裸 `MaterialPageRoute`。
