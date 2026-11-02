# 六经合病规则可达性矩阵

审计基线：`master` @ `3d0b8de1d659a8c799f74a906de0a9bd752c9ab2`  
审计范围：`lib/engine/diagnostic_engine.dart` 的 `_detectCombinedPattern()`、`diagnose()`；`lib/engine/diagnostic_rules.dart` 的 `combinedPatterns`。  
本轮性质：静态控制流审计；未修改诊断规则、处方或问诊输入。

## 1. 判定口径

- **产生**：当前 `_detectCombinedPattern()` 的控制流是否能把该 condition 写入 `_combinedPatternCondition`。
- **表命中**：产生的字符串是否与 `DiagnosticRules.combinedPatterns[].condition` 精确相等。
- **主规则路径**：`diagnose()` 中 `diagnoseByRules()` 返回非空方剂后，是否将合病方剂应用到最终 `DiagnosisResult.formula`。
- **旧兜底路径**：规则引擎未给出方剂、且 `_diagnoseMiscellaneous()` 未提前返回时，是否进入旧六经分支并执行合病表覆盖。
- 本矩阵只判代码可达性，不代表任何证候/方剂适用性的医学确认。

## 2. 逐条条件矩阵

| # | CombinedPattern.condition | 当前产生情况 | 表精确命中 | 主规则命中后应用 | 旧兜底应用 | 结论 |
|---:|---|---|---|---|---|---|
| 1 | `sun_symptoms + yangming_symptoms` | 否 | — | 否 | 否 | 表项没有对应生成键；注释中的“默认葛根汤”不是执行代码 |
| 2 | `sun+shaoyang_combined` | 是，太阳主经且少阳证达到门槛；或少阳主经且太阳残留证据 | 是 | 否 | 有条件 | 规则引擎先命中时被提前返回；旧兜底才可能覆盖 |
| 3 | `shao_yang_symptoms + yangming_symptoms` | 否 | — | 否 | 否 | 表项没有对应生成键 |
| 4 | `three_yang_symptoms` | 否 | — | 否 | 否 | 表项没有对应生成键；现有三阳分支产生的是另一个键 |
| 5 | `taiyin_symptoms + shaoyin_symptoms` | 否 | — | 否 | 否 | 表项没有对应生成键；太阴主经且少阴分数达门槛时只写 combinedMeridian，不写 condition |
| 6 | `sun+yangming_vomit` | 是，太阳主经、阳明分数达门槛且恶心/呕吐 | 是 | 否 | 有条件 | 同主路径提前返回问题 |
| 7 | `sun+yangming_chest_full` | 是，太阳主经、阳明分数达门槛且喘/胸满 | 是 | 否 | 有条件 | 同主路径提前返回问题 |
| 8 | `sun+shaoyang_diarrhea` | 是，太阳主经、少阳分数达门槛且下利 | 是 | 否 | 有条件 | 同主路径提前返回问题 |
| 9 | `sun+shaoyang_vomit` | 是，太阳主经、少阳分数达门槛且恶心/呕吐 | 是 | 否 | 有条件 | 同主路径提前返回问题 |
| 10 | `shaoyang+yangming_tidal_fever` | 是，少阳主经、阳明分数达门槛且潮热 | 是 | 否 | 有条件 | 同主路径提前返回问题 |
| 11 | `yangming+shaoyin_urgent` | 是，阳明主经、少阴分数达门槛 | 是 | 否 | 有条件 | 同主路径提前返回问题；适用条件本身仍需独立医学核验 |
| 12 | `jueyin+shaoyang` | 是，两个相反主经分支均可能写入同一键 | 是 | 否 | 有条件 | 键相同但生成方向相反；需确认是否应统一 meridian 顺序/表达 |
| 13 | `sun+yangming_unresolved` | 是，太阳主经、阳明分数达门槛、有汗且阳明分数低于 5 | 是 | 否 | 有条件 | 同主路径提前返回问题 |
| 14 | `three_yang_sleep` | 否（当前分支不可达） | 是 | 否 | 否 | 太阳+阳明分数≥3 的分支先截获；若阳明分数仅为 2，则太阳+少阳分支先截获 |
| 15 | `sun+yangming_interior_heat` | 是，太阳主经、阳明分数达门槛、烦躁且无汗 | 是 | 否 | 有条件 | 同主路径提前返回问题 |
| 16 | `sun+shaoyin_two_cold` | 是，太阳主经、少阴分数达门槛 | 是 | 否 | 有条件 | 同主路径提前返回问题 |
| 17 | `shaoyang+taiyin` | 是，少阳主经、太阴分数达门槛 | 是 | 否 | 有条件 | 同主路径提前返回问题 |
| 18 | `sun+taiyin` | 是，太阳或太阴主经、太阳证据及下利条件达到门槛 | 是 | 否 | 有条件 | 同主路径提前返回问题 |
| 19 | `sun+yangming_diarrhea_heat` | 否（当前分支不可达） | 是 | 否 | 否 | 与第一个 `primary == 太阳 && yangmingScore >= 3` 分支重叠；该分支不命中后续下利热条件，后续 `else if` 永远没有机会执行 |

