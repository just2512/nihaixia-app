# 经典条文与医案来源审计（第一轮）

审计范围：
- `DiagnosticRules.combinedPatterns` 当前 19 条规则；
- `assets/shanghan/clause_*.md` 的文件编号与正文编号；
- `assets/medical_cases/cases_table.md` 的案例来源字段与条数一致性。

审计基线：
- 在线对照文本：维基文库《伤寒论》（页面标注汉张仲景著、宋林亿等校、明赵开美校刻）。
- 页面自身声明“校订不足”，并说明不同卷章校订状态不一。因此本轮只用于核对条文语义，不把该网页单独视为最终版本校勘依据。
- 参考地址：https://zh.wikisource.org/zh-hans/傷寒論
- 本地倪师讲课转录和讲解属于二级/讲授材料，不得伪装成仲景原文。

状态定义：
- `TEXT_AND_FORMULA_MATCH`：原文症状与方剂均可直接对应。
- `TEXT_MATCH_CLASSIFICATION_MISMATCH`：条文或方剂存在，但当前“合病/并病/脏腑”分类与原文不一致。
- `FORMULA_MATCH_CONTEXT_MISSING`：方剂能对应，但当前触发条件缺少原文中的关键前提。
- `FORMULA_NOT_IN_CLAUSE`：条文有病证描述，但原文没有指定当前表项方剂。
- `MISSING`：没有可追溯的原文或版本信息。
- `REVIEW_REQUIRED`：需要进一步核对底本、异文或讲授来源。

## 一、当前 19 条合病表项核对

| 当前条件键 | 当前表项方剂 / 来源 | 原文核对 | 审计结论 |
|---|---|---|---|
| `sunYangmingBase` | 葛根汤；《伤寒论》第32条 | 原文“太阳与阳明合病者，必自下利，葛根汤主之”语义、方剂均对应 | `TEXT_AND_FORMULA_MATCH`；检测器当前未赋值，必须补可达路径和最终结果测试 |
| `sunShaoyangBase` | 柴胡桂枝汤；第146条 | 第146条为伤寒六七日、发热微恶寒、支节烦疼、微呕、心下支结、外证未去，柴胡桂枝汤主之；原文没有直接称“太阳少阳合病” | `TEXT_MATCH_CLASSIFICATION_MISMATCH`；保留方证关联，不能将原文标成明确合病 |
| `shaoyangYangmingBase` | 大柴胡汤；第103/165条 | 第103相关文字为太阳病过经、柴胡证仍在、呕不止、心下急等；第165条为伤寒发热汗出不解、心中痞硬、呕吐而下利；两处均非原文明确的“少阳阳明合病” | `TEXT_MATCH_CLASSIFICATION_MISMATCH`；另有第256条明确“阳明少阳合病，必下利……脉滑而数……宜大承气汤”，当前表项漏掉了更直接的合病条文 |
| `threeYangBase` | 小柴胡汤；第99条 | 第99条对应身热恶风、颈项强、胁下满、手足温而渴，小柴胡汤主之；“三阳并病、必须合解少阳”属于讲授解释，不是该段原文直述 | `REVIEW_REQUIRED`；必须把原文与倪师解释分开标注 |
| `taiyinShaoyinBase` | 四逆汤；临床经验 | 没有条文、篇名、版本或具体医案定位 | `MISSING` |
| `sunYangmingVomit` | 葛根加半夏汤；第33条 | 原文“太阳与阳明合病，不下利，但呕者，葛根加半夏汤主之”对应 | `TEXT_AND_FORMULA_MATCH` |
| `sunYangmingChestFull` | 麻黄汤；第36条 | 原文“太阳与阳明合病，喘而胸满者，不可下，宜麻黄汤”对应 | `TEXT_AND_FORMULA_MATCH` |
| `sunShaoyangDiarrhea` | 黄芩汤；第172条 | 原文“太阳与少阳合病，自下利者，与黄芩汤”对应 | `TEXT_AND_FORMULA_MATCH` |
| `sunShaoyangVomit` | 黄芩加半夏生姜汤；第172条 | 同条“若呕者，黄芩加半夏生姜汤主之”对应 | `TEXT_AND_FORMULA_MATCH` |
| `shaoyangYangmingTidalFever` | 柴胡加芒硝汤；当前标第104条 | 原文有伤寒十三日不解、胸胁满而呕、日晡潮热、微利，先小柴胡解外、后柴胡加芒硝汤；但未直接称“少阳阳明合病” | `TEXT_MATCH_CLASSIFICATION_MISMATCH`；不能作为明确合病表项 |
| `yangmingShaoyinUrgent` | 大承气汤；第320条 | 原文是“少阴病，得之二三日，口燥咽干者，急下之，宜大承气汤”；没有“阳明少阴合病”字样 | `TEXT_MATCH_CLASSIFICATION_MISMATCH`；应作为少阴急下条文关联，不应伪装成合病 |
| `jueyinShaoyang` | 乌梅丸；临床经验 | 未提供可追溯经典条文或医案编号 | `MISSING` |
| `sunYangmingUnresolved` | 桂枝汤；第53条 | 对应段落明言“二阳并病”，太阳证未罢不可下、可小发汗；“并病”与“合病”不可互换 | `TEXT_MATCH_CLASSIFICATION_MISMATCH` |
| `threeYangSleep` | 小柴胡汤；第268条 | 第268条明确“三阳合病，脉浮大，上关上，但欲眠睡，目合则汗”；该条原文未直接给出小柴胡汤 | `FORMULA_NOT_IN_CLAUSE`；需把方剂解释来源单独注明 |
| `sunYangmingInteriorHeat` | 大青龙汤；第38条 | 大青龙汤对应太阳中风、脉浮紧、发热恶寒、身疼痛、不汗出而烦躁等；该段没有太阳阳明合病 | `TEXT_MATCH_CLASSIFICATION_MISMATCH` |
| `sunShaoyinTwoCold` | 麻黄附子细辛汤；第301条 | 原文为“少阴病，始得之，反发热，脉沉者，麻黄细辛附子汤主之”；是少阴病兼表，不是原文明确的太阳少阴合病 | `TEXT_MATCH_CLASSIFICATION_MISMATCH` |
| `shaoyangTaiyin` | 柴胡桂枝干姜汤；第147条 | 原文为伤寒五六日、已发汗而复下之、胸胁满微结、小便不利、渴而不呕、但头汗出、往来寒热、心烦；未明确称少阳太阴合病 | `TEXT_MATCH_CLASSIFICATION_MISMATCH` |
| `sunTaiyin` | 桂枝人参汤；第163条 | 原文为太阳病外证未除而数下之、协热而利、利下不止、心下痞硬、表里不解；不是原文明确的太阳太阴合病 | `TEXT_MATCH_CLASSIFICATION_MISMATCH` |
| `sunYangmingDiarrheaHeat` | 葛根黄芩黄连汤；第34条 | 原文前提为太阳病桂枝证、医反下之、利遂不止、脉促、表未解、喘而汗出；并非“太阳阳明合病、下利臭秽” | `FORMULA_MATCH_CONTEXT_MISSING`；当前检测器只看太阳/阳明分数、便秘与下利，缺失误下史、脉促、喘汗出等关键条件，存在错误触发风险 |

