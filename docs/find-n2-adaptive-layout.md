# OPPO Find N2 内外屏自适应布局与品牌视觉方案

> 当前状态：已落地首页导航窗口宽度自适应、工具分区单/双列、收藏页列表/预览双栏、本地 AI 问诊内容列宽限制；收藏主从布局已加入纵向折痕/铰链避让；Android 自适应图标与矢量兼容资源已加入。Find N2 真机验收仍为 MISSING。本文区分代码已落地、设计约定和实机待验收项。

## 1. 设备基准与当前问题

OPPO 官方规格页列出 Find N2（入网型号 **PGU110**）的显示参数：

| 屏幕状态 | 对角线 | 像素分辨率 | PPI | 根据规格估算的逻辑窗口尺寸* |
|---|---:|---:|---:|---:|
| 折叠外屏 | 5.54 英寸 | 1080 × 2120 | 429 | 约 403 × 791 dp |
| 展开内屏 | 7.10 英寸 | 1792 × 1920 | 370 | 约 775 × 830 dp |

* 估算公式为“像素 ÷ PPI × 160”，仅用于设计预估。ColorOS 显示缩放、系统栏、分屏和可调整窗口会改变实际可用尺寸。运行时必须以 Flutter 的应用窗口约束为准，不按型号写死宽高。

