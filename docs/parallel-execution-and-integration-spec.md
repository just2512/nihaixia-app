# 研纪本地—远程双工作流与统一集成规范

> **状态：** PR 提案，合并后生效  
> **适用仓库：** `just2512/nihaixia-app`  
> **唯一正式集成分支：** `master`  
> **配套约束：** 产品定位、AI 能力审计、五层运行时架构与 AI 改造执行台账

## 1. 目标与不可变约束

建立“本地执行、远程开发、统一集成”的双工作流，使 Find N2 真实设备工作与云端源码/CI 工作能够并行推进，同时保持唯一主线、明确代码所有权和可追溯验收。

本规范不改变研纪的产品定位、业务规则、模型权限、五层 AI 运行时契约或既有发布边界。研纪是离线优先的学习工具；本规范不是新增 Agent 平台、服务、数据库、业务模块或诊疗能力的授权。

必须遵守：

1. `master` 是唯一正式集成主线。所有任务均以完整的主线 commit SHA 建立基线，不建立长期私有主线。
2. 本地与远程可以并行，但同一缺陷、同一文件在同一时间只允许一个代码修改负责人。
3. 每个任务必须有唯一 Task ID、负责人、明确文件范围、依赖和验收条件。
4. 代码修复、测试和共享文档记账解耦。普通任务 PR 默认不修改共享治理文档。
5. 合并依据必须是 PR 最终 HEAD SHA 的适用门禁结果。其他 SHA 的结果不得继承；`skipped`、`cancelled`、`neutral`、缺失结果均不作为本项目门禁 PASS。
6. 自动化通过不代表 Find N2 实机通过；未实测必须保留 `DEVICE MISSING / UNKNOWN`。

## 2. 工作流角色与责任

| 角色 | 主要责任 | 唯一写入范围 |
|---|---|---|
| Local | Find N2 复现、端侧 E4B、GPU/CPU、多轮/恢复、媒体、折叠屏与 Android 生命周期；提交本地发现的代码修复 PR | 实机记录只写 `docs/local-real-device-acceptance-handoff.md`；代码写入自己的任务分支 |
| Remote | 源码审计、缺陷定位、Dart/Kotlin/Native 修复、回归测试、CI 排障和 PR | 不拥有共享治理文档写入权 |
| Integration | 基线、任务/PR 分流、文件归属、冲突排序、合并、执行台账更新 | `docs/ai-modernization-execution-ledger.md` |
| Architecture | 跨模块协议冻结、架构边界审查和规范变更 | `docs/ai-layered-runtime-architecture.md` |

一个人可以兼任多个角色，但同一个任务仍必须明确唯一负责人；角色兼任不代表可以绕过独立分支、PR 和验收。

## 3. 主线基线、工作目录与分支

### 3.1 基线规则

任务启动时执行：

```powershell
git fetch origin --prune
$base = git rev-parse origin/master
git status --short
```

将完整 SHA 写入任务登记和 PR。工作区必须干净后才能创建任务 worktree。

PR 最终验收前重新获取 `origin/master`。如果主线已经前进，必须核对 ahead/behind、文件重叠及接口依赖；合并前分支必须满足保护规则的最新基线要求，并对最终 HEAD 重新运行门禁。

不以固定合并次数作为机械重基阈值；以真实 base SHA、ahead/behind、冲突和 required checks 为准。发现文件重叠或契约依赖时，先解决依赖再继续。

### 3.2 Worktree 隔离

- 主工作目录保持干净，仅用于同步和查看主线，不承担并行代码修改。
- 每个并行代码任务使用独立 worktree 和独立分支。
- 不允许 IDE、Agent 或自动化任务共享同一工作目录写文件。
- 不允许多个 worktree 同时检出同一个本地分支。
- 不允许在包含未提交修改的工作目录中执行重基、切换分支或清理操作。

本地代码任务示例：

```powershell
git fetch origin --prune
$base = git rev-parse origin/master
git worktree add ../nihaixia-local-fix -b local/fix-<topic>-<yyyymmdd> $base
```

设备验收必须针对一个固定 commit SHA 构建。建议设备 worktree 以 detached HEAD 检出该 SHA；实测结束后，从最新 `master` 建立独立证据归档分支，仅提交经脱敏的验收摘要。不得在设备目录中切换代码 SHA 后继续沿用原测试结果。

### 3.3 分支命名

| 工作流 | 前缀 | 示例 |
|---|---|---|
| 本地代码修复 | `local/fix-*` | `local/fix-find-n2-fold-layout-20261128` |
| 本地设备证据归档 | `local/device-*` | `local/device-acceptance-20261128` |
| 远程代码修复 | `fix/*` | `fix/core3-codec-boundary-20261128` |
| 远程审计 | `audit/*` | `audit/core1-session-restore-20261128` |
| 远程测试 | `test/*` | `test/core2-retrieval-contract-20261128` |
| 架构/集成治理 | `docs/*` 或 `ci/*` | `docs/parallel-execution-governance-20261128` |

## 4. 任务登记与代码所有权

