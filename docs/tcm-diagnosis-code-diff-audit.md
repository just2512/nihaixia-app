# 辨证系统代码级差异审计（App master 对照上游规则库）

审计日期：2026-11-02  
审计范围：当前 master 的 diagnostic_engine.dart、diagnostic_rules.dart、formula_rules.dart、rule_engine.dart；对照 Wsy-prog/tcm-diagnosis-system 的 index.html。  
边界：本轮只审计与记录，不改诊断算法、方剂规则、问诊选项或患者数据。

## 一、代码基线与结构

| 文件 | 当前结构 | 主要职责 |
|---|---|---|
| diagnostic_engine.dart | 约 5,502 行 | 问诊状态、答案归一、六经定向、脉舌冲突、合病计算、诊断结果组装 |
| diagnostic_rules.dart | 约 1,753 行 | 十问选项、六经与跟进规则、脉舌数据、合病表、鉴别表 |
| formula_rules.dart | 约 1,469 行；172 条规则项、171 个不同方名 | 结构化必选/参考信号、扩展症状与鉴别链 |
| rule_engine.dart | 独立规则执行器 | 必选门禁、参考命中、候选排序、并列消歧 |

上游 index.html 约 3,981 行，主要逻辑集中在 collectSignals、matchFormulas、matchHebing、matchPulseTongue、matchSiniTrio 和 analyze。

## 二、四类差异清单

### A. 新增：可考虑补充，但必须保持边界

1. **脏腑独立证据分析（核心新增方向）**
   - 上游 collectSignals 将六经之外的标签汇总到 zangfuScore；当前 App 三个目标文件没有对应的脏腑证据集合或独立分析层。
   - 上游标签并不纯粹是脏腑：肝、肺、心、脾、肾之外，还混入血、气、阴虚等概念；不能把 zangfuScore 整体复制为脏腑结果。
   - 可新增独立的“脏腑相关证据”视图/数据结构：每条证据保留问项 key、选项 canonical 值、原始答案、正向依据、反向/不一致依据、资料来源及来源状态；区分脏腑、气血津液、病性等类别。
   - 首版只展示证据及缺失状态，不产生脏腑主诊断、不排序、不打分、不输出方剂剂量、不改变六经结果。未回答、正常、不适用、未知必须分开保存。
   - 该能力的关键不是移植上游标签，而是建立 App 自己可追溯、可解释、可撤销的证据层。

2. **脉象、舌象与问诊的交叉验证**
   - App 已有脉象、舌苔、舌形输入，已有脉舌矛盾提示、组合脉象、真寒假热/真热假寒、传变预警。
   - 值得补的是“证据交叉验证记录”：脉象支持什么、舌象支持什么、问诊支持什么、哪些冲突尚未解决；不应简单规定“以舌为准”。
   - 增加输入值标准化与组合检测后，才能可靠对照上游脉舌表。

3. **六经合病/并病覆盖**
   - App 已有 19 条 CombinedPattern，覆盖太阳-阳明、太阳-少阳、少阳-阳明、三阳、太阳-少阴、少阳-太阴、太阳-太阴等组合。
   - 上游 HEBING_TABLE 有 11 个条目。其价值主要是提供不同组合的症状描述和边界对照，不是直接扩充数量。
   - 应先修复规则调用链、条件键和遮蔽问题，再评估真正缺少的组合。

4. **经典条文与医案证据关联**
   - App CombinedPattern 有 source 字符串，但 formula_rules.dart 的 FormulaRule 主要只有 differential 描述，没有统一的经典篇名、条文原文、版本和医案出处字段。
   - 可新增证据关联元数据：source type、书名/篇名/条文、原文、版本、医案出处、适用条件、编辑校验状态。
   - “条文号字符串”不等于已完成原文核验；医案也不能直接当作规则有效性证明。

### B. 重复：App 已有，不应重复建设

