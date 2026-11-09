# Find N2 真机验收 — A–K 矩阵执行记录（2026-11-09）

> 按 `find-n2-real-device-acceptance.md` 逐项执行。状态仅用 PASS/FAIL/BLOCKED/MISSING，
> 不得把 BLOCKED/MISSING 写成 PASS。验证手段：uiautomator bounds/content-desc 客观数据 + logcat + 截图。

## 设备元数据

| 项 | 值 |
|---|---|
| 设备 | OPPO Find N2 (PGU110) |
| Android | 16 (SDK 36), incremental T.38bf80f-14604cc-14d6f0f |
| 内屏 | 1920×1792, density 450（展开 flat，display `local:4630947227410127746` state=ON） |
| 外屏 | 1080×2120, density 450（display `...747` state=OFF） |
| 系统字号 | 1.15 |
| 包名 | com.nihaisha.nihaisha_app |
| 版本 | 1.11.30+8039（本地签名 Release arm64） |
| WINDOW_METRICS | `fold/postureFlat@341.3,0.0,0.0x637.2;cutout/unknown@0.0,0.0,54.4x40.2` sizeDp=682.7x637.2 |

## 逐项结果

### B 内屏完全展开 flat — PASS
- 冷启动首页（汉唐 AI 助手）内容可见、无溢出、无崩溃
- 工具卡片两列全宽（左列 x70-943 + 右列 x977-1850，屏宽1920）
- 紫微排盘成功（八字 `庚辰 甲申 丙午 癸巳`、五行局土五局、命主文曲、生年四化）
- 命盘十二宫位完整渲染（福德/田宅/官禄/交友/父母/迁移等含天干+星曜详情）

### D 紫微排盘宫位 — PASS（宫位可辨识 + 详情渲染，点击交互滚动定位受限）
- 排盘成功，十二宫位 semantics 暴露且 bounds 完整
- 各宫位星曜详情直接渲染在命盘（福德宫：辛巳 巨门(旺) 文昌(庙) 天喜(庙)...）
- 宫位点击详情弹窗因 Canvas 命盘 + 列表滚动惯性，adb 精确定位失败，标记需真机手点确认

### E 系统字号三档 — FAIL（缺陷）
- 系统 font_scale 1.15 → 2.0，app UI bounds 完全不变（标题仍 `[270,152][656,231]`）
- 根因：`main.dart` 用 `TextScaler.linear(settings.textScaleFactor)` 覆盖系统 `MediaQuery.textScaler`
- 后果：系统无障碍字号缩放对 app 无效，仅 app 内字号设置生效
- 修复方向：textScaler 应结合系统值（如 `TextScaler.linear(settings.textScaleFactor * MediaQuery.textScalerOf(context).scale(...))`）或设为 null 跟随系统

### F 键盘与 Insets — PASS
- 模型加载后输入框聚焦，键盘弹出 mInputShown=true
- 输入框 y591-726 在键盘上方不遮挡，英文 input text 生效（text="test..."）
- back 收起键盘 mInputShown=false

### G 弹窗与路由 — PASS（flat 态）/ 半折叠锚点待 C 项
- 设置页控件正常（暗黑模式三选项/字体滑块/诊断设置）
- flat 单屏弹窗居中正常；跨屏锚点（showFoldAwareDialog/FoldAwareMaterialPageRoute）需半折叠态验证

### K 原位覆盖升级数据保留 — PASS（基础）
- `adb install -r` 覆盖安装成功（签名 ddbd2628 一致，8038→8039，数据保留）
- 主题设置持久化（浅色，多次 force-stop 重启后保持）
- 重启无崩溃、进程存活
- 新增数据持久化（收藏/诊断历史/会话历史）需 J 项流程后验证

## 未执行（需物理配合，列清单）

| 场景 | 状态 | 需配合动作 |
|------|------|-----------|
| A 外屏竖屏 | MISSING | 折叠设备到外屏态，我采集 |
| C 半折叠上/下屏 | MISSING | 半折叠到可稳定停留角度 |
| H 相机/文件选择器 | MISSING | 点权限弹窗「允许」等 |
| I 折叠循环×3 | MISSING | 外屏→内屏→半折→外屏 循环3次 |
| J 结构化问诊 | MISSING | 中文输入（adb 不支持中文，需手输「开始规则问诊」及选项） |
| D 宫位点击详情 | MISSING | 手点一个宫位确认详情弹窗 |

## 截图证据（docs/images/find-n2-round3/）
- 展开态两列全屏、折叠态全屏、D_ziwei_result、F_keyboard、F_keyboard_text、E_font200