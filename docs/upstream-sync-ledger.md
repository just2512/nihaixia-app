# 上游同步执行台账

> 本文件约束 `just2512/nihaixia-app` 对原始仓库的增量吸收。同步源固定为
> `jangviktor-web/nihaixia-app:main`；禁止将上游分支整仓合并到本仓库。
> 状态只表示本台账所列范围，不得从源码存在、上游 CI 通过或提交说明推定本仓库验收通过。

## 1. 本轮固定基线

| 项目 | 值 |
|---|---|
| 本仓库集成分支 | `master` |
| 本仓库基线 HEAD | `09a3a00148aba99eb03d6f7cd99f6791e66ff936` |
| 唯一上游源 | `jangviktor-web/nihaixia-app` |
| 上游分支 | `main`（上游默认分支；不再使用其旧 `master`） |
| 上游基线 HEAD | `4c66bd3af3c45523033ebcb68e1afba45f429351` |
| 共同祖先 | `c0f14e77a7fb721fc332576d21fef5f100392d0b` |
| 核验日期 | 2026-11-16 |

本轮 Compare API 核验：本仓库相对上游 main 领先 1242、落后 632 个提交。基于共同祖先的文件树比较：上游单方面变化 3064 个文件、本仓库单方面变化 330 个文件、双方均修改 40 个路径；其中 37 个路径的双方最终内容不同，另有 3 个路径是本仓库删除而上游仍修改。文件树统计包含 Web 构建输出等生成文件，不能直接当作应同步的源码数量。

## 2. 不可覆盖的本仓库边界

以下内容是同步硬约束：

1. 保持本仓库 `master` 为唯一集成基线；功能切片从最新 `master` 或已合入的同步基线派生独立分支，经 PR、小批量验收后集成。
2. 保留本仓库产品规范、AI 能力审计、AI 执行台账和并行工作协议。任何上游内容不得降低这些规范的要求。
3. 保留本仓库 AI 现代化实现：问诊控制器、确定性诊断规则、Headless Capability、AI 对真实业务结果的解释、知识来源 ID、TRACE、Find N2 适配和现有数据清理边界。共享文件必须手工语义合并。
4. 不恢复上游自动更新提示/下载链路。当前本仓库已删除 `lib/services/update_service.dart` 和 `test/update_download_sources_test.dart`；不得重新引入启动时检查上游 Release、弹窗或自动下载。
5. 不恢复上游 `.github/workflows/gitee-sync.yml`，除非另有明确的镜像同步决策。
6. 不复制上游 `docs/web/**`、Pages bundle、缓存、打包产物或版本发布文件。源码和资源整合完成后，使用本仓库自己的构建命令生成 Pages。
7. 不直接继承上游 `pubspec.yaml` 的版本号、README 下载地址、Release Notes、APK 或签名配置。发布版本由本仓库单独管理；升级兼容必须验证 applicationId、签名证书、versionCode 和旧库迁移。
8. 不以提交说明代替核验。数据文件要校验条目数、主键、引用、来源及原文；生成索引需证明输入、排序、映射与幂等性。

权威约束文件：
- `docs/product-positioning-and-boundaries.md`
- `docs/ai-capability-audit.md`
- `docs/ai-modernization-execution-ledger.md`
- `docs/ai-parallel-execution-protocol.md`

## 3. 第一批：经典资料、本草资料、穴位功能

### 3.1 本草讲稿库

| 上游提交 | 文件范围 | 决策 | 原因 / 验收条件 |
|---|---|---|---|
| `b120bc04cd6894ac329c94d05401d2c5cb2fd085` | `assets/bencao_lecture/**`（提交说明称 335 篇） | `HOLD / MISSING_PROVENANCE` | 上游有 335 篇《人纪·神农本草经》讲稿整理内容，但仓库根目录 Apache-2.0 声明不足以单独证明第三方讲稿/转录文本的著作权授权链。暂不复制整批正文。先核对权利来源、授权/许可范围、版本来源和内容审核责任；通过后再同步正文、索引、阅读入口及药材双向链接。 |
| `b120bc04cd6894ac329c94d05401d2c5cb2fd085` | 本草讲稿数据结构、阅读入口、索引及相关工具（以 `main` 文件树为准） | `REVIEW_REQUIRED` | 只有确认正文授权后才整体接入；避免把指向未导入资产的阅读入口或索引单独合入。还需检查 `herbs.json` 主名/别名口径、讲稿序号连续性和反向引用。 |

备注：上游 `docs/bencao_ingestion_plan.md` 记录过 SHELVED 状态和本地原始讲稿来源描述。该文件是上游项目记录，不自动构成本仓库的授权证明或产品决策。

### 3.2 针灸穴位功能

