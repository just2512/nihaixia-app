# AI 能力审计报告

> 审计时间：2026-11-10  
> 代码基线：`master` @ `3d982e8129a2659547df1cd21143a825c8c5f8fb`  
> 规范来源：[ai-capability-audit.md](ai-capability-audit.md)  
> 执行约束：[ai-modernization-execution-ledger.md](ai-modernization-execution-ledger.md)  
> 并行执行协议：[ai-parallel-workstreams.md](ai-parallel-workstreams.md)

本报告区分“代码已实现”“分支测试通过”“PR 全量 CI 通过”“真机验收通过”。未完成的证据不得用文档或静态检查代替。

## 总体状态

| 工作流 | 当前状态 | 证据 / 阻断 |
|---|---|---|
| A. 多轮 Native 会话恢复 | IN_PROGRESS | PR #21；首次 Android APK build PASS，但 transcript 单测因 Java 17 测试 JVM 直接加载 Java 21 编译的 LiteRT Message 类失败；已将纯策略与 SDK 类型解耦，最新 Android unit test 待复验 |
| B. 红旗 preflight | PARTIAL / BLOCKED | 纯 Dart 策略与测试已实现；没有真实医学审核 detector，也未接入所有 Flutter/Native 入口；未经医学审核不得启用 |
| C. 经典检索黄金基线 | IN_PROGRESS | 黄金请求和捕获测试已建立；branch validation PASS；真实 hit IDs/order/snippets/context JSON 仍待 PR 全量 CI artifact 审阅并固化 |
| D. Page / Executed / Headless | AUDIT PASS | Router 24 项；ToolsScreen 22 个卡片入口；9 项有结果回传设计；Headless 0 项；详见 inventory audit |
| E. AI 数据清除 | IN_PROGRESS | SQLite 事务、附件专属目录、UI 二次确认、Native cleanup helper 已实现；MainActivity MethodChannel handler 待 A 工作流完成后接入 |
| F. TRACE 与隐私 | FAIL / MISSING | 没有端到端 trace_id、默认关闭的审计开关或 NOT_STARTED/SUCCEEDED/FAILED/UNKNOWN 状态链 |
| G. 版本一致性 | IN_PROGRESS | pubspec 当前 1.11.30+8039；README 已同步；一致性测试已添加，分支 CI PASS，尚未合并 |

## 本轮新增事实

### CI 与 UI

- 主线曾有 8 个 `test/local_ai_adaptive_content_test.dart` 折叠屏布局失败，根因是 `local-ai-content-width` 约束缺失。
- PR #22 恢复 `AdaptiveSinglePane` 与 Scaffold.body 内的 640dp 内容约束，并保持 Scaffold 全宽和键盘 inset 策略。
- 旧 head `7d726b943168004e6f30da3497efe97150fe9fa0` 的全量 Flutter regression run `42850952540` 已 PASS；该 PR 级 Android arm64 job 仍在执行。
- PR #22 当前 head 的完整 Flutter regression run `42851126046` 仍在执行；必须以该 head 的最终结果作为合并依据。

### 数据保护

- PR #19 的 Android arm64 APK build 曾 PASS；Flutter 全量回归受主线折叠屏失败影响。
- 当前 Android 备份关闭方案影响整个 app 的私有数据，不仅是 AI 会话；会影响收藏、设置等非 AI 数据的自动备份/设备迁移。合并前必须在报告和 PR 中保留这一影响，不能称为“仅禁用 AI 数据备份”。

### 多分支工作流

- A/B/C/D/E/F/G 均按文件所有权拆分，避免同时修改 `MainActivity.kt`、检索服务或同一 Flutter screen。
- 分支 validation 仅代表静态分析与 changed tests；不能代替 full Flutter regression、Android APK/unit tests 或 Find N2 真机验收。
- 完整约束见 [ai-parallel-workstreams.md](ai-parallel-workstreams.md)。

## 未通过的硬门槛

1. A：最新 transcript policy Kotlin unit tests 必须在 JDK17 CI worker 通过；多轮失败后不得自动重放当前执行状态未知的请求。
2. B：医学专家审核红旗规则/阈值/急救文案；所有输入入口和 Native 边界必须有覆盖测试。
3. C：审阅真实黄金基线 artifact，固定 expected JSON，确认来源身份、顺序、摘要和上下文截断。
4. E：完成 Native `clearAiData` handler；确认先释放 Engine 再删除缓存；清除四张 AI 会话表和专属附件；重启后不可恢复；保留非 AI 数据。
5. F：实现默认关闭的脱敏 trace；关闭时业务输出和执行顺序必须一致；UNKNOWN 状态不得伪装成 FAILED/SUCCEEDED。
6. G：README/pubspec 版本一致性测试进入主线全量 CI。
7. Find N2：GPU/CPU 多轮 state:7、附件后续轮、清除前已加载 Engine、进程重启均需要真实 TRACE；CI 不能替代设备验收。

## 专项报告

本分支内已包含：
- [能力清单](ai-capability-inventory.md)
- [Page / Executed / Headless 逐项审计](ai-capability-inventory-audit.md)
- [TRACE 与隐私审计](ai-trace-privacy-audit.md)

其他专项报告目前分别位于独立工作分支，待对应 PR 集成后再建立主线链接：
- A `work/ai-p0-transcript-rehydration`：`docs/ai-p0-transcript-rehydration.md`
- B `work/ai-redflag-policy`：`docs/ai-redflag-entrypoint-audit.md`、`docs/ai-redflag-preflight-policy.md`
- C `work/ai-retrieval-golden-snapshot`：`docs/classic-retrieval-golden-baseline.md`
- E `work/ai-data-clear-audit`：`docs/ai-data-clear-audit.md`

