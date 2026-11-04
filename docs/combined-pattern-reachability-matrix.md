# 合病规则可达性矩阵

审计基线：`master`（2026-11-04）。本文件核对代码调用链，不代表经典条文的医学适用性已获验证。

## 判定口径

每条规则分别检查四个环节：

1. **条件产生**：`DiagnosticEngine._detectCombinedPattern()` 是否能把输入证据转换成该条件键。
2. **规则表命中**：`_matchedCombinedPattern()` 是否能按完全相同的 key 命中 `DiagnosticRules.combinedPatterns`。
3. **结构化主路径**：`diagnoseByRules()` 返回有效方剂后，`diagnose()` 是否用合病表方覆盖规则方，并同步推荐方、说明和处方。
4. **旧兜底路径**：结构化规则无命中时，杂病兜底或六经硬编码分支是否仍应用同一合病表方，并同步最终结果。

状态定义：`REACHABLE` = 代码存在完整条件产生与结果映射；`UNREACHABLE` = 没有任何生产代码写入该条件键；`PARTIAL` = 只有部分路径/必要证据存在缺口；`MISSING` = 证据或源码核验不足。这里的 REACHABLE 只表示代码可达，不表示临床规则成立。

## 条件可达性

| 条件键 | 产生条件（摘要） | 规则表 | 主路径 | 旧兜底路径 | 状态 |
|---|---|---|---|---|---|
| `sun_symptoms + yangming_symptoms` | 主经太阳；阳明信号≥3；下利；明确无误下史 | 第32条葛根汤 | 同一合病表覆盖 | 同一合病表覆盖 | REACHABLE |
| `sun+shaoyang_combined` | 主经太阳；少阳信号≥2；未命中更具体的下利/呕吐子型 | 第146条柴胡桂枝汤 | 同一合病表覆盖 | 同一合病表覆盖 | REACHABLE |
| `shao_yang_symptoms + yangming_symptoms` | 主经少阳；阳明信号≥3；下利；明确食积；滑数组合脉 | 第256条大承气汤 | 同一合病表覆盖 | 同一合病表覆盖 | REACHABLE |
| `three_yang_symptoms` | **无生产代码赋值点**；目前只有规则表条目 | 第99条小柴胡汤 | 不可进入 | 不可进入 | UNREACHABLE |
| `taiyin_symptoms + shaoyin_symptoms` | 主经太阴；少阴信号≥3 | 来源标记为临床经验/MISSING | 同一合病表覆盖 | 同一合病表覆盖 | REACHABLE（来源待核） |
| `sun+yangming_vomit` | 主经太阳；阳明信号≥3；无下利；恶心或呕吐 | 第33条葛根加半夏汤 | 同一合病表覆盖 | 同一合病表覆盖 | REACHABLE |
| `sun+yangming_chest_full` | 主经太阳；阳明信号≥3；无下利；喘或胸满 | 第36条麻黄汤 | 同一合病表覆盖 | 同一合病表覆盖 | REACHABLE |
| `sun+shaoyang_diarrhea` | 主经太阳；少阳信号≥2；下利 | 第172条黄芩汤 | 同一合病表覆盖 | 同一合病表覆盖 | REACHABLE |
| `sun+shaoyang_vomit` | 主经太阳；少阳信号≥2；无下利；恶心或呕吐 | 第172条黄芩加半夏生姜汤 | 同一合病表覆盖 | 同一合病表覆盖 | REACHABLE |
| `jueyin+shaoyang` | 主经厥阴且少阳信号≥2，或主经少阳且厥阴信号≥2 | 来源标记为临床经验/MISSING | 同一合病表覆盖 | 同一合病表覆盖 | REACHABLE（来源待核） |
| `sun+yangming_unresolved` | 主经太阳；阳明信号≥3；无下利/呕吐/喘胸满；有汗且阳明信号<5 | 第53条桂枝汤 | 同一合病表覆盖 | 同一合病表覆盖 | REACHABLE |
| `three_yang_sleep` | 主经太阳；阳明与少阳信号各达门槛；但欲寐且有汗 | 第268条；原文未载方剂，表中方剂需独立核验 | 同一合病表覆盖 | 同一合病表覆盖 | REACHABLE（方剂出处待核） |
| `sun+shaoyin_two_cold` | 主经太阳；少阴信号≥3 | 第301条麻黄附子细辛汤 | 同一合病表覆盖 | 同一合病表覆盖 | REACHABLE |
| `shaoyang+taiyin` | 主经少阳；太阴信号≥3 | 第147条；原文未明言太阴合病 | 同一合病表覆盖 | 同一合病表覆盖 | REACHABLE（分类待核） |
| `sun+taiyin` | 主经太阳或太阴；太阳信号≥3；下利、太阴信号≥2；误下、多次攻下、心下痞硬证据齐备；排除第34条特异路径 | 第163条桂枝人参汤 | 同一合病表覆盖 | 同一合病表覆盖 | REACHABLE（分类/前提待核） |

## 调用链核验

- 结构化主路径：`diagnose()` → `_detectCombinedPattern()` → `diagnoseByRules()` → `_matchedCombinedPattern()` → `combinedPattern.formula` 覆盖 `ruleResult.formula`。结果同步 `recommendedFormulas`、`pattern`、`explanation`、`prescription` 和仅对 `isExplicitCombined` 项输出的 `combinedMeridian`。
- 旧兜底路径：结构化规则无有效方剂时，先走 `_diagnoseMiscellaneous()`，再走六经硬编码分支；后续统一读取 `_matchedCombinedPattern()` 覆盖方剂，并在最终 `DiagnosisResult` 同步说明、推荐方、处方和显式合病经。
- 关键边界：表中存在不等于条件可达。当前 `three_yang_symptoms` 只有数据定义，没有条件赋值点，必须保持 UNREACHABLE，不能为追求覆盖率而凭空补一个宽松阈值。
- 证据前置追问：第32/163条误下史、第163条重复攻下及心下痞硬、第256条食积与滑数脉均由 `getRequiredCombinedPatternFollowUpQuestions()` 处理；未知答案不按阴性证据处理。

## 后续处置

1. 已为所有生产代码可达条件建立正向测试，并分别走结构化规则输入和旧兜底输入，检查最终方剂是否来自对应合病表项。
2. `three_yang_symptoms` 暂不增加触发逻辑。先核对第99条原文、倪师解释及适用条件，再决定是否应删除该表项、改为非合病提示，或补充有来源的精确条件。
3. 表中标记“来源待核”的项目不得作为已完成的经典关联；继续按原文、版本、出处、适用条件逐条复核。
4. 本矩阵不验证处方剂量、安全性或临床有效性；不得将代码可达性宣传为医疗验证。

## 本轮变更

- 增加 `test/engine/combined_pattern_reachability_matrix_test.dart`：覆盖全部 14 个有生产赋值点的条件键，分别验证结构化规则输入与旧兜底输入；同时锁定 `three_yang_symptoms` 当前无生产赋值点，避免误将表项存在当成可达。
