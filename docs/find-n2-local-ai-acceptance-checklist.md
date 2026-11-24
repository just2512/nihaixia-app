# Find N2 本地 AI 后端切换与端侧验收清单

> 本文件是本地执行清单，不是测试结果或 PASS 报告。GPU/CPU 推理、多媒体、进程恢复、清除数据与 TRACE 必须由实体 OPPO Find N2 执行；云端 CI 和 APK 构建不能代替真机证据。
> 本轮应用运行时代码基线：`master @ 1717b36ba0c2359a1526e22d23f75befacd80628`（最近一次运行时代码变更为 PR #455；已包含 v1.2 授权协议/客户端、Headless F0/F1、ContextResolutionGateway、Release Key Ring 和激活/Token 导入 UI；后续 PR #460/#461/#462 仅更新文档与台账），应用版本 `2.0.0+8048`。设备实测必须记录本地 Release APK 与模型的实际 SHA-256；CI Debug APK 不可作为该设备验收安装包。为本地 TRACE 开启 Debug 控件时，可使用本地专用的 Release 签名 Debug 构建（见第 2.1 节）；该构建只用于调试，不作为最终 Release 交付包。

## 0. 本轮实现目标

- 在 App「设置 → 本地 AI → E4B 推理后端」手动选择 GPU 或 CPU；正式版和 Debug 版均可使用。
- 用户偏好保存在 App 私有设置中，重启后仍保留。
- 模型未加载时，切换只保存偏好；下一次加载按所选后端初始化。
- 模型正在运行时，切换通过 Native 串行任务队列完成：等待已进入队列的当前工作结束，释放旧 Engine/Conversation，再按新选择重建；只恢复此前已成功完成的对话轮次，不自动重放正在失败/状态未知的请求。
- 如果所选后端初始化失败，界面显示失败，用户可以选择另一后端再次尝试。
- 同时展示「用户选择的后端」和「Native 实际运行的后端」。GPU 初始化后发生 CPU fallback 时，必须显示实际为 CPU，不能把用户偏好当作运行事实。

## 1. 测试前准备

使用合成、非敏感测试内容，不使用真实病历、真实症状、出生资料或个人照片。

记录以下信息：

| 字段 | 实测值 |
|---|---|
| 设备型号 | OPPO Find N2 / PUG110 |
| Android / SDK / ColorOS | |
| App version | |
| App commit SHA | |
| 安装 APK SHA-256 | |
| 模型文件版本 / SHA-256 | |
| 模型文件大小 | |
| TRACE 开关 | Debug 设置页开启 / 关闭 |
| 测试日期 | |

模型文件不上传仓库或 CI artifact。TRACE 和 logcat 必须脱敏，不保留 prompt、response、用户正文、症状、图片/音频内容、附件路径、模型文件或密钥。

## 2. 后端手动切换功能（B-01）

入口：**设置 → 本地 AI → E4B 推理后端**。

1. 检查 GPU、CPU 两个选项均可见；默认偏好为 GPU（首次安装或尚无偏好时）。
2. 选择 CPU，退出设置并重新进入，确认选择仍为 CPU。
3. 返回助手并加载模型，检查设置页「当前实际运行」为 CPU。
4. 切换到 GPU，等待模型会话重建；确认 Native 实际 backend 为 GPU，或明确显示实际 fallback backend。
5. 模型加载状态下切换 GPU/CPU，检查切换后此前已完成的对话轮次仍可继续引用；正在执行的请求不得被自动重放。
6. 模拟或记录某一后端初始化失败：错误必须可见；切换另一后端后可再次加载，不需要 ADB Intent、后台改配置或重装 App。
7. 关闭 App 并重新启动，检查用户选择保留；实际 backend 仍须以重新加载后 Native 返回的状态为准。

判定：
- PASS：设置偏好持久化；切换运行中后端会安全重建；完成历史仍可用；实际 backend 明确；失败后可切换另一后端。
- FAIL：UI 显示已切换但 Native 实际 backend 未改变；历史串线/丢失；未完成请求被自动重放；选择无法持久化或错误不可见。
- UNKNOWN：无法读取 Native 实际 backend 或没有执行对应场景。

### 2.1 本地 TRACE Debug 构建

最新 master 的 `android/app/build.gradle.kts` 提供显式本地开关 `-PlocalDebugUsesReleaseSigning=true`。它只在本机使用现有 `android/key.properties` 和原 Release keystore，将 Debug 构建改为使用原 Release 签名，使 Debug-only TRACE 控件可见，同时保持包签名身份。默认 Debug 构建不变；CI 会明确拒绝该属性。