## 3. 生成键与规则表集合差

当前生成器写入的 15 个唯一非空键：

- `sun+yangming_interior_heat`
- `sun+yangming_vomit`
- `sun+yangming_chest_full`
- `sun+yangming_unresolved`
- `sun+shaoyin_two_cold`
- `sun+shaoyang_diarrhea`
- `sun+shaoyang_vomit`
- `sun+shaoyang_combined`
- `shaoyang+yangming_tidal_fever`
- `three_yang_sleep`
- `yangming+shaoyin_urgent`
- `jueyin+shaoyang`
- `shaoyang+taiyin`
- `sun+taiyin`
- `sun+yangming_diarrhea_heat`（赋值语句存在，但分支不可达）

集合核对：

- 表中条件：19 个。
- 生成器唯一键：15 个。
- 生成器键在表中找不到：0 个。
- 表中没有生成器对应键：4 个（第 1、3、4、5 项）。
- 生成器键与表项精确匹配：15 个；其中至少 2 个生成分支不可达（第 14、19 项）。

## 4. 最终结果路径审计

### 4.1 RuleEngine 命中路径

`diagnose()` 先调用 `_detectCombinedPattern()`，再调用 `diagnoseByRules()`。当 `ruleResult.formula.isNotEmpty` 时立即构造并返回 `DiagnosisResult`，其中 `formula: ruleResult.formula`。此路径没有读取 `_combinedPatternCondition`，也没有查找 `combinedPatterns`。

**结论：当前 19 个表项无论是否产生、是否命中，在 RuleEngine 命中时都不会影响最终方剂。**

### 4.2 RuleEngine 未命中路径

未命中后进入旧兜底逻辑，但 `_diagnoseMiscellaneous(_answers)` 若返回非空结果，会再次提前返回，仍不应用合病覆盖。

只有同时满足以下条件才会执行合病表覆盖：

1. RuleEngine 没有返回非空方剂；
2. `_diagnoseMiscellaneous()` 返回 null；
3. 旧六经分支成功产生 `result`；
4. `_combinedMeridian` 非空；
5. `_combinedPatternCondition` 与表中 condition 精确相等。

满足后才会将 `formulaOverride` 替换为 `CombinedPattern.formula`，并用于最终结果。

**结论：旧兜底路径也不是无条件可达；它受杂病提前返回、合病键生成和精确表匹配三重限制。**

## 5. 分支遮蔽与状态问题

1. `primary == 太阳 && yangmingScore >= 3` 是第一分支；后面的 `sun+yangming_diarrhea_heat` 要求同样的主经与阳明分数，因此不可达。应把下利热判别纳入该分支内部，并明确它与烦躁无汗、呕吐、喘满、有汗未解等子型的互斥/优先关系。
2. `three_yang_sleep` 分支位于太阳阳明、太阳少阳条件之后，按当前门槛组合无法到达。三阳判别应在两经子型分支之前识别，或重写为明确的优先级决策表。
3. `primary == 太阴 && shaoyinScore >= 3` 只设置 `_combinedMeridian`，没有 condition，导致太阴少阴表项永远不能覆盖。
4. `primary == 少阳 && jueyinScore >= 2` 与 `primary == 厥阴 && shaoyangScore >= 2` 写入同一个 `jueyin+shaoyang`，但方向和证据来源不同；不能仅凭相同字符串推断等价。
5. `_combinedPatternCondition` 在 `reset()` 清空，但 `restoreSnapshot()` 没有恢复该字段。回退快照后若继续诊断，合病条件可能与当前答案状态不一致。需补快照字段或在恢复后可靠重算。

## 6. 修复前必须锁定的行为契约

