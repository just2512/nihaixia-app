# OPPO Find N2 真机折叠屏验收方案
> 本文件仅是 Find N2 折叠屏、窗口姿态、输入法和系统 UI 的专项操作规范，不是独立设备交接单，也不维护当前主线基线或本地进度表。
> 唯一活动设备交接和进度入口：`docs/local-real-device-acceptance-handoff.md`。当前构建 SHA、CI 证据、APK 元数据、场景状态、证据目录、缺口和下一步均以该文件 §1、§7、§7.1 为准。
> 本文件早期记录的 master SHA、PR 编号和版本说明仅作历史背景；每次执行都必须按唯一交接单中的步骤刷新到最新 master。未在 Find N2 实测的项目继续记 MISSING / UNKNOWN，不以 CI 或模拟器代替。


## 1. 验收目标与边界

验证当前 `master` 的 Flutter 页面在 OPPO Find N2 上，面对真实外屏、展开内屏、半折叠姿态、系统窗口 Insets、输入法和 Android 平台 UI 时，是否保持可见、可操作、状态连续且无布局异常。

当前实现约束（以代码和自动化测试为准）：

- 外屏窄窗口使用单栏布局。
- 完全展开内屏（flat）使用完整可用内屏宽度；根导航可保留左侧 NavigationRail，Tab 内容应延伸至其余可用区域，不应被错误限制在右半屏。
- 半折叠/桌面姿态按真实铰链/折痕边界选择安全面板；页面、弹窗和来源控件应位于同一可用屏区。
- 零宽折痕与有物理宽度的铰链必须分别检查，不能把两种 DisplayFeature 当成同一情况。
- 相机、Android 文件选择器等平台系统 UI 的位置由 Android/厂商系统控制，Flutter 路由锚点不能保证它们落在哪一块屏；本方案只验收系统 UI 能否正常启动、完成、返回并正确回传结果。

## 2. 设备与构建前置条件

执行前记录：

| 项目 | 必须提供的值 |
|---|---|
| 设备 | OPPO Find N2，型号以 `getprop ro.product.model` 实测值为准 |
| Android | 系统版本、SDK、ColorOS 版本（设置页截图或设备信息） |
| 系统显示 | 屏幕分辨率、密度、系统字号、显示大小 |
| 应用 | 包名 `com.nihaisha.nihaisha_app`、Git commit、APK SHA-256 |
| 构建 | CI 只产出 arm64 Debug ABI 证据包；实际安装包由本地使用既有 Release 签名密钥构建 |
| 连接 | USB 调试已授权；电脑有 Android platform-tools（adb）和 PowerShell |

在安装前先完成旧包签名核对；签名与版本条件满足后，使用覆盖安装，不得先卸载。安装本轮 APK 后再确认：

```powershell
adb devices
adb shell getprop ro.product.model
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.sdk
adb shell wm size
adb shell wm density
adb shell settings get system font_scale
adb shell pm path com.nihaisha.nihaisha_app
```

如设备型号、APK commit 或 SHA-256 不明，先标记 BLOCKED，不开始正式验收。

## 3. 采集工具与证据目录

仓库已有窗口诊断脚本：

```powershell
./tool/capture_find_n2_metrics.ps1
```

脚本自动检查 adb 设备、包名和已安装状态，记录设备元数据，并只保存 Flutter 日志中带 `[WINDOW_METRICS]` 的行。采集期间依次切换外屏、展开内屏、半折叠，并操作键盘、相机和文件选择器；按 Ctrl+C 结束。

每轮证据建议按以下结构整理：

```text
output/find-n2/<run-id>/
  device-metadata.json
  window-metrics.log
  capture-summary.json
  apk-info.txt
  screenshots/
    01-outer-home.png
    02-inner-flat-home.png
    03-half-fold-home.png
    04-ziwei-chart-outer.png
    05-ziwei-chart-inner.png
    06-palace-detail-half-fold.png
    07-dialog-source-panel.png
    08-keyboard-visible.png
    09-system-file-picker.png
    10-after-return.png
    11-acupuncture-context-outer.png
    12-acupuncture-context-inner.png
    13-acupuncture-context-half-fold.png
  test-results.md
```

截图需保留完整屏幕边界和系统状态栏/导航栏；截图中如含真实个人资料、出生信息、问诊内容或账号，应使用专门测试数据或先遮盖敏感内容。不要提交真实个人健康信息。

## 4. 真机测试矩阵

每个场景均需记录：步骤、预期、实际、结果状态、截图编号、对应 `[WINDOW_METRICS]` 时间戳。状态只能使用：

- **PASS**：实机行为满足本节全部通过条件，且证据齐全。
- **FAIL**：实际行为违反任一通过条件。
- **BLOCKED**：因设备、权限、构建或环境原因无法执行。
- **MISSING**：尚未执行或缺少足够证据。

不得把 BLOCKED/MISSING 写成 PASS；同一场景部分通过也不能整体 PASS。

### A. 外屏竖屏

1. 折叠设备，仅使用外屏冷启动应用。
2. 依次打开首页、统一助手、紫微排盘、命盘详情。
3. 在紫微页面检查命盘、十二宫位、宫位名称/星曜文本、底部操作入口和滚动区域。
4. 打开宫位详情、普通对话框、日期/时间选择器；逐个关闭并返回。
5. 滚动长内容至顶部和底部，执行返回、再次进入。

通过条件：
- 页面没有横向溢出、RenderFlex overflow、文字/按钮裁切或不可触达控件。
- 主要操作不被状态栏、导航栏、圆角/挖孔或键盘遮挡。
- 页面纵向滚动正常，底部内容可到达；弹层可完整查看并可关闭。
- 返回后页面状态与进入前一致，不出现空白页、重复页面或卡死。

### B. 内屏完全展开（flat）

1. 展开设备至完全平展，等待系统完成窗口尺寸变化。
2. 冷启动应用；记录根导航、Tab 内容和命盘布局。
3. 分别进入统一助手和紫微排盘，检查横向布局、命盘完整性、长文本和详情入口。
4. 从左侧/顶部导航切换多个 Tab，再返回原页面。

通过条件：
- `[WINDOW_METRICS]` 显示实际内屏尺寸和系统上报的 DisplayFeature；以设备真实报告为准。
- 当前代码定义的 flat 行为成立：内容使用可用内屏宽度，不因残留 DisplayFeature 被错误压缩成单侧窄屏；导航和内容均不被裁切。
- 命盘各宫位位置、连线、文字和交互区域完整；无异常缩放、重叠或横向滚动条。
- 切换 Tab 后状态恢复符合页面既有设计，无状态丢失或内容错位。