1. 六经主证、六经问项和六经跟进：App DiagnosticRules 与上游 DIAG_FORMULAS 的六经提纲、类型描述存在大量语义重合。
2. 脉象基础分类：双方都有浮、浮缓、浮紧、洪/大、弦、微细等分类；App 另有迟、数、滑、涩、紧、弱、结、代等输入。
3. 舌象分类：双方均覆盖薄白、白厚、黄燥/黄厚、舌淡、舌红、紫暗等方向；表达粒度不同，不能按字符串直接拼接。
4. 真寒假热/真热假寒：双方已有独立线索或规则。上游八维描述可作为来源审查对象，不构成 App 需要整体新增的模块。
5. 合病并病：App 19 条条件表和引擎分支已存在；上游 11 条表不能简单视为 App 缺失。
6. 方剂匹配：App FormulaRule 已采用 required、reference、extRequired、extReference 的结构化门禁；上游 DIAG_FORMULAS 使用 ifs 文本包含命中。两者不是同一实现，不能把上游文本命中逻辑当作升级。

### C. 冲突：必须先修复/澄清，不能叠加新规则

1. **主诊断路径绕过合病覆盖**
   - diagnose() 先执行 _detectCombinedPattern()，随后调用 diagnoseByRules()。
   - 当 RuleEngine 命中方剂时，diagnose() 的主路径立即返回 ruleResult.formula。
   - _combinedPatternCondition 对应 CombinedPattern 的 formulaOverride 逻辑位于后续旧硬编码兜底路径。
   - 结果：主规则路径命中时，精确合病条件虽然被计算，却没有应用到最终方剂。需以测试确认具体病例路径；当前代码结构已构成明确的调用链缺口。

2. **合病条件键不一致**
   - CombinedPattern 中存在 sun_symptoms + yangming_symptoms、shao_yang_symptoms + yangming_symptoms、three_yang_symptoms、taiyin_symptoms + shaoyin_symptoms 等条件键。
   - _detectCombinedPattern 使用的是 sun+yangming_*、shaoyang+yangming_tidal_fever、three_yang_sleep 等键。
   - 前述几项没有看到对应赋值路径；需统一条件常量或明确删除不可达规则，不能保留“表中存在但引擎不产生”的假覆盖。

3. **合病分支遮蔽**
   - _detectCombinedPattern 中 primary == 太阳 且 yangmingScore >= 3 的分支先于后面的 sun+yangming_diarrhea_heat 条件。
   - 后面的条件要求同样的 primary 与 yangmingScore 门槛，因此在该分支链中不可达。
   - primary == 太阳 且 yangmingScore >= 3 时，较早分支也可能先行截获本应进一步判断的三阳组合。需要用条件决策表和回归用例明确优先级。

4. **脉象组合检测并非真正的双脉组合验证**
   - App PulseCombination 数据有 pulse1/pulse2，但 _detectPulseCombination 只拿单一 _pulseType 与 pulse1 比较，匹配后直接返回；没有同时验证 pulse2。
   - 当前问诊输入是单一脉象值，不能据此宣称识别了“浮紧”“沉细”等组合脉。
   - 应将单脉提示与双脉组合识别区分；没有两个独立输入或明确的组合选项时，不应触发组合结论。

5. **脉舌冲突处理采用固定优先级**
   - App _detectPulseTongueContradiction 对数脉+淡舌、迟脉+红舌、浮脉+厚苔等直接提示“以舌为准”或指定真假寒热方向。
   - 这不是完整交叉验证；部分组合只凭两项输入就推断真假寒热，缺少胸腹、口渴、二便、脉力等条件。
   - 需要改为“冲突待核验 + 追问缺失证据”，不能让单一舌象覆盖脉象或问诊。

6. **输入术语标准化不一致**
   - 上游 ADV_QUESTIONS 将脉值存为“浮、浮缓、浮紧、大、弦、微细、数、结代”；PULSE_TABLE 的名称却包括“大/洪大”“微细/沉”等复合字符串。
   - matchPulseTongue 使用精确相等查表，存在输入值与表项无法精确命中的风险。
   - App 也有独立 qOptions 与 pulseOptions 两套脉象输入路径；需明确 canonical code 与显示文本，避免同义词漏匹配。

7. **脏腑概念混类**
   - 上游 collectSignals 把所有非六经 meridians 键都放入 zangfuScore，因此血、气、阴虚等也被计入。
   - 上游 analyze 在没有六经命中时，将最高 zangfuScore 标签作为 primary 兜底。这会把线索标签提升为主证，必须拒绝移植。

8. **方剂规则存在重复**
   - App allFormulaRules 有 172 条规则项、171 个不同方名；猪苓汤重复出现。
   - 需要确认重复项是有意的不同证型，还是规则重复；不能直接删除其中一条，应先比较 required/reference/ext 条件及鉴别链。