每个独立缺陷、审计切片或设备批次必须先登记任务，至少填写：

- Task ID / 标题及所属 Core 或 Device / Infra；
- Workstream：`Local`、`Remote`、`Integration` 或 `Architecture`；
- 完整 Base SHA；
- 唯一 Owner；
- 允许修改的路径清单；
- 依赖任务 / PR；
- 云端验收命令及适用门禁；
- 是否需要 Find N2 实机、实机场景和证据要求；
- 当前状态及下一步。

**GitHub Issues 过渡规则：** 当前仓库 Issues 功能关闭，不能创建 Issue。仓库管理员开启 Issues 后，每个新任务必须先建 Task Issue，PR 通过 `Closes #<issue>` 关联。在 Issues 尚未开启期间，每个任务必须在代码开始前建立 Draft PR 作为任务登记卡，使用唯一 Task ID，并填写本节全部字段；不得以未登记的私聊或临时分支代替任务记录。PR 转 Ready for review 前必须补齐登记信息。

同一时间，两个开放任务的实际变更文件不得重叠。确需重叠时，由 Integration 明确先后顺序；不得依赖最后一次合并时再解决同文件覆盖。

PR 的实际变更文件必须属于任务登记声明范围。发现超范围文件，先拆分 PR 或更新任务登记并说明原因，再继续验收。该检查在自动化脚本落地前由集成负责人逐项核对，不宣称当前已自动强制。

## 5. 共享文档单写者与代码/台账解耦

以下文件实行单写者：

| 文件 | 唯一负责人 | 更新时机 |
|---|---|---|
| `docs/ai-modernization-execution-ledger.md` | Integration | 代码 PR 合并后或一个集成批次完成后集中登记 |
| `docs/ai-layered-runtime-architecture.md` | Architecture | 接口合同冻结、架构约束确有变化时 |
| `docs/local-real-device-acceptance-handoff.md` | Local | 完成真实设备复现/验收后归档实际证据 |

普通 `fix/*`、`audit/*`、`test/*`、`local/fix-*` PR 不得顺手修改以上共享文件。任务结论、拟追加的台账文字、测试证据和状态写在 PR 描述中；Integration 在合并后统一更新执行台账。这样降低共享文件的并行写入冲突，但不声称所有 Git 冲突都能归零。

凡涉及跨 Core DTO、公共协议或状态语义变更，先由 Architecture 建立独立接口/规范 PR，冻结字段、类型、失败语义和契约测试；该 PR 合入后，依赖它的实现任务再从新基线并行开发。

本规范生效前已经打开、且已修改共享文档的 PR（当前包括 PR #611）作为在途例外处理：不要求为符合新规则而扩大其修改范围；合并后新任务必须执行本节规则。

## 6. 统一验收：精确 SHA 与门禁定义

所有门禁必须针对 PR 最终 HEAD SHA：

| 检查 | 要求 |
|---|---|
| Base / branch freshness | 从已登记基线派生；合并前满足最新主线要求 |
| File scope | 实际变更文件属于任务登记范围 |
| PR branch validation | `PASS`，不可用 `SKIPPED` 代替 |
| Flutter regression | 完整回归 `PASS` |
| Android arm64 / JVM | 构建、ABI 和 Native 单元测试适用项 `PASS` |
| Fork License | `PASS` |
| PR required gate | `PASS`；汇总任一 prerequisite 非 `success` 时失败 |
| 测试完整性 | 不删除失败测试、不降低断言、不用空测试/跳过测试制造绿灯 |
| 设备状态 | 按实际情况记录 `PASS / FAIL / BLOCKED / DEVICE MISSING / UNKNOWN / NOT REQUIRED` |

### 6.1 当前 GitHub Actions 门禁结构

`.github/workflows/flutter-tests.yml` 中：

- `branch-validation` 在每个 PR 上运行，不再因仅支持 `work/**` push 而在 PR 被条件跳过；它负责分析、变更测试和测试配对检查。
- `test` 执行 Flutter 完整回归。
- `build-apk` 执行 Android arm64 APK 验证和 JVM / Native 单元测试。
- `pr-required-gate` 通过 `always()` 等待上述三个 job 结束；只有三个结果全部严格等于 `success` 才成功。任何 `failure`、`cancelled`、`skipped` 或其他结果都使汇总门禁失败。

Fork License 由独立 workflow 触发，必须作为独立 required check 配置，不能声称它已被跨 workflow 的 `PR required gate` 汇总。

`Flutter Quality Gate` 当前只在 master push 上运行。PR 的阻断性回归由上述 `test`、`build-apk` 和 `PR required gate` 承担；不要仅因为 workflow 名称不同就把同一套全量测试重复设为 required。主线 push 上的 Quality Gate 仍须检查。

### 6.2 master 保护配置

先合并并验证本规范及 PR 汇总门禁，再启用 branch protection。保护配置应要求 PR、要求分支最新、禁止强推和删除，并只要求已经在 PR 上实际出现且名称核实无误的检查：