### C. 半折叠 / 桌面姿态

1. 将设备置于可稳定停留的半折叠姿态，分别测试上屏和下屏作为来源区域的场景。
2. 从可见屏区进入紫微排盘，滚动命盘和说明文档。
3. 点击宫位打开详情；再从该屏区打开普通弹窗、日期/时间选择器。
4. 分别从上侧与下侧触发可用弹层/导航入口，检查其显示位置。
5. 尝试在半折叠状态切换到助手并输入文本。

通过条件：
- 页面主内容被约束在安全物理屏区，不穿过实际铰链/遮挡区域；触控目标位于可见且可触摸区域。
- 弹窗/详情应锚定到触发控件所在屏区；不允许从下屏触发却显示在上屏不可见区域，反之亦然。
- 页面、AppBar、滚动区、底部操作区不互相覆盖；滚动到两端均无溢出。
- 如果设备或系统不支持稳定半折叠姿态，记录设备状态和系统信息并标记 BLOCKED，不以模拟器替代。

### D. 紫微排盘与宫位详情（核心业务）

分别在外屏、内屏 flat、半折叠可用屏区执行：

1. 打开排盘页，检查命盘整体布局及十二宫位。
2. 逐一点击至少四个不同位置的宫位（包含边缘宫位和中间区域），打开宫位详情。
3. 在详情内滚动到最底部，再返回顶部；关闭后再次打开另一个宫位。
4. 从详情页跳转关联文档（若入口存在），返回排盘页。
5. 旋转/折叠状态切换后复查当前命盘和详情状态。

通过条件：
- 命盘十二宫位均可辨识、点击区域与视觉位置一致；不得有宫位被铰链遮挡或点击错位。
- 详情弹层显示在正确屏区，长内容完整可滚动；底部按钮可见、可触达。
- 关闭/返回后命盘数据和当前页面恢复；不丢失出生参数，不产生重复路由。
- 任何真实布局异常、点击偏移或文本遮挡均判 FAIL，即使截图看起来大致正常。

### E. 系统字号与显示大小

至少执行系统字号 100%、150%、200% 三档（以 Android 设置可选档位为准），每档重复外屏、内屏 flat、半折叠的关键页面检查。记录实际 font_scale，不只记录设置档位。

通过条件：
- 不裁切关键文本、命盘宫位名称、按钮标签和表单输入内容。
- 文本增大后允许页面变高并滚动，不允许通过缩小字体、固定高度裁切或隐藏内容规避问题。
- 交互控件仍可触达，弹层内容可滚动到底部。

恢复设备原字号和显示大小后再继续下一组测试。

### F. 键盘、输入区与 Insets

分别在外屏、内屏 flat、半折叠执行：

1. 进入统一助手，聚焦输入框并输入多行测试文本。
2. 弹出键盘，滚动历史消息，发送消息；再聚焦输入框。
3. 使用系统返回键收起键盘，再次打开键盘；切换屏幕姿态时保持键盘打开一次。
4. 在有底部操作区的页面重复检查。

通过条件：
- 输入框、发送按钮和正在编辑的文本不被键盘遮挡；键盘出现后内容区域正确缩小/滚动。
- `viewInsets` 随键盘变化，键盘收起后恢复；无底部空白残留、跳屏或布局抖动。
- 折叠/展开期间不丢失输入草稿，不出现重复发送。
- 软键盘关闭后页面能恢复到原滚动位置附近。

### G. 弹窗、底部弹层和全屏路由

1. 从左右/上下不同物理屏区触发普通对话框、宫位详情、日期/时间选择器。
2. 从来源屏区打开全屏详情页，再返回。
3. 在半折叠姿态重复从两个屏区触发弹层。
4. 在 flat 状态检查弹窗是否错误地被限制在半屏。

通过条件：
- 弹窗/路由的位置与调用来源一致，且完整处于可用物理屏区。
- flat 状态按当前设计使用完整可用内屏；half-opened 状态遵循安全屏区。
- 背景遮罩、关闭按钮、返回键和点击外部关闭行为符合组件原有设计。
- 不出现 DialogRoute 默认锚点导致的跨屏、弹窗超界或无法关闭。

### H. 相机、系统文件选择器和权限

1. 从真实业务入口启动相机拍照。
2. 从真实业务入口启动 Android 系统文件选择器，选取一个非敏感测试文件。
3. 分别在外屏、内屏 flat、半折叠姿态执行；如系统不允许某姿态，记录原因。
4. 完成选择后返回应用，检查预览、文件名/类型、后续流程。
5. 拒绝权限、首次授权、再次进入分别检查；如支持“仅本次允许”，也需覆盖。

通过条件：
- 系统 UI 可启动、可取消、可完成；系统返回后应用仍可操作。
- 成功选择时 URI/文件结果正确回传，预览内容与选择文件一致；取消时不残留错误附件。
- 权限拒绝后应用给出可理解反馈，不崩溃、不假装成功；重新授权后可恢复。
- 不要求系统文件选择器/相机窗口必须由 Flutter 锚定到指定屏区；但必须记录系统实际显示位置和返回行为。

### J. 统一助手、结构化辨证与诊断结果操作

分别在外屏、内屏 flat、半折叠姿态执行；使用专门测试资料，不输入真实患者信息。

1. 冷启动统一助手，分别发送普通问题、知识检索问题和明确工具任务；检查助手没有把普通聊天误路由为诊断或工具。
2. 明确输入“开始规则问诊”，按界面选项完成寒热、舌脉和十问；另测一次跳过舌脉的路径。
3. 检查结构化结果卡：六经、证型、合病字段（如适用）、证据说明、方剂及处方内容；证据不足时不得自动推荐方剂。
4. 对结果执行“收藏辨证结果”，再进入收藏列表，确认标题、分类、来源和正文完整；返回后再次打开收藏条目。
5. 执行“分享辨证结果”，确认 Android 系统分享面板可拉起；选择目标应用后核对分享文本包含诊断结果、舌脉信息、处方和必要的风险提示。
6. 执行“复制处方”，粘贴到系统便签或输入框，逐项核对方剂、组成、剂量、煎服法和禁忌；没有处方时不应显示可用的复制操作。
7. 进入诊断历史，确认本次记录存在；强制停止 App 后重新启动，再次检查记录及结构化详情。
8. 打开历史对话，恢复已完成的问诊；确认结果卡和收藏、分享、复制操作仍可用。另对未完成任务检查待答问题、选项和已答内容是否恢复。
9. 在知识检索结果中打开来源回链；执行至少一个真实工具任务，确认结构化执行结果返回同一助手会话，而不是只显示“已打开页面”。

