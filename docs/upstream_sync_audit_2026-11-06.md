# Upstream 同步审计（2026-11-06）

## 当前分支关系

- Fork：`just2512/nihaixia-app:master`
- Upstream：`jangviktor-web/nihaixia-app:master`
- Compare：Fork ahead **824** commits，behind **29** commits，状态 `diverged`。
- merge-base：`c0f14e77a7fb721fc332576d21fef5f100392d0b`。
- 当前 compare 返回 207 个差异文件；路径重叠不等于文本冲突，也不代表可以直接合并。
- 本记录基于 2026-11-06 读取的 upstream 29 commits；后续 upstream 新提交需重新审计。

## 同步硬约束

1. 不执行 GitHub Sync fork / Update branch，不做 29 commits 整体 merge。
2. 不恢复 `.github/workflows/gitee-sync.yml`、Gitee Release 同步、App 启动时检查上游版本或上游更新公告。
3. 不覆盖 Fork 的问诊引擎、经典来源 manifest、医案数据口径、知识库、AI 对话、Find N2 适配和项目 README。
4. 上游内容可以作为候选证据，但不能因其位于 upstream 或标注“高置信”就当作原典校勘结果。
5. 同步以独立文件或最小代码差异为单位；每次同步后必须有回归测试和 Fork CI。

## 已执行的选择性同步

### PASS — 药材古名错误映射修正

来源 upstream commit：`7b3d9b453f8491522bbdcd78a23a12d30ccf5833`

Fork 已选择性吸收其 `lib/data/herb_repository.dart` 中可独立验证的最小变更：

- 删除错误映射 `雀瓮 → 蝉蜕`。雀瓮为黄刺蛾之茧，药库没有雀瓮/天浆子条目，因此保持未映射。
- 删除错误映射 `姑活 → 冬葵子`。姑活作为失传药名保留，不用现代冬葵子替代。
- 补充药库确有目标条目的古名检索：菥蓂子→析蓂子、庵闾子→奄闾子、高山蓍→蓍实、山羊角→羖羊角、巨胜苗→胡麻。
- 保留 Fork 已有的其他别名与医案药材归一逻辑，没有覆盖整个上游文件。

Fork commits：
- `0edd7f1b5a6fb5e77196b3813e6b68b0adb75188`：修正古名映射。
- `74a58b3b228a6413454ae0d6a957c5b54d58cc70`：增加别名回归测试。

注意：代码变更已提交；该批提交的 CI 仍需最终 PASS，不能仅凭提交记录认定验证完成。

## 29 个 upstream commits 的处理矩阵

| Upstream commit | 主要内容 | 处理结论 |
|---|---|---|
| `7b3d9b45` | 药名归一表纠错 | **SELECTIVE SYNC**：只吸收上述最小映射修正 |
| `b120bc04` | 335 篇《神农本草经》讲稿及双向联动 | **HOLD**：讲稿含临床判断/用药内容；先做内容来源与安全审计，不批量入库 |
| `12ad0ab4` | README 截图和版本折叠排版 | **SKIP**：Fork README 与版本线已分歧 |
| `d1792b24` | Gitee 同步工作流与上传脚本 | **REJECT**：与 Fork 更新隔离要求冲突 |
| `63e4f0e2` | 金匮讲稿 30 篇及版本升级 | **SKIP**：后续 upstream 已撤回，且存在与条文卡内容重叠 |
| `ef17b6d7` | 方剂经典出处预索引、重复方合并、诊断引擎引用调整 | **HOLD**：涉及 Fork 方剂库和辨证引擎，必须逐项比较数据键与规则引用 |
| `066f0baa` | 撤回金匮讲稿 | **SKIP**：撤回记录，不改变 Fork 数据 |
| `1ac79321` | 条文编号撞号修正 | **HOLD**：需与 Fork 当前 clause ID/标准条号 manifest 对照 |
| `688d6b30` | 大规模条文讲解、方剂、药材、医案与索引变更 | **REJECT BULK SYNC**：大范围语料改写，逐项核验前不覆盖 Fork |
| `9be168f7` | 繁体输入搜索与全库异体字规范化 | **HOLD**：Fork 已有自己的检索/繁简处理，不能覆盖 |
| `fe6dcf2f` | OpenCC 繁体显示依赖与版本升级 | **SKIP**：依赖、包体和版本线需单独评估 |
| `e2f86fd9` | 繁体显示抽取为共享服务 | **HOLD**：需检查 Fork 当前详情页与缓存实现 |
| `ed07329e` | 繁体切换按钮共享组件 | **HOLD**：依赖上一项重构，不单独 cherry-pick |
| `65e80314` | upstream release 版本升级 | **SKIP**：不继承 upstream 版本号和发布状态 |
| `00ff0d03` | README 包体积更新 | **SKIP**：Fork 构建产物不同 |
| `a0380f2a` | 839 张条文卡补原文引用 | **HOLD**：原文引用有价值，但必须核对 Fork 当前条文文本与来源，不批量覆盖 |
| `5a2f79a2` | 条文原文补齐分类清单 | **HOLD**：可作候选审计材料，需与 Fork 资产重新对账 |
| `f9f0d059` | 474 个文件统一标点 | **REJECT BULK SYNC**：格式改写范围过大，且可能覆盖 Fork 校订 |
| `6e6374e8` | 条文格式审计报告与脚本 | **HOLD**：需验证脚本对 Fork 当前文件格式的适用性 |
| `7db994f4` | 统一倪师解读标记 | **HOLD**：属于内容标签调整，待与 Fork 标签规范对照 |
| `415279c7` | 伤寒论条号标注检查清单 | **HOLD**：可用于对账，但不是条文来源证明 |
| `516378ee` | 宋本 398 条对照库和全局映射 | **REJECT AS AUTHORITY**：上游使用赵开美本编号口径及微信来源文本；Fork manifest 声明的是 1955 年 398 条编号体系、三芦书屋二次转录，并明确保留底本页码缺失。两套来源不能直接混用 |
| `050635c6` | 宋本标注方案预览和幂等标注工具 | **HOLD**：依赖上游映射表；不能直接在 Fork 条文上运行 |
| `3faa6328` | upstream 内容整备 changelog | **SKIP**：不继承上游版本发布记录 |
| `bc57dce0` | 抵当丸方剂经典关联 | **HOLD**：需检查 Fork 当前 formula ID/别名和原文载方条件 |
| `91c07d0f` | 26 处讲解内原文改引用块 | **HOLD**：需按 Fork 当前资产逐条比较 |
| `ffff7ba4` | 伤寒论条文大规模校订、补录和检索修复 | **HOLD**：属于高价值但高风险语料更新，必须逐条比对原文、版本和 Fork 已有校订 |
| `741afaa6` | 替换伤寒资产为宋本统一版并发布 | **REJECT BULK SYNC**：会改变 Fork 条文 ID/文件结构和现有规则映射 |
| `e29610fd` | 中英繁体 README | **SKIP**：项目说明与发布信息需按 Fork 实际能力单独编写 |

