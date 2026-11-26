# PR #576：Find N2 本地验收交接单

> **状态：LOCAL ONLY / NOT RUN。** 本文是设备执行说明，不是 PASS 报告。本文不将设备验收扩展为临床红旗检测或医学审核。
>
> **PR：** [#576](https://github.com/just2512/nihaixia-app/pull/576)  
> **分支：** `fix/retire-clinical-redflag-requirements-2026-11-26`  
> **编制日期：** 2026-11-26  
> **设备：** OPPO Find N2（PUG110）

## 1. 验收范围与明确排除项

研纪是**中医学习辅助工具**，不是医疗诊断软件、临床分诊系统或医疗决策软件。本交接只验证 PR #576 涉及的普通学习助手调用链，以及应用在 Find N2 上的基本运行情况。

本轮设备验收**不包括，也不要求**：

- 临床红旗 detector、临床风险分类或临床分诊；
- 医学词表、阈值、处置文案的医学背景人员审核；
- 医学审核人员、规则版本、审核日期、审批/签字记录；
- 对本人、他人、知识问题、假设句、引用、既往史、否定表达或时间信息进行临床红旗语义分类；
- 为任何模型入口建立临床红旗正反向测试矩阵；
- 因未执行上述事项而阻断模型调用、普通模式路由、工具执行或版本发布。

这些事项均为 **NOT_APPLICABLE**，不是 MISSING、UNKNOWN、BLOCKED，也不是设备验收的前置条件。

继续保留并验证的只是普通工程契约：输入结构、附件格式/权限、会话归属与历史恢复、模式路由、工具参数/权限、App 确定性规则的真实执行、结果/来源/协议校验，以及失败状态不得伪装成功。它们不构成临床红旗门禁。

## 2. 开始前的版本门禁

**不要直接使用本 PR 分支上的旧快照作为最终实机安装包。** 在 PR #576 完成最新 CI、合并冲突核验并进入最新 `master` 后，再从最新 `master` 构建。当前 master 可能已继续前进，PR head、旧交接文档中的 SHA 和旧 APK 都不能代替实际构建基线。

在仓库根目录执行：

```powershell
git fetch origin
git checkout master
git pull --ff-only origin master
$commit = git rev-parse HEAD
$commit
git show -s --format=fuller HEAD
```

记录以下信息到本轮证据目录：

| 字段 | 记录内容 |
|---|---|
| Git commit | 实际构建的 master HEAD |
| App version / versionCode | 从实际 APK manifest 读取 |
| applicationId | 必须为 `com.nihaisha.nihaisha_app` |
| APK SHA-256 | 实际安装 APK 的哈希 |
| signer certificate SHA-256 | 与设备旧版安装证书核对 |
| Android / ColorOS | Find N2 实测值 |
| 模型文件 SHA-256 | 仅本地记录，不上传模型文件 |
| Native 实际 backend | 每次会话实际返回的 GPU 或 CPU，不以设置值推定 |

安装前必须确认 applicationId 与旧包一致、versionCode 高于旧包、签名证书一致或有 Android 认可的 signing lineage、APK 验签成功且包含目标 ABI。任何一项不满足，标记 **BLOCKED**，不要卸载旧版或清除数据来绕过。

## 3. 最低设备场景

使用合成、非敏感的学习问题和测试文件。每个场景记录实际观察结果。

| ID | 场景 | 操作 | 验收重点 |
|---|---|---|---|
| P576-01 | 普通学习对话 | 询问一个普通中医基础知识问题 | 能正常发起模型调用、返回非空回答并展示；无临床预检阻断 |
| P576-02 | 五模式可用性 | 分别进入自动、问诊学习、学习、工具、玄学模式，各执行一个普通的非临床测试请求 | 模式入口正常；按现有业务规则路由；不因临床检测状态阻断 |
| P576-03 | initialPrompt / 情境入口 | 从一个知识条目或结果页面点击“问 AI”进入对话 | 初始上下文能正确带入；来源或情境锚点不串项 |
| P576-04 | 历史续聊 | 打开一条已有助手会话，追问“继续解释上一条的第二点” | 历史消息恢复；上下文指代正确；不重复提交旧轮次 |
| P576-05 | 图片附件 | 使用无个人信息的普通知识图片作为附件 | 选择、读取、模型处理、展示和消息关联正常；取消或解码失败不得写成成功 |
| P576-06 | 语音附件 | 使用无个人信息的普通短语音样本 | 录音/选择、转写或模型处理、结果展示和持久化正常；失败状态清楚 |
| P576-07 | 工具结果回流 | 发起一个已有确定性工具的普通请求 | 参数校验、真实工具执行、结果校验和 AI 解释可关联；AI 不得伪造工具结果 |
| P576-08 | 会话切换 | 在两个会话间切换后分别追问 | 消息、附件、上下文锚点不跨会话污染 |
| P576-09 | 应用重启恢复 | 完成一轮对话，强制停止并重新打开 App | 已完成消息可恢复；未完成轮次不冒充成功；无重复消息 |
| P576-10 | TRACE（可选 Debug） | 在 Debug 设置页显式启用本地 TRACE，执行上述代表场景 | trace_id 与实际轮次可关联；仅保留允许的元数据；新版本不要求或产生 PREFLIGHT / RED_FLAG 临床阶段 |

**不执行临床红旗正向/否定/他人/历史/知识/歧义分类测试。** 不能为了“把旧清单打勾”重新实现或模拟临床检测器。

如本轮同时需要完整 E4B 稳定性验收，沿用 `docs/find-n2-local-ai-acceptance-checklist.md` 和 `docs/find-n2-ai-trace-acceptance-plan.md` 的 GPU/CPU、多轮、附件、恢复和数据清除步骤；这属于设备运行质量，不是 PR #576 的医学审核替代项。设备资源或时间不足时，将未执行项标为 UNKNOWN，不作推断。

## 4. 覆盖安装与数据保留

先读取设备当前安装包的 applicationId、versionCode 和签名证书 SHA-256，再与新 APK 比较。通过第 2 节全部门禁后，只允许覆盖安装：

```powershell
adb install -r .\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

严禁执行 `adb uninstall`、`pm clear` 或系统设置中的清除数据操作。失败时保留旧 App 和数据，记录完整错误后排查；不得通过卸载重装把升级失败改成通过。

升级后核对已有收藏、诊断历史、命盘、助手会话、设置及已导入模型状态。至少打开一条升级前已有的会话，再新建一条测试会话并重启 App，确认旧数据未丢失、新数据可持久化。

## 5. 证据留存与结果判定

在仓库本地建立独立目录，例如：

```powershell
$runId = Get-Date -Format "yyyyMMdd-HHmmss"
$outDir = ".\output\pr-576-find-n2\$runId"
New-Item -ItemType Directory -Force -Path "$outDir\screenshots" | Out-Null
New-Item -ItemType Directory -Force -Path "$outDir\logs" | Out-Null
```

建议保存：

- `device-metadata.json`：设备型号、Android/ColorOS、屏幕姿态；
- `app-build.json`：commit、版本、applicationId、APK SHA-256、签名证书 SHA-256；
- `model-metadata.json`：模型版本和 SHA-256（不附模型本体）；
- `scenario-results.md`：逐场景的预期、观察、结果和缺陷；
- `trace/ai_trace.jsonl`：仅在 Debug TRACE 启用时保存；
- `logs/logcat-redacted.txt` 和必要截图。

每个场景只允许使用以下状态：

- **PASS**：该场景全部实际验收条件均有设备证据；
- **FAIL**：观察到可复现的行为缺陷；
- **BLOCKED**：因版本、签名、设备或环境前置条件不满足而无法执行；
- **UNKNOWN**：缺少充分日志或证据，无法判断；
- **NOT_RUN**：本轮未执行。

不得把未执行项写成 PASS；也不得将局部场景 PASS 扩大为全部 Find N2 验收通过。提交任何证据前，删除真实健康信息、个人资料、会话正文、模型文件、密钥及数据库原件，只提交脱敏摘要。

## 6. 交接完成条件

本地执行人完成后，回传：

1. 实际 master commit、APK SHA-256、签名证书 SHA-256、版本和实际 backend；
2. P576-01 至 P576-10 的逐项结果及未执行原因；
3. 可复现失败的脱敏日志、TRACE 行范围和截图编号；
4. 升级前后数据保留核对结论。

**最终报告只评价普通学习助手链路和设备运行质量。** 临床红旗检测、医学审核、审核版本/记录等事项保持 NOT_APPLICABLE，不进入本地验收统计或发布门槛。