| 上游提交 | 文件范围 | 决策 | 验收条件 |
|---|---|---|---|
| `e7d1edaec63b9cebf3e0d81f6e9f47db703a9ce1` | `lib/screens/acupoint_detail_screen.dart`、`test/acupoint_sparse_detail_test.dart` | `ACCEPT_CANDIDATE` | 移植同经络左右滑动及 State 更新逻辑；合并本仓库现有 AI/页面改造；验证边界不循环、纵向滚动不被抢占、同位置换穴时标题与内容同步。 |
| `b8146d3a17d4934045770142f3b9faf73e6ca9bd` | `lib/screens/acupoint_detail_screen.dart`、`lib/screens/bookmarks_screen.dart` | `ACCEPT_CANDIDATE` | 复用既有 bookmarks 表，不新增收藏表；核对收藏类型/路由跳转及已有药材、方剂收藏不回归。 |
| `e9aab33003048d47191b1530c35f5b3188c13f75` | `lib/screens/acupuncture_screen.dart`、`test/acupoint_sparse_detail_test.dart` | `ACCEPT_CANDIDATE` | 字段稀疏穴位仍可打开详情；验证原有列表筛选、详情入口及异常降级。 |
| `cbb72f05a3ed00242319b474c5de7f1bcdefe61b` | `lib/screens/acupoint_detail_screen.dart`、`test/acupoint_detail_layout_test.dart` | `ACCEPT_CANDIDATE` | 属性文字改为可换行容器；保留现有主题样式；运行 320dp/大字号几何回归。 |
| `df410b47eaa32d76680d83536e28b87bef0e9c3f` | `assets/zhenjiu_lecture/acupoint_index.json`、`tool/import_renji_zhenjiu.py`、`tool/reindex_zhenjiu_index.py` | `ACCEPT_CANDIDATE` | 先核对输入讲稿未变化；复算 9 个跨经重名穴过滤规则；验证篇目归属、索引键及重建幂等性。不得运行会重写全部讲稿正文的旧导入器。 |
| `0fa22644b185b6383114fb12893524a7e353a905` | `lib/data/acupoint_repository.dart` | `ACCEPT_CANDIDATE` | 只评估 `跗阳/附阳`、`譩譆/譩嘻` 异体字映射；与本仓库别名表合并，确认正反向解析一致，不覆盖其他别名规则。 |

以下上游提交不随 UI 功能一并引入：

| 上游提交 | 文件范围 | 决策 | 原因 |
|---|---|---|---|
| `97498712911264054d20d23537b5df4bb21a688d` | `assets/data/acupoints.json` | `HOLD / DOMAIN_REVIEW` | 该提交批量改写 401 条临床心悟格式并清理内容。它不只是 UI 格式修复，涉及医学文本的删改、字段归属和含义；必须按条目审查差异及来源，不能整文件覆盖。 |
| `16487d0a61fd14e878d44097b5f4a72bb418f295` | `CHANGELOG.md`、三语 README、`RELEASE_NOTES.md`、`pubspec.yaml`、`release_notes/**`、`docs/web/**` 等 | `REJECT_AS_RELEASE_BUNDLE` | 上游发版信息、下载链接、版本号、Screenshots 和 Web 构建产物不属于本仓库发布，不直接同步。可单独吸收经验证的源代码修复，不能照搬整个 release commit。 |

第一批总状态：`IN_PROGRESS`。以上 `ACCEPT_CANDIDATE` 不是已合入或已验收；必须在本仓库独立分支完成语义合并和自动测试后才能改为 `PASS`。

## 4. 第二批：共享逻辑专项复核

| 文件/领域 | 当前状态 | 处理要求 |
|---|---|---|
| `lib/engine/diagnostic_engine.dart`、`diagnostic_rules.dart` | `NOT_STARTED` | 对照规则差异，检查 canonical keys、分支遮蔽、合病/兼病可达性、脉舌问诊映射及回归；禁止整文件覆盖。 |
| `lib/data/medical_case_data.dart`、`database_helper.dart`、医案资产 | `NOT_STARTED` | 检查 schema、迁移、旧库保留、来源 ledger、主键和引用完整性；先做只读差异盘点，再做最小迁移。 |
| `lib/screens/chat_screen.dart`、`main.dart`、首页/设置/知识库共享页面 | `NOT_STARTED` | 保护本仓库 AI 调度、模式边界、Headless 工具、TRACE、折叠屏布局和更新机制；按函数/调用链移植。 |
| `pubspec.yaml`、`android/app/build.gradle.kts`、CI | `NOT_STARTED` | 逐项比较依赖、SDK、签名、ABI 和 workflow；不继承上游版本号，不引入上游 release/update 工作流。 |

## 5. 验收证据和状态定义

统一采用：`NOT_STARTED / IN_PROGRESS / PASS / PARTIAL / FAIL / BLOCKED / UNKNOWN`。

每个完成条目必须记录：
- 上游 commit SHA 与上游文件路径；
- 本仓库工作分支、base SHA、head SHA；
- 实际变更文件和语义合并说明；
- 测试名称/命令、真实结果、CI workflow 与 run ID；
- 数据迁移/索引检查结果；
- 未完成项、风险、回滚方式。

未运行的测试记为 `UNKNOWN`；只有局部通过记为 `PARTIAL`；上游提交自身的测试结论不得直接记作本仓库 PASS。涉及 Find N2、APK 覆盖安装和签名的项目必须等待本地设备证据。

## 6. 本轮下一步

1. 完成本草讲稿正文的权利来源与内容来源核验；未核验前不复制 335 篇正文。
2. 单独移植针灸穴位 UI/索引修复，不带入 `assets/data/acupoints.json` 的批量临床文本改写。
3. 经典文本资产按书种/条目记录来源和差异，再决定是否导入；禁止复制 `docs/web/**`。
4. 建立第二批只读差异报告后，分别处理诊断引擎、医案数据库和共享页面。
