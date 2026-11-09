# Find N2 真机验收记录 — 内屏导航重设计（2026-11-09）

## 设备元数据

| 项 | 值 |
|---|---|
| 设备 | OPPO Find N2 (PGU110) |
| Android | 16 (SDK 36) |
| 内屏 | 1920×1792, density 450 |
| 外屏 | 1080×2120 |
| 系统字号 | 1.15 |
| 包名 | com.nihaisha.nihaisha_app |
| 版本 | 1.11.30+8039 |

## 本轮修复（代码）

| 文件 | 改动 |
|---|---|
| lib/widgets/adaptive_home_navigation.dart | 内屏左侧菜单栏重设计 |
| lib/widgets/window_metrics_diagnostics.dart | WINDOW_METRICS 诊断开关（dart-define，默认关闭） |

### 修复的 3 个问题

1. **半屏空白（真根因）**：flat 展开态根导航走宽屏分支时未清空 `displayFeatures`，`fold/postureFlat` 折痕泄漏进工具卡片容器（`_FoldAwareZoneCards`），触发其 fallback 单列放右，卡片全挤右、左空白。修复：`_buildFullWindowScreens()` 用干净的 MediaQuery 包裹 tab 子树。
2. **主题按钮位置**：从"紧贴设置图标"改为沉底（`Column[Expanded(NavigationRail), SafeArea(主题按钮)]`）。
3. **折叠逻辑**：原实现只隐藏图标未释放空间。改为折叠后菜单栏彻底消失、内容全屏，仅左边缘 1/3 高度留微小展开按钮。

## 真机实测（uiautomator bounds/content-desc 客观证据）

| # | 验收项 | 结果 | 证据（bounds） |
|---|--------|------|----------------|
| 1 | 半屏空白解决 | PASS | 工具卡片两列全宽：左列 x70-943，右列 x977-1850（屏宽1920） |
| 2 | 主题按钮沉底 | PASS | content-desc="切换深色模式" bounds=[45,1623][180,1758]（屏高1792，靠底框） |
| 3 | 主题循环切换 | PASS | 点击后 content-desc 由"切换深色模式"→"切换浅色模式" |
| 4 | 折叠彻底 | PASS | 折叠后 5 tab + logo 消失，内容两列全屏 |
| 5 | 微小展开按钮 | PASS | content-desc="展开菜单栏" bounds=[0,591][51,726]（左边缘51px宽，y≈屏高1/3） |
| 6 | 展开恢复 | PASS | 点击后 logo + 5 tab + 主题按钮完整恢复 |
| 7 | 无崩溃 | PASS | 冷启动 + 折叠/展开 + 主题切换全程无 FATAL/overflow |

## 截图证据

- `docs/images/find-n2-round3/v_展开态两列全屏.png`
- `docs/images/find-n2-round3/v_折叠态全屏.png`

## 未执行项（需物理配合，如实标记，不写 PASS）

| 场景 | 状态 | 说明 |
|------|------|------|
| A 外屏竖屏 | 待执行 | 需折叠设备到外屏态 |
| C 半折叠上/下屏 | 待执行 | 需手动半折叠 |
| D 紫微十二宫位点击 | 待执行 | 需进入紫微排盘逐宫位验证 |
| E 系统字号 150/200% | 待执行 | 需切换系统字号 |
| F 键盘/Insets | 待执行 | 需输入框聚焦弹键盘 |
| H 相机/文件选择器 | 待执行 | 需操作系统权限弹窗 |
| I 折叠循环×3 | 待执行 | 需反复展开/半折/合盖 |
| J 结构化问诊全流程 | 待执行 | 需完整走寒热/舌脉/十问 + 收藏/分享/复制 |
| K 升级数据基线核对 | 部分 | 覆盖安装成功（install -r 数据保留），升级前基线未逐项记录（已发生疏漏） |