### D. 不应引入：明确拒绝迁移

1. 上游 matchHebing 的前两位六经分数达到 70% 比例即判合病。App 已有显式条件分支，比例阈值不能替代条文语义与必要条件。
2. 上游 matchFormulas 的 ifs 字符串包含匹配。App 已有稳定问项 key、canonical 选项号和 required 门禁；不能退回文本子串匹配。
3. 上游“无六经命中时以最高脏腑标签兜底 primary”的策略。
4. 把血、气、阴虚等非脏腑标签混入脏腑分析。
5. 上游 matchSiniTrio 以失眠、便秘、寒冷、无汗等宽泛词汇达到 3 项即输出重症提示，并进一步给出生附子剂量建议。不得接入 App 自动诊断、处方或剂量链。
6. 将上游五脏疾病速查、癌症/糖尿病/心脏病等病种表及其处方话术当作临床规则迁移。
7. 未经逐条出处核验的脏腑时辰映射、睡眠时间映射及“某问项直接等于某脏腑”的排他性结论。

## 三、覆盖差异与量化事实

1. App CombinedPattern：19 条；上游 HEBING_TABLE：11 条。数量较多不代表运行覆盖完整，需以条件产生、分支可达和最终结果应用为准。
2. App FormulaRule：172 条，171 个不同方名；猪苓汤有重复规则项。
3. 上游 DIAG_FORMULAS 是六经级模板，包含 11 个代表方剂/方剂组的 rx 文本，不是与 App 172 条 FormulaRule 同粒度的方剂规则集合。不能将两个数组按数量或方名直接比较。
4. 上游 HEBING_TABLE 与 App CombinedPattern 有明显语义重合；App 额外细分了呕吐、喘满、潮热、太阳少阴两感、太阳太阴等条件。
5. 上游 543 处 rx 字符串引用中，部分是具体方名，部分是方剂组、组合方、剂量文本或描述性内容；字符串命中不能作为规则覆盖率。只将其用作待核对索引，不作为“缺方”结论。
6. App FormulaRule 以 required/reference 的选项编号为核心；上游 DIAG_FORMULAS 以 ifs 关键词匹配。由于两套问项、选项和语义不同，不做数组下标映射。

## 四、下一阶段实施顺序（本轮不改代码）

1. **先做可达性测试矩阵**：逐个 _combinedPatternCondition 验证是否能被引擎产生、是否能匹配 CombinedPattern、是否能影响最终 DiagnosisResult.formula；特别覆盖主 RuleEngine 命中和未命中两条路径。
2. **修复合病调用链与条件遮蔽**：统一条件常量；对三阳、太阳阳明下利、太阳少阳呕吐、太阳太阴并病等建立最小回归用例。不得仅靠增加 CombinedPattern 行数。
3. **脉舌问诊交叉验证**：先统一 canonical 值；区分单脉、组合脉、舌质、舌苔；每条冲突规则列出支持证据、反证、缺失追问和不可判断条件。
4. **脏腑独立证据层**：先确定脏腑/气血津液/病性分类和数据来源；首版只读展示，不输出脏腑诊断或处方。每条映射必须有来源证据和适用边界。
5. **经典条文与医案关联**：给规则建立结构化 source reference；先核验原文与版本，再关联医案；无来源标记 MISSING，不以相似语句补造出处。

## 五、当前审计结论

- 脏腑独立证据分析：**新增方向成立**，但上游脏腑标签本身不能直接移植。
- 脉象、舌象交叉验证：**已有基础，存在输入标准化与规则推断边界问题**。
- 六经合病并病：**已有大量规则，但主路径应用、条件键一致性和分支可达性存在代码级缺口**。
- 经典条文与医案关联：**结构化证据元数据不足**，应作为后续基础设施补齐。
- 本轮没有修改任何诊断/处方行为；没有改变问项、规则、患者数据或模型调用。

## 六、代码定位

- App：lib/engine/diagnostic_engine.dart
- App：lib/engine/diagnostic_rules.dart
- App：lib/engine/formula_rules.dart
- App：lib/engine/rule_engine.dart
- 上游：Wsy-prog/tcm-diagnosis-system/blob/master/index.html