通过条件：

- 规则诊断结果由 App 内确定性辨证引擎产生；不能由模型自由生成证型、方剂或剂量。
- 收藏写入成功且重启后仍可读取；重复点击不得造成无法解释的重复记录。
- 分享面板、剪贴板均有真实系统交互结果；不得只以按钮点击无异常作为通过。
- 诊断历史和会话历史在强制停止、重新启动后可恢复；结构化结果与原始任务对应，不得只恢复一段文本。
- 知识来源可回链；缺失来源必须明确标记，不得补造出处。
- 工具失败应保留真实失败状态和参数，不能把失败显示成成功。
- 任一功能闪退、ANR、结果丢失、处方内容错乱或状态无法恢复，均判 FAIL。

### L. 针灸处方条目情境解读（AI-CTX-ACU-01）

本项只验收当前已接入的「穴位处方」Tab 单条记录入口。不要把普通针灸讲稿、透针或耳穴资料当成这次同一入口。

1. 在「穴位处方」Tab 选择一条记录，展开详情，确认仅在来源身份可唯一确认时显示「问 AI 解读当前处方条目」；点击后进入现有学习助手。
2. 使用分类 `01` / 条目 `1` 与分类 `08` / 条目 `1` 两组数据分别执行。两者数字 entryId 相同但属于不同分类，必须生成不同的 `anchorId`、`sourceId` 和快照，不得跨分类混用。
3. 检查对话上下文只包含当前选中的一条本地记录；其中 `kind=knowledgeEntry`、`moduleId=acupuncture-prescriptions`，锚点格式为 `acupuncture-prescriptions:{categoryId}:{entryId}`，来源 ID 格式为 `acupuncture:{categoryId}:{entryId}`。
4. 在同一条目内追问并关闭/重开会话，确认 user/assistant 消息均保留相同 ContextRef；切换另一分类或另一条目时不得复用旧锚点会话。
5. 确认此流程只解释现有结构化条目，不触发排盘、问诊或其他工具执行，不重算处方、不改写本地资料。
6. 在外屏、内屏完全展开和半折叠姿态各执行一次；检查按钮、上下文面板、输入框、键盘和滚动区域无裁切、遮挡、跨铰链或失效点击区域，并分别保存截图。
7. 当前 `透针透穴`、`穴位讲解`、`耳穴` Tab 不属于本次接入范围；这些 Tab 没有此情境 CTA，记录为 `NOT_ENABLED`，不要误报为首个 Tab 的入口故障。

来源与安全核对：

- `source=nihaisha+bbxx` 只是本地数据保存的原始来源标记，表示混合来源标签，不代表纸本出处、独立验证或临床证据。没有本地字段支持的版本、页码或依据记录为 `UNKNOWN / MISSING`，不得补造。
- AI 只解释条目原文中已有的穴位、操作文字、备注和案例字段；不得生成针对个人的诊断、治疗方案、配穴、针刺深度/角度/方向/手法/留针时间、针刺频次或自行施治指导。
- 使用合成测试资料，不输入真实患者信息。任一跨分类内容串入、错误锚点、工具误执行、来源伪造或个人施治指导均判 `FAIL`。


### M. 内经 / 本草讲稿段落级情境解读（CTX-PARAGRAPH-01）

本项只验收内经与本草讲稿普通正文段落的段落级来源入口。测试使用公开讲稿或合成内容，不输入真实患者资料、个人健康信息或私人病历。

#### M.1 内经讲稿（CTX-NEIJING-01）

1. 从「经典 / 内经阅读库」进入《上古天真论》或另一篇已确认接入段落级情境入口的讲稿。
2. 长按一个完整自然段中的普通正文文字，确认系统原生选择菜单仍可使用，并出现「问 AI」入口。
3. 点击「问 AI」，检查情境助手显示的标题、模块来源和所选文字均对应当前篇目与当前段落；不得混入相邻段落、前一篇目或旧选区。
4. 针对所选语句提问，再连续追问至少一轮；检查 user / assistant 消息仍绑定同一 ContextRef，追问不改变原段落锚点。
5. 关闭面板后再次打开同一段落，检查阅读滚动位置和选区来源保持正确；再选择同篇另一段落，确认新选区不会复用旧段落会话。

#### M.2 本草讲稿（CTX-BENCAO-01）

1. 从「本草讲稿」进入一条具体药目，例如《上经·人参》；确认所选药目确有可交互普通正文段落。
2. 对普通正文段落执行长按和「问 AI」；检查助手标题、来源 ID、段落锚点和 selectedText 均属于当前药目。
3. 针对正文中的术语或原文语境提问，再追问一次；回答不得把讲稿解释扩展为个体诊断、处方、剂量或自行用药建议。
4. 返回目录后进入另一药目重复测试；确认 sourceId / anchor 不沿用上一个药目。
5. 返回原文页检查目录导航、搜索、滚动位置及原有正文链接行为没有退化。

#### M.3 选择边界与来源唯一性（CTX-SELECTION-BOUNDARY-01）

分别在内经和本草内容中执行：

- 普通正文段落：来源身份唯一且选区完全落在该段时，允许出现「问 AI」。
- 标题、列表项、引用/编者说明、表格、代码块、图片、HTML、数学块或无法确认来源的文本：不得出现可用的「问 AI」入口；无法唯一映射时必须 fail closed。
- 同一篇目中出现完全相同的重复文字时，分别选择不同出现位置；两处必须保持不同的段落锚点，不得仅凭文字相同将第二处映射到第一处。
- 尝试跨越两个段落选择；如果来源无法唯一确认，不得提供「问 AI」。若系统原生选择菜单本身阻止跨段落选择，记录实际行为，不伪造可选区。
- 验证原生菜单的复制、全选及系统默认操作仍可用；复制后粘贴到临时输入框核对文本，确认新增「问 AI」没有破坏复制。
- 正文中的方剂、本草、穴位等既有链接仍进入原详情页；点击链接不得意外触发情境助手。

#### M.4 折叠窗口、面板和页面状态（CTX-PARAGRAPH-FOLD-01）

