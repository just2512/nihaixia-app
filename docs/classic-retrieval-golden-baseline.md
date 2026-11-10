# 经典知识检索黄金基线（待实测锁定）

- 基线代码：`master` @ `60011c4d237cd8d80659038beb6a3a7257228e01`
- 分支：`work/ai-retrieval-golden`
- 当前状态：`PARTIAL`；已记录实现算法和测试入口，尚未执行测试并保存实际命中快照。
- 禁止事项：在真实输出快照完成前，不抽取检索适配器、不更换检索算法、不引入 FTS5。

## 1. 黄金请求

用户输入：

> 查桂枝汤组成，并找《伤寒论》对应条文。

此请求同时验证：
1. 方剂结构化数据是否命中桂枝汤组成；
2. 经典全文索引是否召回《伤寒论》讲稿/相关条目；
3. 来源标识能否反查；
4. 上下文是否清楚区分方剂数据、讲稿与古籍原文；
5. 不得把倪师讲稿冒充仲景原文或虚构条文号。

## 2. 当前实现行为（源码可证）

### 2.1 结构化方剂检索

`AssistantKnowledgeContextBuilder.build()`：
- 方剂名称/别名精确包含匹配；
- 其次匹配关键词；
- 再匹配药味组成；
- 去重后最多保留 `maxFormulaEntries = 4`；
- 方剂结果属于 App 方剂库，不自动等于经典原文出处。

### 2.2 经典全文检索

`AssistantKnowledgeContextBuilder.buildAsync()`：
- 原始 query 加入 `classicQueries`；
- query 中包含某方剂名称时，追加该方剂名称作为独立经典检索 query；
- query 中包含“伤寒论”时追加“伤寒论”；
- 按 query 集合遍历，每次调用 `ClassicSearchService.search()`；
- 按 `source|asset/bookId|chapterIndex|title` 去重；
- 全部经典结果最多收集 4 条，达到上限即停止。

`ClassicSearchService.search()`：
- 对整个 query 做小写化后的字面子串匹配；
- 标题命中优先于正文命中；
- 标题/正文各自保留索引原始遍历顺序；
- 总命中数单独统计，展示最多 40 条；
- 摘要取命中位置前后约 32 字；
- 当前没有模糊分词、BM25 或向量检索。

### 2.3 来源与上下文限制

- `buildWithSourcesAsync()` 从上下文中的“来源标识”收集 source ID，并通过本地索引反查。
- 无法反查的 source ID 不得作为有效引用展示。
- 讲稿、古籍文本资产和方剂数据必须保留不同来源类型。
- 当前上下文上限为 6500 字符；超限时直接按字符截断，可能截断条目边界或来源尾部。

## 3. 当前已有测试

`test/classic_search_test.dart` 已覆盖：
- 空查询；
- “桂枝汤”可命中伤寒讲稿；
- “标幽赋”可命中针灸大成；
- “九针”可命中灵枢；
- 标题命中优先于正文命中；
- 展示上限 40、总数照实统计。

`test/classic_search_backlink_test.dart` 已覆盖：
- 来源 ID 可反查；
- 未知/MISSING ID 不回退模糊检索；
- 同一条目重复检索生成稳定 ID。

`test/assistant_knowledge_context_test.dart` 还需针对本黄金请求补齐完整上下文和来源类型断言。

## 4. 必须由 CI/本地运行生成的实测快照

以下数据目前没有从实际测试运行中取得，均标记 `UNKNOWN`，禁止填入猜测值：

| 字段 | 当前值 |
|---|---|
| 原始 query 的命中数/前 40 条 | `UNKNOWN` |
| “桂枝汤” query 的命中数/前 40 条 | `UNKNOWN` |
| “伤寒论” query 的命中数/前 40 条 | `UNKNOWN` |
| 方剂库桂枝汤条目 ID、组成原文 | `UNKNOWN` |
| 经典结果 source ID、title、source、asset/bookId、chapterIndex | `UNKNOWN` |
| 命中摘要原文 | `UNKNOWN` |
| buildAsync 最终上下文文本 | `UNKNOWN` |
| buildWithSourcesAsync 最终来源 ID/顺序/状态 | `UNKNOWN` |
| 6500 字符截断是否切断条目/来源 | `UNKNOWN` |

实测时必须保存完整结构化快照（JSON），至少包含 query、total、hits 顺序、sourceId、title、sourceLabel、asset/bookId、chapterIndex、snippet、localBacklink，以及最终 context 文本和 sourceIds。测试必须能在同一 commit 重复运行得到相同结果。

## 5. 适配器重构放行条件

只有满足以下条件才允许抽取 Headless Retrieval Capability：

1. 黄金请求和现有三类经典检索测试在基线 commit 上通过。
2. 当前真实快照已经保存并由测试断言。
3. 适配器前后比较 hit 数量、顺序、source ID、来源类型、摘要、上下文片段和引用状态。
4. 任何差异均逐项说明原因，并增加有意变更的独立回归测试。
5. 适配器不得把页面打开、工具名注册或模型口头回答当成检索执行证据。

FTS5 暂缓。只有当黄金集证明当前字面检索存在可复现的漏召回/排序缺陷，并且对照实验验证改进，才可单独立项。