```bash
flutter build apk --debug --target-platform android-arm64 -PlocalDebugUsesReleaseSigning=true
```

执行前确认本地原签名配置完整且 keystore 存在；不得新建密钥替代原密钥。安装前核对 APK 的 applicationId、versionCode 和签名证书 SHA-256。该 Debug APK 仅用于本地 TRACE 调试，不作为 Release 发布包；不得使用 CI Debug APK 代替，也不得卸载旧版或清除数据。正式交付仍须使用原签名 Release APK。

## 3. GPU 连续多轮（G-01）

1. 设置页选择 GPU，确认选择已保存。
2. 在助手页加载模型；设置页确认 Native 实际 backend 为 GPU。
3. 新建空白会话，连续完成至少 20 轮文字对话。
4. 场景至少覆盖：简单问答、上一轮追问、较早实体回指、本地知识检索命中、检索无命中、信息不足时澄清。
5. 每轮记录是否有非空新回复、trace_id、耗时、实际 backend、持久化状态。
6. 记录是否出现 state:7、空回复、首轮 OpenCL fallback、CPU fallback、Conversation 重建；不得把 fallback 后的 CPU 回复计为 GPU 成功轮次。

GPU 模式使用项目现有 EngineConfig：语言模型和视觉后端请求 GPU，音频后端仍为 CPU。不要把音频 CPU 路径记为 GPU。

## 4. CPU 连续多轮（C-01）

1. 在设置页选择 CPU；不需要使用 Debug 启动 Intent。
2. 新建空白会话并加载模型，确认 Native 实际 backend 为 CPU。
3. 使用与 GPU 组相同的文字场景，连续完成至少 20 轮。
4. 检查输出非空、历史逐轮累积、会话隔离、无 state:7/空回复假成功。
5. CPU 模式下语言、视觉和音频后端均配置为 CPU。

## 5. GPU/CPU 多媒体（ATT-01）

GPU 与 CPU 两种实际 backend 分别执行：

- 图片：选择一张非敏感测试图 → Native 接收 → 回复 → 消息持久化。
- 语音：录制一段合成测试语音 → Native 接收/转写 → 回复 → 消息持久化。
- 每类附件额外执行一次取消或无权限路径，确认取消没有伪成功消息。
- 每次都从 Native 状态核对实际 backend；GPU 模式中的音频路径仍按当前 CPU 音频配置记录。

检查附件不跨会话串用；TRACE 不记录附件路径或媒体正文。

## 6. Activity / 进程恢复（REC-01）

1. 在同一会话完成至少 5 轮，包含一次检索和一次附件输入。
2. 记录最后一条成功消息 ID、conversation_id 和脱敏 trace_id。
3. 执行 Activity recreation；再执行命令：adb shell am force-stop com.nihaisha.nihaisha_app
4. 重新打开 App 并恢复原会话，比较 SQLite transcript、Flutter 时间线和 Native 重建的 completed-turn history。
5. 对早期实体做一次跨轮追问。
6. 若恢复无法确认，不继续重放未完成请求；记为 UNKNOWN/FAIL 并保留错误码。

## 7. 清除 AI 数据后重启（CLR-01）

使用合成数据建立至少两个 AI 会话，包含文字、问诊任务快照、图片附件、音频附件和 TRACE；同时创建非 AI 数据哨兵（收藏、诊断历史、命盘、设置）。

1. 在 App 设置中执行「清除全部 AI 数据」并确认。
2. 记录清除结果各数据域及失败状态。
3. force-stop 后重新启动，检查 AI 会话、消息、问诊快照、AI 附件、Native runtime cache 和 TRACE 不可恢复。
4. 检查非 AI 数据仍存在，已安装模型文件按当前产品契约保留。
5. 如执行设备重启，再复查一次并单独记录。
6. 不得删除整个共享 SQLite、共享临时目录或全局关闭 Android Backup 来代替范围明确的清除验收。

## 8. TRACE 完整性（F-01）

在 Debug 设置页开启「本地 AI 调试 TRACE」，GPU 和 CPU 两种 backend 分别执行一轮工具请求、一轮知识检索、一轮普通文本对话和一轮附件对话。

