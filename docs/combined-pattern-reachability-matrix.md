# 合病规则可达性矩阵

基线：`master`（2026-11-04）。本矩阵记录规则条件、问诊输入、主路径与旧兜底路径的代码行为。

## 判定口径

逐条检查：条件是否由问诊输入产生；条件键是否命中唯一规则表项；结构化规则主路径是否正确覆盖最终方剂、推荐方、说明和处方；结构化规则无命中时旧兜底路径是否应用相同结果；必要问项是否被明确回答。

`REACHABLE` 只表示代码路径可达，不代表临床有效。必要问项缺失、未知或冲突时，不形成自动方剂推荐。

## 当前保留的规则表（12项）

| 条件键 | 规则触发条件 | 当前处理 | 主路径 | 旧兜底路径 | 状态 |
|---|---|---|---|---|---|
| `combined.sun_yangming.base` | 太阳与阳明证据并见、下利；误下史必须明确排除 | 葛根汤 | 统一覆盖 | 统一覆盖 | REACHABLE |
| `combined.sun_yangming.clause33_vomit` | 太阳与阳明证据并见、呕吐且明确没有下利 | 葛根加半夏汤；缺少下利状态时先追问，明确无下利后才允许命中 | 统一覆盖 | 统一覆盖 | REACHABLE（含显式阴性门槛） |
| `combined.sun_yangming.clause36_chest_full` | 太阳与阳明证据并见，喘与胸满必须同时成立 | 麻黄汤；仅有喘而胸满状态缺失时追问，不以单项替代合取条件 | 统一覆盖 | 统一覆盖 | REACHABLE（含双条件门槛） |
| `combined.sun_shaoyang.clause172_diarrhea` | 太阳与少阳证据并见、下利 | 黄芩汤 | 统一覆盖 | 统一覆盖 | REACHABLE |
| `combined.sun_shaoyang.clause172_vomit` | 太阳与少阳证据并见、下利且呕吐 | 黄芩加半夏生姜汤；必须同时满足自下利和呕吐，呕吐分支优先于单纯下利方 | 统一覆盖 | 统一覆盖 | REACHABLE（含共同下利前提） |
| `combined.shaoyang_yangming.clause256` | 阳明与少阳证据并见、下利、滑数脉和明确食积表现 | 大承气汤 | 统一覆盖 | 统一覆盖 | REACHABLE |
| `combined.sun_shaoyang.clause146` | 发热微恶寒、支节烦疼、微呕、心下支结、外证未去及病程条件 | 柴胡桂枝汤；逐项追问微呕和病程6—7天 | 统一覆盖 | 统一覆盖 | REACHABLE |
| `combined.shaoyang.clause147` | 已发汗而复下、胸胁满微结、小便不利、渴而不呕、但头汗出、往来寒热、心烦及病程条件 | 柴胡桂枝干姜汤；先核对不呕，再核对误汗复下及病程5—6天 | 统一覆盖 | 统一覆盖 | REACHABLE |
| `combined.sun.clause163` | 太阳病外证未除、反复攻下、下利不止、心下痞硬及表里未解 | 桂枝人参汤；限定太阳病、发热恶寒、误下史、多次攻下、下利、心下痞硬 | 统一覆盖 | 统一覆盖 | REACHABLE |
| `combined.three_yang.clause268_sleep` | 三阳证据并见，需同时确认浮大脉、脉位特征、但欲眠睡及目合则汗 | 仅当浮+大组合脉成立且由专业人员确认“上关上”后显示现有规则证据；未确认/不清楚/缺脉象均不命中，不自动推荐方剂 | 统一覆盖 | 统一覆盖 | REACHABLE（严格脉象门槛、无自动方剂） |
| `combined.taiyin_shaoyin.no_auto_formula` | 太阴与少阴相关线索并见，当前不配置自动方剂推荐 | 暂不自动推荐四逆汤 | 统一覆盖 | 统一覆盖 | REACHABLE（不自动推荐方剂） |
| `combined.jueyin_shaoyang.no_auto_formula` | 厥阴与少阳相关线索并见，当前不配置自动方剂推荐 | 暂不自动推荐乌梅丸 | 统一覆盖 | 统一覆盖 | REACHABLE（不自动推荐方剂） |

## 已移除的历史规则关联

| 历史规则关联 | 规则处理 | 当前行为 |
|---|---|---|
| `combined.three_yang.base` | 旧规则与当前三阳证据条件不一致 | 从合病表删除，不再自动触发 |
| `combined.sun_yangming.unresolved` | 旧规则把并行证据路径与当前合病路径混用 | 从自动规则表删除，不再推荐桂枝汤 |
| `combined.sun_shaoyin.two_cold` | 该条件属于少阴兼表问诊路径，不属于当前合病路径 | 从合病表删除；改由少阴兼表追问路径处理 |

