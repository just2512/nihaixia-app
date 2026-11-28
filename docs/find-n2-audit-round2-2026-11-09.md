# Find N2 增强审计 + 前端实测验收（2026-11-09）

## 背景

上轮远程（并行 CI）在 `1a930d7` 之后合入了大批未经审查的改动（生产代码 64 文件 +8992/-2155 行），包含导航收敛、杂志风主题、SQLite 持久化、紫微命盘专项等。本轮对这些改动做**系统性对抗性审查 + 本地全量测试 + 真机前端实测 + 修复 + 覆盖升级**。

## 审查范围

`git diff 1a930d7..HEAD`，生产代码（lib/ + android/）64 文件，+8992/-2155 行。

## 发现并修复的 Bug

| # | 严重度 | 文件 | 问题 | 修复 |
|---|--------|------|------|------|
| 1 | 高 | lib/screens/home_screen.dart | 未推送提交 303f053（杂志风主题）在收敛导航后误加「工具」tab，违反既有测试契约（知识/工具应是一级入口的断言被反向写成 findsNothing），导致 home_screen_entry_test 失败 | 恢复 AI/工具/知识/收藏/设置 5 并列一级入口，修正测试断言 |
| 2 | 中 | MainActivity.kt (runAiTask) | aiExecutor 在 onDestroy 后 shutdown，任务被拒抛 RejectedExecutionException 且不在 try 内，Dart Future 永久悬挂 | execute 调用包 try，拒绝时回传 LOCAL_AI_SHUTDOWN |
| 3 | 中 | MainActivity.kt (import) | 同上的 import 路径 executor 拒绝悬挂 | 同样回传错误 |
| 4 | 中 | MainActivity.kt (releaseLoadedRuntimeQuietly) | catch Exception 捕获不到 Error（如 UnsatisfiedLinkError），close 抛 Error 覆盖原始完整性错误 | catch Throwable |
| 5 | 中 | classic_search_service.dart | _loading ??= _load() 缓存失败 Future，首载失败后索引永久不可用无法重试 | 失败时清空 _loading 允许重试 |
| 6 | 低 | tcm_interview_conversation_controller.dart | 一处 _completeWithText 用字面 \\n（双反斜杠）而非 \n，该分支 UI 会显示 \n 文字而非换行 | 改为 \n |

## 记录但不修（设计权衡）

- **GPU Engine 初始化失败候选未 close**：LiteRT-LM 文档明确关闭 initialize 失败的 Engine 会抛异常，原代码注释已说明。
- **门禁脚本 check_design_tokens.dart 漏检**：对比 HEAD 机制在改动 commit 后失效；且漏 Color.fromRGBO/Colors.* 变体。属开发工具，不影响运行。
- **模型完整性指纹缓存键弱**（length:lastModified）：需文件替换权限才可绕过，记录为残留风险。
- 原生层 agent 报告的其余低危项（WAV 边界、_snippet 代理对截断、知识上下文 sourceId 提取等）。

## 验证结果

| 项 | 结果 |
|----|------|
| dart analyze | 0 error 0 warning（116 全 info 级 avoid_print） |
| Flutter 全量测试 | 1256 passed / 15 skipped / 0 failed |
| Kotlin compileReleaseKotlin | EXIT 0 |
| Kotlin testDebugUnitTest | 本地因 sqlite3 native assets hook 失败（环境，非代码）；CI 已跑 46 项全绿 |
| Release APK | 57.1MB arm64，SHA-256 `bf52296b7b7be0cf135b118471ec710ffb0496cec4e83cdcd45af6b6ab20b162` |

## 真机前端实测（OPPO Find N2）

| # | 验收项 | 结果 |
|---|--------|------|
| 1 | 覆盖升级安装 | PASS（adb install -r，签名一致 versionCode 8038→8039，数据保留） |
| 2 | App 启动 | PASS（进程存活，MainActivity 前台） |
| 3 | 5 个一级 tab 切换 | PASS（AI/工具/知识/收藏/设置，进程无崩溃无异常） |
| 4 | 无 crash / uncaught exception | PASS（logcat --pid 零 app 异常） |

截图证据：`docs/images/find-n2-test-round2/01-05_*.png`（5 个 tab 外屏态）。

## 未完成项

- 真机「SQLite 持久化跨释放/重启恢复」/「模型加载文字/图像推理」未在本次实测定（模型 3.66GB 已在手机，但本轮重点在导航回归修复；如需可补测）。
- 前端实测因 Flutter 语义树未开 accessibility，uiautomator dump 拿不到文本节点，改用截图 + 进程/logcat 证据。