官方参数：[OPPO Find N2 产品规格](https://www.oppo.com/cn/smartphones/series-find-n/find-n2/specs/)。

### 当前代码审计

- Android Manifest 的应用名为「汉唐中医」，Flutter 的 MaterialApp 标题也是「汉唐中医」；没有发现强制锁定竖屏的配置，Activity 已声明处理屏幕尺寸和最小尺寸变化。
- 首页之前无条件使用底部 NavigationBar。外屏合适，但展开内屏仍把四个主入口压在底部，未利用可用宽度。
- Flutter 根入口未统一建立窗口尺寸类别；各业务页面仍有各自的 Scaffold 和内容布局，需要按页面类型继续适配，不能认为首页导航改造已代表全应用通过。
- Android 已配置 Android 8.0+ adaptive icon foreground/background，并为当前 minSdk 24 提供 anydpi 矢量兼容资源；原有多密度 PNG 保留在仓库中作为旧资源。
- 原有多密度 PNG 已保留作回退；Manifest 现已指向简化书页自适应矢量图标，不含小字或“中医大师”表述。
- `pubspec.yaml` 描述已统一为“汉唐中医 - 中医经典知识与本地健康信息工具”，与知识、工具和本地健康信息整理的实际范围一致。

## 2. 已落地的基础导航规则

新增 `AdaptiveHomeNavigation`，只根据当前窗口宽度决策，不识别 Find N2 型号：

| 当前窗口宽度 | 首页导航 | 目标交互 |
|---|---|---|
| 小于 600 dp | 底部 NavigationBar | 单手操作、单列内容，适用于 Find N2 外屏 |
| 600–839 dp | 左侧 NavigationRail，图标和文字同时显示 | 释放垂直空间，适用于 Find N2 展开内屏的预估宽度 |
| 840 dp 及以上 | 扩展 NavigationRail | 平板、桌面和更宽的分屏窗口 |

导航仍使用 IndexedStack，切换内外屏、旋转或改变窗口大小时，不主动重建当前 Tab 的业务状态。断言和自动化测试覆盖 402 dp 外屏预估窗口与 775 dp 内屏预估窗口，以及切换后选中 Tab 保持。工具页 ZoneSection 在内容区宽度达到 600 dp 时切换两列，测试分别验证 402 dp 单列和 700 dp 双列；收藏页在 600 dp 以上进入列表/预览双栏；本地 AI 问诊内容最大宽度为 640 dp。

## 3. 全页面适配规范

### 外屏（compact）

- 保持单列主流程，底部四入口导航。
- 主要动作保持在拇指可触达区域；输入框、发送按钮和底部安全区不能被系统手势区遮挡。
- 长内容纵向滚动，避免把多个功能压缩到同一行。
- 弹窗根据窗口宽度设最大宽度，不使用固定的大尺寸对话框。

### 内屏（medium）

- 保留左侧主导航，业务内容在剩余区域展开；不把外屏的 UI 直接等比放大。
- 工具页分区卡片根据可用宽度自动从单列切换为两列（本轮已落地）；首页和知识库的多列/双栏细化仍按页面结构分别实施，不硬编码“平板设备”判断。
- 知识库方剂/本草 Tab 已落地内屏列表 + 摘要预览双栏；搜索和筛选保留在列表上方，选择后在右侧阅读适应证/组成或本草资料，点击“打开完整详情”仍进入原有详情页面。其他知识分类、医案和经典检索仍需按页面分别适配。
- 问诊/AI：消息流、模型状态、附件和输入区继续保持同一纵向流程；本轮已把页面主内容限制为最大 640 dp 并居中，避免内屏/平板上消息和输入框横向铺得过宽。收藏页复用的主从布局已按纵向 hinge/fold bounds 避让；本地 AI 问诊 Scaffold（含消息流、附件与输入区）已整体约束在折痕一侧；工具区卡片按 hinge bounds 分栏和右侧会话辅助面板仍待实现。
- 收藏页已落地内屏列表 + 内容预览：左侧列表负责筛选/管理，右侧预览正文并提供“打开完整详情”；外屏仍使用原有点选跳转。其他命盘和历史记录仍按页面逐项判断是否需要双栏。
- 保留 200% 字号缩放能力，字号放大后布局可换行、卡片增高，不以裁切文字换取整齐。

### 展开折痕与半折叠姿态

Flutter Android 的 `MediaQuery.displayFeatures` 可提供折痕/铰链位置和状态：

- `DisplayFeatureType.fold` 是柔性屏折痕，通常不遮挡像素，可作为双栏分界线。
- `DisplayFeatureType.hinge` 是遮挡区域，内容必须避开。
- `DisplayFeatureState.postureHalfOpened` 表示设备处于半开姿态；适合让预览/阅读内容位于上半区域、播放/录音/拍摄等控制位于下半区域。
- 不根据设备型号、屏幕像素常量或简单的 portrait/landscape 判断折叠状态。以实际窗口尺寸、`displayFeatures` 和布局约束决策。
- 系统未上报折痕时必须正常工作；不能因没有折痕事件而退化为黑屏或固定空白区。

折痕处理不能简单地在整个 `MaterialApp` 外包一层 `DisplayFeatureSubScreen`：该组件会根据 `anchorPoint` 选择一个子屏幕并把内容放入该区域，它适合单屏弹窗或明确只在一侧显示的单栏页面；若全局使用，会把整套应用限制在一个子屏幕，反而浪费展开屏另一侧空间。

全屏双栏页面应直接读取 `MediaQuery.displayFeatures` 和每个 feature 的逻辑坐标，按实际 hinge/fold bounds 分配左右内容区域：物理 hinge 必须留空，零宽 fold 是视觉折痕而不是不可绘制区域，应以列间距/留白把重要交互与文字列避开折痕，但不要无故损失整条屏幕宽度。对于没有上报 display feature 的设备，回退到普通 LayoutBuilder 宽度策略。

`DisplayFeatureSubScreen` 与按 feature bounds 分栏是两种不同布局策略：前者选一个子屏幕，后者才是双栏全屏。第一批需要按页面结构实现折痕感知的页面仍是本地 AI 问诊、知识库检索/详情、方剂与本草列表/详情。折痕正好穿过按钮、输入光标、图片主体或文本阅读列时，必须调整锚点、列宽或分栏位置。

参考：[Flutter 折叠屏与大屏指南](https://docs.flutter.dev/ui/adaptive-responsive/large-screens)、[Flutter DisplayFeature API](https://api.flutter.dev/flutter/widgets/MediaQueryData/displayFeatures.html)。

## 4. 应用名称与图标方案

### 名称建议

- **桌面短名称：保留「汉唐中医」**。现有 Manifest 与 MaterialApp 已统一为这个名称，四字长度适合桌面图标下方显示；不建议在短名称里追加副标题。
- 应用商店/介绍副标题建议统一为：**「中医经典 · 知识工具 · 本地健康信息」**。
- 项目描述不再使用“中医诊断助手”作为总定位；中医规则辨证、传统文化工具和 E4B 健康信息整理应在功能说明里分别描述。
- Android applicationId `com.nihaisha.nihaisha_app` 不改，避免影响升级覆盖安装、数据目录及本地模型路径。

### 图标方向

**方向：朱砂印记 + 经典书页的现代简化符号。**

- 主色：朱砂红（约 `#A93226`）；辅色：墨黑（约 `#24211F`）、米纸白（约 `#F3EBDD`）、少量古金（约 `#B89453`）。
- 主图形只保留一个清晰主体：打开的书页与圆形阴阳/经络线的抽象组合，或单字「汉」的简化印记。两者择一，不把所有传统元素堆进同一图标。
- 禁止在图标里放小字、四角印章、长副标题和“中医大师”字样；桌面图标不承担说明书功能。
- Android 8.0+ 使用 `mipmap-anydpi-v26/ic_launcher.xml`，分离 foreground 与 background，主体置于系统安全区；同时提供旧版 launcher PNG，确保旧系统和第三方桌面显示一致。
- 交付源文件优先使用 SVG/矢量母版，再导出各密度资源；图形在圆形、方圆形和水滴形遮罩下都要可识别。

本轮已按上述方向落实首版矢量资源：打开书页作为唯一主体、朱砂红页面、米纸白底、墨色书页线条与古金色中缝；不放小字或“中医大师”字样。Android 8.0+ 使用独立 foreground/background 自适应图层；API 24–25 使用 anydpi vector 图标。桌面短名称仍统一为“汉唐中医”，MaterialApp.title 与 Manifest label 保持一致，applicationId 不变。

## 5. 实机与 CI 验收标准

### 自动化必须覆盖

- 窗口宽度 402 dp：底部 NavigationBar 显示，NavigationRail 不显示。
- 窗口宽度 775 dp：NavigationRail 显示，底部 NavigationBar 隐藏。
- 窗口宽度 840 dp 以上：扩展 NavigationRail 生效。
- 窗口变化后当前 Tab、输入内容和滚动状态不被导航壳主动清空。
- `test/adaptive_master_detail_test.dart` 已用模拟 `displayFeatures` 覆盖纵向 hinge、零宽 fold、窄面板退化；该测试只验证组件布局，不能替代 Find N2 真机验收。

### Find N2 真机必须逐项记录

1. 折叠外屏启动、四个主 Tab 切换、返回和键盘弹出，确认没有底部遮挡或横向溢出。
2. 展开内屏启动，导航切换为左侧 Rail；逐个打开知识、工具、问诊、收藏页面，检查内容列宽、文字折行、图片比例和弹窗宽度。
3. 在内外屏之间切换，确认问诊草稿、Tab、滚动位置和本地模型状态仍然正确。
4. 分别测试 100%、150%、200% 字号。
5. 半折叠/桌面姿态、横屏、分屏窗口（系统支持时）检查主操作是否可触达。
6. 相机拍摄、系统文件选择器、键盘输入和 3.66 GB 模型导入在内外屏状态都要走一遍。
7. 记录系统版本、窗口实际 dp 尺寸、`displayFeatures`、页面截图与异常日志。

在 Find N2 实机完成前，状态统一标记为 `MISSING`，不将窗口模拟测试标记为设备验收 PASS。

## 6. 官方实现参考

- [OPPO Find N2 官方规格](https://www.oppo.com/cn/smartphones/series-find-n/find-n2/specs/)
- [Flutter Adaptive & Responsive](https://docs.flutter.dev/ui/adaptive-responsive)
- [Flutter Large screens and foldables](https://docs.flutter.dev/ui/adaptive-responsive/large-screens)
- [Flutter DisplayFeature](https://api.flutter.dev/flutter/widgets/MediaQueryData/displayFeatures.html)
- [Android Adaptive app quality](https://developer.android.com/develop/adaptive-apps/quality-guidelines/adaptive-app-quality)