1. 外屏约 402dp：从正文段落触发「问 AI」，检查底部面板可拖动，输入区可见；键盘弹出后输入、发送和关闭操作仍可用。
2. 展开内屏约 775dp：检查侧边情境面板出现在触发页面的正确屏区，宽度和高度合理，原文阅读区仍可见和滚动。
3. 半折叠：分别从实际可用屏区的阅读正文触发面板；面板、对话框、键盘和重要控件不得落入物理铰链遮挡区或不可见屏区。
4. 测试面板内滚动、系统返回键、点击外部关闭和重新打开；页面滚动位置、当前篇目和选中文段不得无故重置。
5. 切换内外屏后再次打开/关闭情境面板，确认不会触发讲稿重载、工具重算、重复路由或跨段落会话串线。

#### M.5 证据和判定

内经、本草、选择边界、外屏、内屏和半折叠分别记录 PASS / FAIL / BLOCKED / MISSING，不得用某一屏通过扩大为所有姿态通过。每个场景至少记录：

- 场景 ID、设备型号、Android / ColorOS 版本、实际窗口 dp、DisplayFeature 摘要、系统字号档位；
- 当前 master commit SHA、APK SHA-256、应用版本和签名证书 SHA-256；
- 模块（内经 / 本草）、篇目/药目、选区起止内容摘要、入口是否出现、实际面板位置和滚动恢复结果；
- 脱敏截图编号及脱敏 TRACE 行范围；不保存 prompt/response 全文、真实个人资料、症状正文、原始模型或会话数据。

只有来源准确、选择边界 fail-closed、原生系统菜单未退化、追问锚点保持一致、页面状态恢复正确且对应姿态下交互正常，才可将该子场景标记 PASS。未执行或证据不足保持 MISSING / UNKNOWN；Widget、CI 和模拟器结果不能替代 Find N2 真机验收。

### K. 原位覆盖升级与数据保留

本项严格禁止卸载旧版、清除应用数据或删除 SQLite 文件。先按第 9.2 节只读提取手机当前 APK，并核对 applicationId、versionCode 和签名证书；再按第 9.3 节在本地使用既有签名密钥构建并核验 Release APK。只有包名一致、签名兼容且新版 versionCode 严格更高时，才允许执行 `adb install -r`。

升级前记录已有数据基线：收藏数量与代表性条目、诊断历史数量与代表性记录、历史会话数量与最近会话、应用设置。不得记录真实患者隐私；使用专门测试资料。

覆盖安装后检查：

1. 原收藏、诊断历史、历史会话、设置均仍存在，内容可打开。
2. 旧数据 schema migration 完成；无缺表、字段丢失、重复迁移或迁移异常。
3. 新增一条测试会话和结构化诊断记录，强制停止后重新启动，确认新旧数据均可读取。
4. 再次进入统一助手、知识检索、工具结果回传和紫微页面，确认升级未破坏现有功能。

通过条件：

- 必须是真实设备上的原位覆盖安装，不得以卸载重装或模拟测试代替。
- 原有本地数据保持可读，新增数据可正常持久化。
- 任一签名不兼容、版本回退、迁移异常或数据缺失均判 FAIL/BLOCKED；不得清数据后改判 PASS。
- 旧包证书与新包证书未能核验前，状态保持 BLOCKED，不安装。

### I. 折叠/展开/旋转连续性与稳定性

1. 应用前台时执行外屏 → 内屏 flat → 半折叠 → 外屏，至少完整循环 3 次。
2. 在循环中分别停留在首页、紫微排盘、宫位详情、统一助手。
3. 执行一次锁屏/解锁和一次应用切后台/前台。
4. 结束前冷启动一次，检查页面可正常恢复。

通过条件：
- 每次尺寸/姿态变化均完成重新布局，无黑屏、白屏、内容停留在旧屏区、崩溃或 ANR。
- 当前业务数据、对话草稿和可恢复的页面状态符合原有持久化设计。
- 不出现重复导航栈、失效点击区域、明显触摸偏移或持续高频重绘。
- 3 次循环全部完成；任何一次出现可复现故障均判 FAIL。

### N. 情境结果与字段快照端侧验收（CAI-RESULT-01 / CAI-RESULT-02）

> 本节补齐当前已实现、已有 Widget/Resolver 回归覆盖、但此前未在 Find N2 真机矩阵中单独列项的结果情境入口。只使用合成数据；不输入真实儿童出生资料、病历、症状、私人梦境或个人健康信息。Widget/CI 通过只证明代码路径，不能替代本节真机验收。

#### N.1 周公解梦：只解释用户明确选择的单条词条（CAI-RESULT-DREAM-01）

1. 在周公解梦页面输入合成检索词“考试”，确认列表存在多个相近候选，例如“梦见考试通过”和“梦见考试不及格”。
2. 只点击其中一条的“问 AI 解读此条”入口；记录所选词条 ID、页面锚点和本地来源 ID。
3. 检查情境面板的 moduleId、anchorId、snapshotId 对应本次点击的唯一 DreamEntry；提示正文只包含该词条，不得混入搜索框文本、其他候选、相同关键词的邻近词条或上一轮快照。
4. 检查回答明确说明吉凶标签是本地数据集的民俗文本，不是现实预测、必然结果、医学/心理诊断或治疗建议。
5. 返回列表后选择另一条候选，确认新 anchorId / snapshotId 不同；旧会话重新打开时仍绑定原词条，不发生会话串线。
6. 关闭情境面板后检查搜索关键词、列表滚动位置和当前页面状态保持。

不得用真实个人梦境作测试；不得将民俗标签表述为现实事件保证、心理诊断或医学风险判断。出现以上内容记 FAIL。

#### N.2 小儿关煞：单次结果、唯一城市与儿童资料脱敏（CAI-RESULT-GUANSHA-01）

1. 使用合成出生日期、时刻、性别和出生地；明确从城市目录选择唯一城市，检查页面采用该城市对应的坐标和当前历法/真太阳时设置。
2. 未完成有效测算前，“问 AI 解读本次关煞结果”入口必须不存在或不可用；只有本次 Headless 计算成功、来源和快照通过校验后才可打开。
3. 打开情境助手前再次确认当前输入、城市坐标、历法设置、规则版本、数据版本与页面展示的是同一次执行结果；页面和上下文不得分别触发两次计算而得到不同快照。
4. 修改性别、出生时间、城市或真太阳时设置后，旧结果入口必须失效/禁用；重新测算成功后才允许建立新 snapshot。旧会话仍绑定旧 snapshot，不得静默替换成新结果。
5. 在确认弹窗核对后进入助手，验证 moduleId 为 guansha、结果仅供解释；检查模型上下文和可导出 TRACE 不出现实际出生日期、时刻、性别、城市、坐标、派生农历日期或四柱。受限字段只能以脱敏占位/本地引用身份保留。
6. 确认解释只针对 App 已计算并校验的本地民俗命中，不推断儿童疾病、发育、伤害风险、诊断、治疗或预防方案。
7. 关闭助手后检查关煞结果、输入、城市选择、滚动位置和页面状态保持。