每轮核对：
- 同一个 trace_id 能关联 INPUT、ROUTE、RETRIEVAL（适用时）、CONTEXT_ASSEMBLY、MODEL/NATIVE_INFERENCE、TOOL_EXECUTION（适用时）、RESULT_VALIDATION（适用时）、PERSISTENCE、PRESENTATION 和 FINAL_RENDER。
- 每轮实际 backend 与模型版本可识别。
- 所选 backend 与实际 backend 分开记录。
- 当前正常问诊不要求临床 detector；应用应将 PREFLIGHT / RED_FLAG 明确记录为 NOT_APPLICABLE（NOT_REQUIRED），不得把它写成 detector 已评估、CLEAR 或安全 PASS。只有明确要求实际评估的专门路径才必须出现真实评估结果；应评估但未调用/未配置时记 UNKNOWN。
- 不记录 prompt/response、正文、症状、出生信息、图片/语音内容、附件路径、模型文件或密钥。

TRACE 关闭后确认普通业务路径不受影响；关闭 TRACE 不应改变后端选择或业务执行。

## 9. 针灸处方单条来源情境解读（AI-CTX-ACU-01）

本场景在 GPU 与 CPU 实际 backend 下分别执行；每次均记录 Native 返回的实际 backend，不能把设置页选择当成实际运行事实。使用合成内容，不输入真实患者资料。

1. 打开「穴位处方」Tab，选择分类 `01` / 条目 `1`，展开后点击「问 AI 解读当前处方条目」。确认助手以学习模式打开，并且只传入该条目的结构化快照。
2. 新建另一会话，选择分类 `08` / 条目 `1`。这两个记录的数字 entryId 相同，但必须保持分类复合身份：`acupuncture-prescriptions:01:1` 与 `acupuncture-prescriptions:08:1` 是不同锚点；`sourceId` 分别为 `acupuncture:01:1` 与 `acupuncture:08:1`。
3. 在同一个锚点会话连续追问并重开历史。检查本轮 user/assistant 消息的 metadata 都保留完全相同的 ContextRef：`kind=knowledgeEntry`、`moduleId=acupuncture-prescriptions`、对应 `anchorId`、`sourceId`、`snapshotId=anchorVersion` 和资料 `ruleVersion`。
4. 切换到不同分类或不同条目后，应新建独立情境会话，不得把上一个条目的快照或回答带入新会话。
5. 当前 `透针透穴`、`穴位讲解`、`耳穴` Tab 未启用本次 CTA，记录为 `NOT_ENABLED`；不要将其误记为已通过的功能。
6. 检查 `nihaisha+bbxx` 等 source 字段按原值保留。该字段只是 App 本地来源标签，不等于可核验的独立出处；缺少版本、页码、依据记录时必须标记 `UNKNOWN / MISSING`，不得让模型补造。
7. 核对 Prompt 的限制：只解释当前一条记录；不执行工具或重新计算；不推断用户诊断；不输出个人治疗方案、配穴、针刺深度、角度、方向、手法、频次或自行施治步骤。
8. 分别检查实际 backend、每轮独立 trace_id、上下文锚点与消息持久化。对本场景未发生的检索、工具执行或业务执行阶段标记 `NOT_APPLICABLE`，不得为了填满 TRACE 阶段而制造伪事件。

判定：
- PASS：锚点、快照、会话隔离、数据来源、安全边界和本机实际 backend/TRACE 证据全部一致。
- FAIL：发生跨分类/跨条目串线、快照不匹配仍继续、工具误执行、来源伪造或越界个人施治指导。
- UNKNOWN：无法读取消息 metadata、Native 实际 backend 或关键 TRACE 证据。
- 未执行项保持 MISSING，不得计入 PASS。

## 10. 单场景结果记录模板

每个场景复制一份：

| 字段 | 记录 |
|---|---|
| Scenario ID | |
| trace_id（脱敏） | |
| 用户选择 backend | GPU / CPU |
| Native 实际 backend | GPU / CPU / UNKNOWN |
| App commit / APK SHA-256 | |
| 模型版本 / SHA-256 | |
| 输入摘要（合成数据） | |
| 预期结果 | |
| 实际结果 | |
| 轮次 / 耗时 | |
| error code / fallback | |
| transcript / 持久化一致性 | |
| TRACE 缺失阶段 | |
| 判定 | PASS / FAIL / BLOCKED / UNKNOWN |
| 失败分类 | 理解 / 检索 / 上下文 / 执行 / 模型上限 / 安全 / UNKNOWN |
| 截图或脱敏证据文件 | |

不得将未执行场景计为 PASS。设备验收证据保存在本地 output/find-n2-ai/<run-id>/，提交仓库前只提交脱敏的摘要结果，不提交原始会话、模型或个人数据。
