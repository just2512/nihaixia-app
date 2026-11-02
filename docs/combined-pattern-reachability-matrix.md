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

## 复核补充：死键并非同一种问题

2026-11-02 对 `_detectCombinedPattern()` 与 `DiagnosticRules.combinedPatterns` 再次逐分支比对，发现三条未赋值基础键的规则意图与当前可达子型并不完全相同：

| 规则键 | 规则表描述/来源 | 检测器当前对应行为 | 结论 |
|---|---|---|---|
| `sunYangmingBase` | 葛根汤；描述“太阳与阳明合病，必自下利”；来源标为《伤寒论》第32条 | 太阳主证且阳明分数达阈值、下利时赋值 `sunYangmingDiarrheaHeat`，不是 Base；无下利时仅在烦躁无汗、呕吐、喘/胸满、有汗未解等子型命中时赋其他键 | Base 键不可达；且基础条目与下利子型存在语义重叠，需文献核对后决定是否保留独立键 |
| `shaoyangYangmingBase` | 大柴胡汤；描述“少阳阳明合病，呕不止，心下急”；来源标为《伤寒论》第103/165条 | 少阳主证且阳明分数达阈值时，只有 `tidal_fever` 为真才赋值 `shaoyangYangmingTidalFever`；没有潮热时只设置 `_combinedMeridian='阳明'`，条件键仍为空 | Base 键不可达；当前代码并未实现表项文字中的“呕不止、心下急”触发条件 |
| `threeYangBase` | 小柴胡汤；描述“三阳并病，必须合解少阳”；来源标为《伤寒论》第99条 | 仅在太阳主证、阳明和少阳分数达阈值，并且但欲寐与有汗同时成立时赋值 `threeYangSleep` | Base 键不可达；现有实现只覆盖三阳合病的但欲眠睡子型，不能推断一般三阳并病 |

### 新发现：检测器设置合并经络但不设置条件键

当前 `_detectCombinedPattern()` 在以下场景会设置 `_combinedMeridian`，但不设置 `_combinedPatternCondition`：

- `primary == '少阳' && yangmingScore >= 3`，但 `tidal_fever != true`；
- `primary == '太阳' && yangmingScore >= 3`，但没有命中下利热、烦躁无汗、呕吐、喘/胸满、有汗未解子型（此分支保留 `_combinedMeridian='阳明'`）；
- `primary == '太阳' && shaoyangScore >= 2` 分支本身总会给基础或子型条件；其它两经分支亦需逐条检查。

这会产生“合并经络已标记、规则表却没有命中”的中间状态。当前最终结果通过 `_matchedCombinedPattern()` 决定是否覆盖方剂与合病描述，因此这类场景不会应用合病表项。此状态不应自动等同于 bug：可能是仅有传变线索而证据不足，也可能是遗漏了应有规则。必须依据条文和产品规则意图决定；在第五阶段文献核验之前，不应自动给它补方剂。

### 结果传播复核边界

`diagnose()` 先重算合病条件，再调用 `diagnoseByRules()`。若规则引擎有方，主路径使用 `_matchedCombinedPattern()` 覆盖方剂与合病描述；若没有方，则进入杂病或六经旧兜底路径。旧兜底路径中：
- 杂病分支单独组装并返回，使用合病表覆盖方剂、pattern 和处方；
- 六经分支在基础证型结果之后应用合病方剂覆盖，但还会运行后续补虚方优先逻辑，需特别测试是否可能覆盖合病方；
- 证据不足提前返回会跳过最终合病结果组装。

因此，“检测器级条件键可达”与“最终结果确实应用规则表”是两种不同验收。必须对每个可达键检查最终路径，尤其检查后续优先规则、证据不足提前返回、处方对象是否与 formula 同步。

### 本轮追加验收项

- [ ] 为少阳主证 + 阳明分数达标 + 无潮热建立测试，明确预期是“传变线索但无合病表命中”还是应补规则；不得无依据补方。
- [ ] 为太阳主证 + 阳明分数达标但未命中子型建立测试，检查 `combinedMeridian` 与 `combinedPatternCondition` 的差异是否在 UI 被误呈现为确诊合病。
- [ ] 对 `sunYangmingDiarrheaHeat` 验证规则表命中和最终处方同步；同时确认它与 `sunYangmingBase` 的条文描述没有重复覆盖。
- [ ] 为主路径、杂病兜底、旧六经兜底各建立最终结果断言；至少断言 `formula`、`recommendedFormulas`、`prescription.formulaName`、`pattern`、`combinedMeridian`。
- [ ] 检查六经兜底中补虚方优先逻辑是否会覆盖已命中的合病方；如会，先确定明确的优先级规则再改代码。