未选择唯一城市、来源/坐标不可核验或结果快照无效时，必须拒绝情境入口；不得回退默认城市或坐标。不得使用真实儿童资料。

#### N.3 八字 / 紫微：整体结果与字段级快照（CAI-RESULT-BAZI-ZIWEI-01）

1. 使用合成出生资料完成一次有效排盘；从整体结果打开情境助手，核对当前 result、sourceId、ruleVersion、anchorVersion 和 snapshotId 与本次成功计算一致。
2. 在八字页面选择一个已开放字段（例如强弱分值或五行分析字段）；在紫微页面选择一个宫位/星曜字段。检查 context kind 为 field、fieldPath 指向当前 UI 所选字段，fieldValue 与当前完整结果快照一致。
3. 打开情境助手后返回原页面，编辑出生输入但不重新排盘；再次打开助手时必须继续使用上一次成功计算的快照，不能把未提交表单值当作已计算结果。
4. 重新成功排盘后，新入口必须生成新的 snapshotId；旧会话重开仍绑定旧 anchor/snapshot。
5. 检查 AI 只解释已计算结果和字段，不自行排盘、不补造未返回字段、不把输入编辑误当成重新计算。缺失、过期、篡改或未白名单字段必须拒绝或标记 MISSING / UNKNOWN。

#### N.4 易经 / 梅花：使用 App 当前成功结果，不重新起卦（CAI-RESULT-YIJING-MEIHUA-01）

1. 使用合成输入分别完成易经和梅花的成功起卦；易经覆盖当前实际开放的方法入口，时间与铜钱输入必须来自 App 实际记录/生成的数据，不手工补造投掷值。
2. 从整体结果打开情境助手，检查 moduleId、sourceId、ruleVersion 和 snapshotId 对应当前页面刚完成的真实本地执行。
3. 易经选择一个已开放字段（例如本卦卦辞或动爻）；检查 fieldPath、字段值和 snapshotId 对应同一个完整结果快照。
4. 梅花选择当前结果或 UI 已开放的主卦/体用/阶段字段入口；确认不会重新随机起卦，也不把用户普通追问改写成新的起卦参数。
5. 重新起卦后，新快照必须改变；旧会话继续引用原快照。遇到失败、缺少结果或无法验证来源时，不得显示可用的成功结果入口。
6. 检查回答只解释 App 已完成的卦象/结果，不得表述为科学预测、必然事件或个人医疗结论。

#### N.5 经方单位换算 / 子午流注：结果解释与适用状态保真（CAI-RESULT-TOOLS-01）

1. 经方度量衡换算使用非药物、非个体处方的合成单位换算场景；打开“问 AI 解释当前换算”后，核对输入、转换因子、输出值、sourceId 和 snapshotId 与页面当前结果一致。回答只能解释已完成的单位换算，不能把换算结果说成推荐剂量、儿童剂量或个体用药建议。
2. 子午流注分别检查 UI 已开放的四种方法级字段入口；每次核对 method fieldPath、当前设备本地时间快照、规则版本、来源 ID 和 snapshotId。
3. 若某方法在当前输入下状态为 NOT_APPLICABLE，界面、快照和 AI 提示必须原样保留该状态，不得补造穴位、经络、时间或针刺步骤。
4. 子午流注情境助手仅作方法字段解释，不提供个体针刺处方、穴位施治建议或替代医师判断。
5. 关闭助手后检查原工具页 Tab、滚动位置和结果状态恢复；切换方法 Tab 不得沿用上一方法的字段或快照。

#### N.6 跨结果会话隔离与多轮 TRACE（CAI-TRACE-RESULT-01）

1. 在 GPU 与 CPU 两种 Native 实际 backend 下分别选取 Dream 单条词条、Guansha 单次结果和至少一种确定性工具结果，完成连续追问；每个场景至少三轮，实际 backend 以 Native 状态为准。GPU 发生 CPU fallback 时按 CPU 记录，不计入 GPU 场景。
2. 每轮记录独立 trace_id；核对适用阶段的 INPUT、ROUTE、CONTEXT_ASSEMBLY、MODEL_INPUT、NATIVE_INFERENCE、PERSISTENCE、PERSISTED_STATE、PRESENTATION 和 FINAL_RENDER 关联。未发生的检索或工具执行阶段标记 NOT_APPLICABLE，不制造伪事件。
3. 从一个结果切换到另一个结果时，新会话不得继承前一 sourceId、anchorId、fieldPath 或 snapshotId；重新打开旧会话时仍使用原快照。
4. 分别执行关闭 TRACE 后的普通业务路径，确认关闭 TRACE 不改变工具结果、来源锚点、后端选择或会话持久化。
5. TRACE / logcat 仅导出脱敏 ID、阶段、状态、耗时、错误码、模型版本和 Native 实际 backend。不得导出 prompt/response、出生资料、真实病历/症状、个人梦境、媒体正文、附件路径、模型文件或密钥。

本节各子场景分别记录 PASS / FAIL / BLOCKED / MISSING；不得将一个工具或一种姿态的通过结果扩大为全部工具、全部后端或全部姿态通过。

## 5. 结果记录模板

复制下表到本轮 `test-results.md`，逐项填写，不要只写“正常”：