- `PR required gate`
- `Fork license inventory and boundary`

单人仓库不设置无法满足的自审 approval 数；`required_pull_request_reviews` 可保持 null / 不要求审批。管理员也应受状态检查约束（`enforce_admins=true`）。

仓库管理员在本地已认证的 GitHub CLI 中执行以下命令；不要把 Token 写进仓库或命令历史：

```powershell
@'
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "PR required gate",
      "Fork license inventory and boundary"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
'@ | gh api --method PUT repos/just2512/nihaixia-app/branches/master/protection --input -
```

执行后读取保护配置并检查 required contexts 与实际 check-run 名称完全一致。若 GitHub CLI 返回 403 / 404 / 422，不得宣称保护已生效；先检查当前账号 Admin 权限及所需授权。若改用 Rulesets，配置等价的 required checks 和禁止绕过策略。

## 7. Find N2 设备验收与证据绑定

设备验收记录必须绑定实际构建的 SHA 和制品，不得只记录“最新版”：

- 仓库、完整 commit SHA、分支；
- APK versionName / versionCode、APK SHA-256、签名证书 SHA-256；
- 设备型号（Find N2 / PUG110）、Android / ColorOS 版本；
- E4B 模型标识、模型 SHA-256、LiteRT-LM 版本；
- 实际后端：GPU / CPU / UNKNOWN；
- 场景 ID、时间、预期、实际、结果、脱敏 trace / 日志 / 截图路径；
- 缺口、复测 SHA 和下一步。

设备结果状态：

- `PASS`：该 SHA 构建在目标 Find N2 设备上实际完成场景且通过。
- `FAIL`：已在设备上复现实际问题，必须形成最小复现并回到任务队列。
- `BLOCKED`：模型、签名、设备或必要环境缺失，暂不能执行。
- `DEVICE MISSING` / `UNKNOWN`：尚未执行或证据不足。
- `NOT REQUIRED`：该任务确实不涉及设备行为，必须说明原因。

代码 SHA 变化后，不机械地把所有历史设备结果清零；由 Local 按变更路径和依赖影响判定受影响场景。涉及被测代码、Native 接口、模型配置、构建/签名或运行时依赖的变更必须重测相关场景。结果不能从旧 SHA 自动继承到新 SHA。

原始病历、个人信息、数据库、模型权重、密钥、`key.properties` 和未脱敏 prompt/response 不得提交仓库或 PR。只归档必要的脱敏元数据和合成测试证据。

设备结果只更新唯一交接文件：`docs/local-real-device-acceptance-handoff.md`。不为每个 PR 或 GPU/CPU 子项新建平行交接文档。

## 8. Open PR 生命周期

每个 Open PR 由 Integration 归类为：

- `ACTIVE`：范围有效、负责人明确、基线可用且正在推进；
- `NEEDS_REBASE`：功能仍有效，但基线落后或冲突，需要重新核验和运行最终 SHA 门禁；
- `BLOCKED`：缺少前置接口、环境或证据，暂时无法继续；
- `SUPERSEDED`：已由明确的新 PR / 合并提交取代，关闭前必须关联替代项并确认无独有成果遗漏。

PR 超过 14 天没有更新时，必须由负责人登记原因和下一步，标记为需复核；不自动关闭、不自动判定 SUPERSEDED。所有关闭动作先核对变更是否已被主线或替代 PR 覆盖。

## 9. PR 合并顺序与集成规则

1. 无依赖、文件范围不重叠的任务可以并行开发和运行 CI。
2. 公共接口或文件重叠任务按任务依赖和单写者规则串行。
3. PR 可以在其他分支 CI 执行时继续开发；不要求所有工作排队等待。
4. 合并前核对最新 master、冲突、文件范围、最终 SHA 的 required checks。
5. 合并后 Integration 在执行台账登记真实合并 SHA、PR、CI run / job 和状态。
6. 若主线合并后出现回归，建立新任务定位，不修改或删除原始失败证据。
7. 不允许为了并行数量而拆分有强依赖的实现，也不为形式上的五层划分新增 Agent、服务或数据库。

## 10. Phase 1 落地顺序

- [ ] 合并本规范 PR，并确认 `PR required gate` 在真实 PR 中成功运行。
- [ ] 在 Settings / Rulesets 中启用 master 保护；核验 required contexts。
- [ ] 复核所有 Open PR，填写 ACTIVE / NEEDS_REBASE / BLOCKED / SUPERSEDED 和负责人；不得批量关闭。
- [ ] Issues 开启前，新任务先建 Draft PR 任务卡；Issues 开启后改为先建 Task Issue。
- [ ] 本地建立独立代码 worktree；设备构建使用固定 SHA 的 detached worktree。
- [ ] 远程从相同主线基线推进不冲突任务，任务 PR 不修改共享文档。
- [ ] 本地 Find N2 任务按唯一交接单记录 SHA、APK 哈希、模型与后端证据。

**本规范只定义工程流程和合并门禁，不预先宣称任何尚未执行的真机、CI 或分支保护已经 PASS。**