### 新发现：第256条存在漏项

《伤寒论》阳明篇第256条原文为“阳明少阳合病，必下利，其脉不负者，为顺也……脉滑而数者，有宿食也，当下之，宜大承气汤”。这是当前表项中最直接的“阳明少阳合病”原文依据。

后续应新增独立条件键，不得把它继续混入当前“大柴胡汤/第103或165条”表项。触发条件至少要核验阳明、少阳线索、下利、滑数脉与宿食证据；缺少滑数脉或宿食线索时不得直接套用该条。

## 二、原文与讲授解释必须拆开

以下概念不能混作同一个来源字段：
- 仲景原文：仅记录可逐字定位的条文。
- 版本校勘：记录底本、校注者、异文和条文编号体系。
- 倪师讲授：独立记录讲座/课程、讲授日期或章节、转录版本。
- 后世注家：记录注家姓名、著作、卷次和对应注文。
- App 规则解释：记录本项目如何把原文转成检测条件，必须标注这是工程映射，不是原文。

特别是“并病”不能被改写成“合病”；原文未指定方剂时，不能把讲授或后世解释写成仲景原方。

## 三、本地经典文件编号审计

抽查发现 `assets/shanghan/clause_*.md` 的文件名数字不能直接当作仲景条文号：

| 本地文件 | 正文标题 |
|---|---|
| `clause_032.md` | 条文43 |
| `clause_033.md` | 条文99 |
| `clause_034.md` | 条文109 |
| `clause_036.md` | 条文34 |
| `clause_038.md` | 条文34续二 |
| `clause_053.md` | 条文48 |
| `clause_099.md` | 条文94 |
| `clause_103.md` | 条文98-99 |
| `clause_104.md` | 条文100 |
| `clause_146.md` | 条文153 |
| `clause_147.md` | 条文154 |
| `clause_163.md` | 条文173 |
| `clause_268.md` | 条文288 |
| `clause_301.md` | 条文329 |
| `clause_320.md` | 条文351 |

因此，禁止用 `clause_<条文号>.md` 直接拼接来源。必须先建立显式 manifest，将内部文件 ID 与书名、篇章、真实条文号、讲授章节、文本类型分别对应；未完成 manifest 前，本地文件关联状态为 `MISSING`。

## 四、医案数据来源审计