## 调用链

- 结构化主路径：`diagnose()` → `_detectCombinedPattern()` → `diagnoseByRules()` → `_matchedCombinedPattern()` → 覆盖最终方剂与结果字段。
- 分支优先级：第146、147、163条逐项满足既有规则的特异证据先于宽泛太阳阳明、太阳少阳、少阳阳明组合；三项重叠输入均有回归测试，不允许分数分支遮蔽已满足的规则条件。
- 第33条“不下利但呕”中的“不下利”是必要阴性证据：当太阳主经、阳明候选及呕吐证据成立但下利状态缺失时，先询问 `combined_diarrhea_status`；只有明确回答“明确没有下利（第33条）”才命中葛根加半夏汤。回答“有下利”转入第32条相关证据核对；“不确定”不写入阴性值。
- 第172条黄芩加半夏生姜汤沿用同条“太阳与少阳合病自下利”的共同前提；必须同时有下利与呕吐，呕吐分支优先于黄芩汤。太阳少阳呕吐候选缺少下利状态时，通过 `combined_clause172_diarrhea` 追问；只有明确有自下利才命中第172条呕吐方。没有下利或不确定均不得命中。
- 第36条“喘而胸满”按合取条件实现：必须同时确认喘与胸满。太阳阳明候选且未命中下利/呕吐分支时，主动核对喘证；喘证以问诊归一字段 `asthma == true` 判断，不直接比较展示文案。只确认一项时追问另一项（`combined_clause36_dyspnea` / `combined_clause36_chest_fullness`），“没有”或“不确定”均不得命中麻黄汤规则。
- 旧兜底路径：结构化规则无命中 → `_diagnoseMiscellaneous()` 或六经硬编码分支 → 使用同一 `_matchedCombinedPattern()` 结果覆盖最终字段。
- 旧杂病兜底另发现一处布尔优先级错误：小陷胸汤原条件 `hasChestPain && pulse == 浮 || pulse == 滑` 会让单独滑脉越过胸痛门槛；已改为 `hasChestPain && (pulse == 浮 || pulse == 滑)`，新增 `test/engine/diagnostic_engine_test.dart` 正反向回归。该修复是旧兜底安全修正，不改变合病规则表。
- 对 `formula == ''` 的条目：最终 `formula` 为空、`recommendedFormulas` 为空、`prescription` 为空，并设置 `recommendConsult`；不得退回结构化规则或旧兜底方剂。
- 少阴兼表：必须在少阴问诊中明确回答“反发热+脉沉”，且脉象 canonical 值为“沉”，才允许推荐麻黄附子细辛汤；不写入合病经。

## 回归测试

- `test/engine/combined_pattern_reachability_matrix_test.dart`：12项有效条件分别覆盖结构化规则主路径和旧兜底路径，核验最终 `pattern`、`formula`、`recommendedFormulas`、`prescription` 与显式合病经。
- `test/engine/combined_pattern_question_flow_reachability_test.dart`：12项条件从缺少必要前提的快照开始，经适配层实际生成提示、校验答案并逐项推进，最终核验 canonical 条件键、规则表命中和完整诊断结果；不以直接注入最终条件键代替问诊流程。
- `test/engine/combined_pattern_negative_reachability_test.dart`：12项条件逐项构造关键门槛被否定与未知（`null`）的输入，并分别经过结构化主路径和旧兜底路径；不允许在缺失或相反证据下命中对应条件。
- `test/engine/combined_pattern_followup_score_test.dart`：覆盖第172条少阳分值的正向门槛、单独恶心不足阈值，以及明确无下利/未知不得命中呕吐方。
- `test/engine/combined_pattern_negative_reachability_test.dart` 另覆盖第256条：仅滑脉、仅数脉、重复同一脉象、脉象未知均不得命中；滑数/数滑两种主脉与兼脉顺序均可通过组合脉门槛。
- `test/engine/three_yang_clause268_gate_test.dart`：第268条必须先有浮+大组合脉，再确认专业人员记录的“上关上”；未确认、不清楚或缺少浮大组合均不得标记三阳合病。
- `test/tcm_interview_adapter_test.dart`：验证第172条缺少自下利证据时，统一问诊适配层先追问并在明确确认后才命中。
- 上述测试覆盖的是代码条件与结果传播，不代表临床有效性或外部考证已完成。旧杂病兜底的穷举仍需单独补齐。

