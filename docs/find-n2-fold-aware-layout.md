# Find N2 折痕与铰链感知布局

本文记录 AdaptiveMasterDetail 的折叠屏落地范围。它是“全页面内外屏适配”中的第二层：第一层根据窗口宽度切换主导航；第二层在列表/详情页面把内容放入真实可用的物理屏幕区域。

## 本次实现

- 运行时读取 MediaQuery.displayFeatures，不按 Find N2 型号或固定像素坐标判断。
- 识别纵向贯穿窗口的 DisplayFeatureType.hinge 和 DisplayFeatureType.fold，将主列表限制在左侧面板、详情限制在右侧面板。
- 对零宽度折痕预留总计 24 dp 的安全间隔，避免分隔线、文字和可交互控件压在折痕上。
- 当两侧面板分别至少容纳 248 dp 主列表和 300 dp 详情时使用双栏；条件不满足时，只在较宽的单侧面板显示主列表，不把控件绘制到铰链或折痕上。
- 外屏小于 600 dp 时继续使用单栏流程；未上报折叠特征的普通窗口继续使用既有列表/详情布局。

## 自动化回归

test/adaptive_master_detail_test.dart 覆盖：
- 402 dp 紧凑窗口仍显示全宽单栏主列表。
- 普通宽屏仍使用列表/详情双栏。
- 800 dp 窗口中存在 24 dp 纵向铰链时，两栏分别落在左右物理面板。
- 零宽度纵向折痕仍保留 24 dp 安全间隔。
- 两个物理面板空间不足时退化为单栏，主列表不跨越铰链。

## 当前边界

这次只把折痕/铰链避让接入复用的主从布局组件，实际影响使用该组件的页面（当前至少包括收藏列表/预览）。首页导航、普通外屏/内屏宽度断点和本地 AI 消息正文宽度仍按各自组件工作；知识库列表、工具首页卡片、问诊输入区、收藏顶部筛选条、弹窗、相机和文件选择器尚未因此自动获得完整的折痕感知能力。

## Find N2 真机验收仍为 MISSING

模拟窗口和 displayFeatures 的 Widget 测试只验证 Flutter 布局逻辑，不等同于 OPPO Find N2（PGU110）实机报告。实机仍需分别检查外屏、内屏、半折叠姿态、100%/150%/200% 字号、键盘、附件选择与模型导入，并记录实际窗口 dp 尺寸、系统版本、displayFeatures 和截图。未执行前不得标为 PASS。

参考：
- https://api.flutter.dev/flutter/widgets/MediaQueryData/displayFeatures.html
- https://api.flutter.dev/flutter/widgets/DisplayFeatureSubScreen-class.html
- https://docs.flutter.dev/ui/adaptive-responsive/large-screens