`assets/medical_cases/cases_table.md` 当前存在以下问题：

1. 文件头声明“总案例数 1257”。
2. 来源统计 45 + 942 + 13 + 78 + 12 + 93 + 154 = 1337，与文件头相差 80。
3. 案例表格没有稳定的原始案例 ID、来源文件路径、原始文档 URL、页码/段落、采集版本或逐案出处。
4. 案例中部分诊断、病因、疗效及讲授评论被压缩在同一行，无法判断哪些是原始病历、讲者判断、整理者摘要或后期补充。
5. 当前没有可复核证据将某个案例与某条经典原文建立一对一关联。

当前所有医案—经典条文关联状态均为 `MISSING`。禁止根据症状相似度自动把案例挂到某条经典；必须回到原始案例文件，逐案确认病例来源、日期、诊断原文、方剂、随访结果及讲授出处。

## 五、后续数据结构要求

经典条文引用至少包含：
- `referenceId`、`workTitle`、`chapterTitle`、`articleNumber`；
- `edition`、`editor`、`volume/page`（有则必填）；
- `originalText`、`variantText`、`sourceUrl`、`localAssetPath`；
- `textVerificationStatus`、`formulaVerificationStatus`、`classificationStatus`；
- `commentaryReferences[]`，与原文分离。

医案引用至少包含：
- `caseId`、`sourceCollection`、`sourceDocument`、`sourceLocator`；
- `caseDate`、`recordedDiagnosis`、`recordedFormula`、`recordedOutcome`；
- `transcriptionVersion`、`reviewStatus`；
- `classicReferences[]`，每条关联需有人工核验说明，不能由模型自动确立。

## 六、当前处置

- 原文明确且方剂对应的条文可以保留文本引用，但仍需补版本和本地 manifest。
- 分类错误的条目先标记 `MISMATCH`，不得继续以“明确合病”向用户展示。
- 缺少方剂原文依据的条目标记 `FORMULA_NOT_IN_CLAUSE`，补齐独立注释来源前不得把方剂归于仲景原文。
- 葛根黄芩黄连汤规则在补齐误下史、脉促、喘汗出等条件前必须关闭当前宽泛触发路径。
- 第256条阳明少阳合病另建规则，不与第103/165条大柴胡汤证混合。
- 医案来源不完整时展示 `MISSING`，不生成自动经典关联。

本轮只完成来源审计和错误定位；后续按上述数据结构逐条修正规则、UI 引用和案例关联。未经复核的原文、版本、页码或医案来源不得补造。

## 2026-11-02 实施回写：合病表已按首轮原文核验修正

本节覆盖上文“当前 19 条合病表项核对”所描述的旧代码状态。首轮审计后，以下代码调整已提交：

1. `sunYangmingBase` 不再保持死键：太阳主证、阳明分数达阈值、下利，并且用户明确回答没有医误下史时，才命中第32条葛根汤。误下史为 true 或未知时不触发。
2. `shaoyangYangmingBase` 不再指向第103/165条大柴胡汤，改为第256条阳明少阳合病，方剂为大承气汤；检测器要求少阳主证、阳明分数达阈值、下利，并且两项 canonical 脉象分别为“滑”和“数”。
3. `shaoyangYangmingTidalFever` 已从合病规则表和检测器移除。潮热与柴胡加芒硝汤的条文关联保留在本审计文档中，但不再伪装成明确少阳阳明合病。
4. `sunYangmingDiarrheaHeat` 已从合病规则表和检测器移除。第34条葛根黄芩黄连汤不得仅凭太阳/阳明分数与下利触发。
5. 当前规则表中 `sunYangmingBase` 与 `shaoyangYangmingBase` 已可达；`threeYangBase` 仍无赋值路径。当前检测器矩阵回归用例覆盖 16 条可达条件键，并对最终 formula、recommendedFormulas、pattern、prescription.formulaName 和 combinedMeridian 做断言。

注意：第32条使用“明确无误下史”作为排除第34条误下协热利的工程闸，是保守的问诊条件，不是原文新增条款。第256条以“下利 + 滑数脉”识别原文所述宿食线索；当前仍需在 UI 明示该条文适用条件，不得把单一滑脉或数脉当成完整证据。

本次修正尚未完成以下工作：
- 将“合病、并病、兼证、单经证”在数据模型和 UI 中分开显示。当前部分旧规则虽有来源分类问题，仍保留在旧规则表中，后续需继续迁移。
- 给每个经典引用补齐可校验的底本、版本、校注者、卷次/页码和本地资产 manifest。
- 为医案逐案补充稳定 caseId、原始文件/页码/日期、转录版本，并人工建立经典条文关联。
- 将 `cases_table.md` 的 1257 与来源统计合计 1337 的差异核清。

所以本节记录的是两条错误合病规则的修复，不代表第五阶段已经完成。

