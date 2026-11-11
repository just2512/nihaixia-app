# Find N2 真机验收 — 最终汇总（2026-11-10 ~ 11）

> 按 `find-n2-real-device-acceptance.md` A–K 矩阵逐项执行，含缺陷修复后的复验结论。

## 设备元数据

| 项 | 值 |
|---|---|
| 设备 | OPPO Find N2 (PGU110) |
| Android | 16 (SDK 36) |
| 内屏 | 1920×1792, density 450 |
| 外屏 | 1080×2120, density 450 |
| 折叠姿态 | HALF_OPENED / OPENED(flat) / CLOSED 均覆盖 |
| 包名 | com.nihaisha.nihaisha_app |
| 版本 | 1.11.30+8039（本地签名 Release arm64） |

## A–K 最终结果

| 项 | 结果 | 关键结论 / 缺陷修复 |
|---|---|---|
| A 外屏竖屏 | ✅ PASS | 外屏 1080×2120 竖屏 rotation=0，compact 底部导航，窗口 0,0–1080×2120 |
| B 内屏完全展开 flat | ✅ PASS | 内容全宽、无溢出、无半屏空白 |
| C 半折叠上/下屏 | ✅ PASS | HALF_OPENED 单面板布局；**修复**：空面板黑屏→`AdaptiveSinglePane` 包 `ColoredBox(surface)`（commit 392f977） |
| D 紫微排盘宫位 | ✅ PASS | 十二宫位 + 星曜详情渲染完整 |
| E 系统字号三档 | ✅ PASS | **修复**：`main.dart` 用 `AppPreferenceTextScaler(platformScaler, preferenceScale)` 继承系统字号（原为 `TextScaler.linear` 忽略系统值） |
| F 键盘与 Insets | ✅ PASS | viewInsets=313dp 报告，输入框贴合键盘 |
| G 弹窗与路由 | ✅ PASS | flat 弹窗居中 + 半折叠跨屏锚点正常 |
| H 相机/文件选择器 | ✅ PASS | **修复**：拍摄舌象增加"从相册选择"入口（原只有拍照，commit 673841d） |
| I 折叠循环×3 | ✅ PASS | pid=32061 全程存活，无 FATAL/ANR，HALF_OPENED↔CLOSED↔OPENED 多轮切换 |
| J 结构化辨证 | ✅ PASS | 异常路径输出 六经/证型/方剂（厥阴/当归四逆汤）；**修复**：健康基线文案对齐老入口（commit dfd5e91） |
| K 原位覆盖升级 | ✅ PASS | `adb install -r` 覆盖安装数据保留、签名一致 |

## 本轮 AI 助手 bug 修复清单（真机验证）

| Bug | 根因 | 修复 | commit |
|---|---|---|---|
| 键盘遮挡空白 | 内外 Scaffold 双重 resize 把 body 压到~0 | AI Scaffold `resizeToAvoidBottomInset:false` + body Column | c5ee955 |
| LiteRtLmJniException | R8 minify 但无 litertlm keep 规则剥离 JNI | proguard-rules 加 `-keep com.google.ai.edge.litertlm.**` | c5ee955 |
| 答非所问 | 固定后缀"请区分资料原文" + noResults 仍注入 context | 移除后缀 + noResults 直接 sendMessage | 2da2796 |
| 第二次发送 state:7 | GPU 多轮不稳无恢复 | 多轮失败切 CPU 引擎重建会话重试 | 5c1ea59 |
| 第三条空回复 | Gemma 偶尔空串 | sendLocalMessage 空回复走 CPU 重建重试 | 5c1ea59 |
| 拍摄舌象无相册 | 仅 `ImageSource.camera` | 加 `pickGalleryImagePath` + 底部菜单 | 673841d |
| 健康基线无意义 | 文案不列明细 | 对齐老入口"恭喜正常人+六条" | dfd5e91 |
| 相册菜单透明 | ColorOS 默认 bottom sheet 半透明 | 显式 `backgroundColor: surface` | 9852155 |
| 录音只转写不回答 | prompt 只让转写 | 改"先转写再问诊助手回答" | 9852155 |
| 回复带 markdown | LLM 输出原样展示 | `stripSimpleMarkdown` 统一剥离 | 9852155 |

## 构建坑（已修）

- **stale rsync**：WSL 从 /mnt/d Windows 挂载 `rsync -a` 保留 DrvFs 时间戳，gradle/flutter 增量编译跳过改动文件（改动没进 APK）。修复：build-apk.sh 同步后 touch 源码（commit 1a1b30c）。

## 遗留（非阻塞）

- 本次未做「AI 对话意图澄清→工具跳转」的端到端自动验证（依赖中文输入交互，已由结构化问诊 J 覆盖同类链路）。
- C/半折叠物理铰链几何（铰链宽度 0 vs 物理 gap）仅在 Find N2 单品实测，未覆盖横向铰链机型。