## 已确认的路径冲突

- `.github/workflows/gitee-sync.yml`：Fork 保持删除，上游修改不得恢复。
- `.gitignore`：双方均修改；仅在确认不影响 Fork 本地构建/备份目录后再合并。
- `README.md`：双方均修改；保留 Fork 项目说明，不用上游 README 覆盖。
- 其他路径没有路径级重叠不代表无语义冲突；方剂、经典、药材和规则数据仍需检查 ID、名称、编号与引用关系。

## 伤寒论宋本映射的关键来源差异

上游 `docs/宋本条号对照表.md` 声称以“赵开美本编号体系”398 条为参照，来源标注为微信文章，并用讲义卡首条原文前缀做 Needleman–Wunsch 对齐。其统计为高置信 190、中置信 131、低置信 59、未匹配 35。

Fork 的 `docs/classic-rule-source-manifest.json` 则声明：
- `numberingScheme`：`1955-chongqing-398`；
- 当前在线二次转录：三芦书屋《宋版伤寒论》；
- 声明参校 1991 年刘渡舟主编《伤寒论校注》、1923 年影赵刻宋版及 1955 年《新辑宋本伤寒论》；
- 纸本具体馆藏、卷页、影像定位仍为 `MISSING`。

因此，上游生成的 398 条映射不能直接写入 Fork manifest，也不能将算法相似度标签当作原典校勘结论。它最多是待核对的候选对照表；在来源统一前不用于运行时诊断、方剂关联或条号替换。

### 条文 381 编号修正：路径和编号语义不兼容

upstream commit `1ac79321` 新增/修改的是 `assets/shanghan/clause_380.md`，内容为桂枝去芍药汤及其标准条号说明。Fork 当前没有同路径文件：
- Fork `assets/shanghan/clause_024.md` 是“条文25：桂枝二麻黄一汤”；
- Fork `assets/jingui/clause_380.md` 是肠痈/大黄牡丹汤，不能被 upstream 的同名文件覆盖；
- Fork 的条文卡目录和编号已独立演进，文件名数字不能直接当标准条号。

因此该 commit 不是简单的同文件修补。当前不复制 upstream 的 `clause_380.md`，也不把它写入 Fork 的条文 manifest；后续应先对《人纪》讲稿序号、Fork clause ID、1955 年条号体系建立三方映射，再决定是否补一张独立条文卡。

## 下一轮同步审查顺序

1. 先完成当前 Fork 新提交 CI，确保古名映射修正和 AI 工具结果协议通过。
2. 对 upstream `ef17b6d7` 方剂索引提交逐文件比较：先核验方剂条目 ID、别名和引用，再决定是否吸收索引生成脚本。
3. 对 `a0380f2a` / `ffff7ba4` 的条文补原文和校订做逐条差异清单；只吸收能定位到明确底本/条号的内容。
4. 对医案和药材讲稿保持来源缺失标记；没有稳定来源 ID、版本和定位时不提升状态。
5. 所有数据同步必须增加 Fork 自己的完整性测试；不以 upstream CI 结果替代 Fork CI。


## 2026-11-06 新增 AI 工具参数垂直切片

Fork 新增 `AssistantToolParameter`、`AssistantToolArguments` 和工具定义参数 schema。五运六气支持从用户消息中抽取 ISO 日期（YYYY-MM-DD），经调度决策、工具请求和页面构造一路传入 `YunQiScreen.initialDate`；未提供日期时仍使用当前日期。新增调度参数测试和统一对话到五运六气页面的 widget 回归测试。

该实现只覆盖五运六气日期参数，不代表 23 个工具已经具备统一参数协议。当前 CI 仍在运行，最终验证以最新 HEAD 的 Flutter Quality Gate 与 Flutter tests 为准。