- 合病条件应先经过单一的、可测试的条件判定器；同一组输入不得因调用顺序不同产生不同条件。
- 先明确多经同时满足时的优先级：三阳整体条件、太阳阳明子型、太阳少阳子型、太阳少阴两感、太阳太阴并病等不能靠当前 `else if` 顺序隐式决定。
- 只有精确匹配且经过证据审查的 CombinedPattern 才可参与最终结果；未知键、缺失证据、冲突未解决时不得自动覆盖。
- 必须分别验证 RuleEngine 命中、RuleEngine 未命中且杂病命中、RuleEngine 未命中且进入旧六经兜底三条路径。
- 最终结果中的 `formula`、`recommendedFormulas`、`pattern`、`combinedMeridian` 必须保持一致，不能只替换处方名而遗留不相符的推荐方或证型文案。
- 修复不应改变六经主经判定，不应添加上游字符串包含匹配，也不应新增未经核验的方剂或剂量建议。

## 7. 下一步

1. 先按第 6 节把合病优先级和最终结果字段契约落实为测试。
2. 再修复 RuleEngine 主路径与旧兜底路径的合病应用缺口。
3. 将条件键改为单一常量/枚举来源，修复三阳和太阳阳明下利热分支遮蔽。
4. 将 `_combinedPatternCondition` 纳入快照或保证恢复时重算。
5. 所有回归测试通过后，再进入脉象、舌象与问诊交叉验证阶段。



---

## 8. 第二阶段修复记录（2026-11-02）

修复基线：`master` 后续提交 `74e6cf3`、`b0d9aac`、`134792b`、`d9dbe83`、`dc3348b`、`fcc3d52`、`6c119e6`。以下为修复后的代码状态，不改变前文作为历史审计基线的含义。

### 8.1 条件键与生成分支

- 19 个表项条件已集中到 `CombinedPatternCondition` 常量，规则表和引擎不再各自维护字符串字面量。
- 当前有生成路径的条件为 16 个，均可与规则表精确匹配。
- 仍保留 3 个“只有表项、没有生成规则”的历史条件：`sun_symptoms + yangming_symptoms`、`shao_yang_symptoms + yangming_symptoms`、`three_yang_symptoms`。本轮没有为它们补造触发条件；需在经典条文证据核验后再决定是否启用。
- `taiyin_symptoms + shaoyin_symptoms` 已在太阴主经且少阴证据达到现有阈值时生成。
- `three_yang_sleep` 提升到两经子型判断之前，要求太阳主经、阳明与少阳分数均达既有阈值，且但欲寐、汗出信号同时存在。
- `sun+yangming_diarrhea_heat` 已前移到一般太阳阳明子型之前，避免被同一主经/阳明阈值分支遮蔽。

### 8.2 最终结果路径

- RuleEngine 命中时，若精确合病条件命中表项，则合病表方剂应用于最终 `formula`、`recommendedFormulas` 和 `prescription`；`pattern`、`patternDetail`、`explanation` 同步使用对应表项描述，`combinedMeridian` 保留合病经。
- 旧六经兜底路径继续按精确键查表；最终方剂的加减规则现在按实际选中的 `formulaOverride` 查询，不再错误地沿用原始兜底方剂的加减规则。
- 三阳合病的 `combinedMeridian` 不再被压缩成单独“阳明”，保留“阳明少阳”组合信息。
- `_combinedPatternCondition` 已纳入 `EngineSnapshot` 的创建和恢复；每次重新检测先清空旧合病状态，避免上一轮条件残留。

### 8.3 回归测试覆盖范围

新增 `test/engine/combined_pattern_regression_test.dart`，覆盖：

1. 19 个规则表键均来自集中常量且没有重复；
2. 合病条件快照保存与恢复；
3. RuleEngine 命中时应用合病表方剂，并同步推荐方、合病经和处方；
4. 旧六经兜底路径中太阳阳明下利热分支的最终方剂覆盖；
5. 三阳“但欲眠睡、目合则汗”分支优先级。

**覆盖边界：** 这组测试验证关键主路径、兜底路径和遮蔽分支，不代表 16 个可生成条件都已拥有独立的端到端病例测试。其余条件仍需在下一轮补齐逐条件测试，并逐条核验医学适用条件；不得把“代码可达”解释成“临床规则已验证”。

### 8.4 CI 追踪

- `Flutter tests` 在提交 `88245b2` 上完整通过，包含 Flutter 静态分析、回归用例和 Android debug APK/ABI 验证。
- 第二阶段代码提交后的最新回归运行仍需以最新 `master` SHA 对应的 Actions 结果为准。
- `Flutter Quality Gate` 曾在全项目静态分析阶段失败，日志显示 80 条既有 info 级诊断，没有 `diagnostic_engine.dart`、`diagnostic_rules.dart` 或新增合病测试文件的 error/warning。该门禁未通过；本轮没有通过关闭静态分析或降低门禁等级来规避。
