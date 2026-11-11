# 经典检索黄金快照复核记录

> 审阅日期：2026-11-11  
> 代码基线：`work/ai-retrieval-golden-snapshot-v2` @ `24d439f823f3414a02b20e1d2cba240f11e46e12`  
> CI：PR #29，run `42922894553`，Flutter regression PASS；Android arm64 APK + Kotlin unit tests PASS  
> Artifact：`ai-retrieval-golden-snapshot`，artifact ID `13811868576`  
> Artifact SHA-256：`51311b321511dcf93603097efc4eea6f0c6eab0af251760d70815968b27be1ea`（ZIP）  
> JSON SHA-256：`d5612a59de89f98775e5e354a1bc4d5b8b51f8df25d289fb49772d118fb6a688`

## 1. 实际执行结果

黄金请求：

`查桂枝汤组成，并找《伤寒论》对应条文`

快照中：

- 方剂实体解析：`桂枝汤`。
- 组成字段：桂枝、芍药、生姜、大枣、炙甘草。
- `AssistantKnowledgeContextBuilder` 最终状态：`RETRIEVED`。
- 上下文长度：3336 字符。
- 上下文来源 ID：9 个（4 方剂库、1 本草库、4 伤寒论讲稿）。
- 经典检索生成 3 个 query，实际结果：

| Query | total | 返回条数 | 来源标签 | locatorStatus |
|---|---:|---:|---|---|
| 原始完整请求 | 0 | 0 | 无 | 无 |
| 桂枝汤 | 196 | 40 | 伤寒论讲稿 | 40/40 MISSING |
| 伤寒论 | 121 | 40 | 伤寒论讲稿 | 40/40 MISSING |

返回上限为每个 query 40 条；表中 total 是检索服务报告的匹配总数，非实际返回条数。

## 2. 已证实的检索与来源问题

### C-01：原始自然语言组合 query 没有直接命中

原始请求 `查桂枝汤组成，并找《伤寒论》对应条文` 返回 0 条。当前命中依赖后续拆分出的 `桂枝汤` 与 `伤寒论` 两个 query。

**含义：** 不能把“原始 query 直接召回”描述为已实现；必须继续核查 query 拆分/派生规则是否保留用户意图。

### C-02：命中结果身份指向讲稿，不等于已核验的仲景原文

两个有效派生 query 的 80 条返回记录均标记来源为 `shanghan`，但来源标签是“伤寒论讲稿”。上下文明确标记“倪师讲稿/整理讲义”，并写明“纸本版本/卷页已核验：NO”。

**含义：** 当前可证实的是 App 内置讲稿索引命中，不是已完成版本校勘的《伤寒论》原文。UI/AI 不得把讲稿来源包装成已核验古籍原文。

### C-03：纸本书目定位缺失，但本地讲稿回链可用

80 条讲稿命中记录的 `locatorStatus` 全为 `MISSING`，`bookId` 与 `chapterIndex` 均为 null；但每条都有 `asset` 与 `localBacklink`，可回链到具体 Markdown 文件。`ClassicHit.locatorStatus` 的实现明确将讲稿资产保持为 `MISSING`，这是书目/纸本定位状态，不代表本地文件链接失效。

**含义：** 本地资产身份和回链可用；缺失的是可核验的书籍/篇章/条文/底本/卷页元数据。引用显示必须区分“本地讲稿文件回链可用”与“古籍版本/卷页已核验”。

### C-04：方剂组成与经典条文的来源链是两类证据

方剂组成来自 App 方剂库 `formula:guizhi_tang`；经典条文候选来自讲稿索引。它们不能合并成一个未经区分的“古籍来源”。

## 3. 尚未验证的项目

- 不能仅凭当前单次快照断言检索排序稳定；需要同一 CI 环境重复执行并比较 JSON。
- 不能仅凭 `total=196/121` 推断召回质量；当前返回上限截断到 40 条，未分析完整集合。
- 尚未验证标题优先/正文匹配对召回排序的全部影响。
- 尚未完成纸本版本/卷页核验；相关字段保持 MISSING。
- 尚未固定 approved expected JSON；本次快照是观测基线，不是正确性判定。

## 4. 下一阶段动作

1. 保留当前 JSON artifact 和哈希作为首次观测证据。
2. 对同一 commit 重复运行黄金测试，比较 query 列表、total、返回 ID 顺序、source、locator、snippet 和上下文文本，先确认可重复性。
3. 逐条检查 40 条截断边界和标题/正文排序实现；只报告可复现问题，不按命中数量扩容。
4. 审计 `ClassicSearchService` 的 `bookId/chapterIndex/locatorStatus` 数据填充来源，确认缺失发生在源数据、索引构建还是映射阶段。
5. 先修来源元数据和显示语义，再讨论 query 变化；不改检索算法、不抽 adapter、不引入 FTS5。
6. 建立有明确来源类别的测试：App 方剂数据、讲稿条目、经版本核验的古籍原文不能互相冒充。

## 5. 当前结论

- **黄金测试运行：PASS**（CI 证明测试可执行并产生 artifact）。
- **当前检索行为正确性：PARTIAL**（已捕获真实输出，但来源定位普遍缺失，原始 query 无命中）。
- **古籍原文来源可信：UNKNOWN / NOT VERIFIED**。
- **检索算法重构许可：NOT GRANTED**（先修来源与元数据缺口，行为基线尚未获批）。