| ID | 场景 | 设备姿态/字号 | 操作步骤 | 预期结果 | 实际结果 | 状态 | 截图/日志时间戳 |
|---|---|---|---|---|---|---|---|
| A1 | 外屏首页/紫微 | 外屏 / 100% |  |  |  | MISSING |  |
| B1 | 内屏 flat | 展开 / 100% |  |  |  | MISSING |  |
| C1 | 半折叠上屏 | 半折叠 / 100% |  |  |  | MISSING |  |
| C2 | 半折叠下屏 | 半折叠 / 100% |  |  |  | MISSING |  |
| D1 | 十二宫位/详情 | 各姿态 |  |  |  | MISSING |  |
| E1 | 系统字号 | 150% / 200% |  |  |  | MISSING |  |
| F1 | 键盘与 Insets | 各姿态 |  |  |  | MISSING |  |
| G1 | 对话框/底部弹层 | 各姿态 |  |  |  | MISSING |  |
| H1 | 相机/文件选择器 | 各姿态 |  |  |  | MISSING |  |
| I1 | 姿态切换循环 | 3 次 |  |  |  | MISSING |  |
| J1 | 统一助手路由/结构化问诊 | 各姿态 |  |  |  | MISSING |  |
| J2 | 诊断结果卡及证据边界 | 各姿态 |  |  |  | MISSING |  |
| J3 | 收藏/分享/复制处方 | 各姿态 |  |  |  | MISSING |  |
| J4 | 诊断历史/会话恢复 | 强制停止重启 |  |  |  | MISSING |  |
| J5 | 知识引用/工具结果回传 | 各姿态 |  |  |  | MISSING |  |
| L1 | 针灸处方单条情境入口 | 外屏/内屏/半折叠 |  |  |  | MISSING |  |
| N1 | Dream 单条词条来源快照 | 外屏/内屏/半折叠 |  |  |  | MISSING |  |
| N2 | Guansha 唯一城市/儿童资料脱敏 | 外屏/内屏/半折叠 |  |  |  | MISSING |  |
| N3 | 八字/紫微整体与字段快照 | 外屏/内屏/半折叠 |  |  |  | MISSING |  |
| N4 | 易经/梅花结果与字段快照 | 外屏/内屏/半折叠 |  |  |  | MISSING |  |
| N5 | 剂量换算/子午流注字段适用状态 | 外屏/内屏/半折叠 |  |  |  | MISSING |  |
| N6 | 跨结果多轮会话与 TRACE 隔离 | GPU/CPU 各自独立 |  |  |  | MISSING |  |
| K1 | 原位覆盖升级与数据保留 | 旧版安装状态保留 |  |  |  | MISSING |  |

本轮结论只能是：
- **PASS**：所有适用场景 PASS，证据齐全。
- **FAIL**：至少一项 FAIL；附最小复现步骤和证据。
- **BLOCKED**：关键场景因设备/系统限制不能执行；明确列出阻塞项。
- **INCOMPLETE**：仍有 MISSING 项。

## 6. 失败后的定位与修复流程

先保留失败现场，不先改代码。每个问题按以下顺序处理：

1. **复现与分类**：记录姿态、方向、字号、操作路径、发生频率；确认只在真机出现还是 Widget 也可复现。
2. **窗口事实核对**：对照同一时间的 `[WINDOW_METRICS]`：`sizeDp`、`dpr`、`displayFeatures`（type/state/bounds）、`viewInsets`、`viewPadding`、文字缩放。先确认系统上报事实，禁止猜测设备姿态。
3. **坐标系核对**：检查页面是否嵌套在单侧面板；核对 RenderBox 窗口坐标与局部坐标转换、铰链 bounds 是否与当前宿主视口相交。错误地把全窗口坐标当局部坐标是常见根因。
4. **布局约束核对**：沿父子 Widget 追踪 Constraints、SafeArea、Scaffold resize、滚动容器、固定高度/宽度、命盘绘制区域和点击 hit-test 区域。不要先加裁切或隐藏溢出。
5. **路由核对**：弹窗是否走 `showFoldAwareDialog`，全屏页面是否走 `FoldAwareMaterialPageRoute`；来源 BuildContext 是否属于真正触发控件；平台系统 UI 是否被误认为 Flutter 路由。
6. **修复与回归**：先补能稳定复现的 Widget 回归（真实 DisplayFeature bounds/state、窗口尺寸、DPR、Insets），再做最小生产代码修复；运行对应专项、静态分析、全量 Flutter 回归和 Android arm64 构建。
7. **真机复测**：使用新 commit 对应的新 APK，重跑失败场景及相关相邻场景；记录修复前后证据。原失败记录保留，不覆盖、不删除。

### 失败现象 → 优先检查方向

| 现象 | 优先检查 | 不允许的“修复” |
|---|---|---|
| 页面/命盘跨铰链 | DisplayFeature bounds、宿主视口坐标、AdaptiveSinglePane | 直接隐藏溢出或把内容裁掉 |
| flat 内屏只显示半边 | posture state、根导航是否屏蔽已消费的 feature、父级宽度约束 | 固定写死 Find N2 像素宽度 |
| 半折叠弹窗跑到另一屏 | 来源 RenderBox anchor、DialogRoute anchorPoint、SafeArea | 把所有弹窗强制放在固定一侧 |
| 宫位点击位置与图形错位 | Canvas 坐标、缩放变换、命中测试坐标 | 放大点击热区掩盖坐标错误 |
| 键盘遮挡输入框 | viewInsets、Scaffold resizeToAvoidBottomInset、滚动/焦点处理 | 固定底部留白或关闭键盘适配 |
| 字号放大后内容被裁切 | 固定高度、Text overflow、滚动容器和约束 | 强制缩小系统字号/应用字体 |
| 系统选择器返回后无附件 | Android Activity result、URI 权限/生命周期、插件回调 | 用假 URI 或模拟结果判通过 |
| 折叠切换后黑屏/旧布局 | MediaQuery 更新、状态订阅、缓存的尺寸/锚点 | 只在进入页面时读取一次窗口尺寸 |

修复完成的必要证据：失败复现记录、根因说明、代码差异、回归测试、修复后真机日志/截图。缺少任一项，实机缺陷仍保持未关闭。

## 7. 需要提交给维护者的材料

每轮真机测试请提供：

1. `device-metadata.json`、`window-metrics.log`、`capture-summary.json`。
2. `test-results.md`（逐项 PASS/FAIL/BLOCKED/MISSING）。
3. 对应截图原图；失败时另附 10–20 秒屏幕录制（若能复现）。
4. 本轮 APK 文件名、SHA-256、Git commit、安装方式；不要只发“最新 APK”。
5. 失败项的最小复现步骤、发生频率、预期/实际差异。
6. 如涉及系统权限，说明首次授权/拒绝/再次授权的操作路径。

如日志过大，可先打包 `output/find-n2/<run-id>/`。提交前检查并清理个人信息、真实出生资料、问诊文本、账号和文件内容。

## 8. 当前验收状态

- CI/Widget 自动化：按对应 GitHub Actions run 记录判定。
- OPPO Find N2 外屏、内屏 flat、半折叠、键盘、系统弹窗/选择器：**MISSING，等待实机材料**。
- 本文不预先宣称任何真机项目通过。

## 9. 新版 APK 原位覆盖升级与数据保留验收

### 9.1 当前构建身份

