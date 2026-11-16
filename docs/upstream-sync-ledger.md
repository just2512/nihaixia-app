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

第一批总状态：`PARTIAL`。穴位功能与医案方名异写已合入；经典/本草正文因权利来源证据缺失仍 HOLD。

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


## 7. 2026-11-16 第一批穴位切片执行记录

| 项目 | 记录 |
|---|---|
| 代码分支 | `sync/upstream-acupoint-code-20261116` |
| 代码分支 HEAD | `08c3ed55ba2ada20049b472e26acaaf4eed749be` |
| PR | [#194](https://github.com/just2512/nihaixia-app/pull/194) | 穴位功能 | `MERGED`；CI run `43781702971` Flutter regression 与 Android arm64 均 SUCCESS；Find N2 实机 UNKNOWN |
| 基线 | `09a3a00148aba99eb03d6f7cd99f6791e66ff936` |
| CI | [run 43781702971](https://github.com/just2512/nihaixia-app/actions/runs/43781702971)：Flutter regression 与 Android arm64 APK/单测均 `SUCCESS`；Find N2 实机 `UNKNOWN` |

本切片对应上游 SHA：
- `e7d1edaec63b9cebf3e0d81f6e9f47db703a9ce1`
- `b8146d3a17d4934045770142f3b9faf73e6ca9bd`
- `e9aab33003048d47191b1530c35f5b3188c13f75`
- `cbb72f05a3ed00242319b474c5de7f1bcdefe61b`
- `df410b47eaa32d76680d83536e28b87bef0e9c3f`
- `0fa22644b185b6383114fb12893524a7e353a905`

本仓库实际改动：
- `lib/screens/acupoint_detail_screen.dart`：同经络滑动、切换 State 重建、收藏按钮、古籍章节入口、长属性换行；保留本仓库临床心悟处方公式显示和折叠屏路由。
- `lib/screens/acupuncture_screen.dart`：稀疏字段不再阻止打开详情；保留折叠屏路由。
- `lib/screens/bookmarks_screen.dart`：支持穴位收藏打开详情；收藏图标单独分类。
- `lib/data/acupoint_repository.dart`：只纳入已核对的异体字映射，不移植上游整套全局别名算法。
- `assets/zhenjiu_lecture/acupoint_index.json`：仅更新九个跨经重名/异写穴位条目；上游 72 篇的 seq→asset 清单经核对与本仓库完全一致。
- `tool/import_renji_zhenjiu.py`：增加章节过滤和稳定排序，保留本仓库现有排除词语义；主导入入口标注为会改写全部讲稿。
- `tool/reindex_zhenjiu_index.py`：新增安全重建工具，只读 72 篇现有 Markdown 和 Dart 清单，仅写回 JSON 索引。
- 测试：新增 `test/acupoint_sparse_detail_test.dart`、`test/acupoint_detail_layout_test.dart`、`test/acupoint_index_cross_meridian_test.dart`。

核验状态：
- 文件级对照：已完成；只触及上述 10 个文件。
- 序号映射：72 篇 Dart 清单与 upstream/main 完全一致；九个索引条目的 seq 均指向预期经络章节。
- 自动验收：PR #194 / #195 云端门禁通过；PR #193、#196 各自最新 head 的验收状态见对应 PR Checks。
- Find N2 真机滑动、收藏持久化、古籍跳转、折叠屏分栏：`UNKNOWN`，需要设备实测。
- 未合并，未改变 `master`。



## 8. 2026-11-16 第二批共享逻辑专项复核

本节是只读差异审计及独立小切片记录。不得把上游旧提交直接 cherry-pick 到当前主线；共享文件以当前 fork 的业务行为、AI 能力规范和数据来源约束为准。

### 8.1 辨证引擎与规则

| 上游提交 | 上游变化 | fork 现状 | 决策 |
|---|---|---|---|
| `c241e695b2d63f1096aa4607ed2f1c7100ea336b` | 增加 `answerZhenJia`、`healthyBaselineOk`、寒热真假线索参与真假寒热辨别；并调整十问流程与结果说明 | fork 的 `diagnostic_engine.dart` 已有上述接口与流程；当前 `getSimilarityRanking` 已返回 `List<(String, double)>` | `ALREADY_PRESENT / NO_PORT`。不能按上游版本覆盖；后续如复核，只比较具体规则分支及合病/兼病可达性。 |
| `f938728fe70095498abca60b5baf64058ad3d0f8` | 口语语料参与方剂相似度排序，委托 `FormulaMatcher.rank` | fork 已采用浮点相似度返回类型，但需保留本仓库现有规则和评分输入契约 | `PARTIAL / REVIEW_REQUIRED`。不单独替换诊断引擎；任何语料排序变化须用现有黄金用例验证，不得影响确定性诊断结论。 |
| `be4bf6b31e1630be293443ef12bcc90d927ac111` | 将寒热真假线索表移入 `DiagnosticRules.zhenJiaClueKeys`，新增一页式症状自查入口 | fork 的 `chat_screen.dart` 仍持有局部线索表；fork 不存在 `lib/screens/symptom_check_screen.dart` | `OPTIONAL_REFACTOR / NOT_PORTED`。只提取常量不改变诊断行为；一页式自查是独立交互产品任务，先确认与当前 AI 问诊流程的关系，再实施。 |

硬约束：不得覆盖 fork 的 `diagnostic_engine.dart`、`diagnostic_rules.dart`、`formula_rules.dart`。诊断结论必须仍来自实际规则执行结果；AI 解释与治疗知识讲解遵守现有产品规范。

### 8.2 医案索引与来源

| 上游提交 | 上游变化 | fork 现状 | 决策 |
|---|---|---|---|
| `5574ae07bed13bf3f6cdaefd3fc46764ad1b1fe3` | 医案方名异写索引 | `lib/data/medical_case_data.dart`、`test/medical_case_formula_alias_extract_test.dart` | `ACCEPTED / PASS`，PR #195 已合入；只收录唯一映射方名异写，过滤非方名称号并跳过歧义别名；医案原文、序号和 source ledger 未改；CI run `43782949576` Flutter regression 与 Android arm64 均 SUCCESS |
| `7e02db56686b0e683de9aa19b4135ff10256e167` | 增加穴位名抽取、`diagnosisNorm`、`matchesNormalized`，用于症状→穴位→医案扩展检索 | fork 的 `assistant_knowledge_context.dart` 已存在医案和穴位分开的检索/引用链，医案引用会读取来源账本 | `HOLD / RETRIEVAL_GOLDEN_REQUIRED`。不把新索引字段直接加到 MedicalCase；须先证明它能改善现有 AI 检索黄金集，且每条召回仍携带稳定 sourceId 与来源状态。 |
| `688d6b30fddc31e0683570bb9029ed38f9666755` | 批量简体化医案、删除占位/不可用记录、修改方药和药材映射、调整条目总量 | fork 保留 1256 条实质病例及原始 seq，并增加逐条 `source_ledger.json` 来源状态 | `REJECT_AS_BULK_DATA_SYNC`。不整表覆盖、不重排 seq、不删除病例。任何内容纠错或删例必须逐条审计原文、身份、来源、引用、AI 检索影响和回归。 |

### 8.3 SQLite / 数据库迁移

| 上游提交 | 上游变化 | fork 现状 | 决策 |
|---|---|---|---|
| `47d7e5b11f9e4d67428866ff84f2cc57fc4a7d01` | 旧问倪师 AI 对话表 `llm_sessions/llm_turns`，数据库 version 5→6 | fork 数据库 version 7，已有 `assistant_conversations`、`assistant_messages`、`tcm_interview_tasks` 等 AI 现代化表和事务/生命周期实现 | `REJECT_OLD_SCHEMA`。禁止将上游 v6 migration 覆盖到 fork v7；保留当前会话持久化、数据清除与恢复行为。 |
| `6260574ee566cdb759452c0256306a0b8066003c` | 引入 Web SQLite 条件工厂 | fork DB helper 与平台文件/AI 数据边界已有差异；上游实现未覆盖 fork 的 v7 AI 表 | `HOLD / PLATFORM_SCOPE_REVIEW`。仅在明确需要浏览器持久化数据库时，单独核对 Web 工厂、资产、测试和数据隔离；不得与 Android 数据库迁移合并。 |

### 8.4 共享页面与启动链路

| 上游提交 | 上游变化 | 决策 |
|---|---|---|
| `2d228f67268ab006b846c173489cd56930fef5b2`、`1318bd960e4d25575ead3ee19c1a9bc8473aeb25` | Home/Chat 宽屏侧边导航、PageBody、选项 chip 换行及编译修正 | `HOLD / RESPONSIVE_SCOPE`。可作为 Web 桌面端独立候选；不得替换 fork 当前 Find N2 折叠屏路由和 AI 页面状态。 |
| `7e02db56686b0e683de9aa19b4135ff10256e167`、`47d7e5b11f9e4d67428866ff84f2cc57fc4a7d01` | 上游旧「问倪师AI」端点设置、单独会话持久化与清除入口 | `REJECT_AS_OLD_AI_IMPLEMENTATION`。不得替换本仓库 AI orchestrator、Tool Router、TRACE、会话表和数据清除边界。 |
| 上游 `main.dart` 并行加载提交 `f72869e397fa5d1cad54c28f27dfbbfee92a5be0` | 将八个仓库的串行启动改为 `Future.wait` | `HOLD / LOAD_DEPENDENCY_CHECK`。先逐个确认 Repository.load 无共享状态依赖、初始化顺序和失败降级语义，再决定是否独立移植。 |

### 8.5 PR 与当前验收状态

| PR | 工作范围 | 状态 |
|---|---|---|
| [#193](https://github.com/just2512/nihaixia-app/pull/193) | 同步台账 | Draft / OPEN；仅一个文档文件，当前 head 与 Checks 以 PR 页面为准 |
| [#194](https://github.com/just2512/nihaixia-app/pull/194) | 穴位 UI、讲稿索引与安全重建工具 | MERGED；CI run `43781702971` Flutter regression 与 Android arm64 均 SUCCESS；实机 UNKNOWN |
| [#195](https://github.com/just2512/nihaixia-app/pull/195) | 医案唯一方名异写抽取 | MERGED；CI run `43782949576` Flutter regression 与 Android arm64 均 SUCCESS |

以上 PR 均从 fork 当前 master 的 `09a3a00148aba99eb03d6f7cd99f6791e66ff936` 单独派生，不把台账分支或未验收代码合入 master。PR/CI 的最终结论以对应 head SHA 的实际检查为准。


## 10. 第一批经典与本草资产来源核验（2026-11-16）

### 10.1 共同祖先之后新增的上游经典资料

按共同祖先与 `upstream/main` 文件树比对，新增文件集中为：

| 目录 | 新增文件 | 内容核验 | 决策 |
|---|---:|---|---|
| `assets/jingui/` | 2 | `clause_453.md`、`clause_454.md` 均包含经典原文，同时含「倪海厦解读」现代讲解段落 | `HOLD / PROVENANCE_REQUIRED` |
| `assets/shanghan/` | 16 | `clause_380.md`—`clause_390.md`、4 篇六经附录及 `176_board.jpg`；条文页含现代课程讲解 | `HOLD / PROVENANCE_REQUIRED` |
| `assets/neijing/` | 0 个新路径 | 有既有文件变化，需要按条文范围核对，不等同于新增原文 | `REVIEW_REQUIRED` |

本轮抽查的金匮/伤寒文件同时包含古典原文和「倪海厦解读」内容；后者属于现代讲课整理，不因古典原文本身属于公版作品，就自动成为可自由复制的文本。因此暂不整文件复制。后续可在确认版本和来源后，仅引入已核验的公版原文部分；现代讲稿、板书图片和整理注释须另有权利依据。

### 10.2 本草讲稿库

上游新增 `assets/bencao_lecture/` 共 336 个文件（335 篇讲稿正文及配套索引/资源）。上游 `docs/bencao_ingestion_plan.md` 记录的源输入是本地文件 `D:/nhx/人纪-神农本草经-倪海厦.txt`，约 59.6 万字，内容为授课实录整理；该计划在上游文档中标记为 `SHELVED`。

当前没有从仓库文件中取得足以核实该讲稿整理文本复制、再发布和二次改编权限的授权材料。仓库根目录许可证不能证明第三方课程文本的权利人已授权。因此：

- `assets/bencao_lecture/**` 正文：`HOLD / RIGHTS_EVIDENCE_MISSING`；
- `bencao_lecture_data.dart`、`bencao_lecture_index.dart`、`bencao_library_screen.dart` 和药材反向联动：`HOLD / DEPENDS_ON_CORPUS`；
- 不导入孤立索引或空入口，避免产生悬空资产引用；
- 可先独立核验已有 `assets/data/herbs.json` 药材结构，但不重复导入或覆盖现有药库。

本轮用户明确提出重新评估/吸收经典与本草资料；故上述 HOLD 是权利证据门槛，不是永久关闭该工作。取得书面授权、明确可再发布许可，或确定只使用公版原文并完成文本比对后，重新打开这两个工作域。

### 10.3 第一批当前交付边界

- 针灸穴位功能：PR #194 已合入 master；Flutter regression 与 Android arm64 CI 均 PASS；Find N2 真机验收 UNKNOWN。
- 金匮/伤寒新增讲稿和附录：HOLD，未复制。
- 本草 335 篇讲稿正文及阅读入口：HOLD，未复制。
- 上游 `docs/web/**` 和发版生成文件：REJECT，不复制。

### 10.4 最新 CI / PR 证据更新

| PR | 最新证据 | 当前状态 |
|---|---|---|
| #194 穴位切片 | Run `43781702971`：Flutter regression SUCCESS；Android arm64 APK/单测 SUCCESS；branch validation SKIPPED | `PASS`（云端）；Find N2 实机仍 `UNKNOWN` |
| #195 医案别名 | head `99c6832f523750f7b616f4304885bb9f08b425d9`；Run `43782949576` Flutter regression 与 Android arm64 均 SUCCESS | `MERGED / PASS`（云端） |
| #193 同步台账 | 最新 head 与 Checks 以 PR 页面为准；已重放到 master `31ed1c7a`，仅台账文件 | `DRAFT / IN_PROGRESS` |



## 11. 经典/本草内容对应的上游提交 SHA 补录

| 内容 | 上游提交 SHA | 说明 |
|---|---|---|
| 金匮新增/讲解条文 | `688d6b30fddc31e0683570bb9029ed38f9666755` | 包含 `clause_453.md`、`clause_454.md` 的条文卡讲解更新 |
| 金匮条文原文引用块 | `a0380f2afd7531e084c61a6db2e758499aab8560` | 为条文卡补原文引用块；现代讲解仍需独立来源核验 |
| 伤寒补录条文 | `ffff7ba46d8906473ac2084736e68dc1c6fd0efb` | 补录条文 380—390 等内容，现代讲稿文本不能整批复制 |
| 伤寒宋本统一与附录/排版 | `741afaa685c4307afb78dd116eefcab067a1d711` | 涉及 `clause_380.md`、`clause_390.md` 和四篇六经附录；需同时复核版本及讲解来源 |
| 伤寒条文编号修订 | `1ac793216168031ca0bd204783d64c4535299fa6` | 条文 381 编号/标准条号修订 |
| 伤寒原文标点统一 | `f9f0d05991e5a0c15934afce6710d33365163d2e` | 全库标点格式调整 |
| 本草 335 篇讲稿库 | `b120bc04cd6894ac329c94d05401d2c5cb2fd085` | 新增本草讲稿正文、索引和药材双向联动 |

上述 SHA 仅建立可追踪来源，不构成采纳许可或内容正确性证明。当前经典/本草文件仍按第 10 节状态处理。


## 12. 2026-11-16 CI 增量复核

| PR | 当前 head | CI 运行 | 结果 | 解释 |
|---|---|---|---|---|
| #194 穴位功能 | `08c3ed55ba2ada20049b472e26acaaf4eed749be` | [43781702971](https://github.com/just2512/nihaixia-app/actions/runs/43781702971) | Flutter regression SUCCESS；Android arm64 APK/单测 SUCCESS；branch validation SKIPPED | MERGED；Find N2 实机 UNKNOWN |
| #195 医案方名异写 | `99c6832f523750f7b616f4304885bb9f08b425d9` | [43782949576](https://github.com/just2512/nihaixia-app/actions/runs/43782949576) | Flutter regression SUCCESS；Android arm64 APK/单测 SUCCESS；branch validation SKIPPED | MERGED |
| #193 上游同步台账 | 当前 PR 文档 head（以页面元数据为准） | [43785885645](https://github.com/just2512/nihaixia-app/actions/runs/43785885645) | Flutter regression IN_PROGRESS；branch validation SKIPPED | Draft，等待检查完成 |

PR #194 与 PR #195 的云端门禁均已通过并合入；Find N2 真机项仍保留 UNKNOWN。PR #193 只包含同步台账文档，等待最新 head CI。


## 13. 合并与重放基线更新（2026-11-16）

| 项目 | 新状态 | 证据 |
|---|---|---|
| 集成主线 | `master` 已从 `09a3a00148aba99eb03d6f7cd99f6791e66ff936` 前进到 `31ed1c7a16e5ebe2b7a355dd76b915d9f3ba764a` | PR #194、#195 已分别 squash merge |
| PR #194 | `MERGED` | [合并提交 `5a9c0271`](https://github.com/just2512/nihaixia-app/commit/5a9c027150f89f730e1c4d9614fcae7f3e7862ac)；Flutter regression 与 Android arm64 APK/单测均 `SUCCESS`；真机仍 `UNKNOWN` |
| PR #195 | `MERGED` | [合并提交 `31ed1c7a`](https://github.com/just2512/nihaixia-app/commit/31ed1c7a16e5ebe2b7a355dd76b915d9f3ba764a)；run `43782949576` Flutter regression 与 Android arm64 均 `SUCCESS` |
| PR #193 | `DRAFT / OPEN` | 已重放到最新 master `31ed1c7a`；只包含 `docs/upstream-sync-ledger.md`；最新 head / Checks 以 PR 元数据为准 |

### #195 最终 CI 记录

PR #195 最新 head `99c6832f523750f7b616f4304885bb9f08b425d9` 的 run `43782949576`：Flutter regression 与 Android arm64 均 `SUCCESS`；已 squash 合入 master，合并提交 `31ed1c7a16e5ebe2b7a355dd76b915d9f3ba764a`。

PR #195 已完成合入，当前 master 已前进至 `31ed1c7a16e5ebe2b7a355dd76b915d9f3ba764a`。

### 重放规则

PR #195 曾以 `5a9c0271` 为父提交独立重放、验收后合入；PR #193 已重新以最新 master `31ed1c7a` 为唯一父提交重放，只保留台账一个文件。
- #195：`lib/data/medical_case_data.dart`、`test/medical_case_formula_alias_extract_test.dart`
- #193：`docs/upstream-sync-ledger.md`

没有把 #193 台账或 #195 医案代码混入 #194 穴位功能提交；本次重放也没有更改已验收代码内容。


## 14. 2026-11-16 第二轮复核：AI 结果真实性门禁

### 14.1 当前主线与唯一上游源
- 当前集成基线：`master @ 31ed1c7a16e5ebe2b7a355dd76b915d9f3ba764a`。
- 当前唯一上游源：`jangviktor-web/nihaixia-app:main @ 4c66bd3af3c45523033ebcb68e1afba45f429351`。
- 本轮未发现 upstream/main 有新的 HEAD 变化；不做整仓合并或盲目同步。
- PR #194（穴位）与 PR #195（医案方名异写）均已完成独立小批量集成；各自 CI 证据见第 12 节。

### 14.2 复核发现与代码切片
- 发现 `AssistantToolResult.validateFor()` 允许 `status=SUCCEEDED` 且 `sourceIds=[]`；结构化字段存在并不证明结果经过 App 业务执行或能追溯来源。
- 发现旧式 Page Tool String 回传被包装成 SUCCEEDED，并被赋予 `local-page-tool:<toolId>`；页面路由身份不是业务执行来源。
- 发现未验证的 UNKNOWN 旧文本在后续轮次及历史恢复时可能被重新放进模型 transcript。
- 独立分支 `work/assistant-verified-tool-results-20261116` / PR [#196](https://github.com/just2512/nihaixia-app/pull/196) 只改：
  - `lib/models/assistant_tool_result.dart`
  - `lib/screens/local_ai_interview_screen.dart`
  - `test/assistant_tool_result_test.dart`
  - `test/assistant_tool_result_handoff_test.dart`
  - `docs/assistant-tool-capability-audit.md`
- 当前 PR head：`d7373e36e6c1fb7e071d982b51b3b5ef8f6ff7a5`；GitHub Actions run [43785779751](https://github.com/just2512/nihaixia-app/actions/runs/43785779751) 正在运行，验收状态保持 `IN_PROGRESS`，不得预先记 PASS。

### 14.3 结果真实性边界
- SUCCEEDED 必须带真实业务来源标识；空 sourceIds 的 success 被拒绝，`local-page-tool:` 页面路由标识被拒绝作为来源。
- 未结构化的 legacy String 页面回传降为 UNKNOWN；仍可在用户时间线查看，但不触发 AI 解读，不写入当前模型 transcript。
- 历史恢复时，旧记录若状态 UNKNOWN 或来源包含 `local-page-tool:`，仍可见，但不回放给模型。
- 本地 deterministic executors 的成功结果继续由各自 App executor 提供 `local-engine:`、`local-data:`、`local-rule:` 等真实标识；缺少来源不能通过通用占位标识绕过。
- 没有修改 `DiagnosticEngine`、`DiagnosticRules`、`TcmInterviewConversationController`、排盘/历法/五运六气/剂量/方剂计算；没有修改 AI Orchestrator、ToolRouter、KnowledgeContextBuilder、数据库 schema 或更新机制。

### 14.4 当前待办
1. 等待 PR #196 最新 head 的 Flutter regression 与 Android arm64 CI；只在二者通过后合并。
2. PR #193 台账文档分支重放到当前 master 后，核实最新 head 和文档 CI，再合并。
3. 金匮/伤寒现代讲稿、本草 335 篇讲稿仍保持来源/权利证据 HOLD；未获得授权证据前不复制。
4. Find N2 实机滑动/折叠屏/本地 E4B 多轮与工具端恢复测试仍为设备侧 UNKNOWN；CI 不替代实机证据。


## 15. 2026-11-16 当前状态与第二轮验收
- PR #194：MERGED；Flutter regression 与 Android arm64 均 PASS；Find N2 实机操作仍 UNKNOWN。
- PR #195：MERGED；Flutter regression 与 Android arm64 均 PASS；未修改医案原文、序号或来源台账。
- PR #196：Draft / OPEN；head `d7373e36e6c1fb7e071d982b51b3b5ef8f6ff7a5`；CI run [43785779751](https://github.com/just2512/nihaixia-app/actions/runs/43785779751) 仍在运行；未合并。
- PR #193：Draft / OPEN；已以 master `31ed1c7a` 为父提交重放，只包含同步台账文档；CI/Checks 以 PR 页面最新 head 为准，避免将台账自身的旧 head 或旧 run 写成当前状态。
- 经典/本草现代讲稿仍保持权利来源 HOLD；不以技术合并替代授权证明。

## 16. 2026-11-16 最终收口记录（本节为当前状态权威）

> 前文 §§1、12—15 保留各阶段快照与审计轨迹；若其中 master SHA、PR 状态或 CI 状态与本节不同，以本节和 GitHub 当前 PR/Actions 元数据为准。

### 16.1 当前同步基线

| 项目 | 当前值 |
|---|---|
| 集成分支 | just2512/nihaixia-app:master |
| 当前 master HEAD（本节写入时） | 2a9929fa30c2c3a9728c08f7645825addf4a90e7 |
| 唯一上游同步源 | jangviktor-web/nihaixia-app:main |
| upstream/main HEAD（本节写入时） | 4c66bd3af3c45523033ebcb68e1afba45f429351 |
| 上游 HEAD 是否发生新变化 | 本轮重新核对未发现变化；不需要重跑整仓差异审计 |

### 16.2 已合入 master 的小批量切片

| PR | 合并提交 | 内容范围 | 云端验收 |
|---|---|---|---|
| #194 | 5a9c027150f89f730e1c4d9614fcae7f3e7862ac | 穴位滑动、收藏、稀疏详情、长属性换行、古籍入口、跨经索引消歧 | run 43781702971 Flutter regression + Android arm64 APK/单测均 SUCCESS |
| #195 | 31ed1c7a16e5ebe2b7a355dd76b915d9f3ba764a | 医案方名唯一异写归一；跳过非方名与歧义别名 | run 43782949576 Flutter regression + Android arm64 APK/单测均 SUCCESS |
| #196 | 2ab2d9e68d125feb8b0d0ef1b35aef6cc1e97afe | 业务结果来源/参数真实性门禁；UNKNOWN 和旧 Page String 不进入模型事实上下文 | run 43787526563 Flutter regression + Android arm64 均 SUCCESS；run 43787521411 静态分析、changed tests 和 pairing SUCCESS |
| #197 | 2a9929fa30c2c3a9728c08f7645825addf4a90e7 | 玉匣灵兆本机时辰查询接入助手对话 Headless 执行；特殊观察占法保留原页面 | run 43790380338 Flutter regression + Android arm64 构建/单测均 SUCCESS；run 43790378186 静态分析、changed tests 和 pairing SUCCESS |

PR #197 的结果边界：
- 当前时辰查询使用 App 本机 DateTime.now() 和现有 kYuXiaJiShiChenOmens 本地数据，返回实际时间、UTC 偏移、时辰、对应条文和 sourceId local-data:yuxiaji-omen。
- “鸦鸣鹊噪方向”“占灯花法”需要用户实际观察；助手不会将其误作当前时辰查询，也不会让 AI 猜测来向或灯芯形态。
- 对话解释明确限定为民俗文本释义，不是科学预测或医学诊断；不得从面热、眼跳、耳鸣、心惊、肉颤等文本推断疾病、病因或健康风险。
- 新工具复用原页面的时辰纯函数，不新增第二套算法、Agent/DAG、ToolRouter、数据库表或诊断规则。

### 16.3 AI / App 业务边界复核结论

当前产品规范、能力审计、执行台账和代码链一致遵守以下原则：

1. **AI 是交互与理解中枢，不是业务规则和计算引擎。** AI 识别意图、提取参数、判断缺项、追问、选择 App 已有能力，并解释经过校验的结果。
2. **App 执行确定性业务。** 排盘、规则问诊、时辰/历法、剂量换算等仍由 App 原有引擎或受控本地 executor 执行；不允许模型自行计算、覆盖或伪造结果。
3. **仅已执行且校验的真实结果进入 AI 事实上下文。** 结果必须为 SUCCEEDED，具有结构化 values、实际参数（若该工具有参数）和可追溯 sourceIds，并通过 validateFor() / validateArgumentsMatch()。FAILED、CANCELLED、NO_RESULT、UNKNOWN 或仅页面路由标识不得作为事实交给模型。
4. **医学诊断必须有双重依据。** 诊断结论来自 App 确定性规则实际执行；每条医学判断还必须有本地知识库可追溯 sourceId 支持。知识库无证据时标记 MISSING，不由模型记忆或推断补成诊断。
5. **同一助手对话完成闭环。** 用户提出需求后由 AI 识别和追问，App 后台执行现有能力，校验通过后在当前对话解释结果；只有确需用户提供方向、形态等现场观察的功能，才进入原页面完成输入。

当前助手能力注册表：
- 18 个 Headless deterministic/data executors；
- 5 个 Page-only 浏览入口（古籍、知识库、医案、诊断历史、重症资料）；
- 1 个 Inline deterministic structured diagnosis workflow。
- Page-only 浏览入口不是待补齐的“后台计算器”，不为增加 Headless 数量而改写。
- 问诊助手、工具助手、学习助手、玄学大师共用现有对话、知识检索和结果解释边界；命理/民俗结果只支持文化释义，不可升级为医学诊断。

### 16.4 保护项核验

- 本轮没有修改 DiagnosticEngine、DiagnosticRules、FormulaRules、问诊规则/题目、排盘引擎、剂量计算算法或数据库 schema。
- 保留 docs/product-positioning-and-boundaries.md、docs/ai-capability-audit.md、docs/ai-modernization-execution-ledger.md 和并行执行协议。
- 没有恢复上游自动更新提示、启动检查、自动下载或 Gitee 同步；手动更新机制未被覆盖。
- 没有将上游 Pages bundle、Release 版本/下载链接、签名配置或构建产物带入主线。

### 16.5 尚未关闭的真实阻塞

| 项目 | 状态 | 关闭条件 |
|---|---|---|
| 金匮/伤寒新增条文与附录 | HOLD / PROVENANCE_REQUIRED | 分离核验公版古籍原文与现代讲课解释，明确版本、出处和文本准确性后，再以原文最小切片导入 |
| 本草 335 篇讲稿与阅读入口 | HOLD / RIGHTS_EVIDENCE_MISSING | 取得可再发布的书面授权/许可，或改为只使用经核对的公版原文；未满足前不复制讲稿正文或导入悬空索引 |
| OPPO Find N2 实机验收 | UNKNOWN | 用户设备实测同经络滑动、收藏持久化、古籍跳转、内外屏/半折叠布局 |
| Native E4B 实机多轮 | UNKNOWN | Find N2 实测多轮、取消、重建/恢复、强制停止重启与 TRACE；云端 CI 不替代设备证据 |

以上属于资料权利或真实设备证据门槛，不得用通过云端 Flutter/Android CI 代替，也不得为了标记完成而降低验收标准。

### 16.6 当前 PR #193

PR #193 仅新增本文件；本节落到当前 master 2a9929fa 后，分支必须以该 SHA 为唯一父提交重放，compare 应为 ahead 1 / behind 0。台账 PR 的 CI 只验文档变更，不替代上表四条代码 PR 的验收证据。
