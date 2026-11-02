# 六经合病规则可达性矩阵

审计基线：`lib/engine/diagnostic_engine.dart`、`lib/engine/diagnostic_rules.dart`、`test/engine/combined_pattern_regression_test.dart`。

本矩阵只描述当前代码的控制流与键匹配，不代表任何临床诊断规则已获经典文献验证。

## 规则表与条件键

| 条件键 | 规则表 | 检测器赋值路径 | 当前可达性 |
|---|---|---|---|
| `sunYangmingBase` | 有 | 未发现赋值 | **UNREACHABLE** |
| `sunShaoyangBase` | 有 | 太阳主证 + 少阳分数达到阈值，且无下利/呕吐子型 | 可达 |
| `shaoyangYangmingBase` | 有 | 未发现赋值 | **UNREACHABLE** |
| `threeYangBase` | 有 | 未发现赋值 | **UNREACHABLE** |
| `taiyinShaoyinBase` | 有 | 太阴主证 + 少阴分数达到阈值 | 可达 |
| `sunYangmingVomit` | 有 | 太阳主证 + 阳明分数达到阈值 + 恶心/呕吐，且未被更早子型截获 | 可达 |
| `sunYangmingChestFull` | 有 | 太阳主证 + 阳明分数达到阈值 + 喘/胸满，且未被更早子型截获 | 可达 |
| `sunShaoyangDiarrhea` | 有 | 太阳主证 + 少阳分数达到阈值 + 下利 | 可达 |
| `sunShaoyangVomit` | 有 | 太阳主证 + 少阳分数达到阈值 + 恶心/呕吐，且无下利 | 可达 |
| `shaoyangYangmingTidalFever` | 有 | 少阳主证 + 阳明分数达到阈值 + 潮热 | 可达 |
| `yangmingShaoyinUrgent` | 有 | 阳明主证 + 少阴分数达到阈值 | 可达 |
| `jueyinShaoyang` | 有 | 厥阴主证 + 少阳分数达到阈值，或少阳主证 + 厥阴分数达到阈值 | 可达；两条方向共用一个键 |
| `sunYangmingUnresolved` | 有 | 太阳主证 + 阳明分数达到阈值 + 有汗且阳明分数低于子型上限 | 可达 |
| `threeYangSleep` | 有 | 太阳主证 + 阳明、少阳分数达阈值 + 但欲寐 + 有汗 | 可达；该专属分支位于两经分支之前 |
| `sunYangmingInteriorHeat` | 有 | 太阳主证 + 阳明分数达到阈值 + 烦躁 + 无汗 | 可达；优先于呕吐、胸满、未解子型 |
| `sunShaoyinTwoCold` | 有 | 太阳主证 + 少阴分数达到阈值，且未先命中太阳阳明分支 | 可达 |
| `shaoyangTaiyin` | 有 | 少阳主证 + 太阴分数达到阈值 | 可达 |
| `sunTaiyin` | 有 | 太阳或太阴主证 + 太阳分数达阈值 + 下利 + 太阴分数达阈值 | 可达；处于分支链末端 |
| `sunYangmingDiarrheaHeat` | 有 | 太阳主证 + 阳明分数达到阈值 + 下利 | 可达；已前置于一般太阳阳明分支 |

## 结果传播路径

| 路径 | 条件键读取 | 最终结果覆盖 | 已有回归覆盖 |
|---|---|---|---|
| 结构化 RuleEngine 命中 | `diagnose()` 重算后调用 `_matchedCombinedPattern()` | 合病表方覆盖规则引擎方；同步 pattern、recommendedFormulas、combinedMeridian、prescription | `sunShaoyangBase` 有测试 |
| 结构化 RuleEngine 未命中，旧杂病兜底命中 | 同上 | 兜底分支读取合病表，覆盖 formula/pattern 并重建处方 | 当前下利热用例覆盖该分支 |
| 结构化 RuleEngine 未命中，旧六经兜底 | 同上 | 旧六经结果末端通过 `formulaOverride` 覆盖合病方 | 需继续补足各分支用例 |
| 早期“辨证依据不足”返回 | 若答案数不足则提前返回 | 不经过后续合病结果组装 | 需要确认合病条件是否可能与该门槛同时成立；不应仅凭条件键已生成就宣称已进入结果 |

## 发现与处理边界

1. **三条死键**：`sunYangmingBase`、`shaoyangYangmingBase`、`threeYangBase` 在规则表中存在，但当前检测器没有任何赋值语句。不得把“规则表存在”误报为“规则可达”。
2. **合病经与合病条件可能脱节**：检测器在部分分支先设置 `_combinedMeridian`，但只有某些子型会设置 `_combinedPatternCondition`。若没有条件键，`_matchedCombinedPattern()` 返回 null，最终结果不会应用合病表方。需要先确定这三条 Base 规则的语义，再决定是否补赋值；不能只为提高覆盖而默认补上。
3. **三阳基础键**：当前代码只实现“但欲寐、目合则汗”的专属条件；缺少睡眠证据时不能自动推断 `threeYangBase`。
4. **同键双向语义**：`jueyinShaoyang` 同时覆盖厥阴主、少阳兼与少阳主、厥阴兼。后续应确认结果描述与主次方向是否需要分别表达。
5. **主路径与兜底路径**：主路径覆盖方剂逻辑已存在；兜底路径也已有覆盖代码，但当前测试只证明了代表场景，不能等同于全部 16 条可达条件均已端到端验证。
6. **临床证据**：本矩阵不验证方剂出处、条文适用条件或临床安全性；这些属于第五阶段的逐条文献核验，不得由代码可达性替代。

## 下一步验收门槛

- 为每个可达条件至少建立一条检测器级输入用例，断言生成的精确键。
- 对结构化主路径与旧兜底路径分别选取代表用例，断言最终 `formula`、`recommendedFormulas`、`prescription.formulaName`、`combinedMeridian` 一致。
- 对三条死键补充明确的 `UNREACHABLE` 测试/注释，直到规则语义得到确认；禁止擅自新增触发条件。
- 对提前返回路径增加门槛测试，确保不出现“检测器命中但最终结果丢失”的静默情况。