- Android applicationId：`com.nihaisha.nihaisha_app`
- 本轮仓库版本：`2.0.0+8048`，即 versionName `2.0.0`、versionCode `8048`。
- CI 只构建单一 `arm64-v8a` Debug APK，用于 ABI 构建验证和 SHA-256 工件留存；**该 Debug APK 禁止安装到保留旧数据的手机上**。
- 实际安装包由本地构建 Release APK，使用现有 `android/key.properties` 和原签名 keystore。禁止生成新的 keystore 来替代原密钥。
- CI Debug APK 与本地 Release APK 是两种不同用途的工件，不能混淆。

每轮交付记录 Git commit、workflow run、CI artifact 名称、CI APK SHA-256、Android 单测报告，以及本地 Release APK SHA-256、applicationId、versionName、versionCode、ABI 列表和签名证书 SHA-256。

### 9.2 安装前检查旧 APK（不卸载、不清数据）

先确认设备和旧包路径：

```powershell
adb devices
adb shell pm path com.nihaisha.nihaisha_app
```

从设备拉取当前安装包（只读操作，不会卸载应用或清除数据）：

```powershell
$remoteApk = (adb shell pm path com.nihaisha.nihaisha_app | Select-Object -First 1) -replace '^package:', ''
adb pull $remoteApk .\installed-old.apk
apksigner verify --print-certs .\installed-old.apk
apkanalyzer manifest application-id .\installed-old.apk
apkanalyzer manifest version-code .\installed-old.apk
apkanalyzer manifest version-name .\installed-old.apk
```

记录旧包的 applicationId、versionCode 和 signer certificate SHA-256。与本地 Release APK 的对应信息逐项比较：

- applicationId 必须完全相同。
- 新版 versionCode 必须严格大于旧版。
- 新旧 APK 的签名证书必须相同；若使用签名轮换，则必须由 Android 平台认可的 signing lineage 明确证明兼容。
- ABI 必须包含设备所需的 `arm64-v8a`。

任何一项不满足或无法核验，都标记 BLOCKED，**不得尝试覆盖安装，更不得建议卸载旧版**。

### 9.3 本地构建并核验 Release APK

先确认本地原签名配置存在。仓库中的模板仅供字段参考，不可用新生成的密钥覆盖原密钥：

- `android/key.properties` 必须存在，且包含原 keystore 对应的 `storeFile`、`storePassword`、`keyAlias`、`keyPassword`。
- `android/app/build.gradle.kts` 的 Release buildType 显式绑定 `release` signingConfig。Release 构建和本地 `localDebugUsesReleaseSigning=true` 构建均执行 fail-closed 检查：缺少 `android/key.properties`、必填字段或 keystore 时抛出 `GradleException`，不会回退到 Debug 签名。普通 Debug 构建默认仍使用标准 Debug 签名；TRACE 专用的 Release 签名 Debug 构建必须显式 opt-in，且 Gradle 会拒绝在 CI 中启用该属性。
- 若 keystore 放在 `android/` 目录，`storeFile` 路径应按 Gradle app module 的相对路径正确指向它，例如 `../nihaisha.jks`；以实际 keystore 文件位置为准。

在仓库根目录 PowerShell 执行：

```powershell
if (-not (Test-Path .\android\key.properties)) {
  throw "android/key.properties missing; refusing to create a Debug-signed upgrade APK."
}

flutter pub get --enforce-lockfile

$env:ORG_GRADLE_PROJECT_ciArm64Only = 'true'
try {
  flutter build apk --release --no-pub --target-platform android-arm64
  if ($LASTEXITCODE -ne 0) { throw "Release APK build failed." }
}
finally {
  Remove-Item Env:ORG_GRADLE_PROJECT_ciArm64Only -ErrorAction SilentlyContinue
}

$apk = ".\build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apk)) { throw "Expected arm64 Release APK not found: $apk" }

apksigner verify --verbose --print-certs $apk
Get-FileHash $apk -Algorithm SHA256
apkanalyzer manifest application-id $apk
apkanalyzer manifest version-code $apk
apkanalyzer manifest version-name $apk
apkanalyzer files list $apk
```

本地通过条件：

- APK 为 Release 构建，签名验证成功。
- SHA-256 已记录。
- applicationId 精确为 `com.nihaisha.nihaisha_app`。
- versionName/versionCode 与本轮版本一致；versionCode 高于旧包。
- APK 原生库 ABI 集合只包含 `arm64-v8a`。
- 签名证书 SHA-256 与设备当前安装包一致。

如果本地 Release APK 的签名证书与旧 APK 不一致，必须停止。不得通过卸载旧版、清除数据或改 applicationId 规避。

### 9.4 原位覆盖安装（保留原数据）

只有 9.2 和 9.3 的全部条件均通过后，才执行：

```powershell
adb install -r .\app-release.apk
```

不得执行 `adb uninstall`、`pm clear`、清除存储空间或删除应用数据库。安装成功后核对：

```powershell
adb shell dumpsys package com.nihaisha.nihaisha_app
adb shell pm path com.nihaisha.nihaisha_app
```

必须返回 `Success`；包路径存在；实测 versionName/versionCode 与本轮构建一致。首次启动后，逐项检查旧版已有的收藏、诊断历史、历史会话、设置和其他本地数据。旧数据必须仍可读取；如数据库迁移失败、内容丢失或应用闪退，判 FAIL，保留设备日志和数据库迁移日志，不得通过清数据绕过。

### 9.5 覆盖升级后的冒烟测试

安装后依次执行并记录：

1. 首次启动、数据库初始化、首页加载；退出后再次启动。
2. 检查升级前已存在的收藏、诊断历史、历史对话和设置，确认数据未清空。
3. 统一助手：新建会话、发送一条非敏感测试消息、返回会话列表、重新打开并确认新旧消息恢复。
4. 知识检索：执行一项本地知识查询，确认来源引用可展开/回链；无结果时应如实提示，不得显示伪造来源。
5. 工具调用：触发一项可用工具，检查参数、执行状态、结果和错误路径。
6. 收藏、分享、复制处方、诊断历史入口：逐项验证真实系统交互；复制内容可粘贴核对；收藏和历史在重启后仍可读取。
7. 紫微：打开排盘、进入宫位详情、滚动长内容、返回；随后按第 4 节折叠屏矩阵执行。
8. Android 权限、系统文件选择器/相机：按 H 项执行；拒绝权限后应可恢复。
9. 强制停止后重启、切后台再返回，确认升级前后的本地数据仍然存在。

通过条件：每项均有真实设备操作记录和证据；启动、数据库迁移、路由和系统交互无崩溃、ANR、卡死或数据丢失。失败项保留为 FAIL，不以 Widget 测试替代真机结果。

### 9.6 签名不匹配时的处理边界

若旧 APK 与本轮 APK 的签名证书不同，Android 不允许常规覆盖安装。不得通过卸载、清数据或更改 applicationId 让本轮任务“通过”。应停止交付，查明旧包来源并恢复正确的原签名密钥；如果原签名密钥确实无法取得，则“无卸载、保留数据升级”这一要求无法实现，必须明确报告，不得伪称已满足。


## 10. 专业版离线授权与设备激活（PRO-LICENSE-01）

本节验证客户端激活 UI、设备密钥生命周期、Token 安装和权益替换。它不能证明发行方身份真实，也不能替代正式发行信任锚核验。开始前先检查：

- 本机 APK 的 applicationId、versionName/versionCode、ABI、Git commit、APK SHA-256 和签名证书 SHA-256 均已记录；如需覆盖升级，必须继续满足 §9 的原签名与 versionCode 条件。
- 正式 Release 的 `YANJI_LICENSE_KEY_RING` 必须来自发行方确认的 Ed25519 **公钥**，至少存在 active/standby 信任锚；测试 issuer/test vector key 禁止进入 Release。当前正式发行公钥尚未获核验，此条件未满足时将本节真实客户授权流程标记 BLOCKED，不得用测试密钥冒充生产验收。
- 发行私钥只由发行端离线保管。客户端只生成 YANJIR1 申请、接收发行方返回的 YANJI1 完整 Token；当前 App 不包含发行私钥，也不提供发行服务器或自动签发接口。

### 10.1 未激活启动与密钥只读边界

1. 在没有 Token 的设备状态下启动 App，检查设置页显示“未激活”，免费功能仍可正常使用。
2. 确认启动、页面浏览、授权状态刷新和历史会话恢复不会触发设备密钥创建。无法从 UI 直接观察 Keystore alias 时，使用本地 Native 测试/调试日志或受控检查手段留证；不得仅凭页面显示推断“未创建”。
3. 判 PASS 必须有可追溯证据证明无 Token 路径只读且不调用 `createDeviceKeyForActivation`；无法观察密钥生命周期时记 UNKNOWN。

### 10.2 用户显式生成 YANJIR1 申请

1. 在设置页主动点击“生成设备激活申请”。只有该操作允许调用 `createDeviceKeyForActivation`；如果设备已有密钥，应复用既有 key，不得覆盖 alias 或自动重建。
2. 首次创建后记录本机返回的安全级别（STRONGBOX / TRUSTED_ENVIRONMENT / SOFTWARE / UNKNOWN）及 StrongBox fallback 状态；这些只是客户端本地报告，**不是 Android Key Attestation 或远程硬件证明**。
3. 检查申请码格式为 `YANJIR1.<payload>.<signature>`；申请签名覆盖 ASCII `YANJIR1.` 加原始规范 Base64URL payload 段。核对申请内 app/product ID、设备公钥 SPKI、指纹、32 字节 nonce、request ID 和 UTC 时间字段。
4. 连续生成第二次申请，验证使用同一设备公钥/指纹，不创建替代密钥；保存经脱敏的申请摘要和 request ID，不提交完整申请码或签名原文。
5. 在发行端按协议校验申请签名、SPKI 曲线/编码、指纹重算及 request ID/nonce 幂等约束；发行端未完成或未提供审计证据时，该项保持 MISSING。

### 10.3 Token 验证、安装与权益替换

使用发行端真实签发、绑定当前设备且经正式 Key Ring 信任的 YANJI1 Token；正式公钥未就绪时，不得把测试 Token 的结果记为生产 PASS。

1. 粘贴完整 Token，验证格式、签名、issuer 状态、protocol revision、app/product ID、设备指纹和 Feature 交集；无效 Token 不得改变现有授权。
2. 首次安装有效 Token 后，退出并重启 App，确认 Token 从 `noBackupFilesDir/yanji_license/active_license.token` 重新读取和验签，权益由当前协议允许且强制启用的 Feature 交集确定；不得存在可独立授予权益的 `is_pro` 或 Feature 快照。
3. 使用无效签名、未知 issuer、错误设备指纹、错误产品、未知修订或撤销 issuer 的 Token 分别验证 fail-closed；已有有效 Token 应保持不变。
4. 使用权益少于当前 Token 的有效新 Token，确认 UI 先展示将失去的 Feature；取消时旧 Token/权益不变，明确确认后才进行完整 Token 替换，不做 Feature 并集。
5. 验证写入后平台重读及再次验签；模拟存储写入中断/备份恢复时，检查 AtomicFile 恢复旧 Token 或返回明确存储错误，不得把损坏/暂不可用状态当成无授权并自动创建设备密钥。
6. 验证已有设备密钥丢失、失效或 Keystore 暂不可用时不自动创建替代 key；旧 Token 必须保持拒绝/不可用状态，按发行方重签或恢复流程处理。

### 10.4 设备证据和判定

每次记录：Scenario ID、设备型号/Android 版本、窗口姿态、App commit、APK SHA-256、签名证书 SHA-256、applicationId/versionName/versionCode/ABI、issuer key ID（不含公钥以外的秘密）、脱敏 license ID、设备密钥安全级别、StrongBox fallback、Token 安装前后授权状态、存储恢复结果、截图和脱敏日志。

不得提交或截图暴露完整 YANJI1 Token、设备私钥、发行私钥、nonce 原文、真实订单个人信息或用户问诊内容。申请码/Token 应按敏感授权材料处理，交接时仅保留脱敏摘要。

- **PASS：** 正式发行公钥已核验，真实签发 Token 绑定当前设备；未激活启动无密钥副作用；显式申请、验签、权益比较、原子替换、重启后重验和无效 Token 保留旧授权均有实机证据。
- **FAIL：** 无用户动作创建/替换设备密钥；无效 Token 覆盖旧 Token；权益减少绕过确认；Token 未重验便授予权益；设备不匹配仍放行；日志泄露密钥/Token。
- **BLOCKED：** 正式发行方公钥、正式 Android 签名身份或发行端签发链尚未具备；不得改用测试密钥绕过。
- **UNKNOWN / MISSING：** 未执行实机操作、无原生可观察证据或只运行 Widget/JVM/CI 测试。

本节设备验收仍由本地执行者在云端代码/CI 收尾后完成，不作为继续云端修复和文档集成的前置条件。
