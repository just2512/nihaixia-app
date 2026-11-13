# AssistantToolRouter 能力目录审计（D-01）

> 审计类型：只读源码盘点；不改变业务行为、不抽取 Headless adapter。
> 基线：master `15b72cffbb357125e8ab7b33bf556e73997ae3b9`（2026-11-12）。
> 核心源码：`lib/screens/assistant_tool_router.dart`（blob `eca8e0d6787274811796d174ec16ff29ccef4ed7`）；路由测试：`test/assistant_tool_router_test.dart`（blob `f266d827f4d5a4e5b758366de0bc799550ead909`）。D-03 结果契约源码：`lib/models/assistant_tool_result.dart`（blob `a03abcf80ff23406eeaf602b7e960085bedaf886`）；测试：`test/assistant_tool_result_test.dart`（blob `32834389b9230df6b510af788146b3b27af3ff2f`）；消费入口：`lib/screens/local_ai_interview_screen.dart`（blob `d14f18edc606e0b01ffeb3c431dd8fcb37ada6d7`）。

## 1. 盘点口径与结论

本次以 `AssistantToolRouter._all` 实际注册项为分母，而不是 README、提示词或历史能力清单。源码当前注册 **24 个 toolId**，ID 唯一性由现有测试覆盖。24 项中：

- `structured_diagnosis`：主流程由 `LocalAiInterviewScreen` 内联规则问诊接管；注册表保留的 builder 主动抛出 `StateError`，不是可直接调用的页面能力。
- 其余 **23 项**：均定义为 `Widget Function()` 页面 builder；只有 `yunqi` 额外定义 `builderWithArguments`。
- `AssistantToolArguments` 当前只有字符串 map；校验支持 required、未声明字段、日期、整数和枚举选项，但没有通用数值范围、单位、对象/数组、跨字段约束或版本化 schema。
- 当前注册表没有统一的 `execute(args) -> typed result` 执行器接口，也没有统一的执行状态、取消、超时、幂等键或副作用等级契约。

因此，注册表覆盖证明的是“可被路由到的目的地”，不能据此认定 24 项都是 Headless Capability 或 Executed Capability。

## 2. 24 项逐项目录

| toolId | 目标 | 模式 | 参数/执行边界 | 当前分类 |
|---|---|---|---|---|
| structured_diagnosis | 结构化辨证问诊 | consultation | 由助手页内联调用规则问诊；旧 builder fail-closed | Inline deterministic workflow（非 ToolRouter Headless） |
| yunqi | 五运六气推算 | tools/metaphysics | 可传 date；builderWithArguments；页面执行 | Page Tool + argument-aware page |
| ziwei | 紫微斗数排盘 | tools/metaphysics | 无统一 args schema | Page Tool |
| bazi | 八字排盘 | tools/metaphysics | 无统一 args schema | Page Tool |
| yijing | 易经起卦 | tools/metaphysics | 无统一 args schema | Page Tool |
| xiaoliuren | 小六壬起课 | tools/metaphysics | 无统一 args schema | Page Tool |
| meihua | 梅花易数起卦 | tools/metaphysics | 无统一 args schema | Page Tool |
| dosage | 经方剂量换算 | tools | 页面打开；无统一 args schema | Page Tool |
| ziwu_liuzhu | 时辰开穴计算 | tools | 页面打开；无统一 args schema | Page Tool |
| guji_library | 古籍原文 | tools/learning | 打开古籍页面 | Page Tool |
| knowledge_hub | 中医知识库浏览 | learning | 打开知识浏览页面 | Page Tool |
| medical_cases | 医案库检索 | tools/learning | 打开医案库页面 | Page Tool |
| almanac | 每日黄历 | tools/metaphysics | 页面声明 returnResultOnComplete | Page Tool（结果回传路径需逐项核验） |
| diagnosis_history | 诊断历史趋势 | tools/consultation | 打开历史页面 | Page Tool |
| critical_illness | 闭门课重症资料 | tools/learning | 打开资料页面 | Page Tool |
| solar_terms | 节气养生 | tools/learning | 打开节气页面 | Page Tool |
| yuxiaji_omen | 玉匣灵兆 | tools/metaphysics | 打开民俗页面 | Page Tool |
| dream | 周公解梦 | tools/metaphysics | 打开梦境释义页面 | Page Tool |
| guansha | 小儿关煞 | tools/metaphysics | 打开民俗页面 | Page Tool |
| sanshan_lingqian | 三山国王灵签 | tools/metaphysics | 打开灵签页面 | Page Tool |
| chenggu | 袁天罡称骨 | tools/metaphysics | 打开称骨页面 | Page Tool |
| shousheng_debt | 受生债 | tools/metaphysics | 打开民俗页面 | Page Tool |
| huangdi_siji | 轩辕黄帝四季歌 | tools/metaphysics | 打开资料页面 | Page Tool |
| saved_charts | 我的命盘库 | tools/metaphysics | 打开保存命盘页面 | Page Tool |

> 模式栏以注册定义为准；本表不表示这些模式下的安全授权已经完整。医疗、个人生辰和健康历史能力仍须遵守全局审计规范中的领域隔离、显式授权和红旗门禁。

## 3. 现有参数契约

源码定义：
- `AssistantToolParameterType`: text / date / integer / choice。
- `AssistantToolParameter`: key、label、type、isRequired、description、choices。
- `AssistantToolArguments.validateAgainst`: 校验 toolId、拒绝未声明 key、检查必填、日期格式、整数解析和 choice 白名单。
- 当前只有 `yunqi` 声明一个可选 date 参数，说明中注明未提供时使用当前日期；只有它有 `builderWithArguments`。

现有测试 `test/assistant_tool_router_test.dart` 覆盖：
- ID 唯一、byId 精确恢复；
- 模式与明确动作词路由；
- 多工具命中时不抢先执行；
- 工具别名澄清；
- 非法日期、额外字段和 toolId 不匹配拒绝；
- 学习知识问题不因工具名误跳转。

测试尚未证明：
- 所有页面参数都由统一 schema 声明；
- 用户输入到参数抽取、缺参澄清、用户确认的完整链路；
- 页面实际业务函数已执行并返回结构化结果；
- 结果的 sourceIds、单位、缺失字段和错误状态已校验；
- 执行取消、超时、重复请求及 UNKNOWN 状态安全。

## 4. Page / Headless / Executed 分类规则

| 分类 | 必须具备的证据 | 本次结论 |
|---|---|---|
| Page Tool | 只证明有页面 builder / 导航目的地 | 23 项均至少达到此级别 |
| Headless Capability | 可脱离 Widget/BuildContext 调用的业务函数；typed args/result；校验、权限、错误、取消契约 | 本次未从 ToolRouter 注册定义中发现统一 Headless 执行接口；具体业务层是否存在可复用函数，需逐项向下追踪，当前 UNKNOWN |
| Executed Capability | 有真实执行记录，含参数校验、业务函数调用、结果校验、source IDs、最终会话回传 | 本次只读目录审计未执行这些能力；不得标记 PASS |

`returnResultOnComplete: true` 只是页面配置线索，不足以单独证明执行成功或结构化结果完整回传。需要按具体 screen 的完成回调和 `LocalAiInterviewScreen._openTool()` 消费逻辑逐个追踪。

## 5. 当前缺口与风险

1. **注册项与真实执行能力混淆**：提示词/quickActions 读取同一目录，能减少列表漂移，但目录统一不等于执行协议统一。
2. **参数覆盖严重不均**：24 项中仅 yunqi 有 argument-aware builder；其余工具不能声称具备模型参数填充能力。
3. **页面与业务函数耦合**：Widget builder 作为注册表主要执行入口，当前不能证明可脱离 UI 执行业务。
4. **结果协议不统一**：页面可能返回字符串，也可能只打开页面；不能把“页面已打开”当作“业务已执行”。
5. **敏感域隔离**：紫微/八字等涉及个人出生资料，问诊/诊断历史涉及健康信息。不能因工具注册在 tools/metaphysics 模式就默认授权跨域读取。
6. **状态语义缺失**：没有统一 NOT_STARTED / SUCCEEDED / FAILED / UNKNOWN 与幂等/取消语义；执行结果未知时不得自动重放有副作用的操作。

## 6. 后续按证据推进，不做大规模迁移

下一阶段按以下顺序执行：

1. 对 23 个页面逐个读取 `_openTool()`、页面构造参数、完成回调和返回值消费逻辑，形成逐项调用链；不先改代码。
2. 将页面标注为 `opens_only`、`returns_text`、`returns_structured`、`executes_deterministic_calculation`，每个标注附源码与测试。
3. 从当前最容易验证且无医疗/个人敏感权限的工具中选一个，验证是否已有可复用 Headless 业务函数；优先建立一个窄切片，不建通用 Agent/DAG。
4. 若需抽适配器，先锁定原页面行为黄金测试，再定义版本化 typed args/result；保留原 UI 作为展示/人工确认界面。
5. 为每个能力增加正向、缺参、非法参数、取消、失败、UNKNOWN 不重放和结果回传测试。
6. 医疗/玄学领域跨域授权、红旗门禁和用户确认不得由模型自行决定。

## 7. 审计状态

- 注册目录数量：**CODE 核验 24 项**。
- 注册 ID 唯一性：**TEST 已有覆盖**；本次没有重新运行测试。
- Page Tool：**23 项**，由 Widget builder 定义直接支持。
- Headless Capability：**UNKNOWN**，需要继续逐项向业务层追踪。
- Executed Capability：**UNKNOWN**，本次未执行真实业务链。
- Find N2 TRACE：**未执行 / UNKNOWN**。
- 本审计不授权重构、不改变任何业务行为。


## 8. D-02 页面调用链与结果回传复核（2026-11-11）

> 基线仍为 master `c7a12ed32140fb2e8e97ea406e5fdc6504216907`。本节为只读静态调用链审计；未修改运行时代码，也未把页面回传等同于 Headless 执行。

### 8.1 统一入口与结果消费链

**CODE：**

- `lib/screens/local_ai_interview_screen.dart:1629-1715`：`_openTool()` 是统一页面调用入口。
  1. `structured_diagnosis` 不进入 ToolRouter 页面，转到 `_startInlineTcmInterview()`。
  2. 其余工具先执行 `AssistantToolArguments.validateAgainst(tool)`；校验失败即停止。
  3. 通过 `Navigator.push<Object?>` 打开注册表 builder；退出时拿到页面返回对象。
  4. `AssistantToolResult` 会校验 toolId/title/成功结果字段；非空 String 被包装成旧式文本结果；其他返回值统一变成 `noResult`。
  5. 结果参数再经 `validateArgumentsMatch()`，随后写入可见消息、持久化 metadata，并调用 `_restoreVisibleConversationToModel()` 同步 Native 模型上下文。
- `lib/models/assistant_tool_result.dart:1-93`：typed result 包含 toolId/title/values/disclaimer/sourceIds/arguments/status；当前状态枚举只有 `succeeded/noResult/failed/cancelled`。
- `lib/screens/assistant_tool_router.dart:488-525`：23 个页面 builder 的实际目标；只有 yunqi 同时有 `builderWithArguments`。

**结果链结论：** 已存在“页面返回值 → 助手消息 → SQLite metadata → Native 上下文恢复”的通用消费路径；但这不证明每个页面都返回结果，也不证明结果有可信 source ID 或业务执行状态。

### 8.2 23 个页面逐项回传分类

分类只描述当前页面与助手之间的返回行为，不代表 Headless 或真机执行能力。

| toolId | 页面 | 回传分类 | 当前可确认事实 |
|---|---|---|---|
| `yunqi` | `yunqi_screen.dart` | `returns_structured` + `executes_deterministic_calculation` | 返回 `AssistantToolResult`；包含本地引擎来源标识 `local-engine:yunqi`；页面接收日期参数 |
| `ziwei` | `ziwei_chart_screen.dart` | `returns_text` | 计算完成后返回排盘摘要 String；出生信息属于敏感个人数据，不能默认跨域授权 |
| `bazi` | `bazi_paipan_screen.dart` | `returns_text` | 通过 `_buildShareText()` 返回文本 |
| `yijing` | `yijing_screen.dart` + `yijing_result_screen.dart` | `returns_text` | 结果页先返回 String，工具页再二次 pop 给助手；存在双层 Navigator 交接 |
| `xiaoliuren` | `xiaoliuren_screen.dart` | `returns_text` | 有结果时返回包含日期、时辰和课体的文本 |
| `meihua` | `meihua_screen.dart` | `returns_text` + `executes_deterministic_calculation` | 使用 `computeMeihuaByNumber()` 生成 chart，再返回摘要文本 |
| `dosage` | `dosage_converter_screen.dart` | `returns_text` + `executes_deterministic_calculation` | `_convert()` 结果以文本返回；页面声明仅单位换算，不构成临床剂量或用药建议 |
| `ziwu_liuzhu` | `ziwuliuzhu_screen.dart` | `returns_text` | 通过 `_buildAssistantSummary()` 返回文本 |
| `almanac` | `daily_almanac_screen.dart` | `returns_text` + `executes_deterministic_calculation` | `getDailyAlmanac(_date)` 本地计算后返回黄历摘要 |
| `guji_library` | `guji_library_screen.dart` | `opens_only` | 当前注册 builder 未启用助手结果回传 |
| `knowledge_hub` | `knowledge_screen.dart` | `opens_only` | 当前注册 builder 未启用助手结果回传 |
| `medical_cases` | `medical_case_library_screen.dart` | `opens_only` | 当前注册 builder 未启用助手结果回传 |
| `diagnosis_history` | `diagnosis_history_screen.dart` | `opens_only` | 当前注册 builder 未启用助手结果回传 |
| `critical_illness` | `critical_illness_list_screen.dart` | `opens_only` | 当前注册 builder 未启用助手结果回传 |
| `solar_terms` | `solar_term_section_screen.dart` | `opens_only` | 当前注册 builder 未启用助手结果回传 |
| `yuxiaji_omen` | `yuxiaji_omen_screen.dart` | `opens_only` | 当前注册 builder 未启用助手结果回传 |
| `dream` | `dream_screen.dart` | `opens_only` | 当前注册 builder 未启用助手结果回传 |
| `guansha` | `guansha_screen.dart` | `opens_only` | 当前注册 builder 未启用助手结果回传 |
| `sanshan_lingqian` | `sanshan_lingqian_screen.dart` | `opens_only` | 当前注册 builder 未启用助手结果回传 |
| `chenggu` | `chenggu_bone_screen.dart` | `opens_only` | 当前注册 builder 未启用助手结果回传 |
| `shousheng_debt` | `shousheng_debt_screen.dart` | `opens_only` | 当前注册 builder 未启用助手结果回传 |
| `huangdi_siji` | `huangdi_siji_screen.dart` | `opens_only` | 当前注册 builder 未启用助手结果回传 |
| `saved_charts` | `saved_charts_screen.dart` | `opens_only` | 页面内部选择器会返回 chart 类型给页面调用方，但不是向助手返回排盘结果 |

**数量复核：** 9 项具备助手回传入口（8 项 String、1 项 typed result），14 项当前只打开页面；其中确认调用本地确定性计算后回传的至少 4 项为 yunqi、meihua、dosage、almanac。其余页面是否包含可抽取的确定性业务函数，仍需按页面继续向下追踪，不能仅凭页面名称推定。

### 8.3 D-03 结果契约复核（2026-11-12）

PR #46 已合并（master 中的 AssistantToolResult 契约）：

1. **UNKNOWN 状态已加入。** AssistantToolExecutionStatus 当前包含 succeeded / noResult / failed / cancelled / unknown；statusLabel 有对应 wire value。
2. **请求参数不再伪装成实际执行参数。** withArguments(fallback) 现在保留真实 arguments；当实际参数为空而请求参数非空时标记 UNKNOWN。validateArgumentsMatch() 在 expected 非空、actual 为空时明确报“工具结果缺少可验证的实际执行参数”。
3. **消费入口有阻断。** LocalAiInterviewScreen._openTool() 先校验 typed result，再做参数匹配；参数证据缺失时设置契约错误并提前返回，不追加到会话历史，也不把 UNKNOWN 当作已验证执行结果持久化。
4. **旧式 String 回传仍有边界。** 非空 String 会被包装为 succeeded，但若本次请求带有参数，随后会因缺少实际参数而被阻断；若本次请求无参数，旧 String 仍可作为 succeeded 展示。该路径没有自动来源 ID，输出中的来源标识仍显示 MISSING。
5. **成功结果仍允许 sourceIds 为空。** validateFor() 检查空白 source ID，但没有要求成功结果必须提供非空 sourceIds。不能将结构化输出存在等同于来源已核验。
6. **失败重试仍缺统一幂等契约。** 当前 failed 显示重试入口，但注册表没有副作用等级/幂等键/执行去重协议；对未来有持久化副作用的工具不能默认安全重试。
7. **工具结果持久化错误可见性不足。** _openTool() 的工具结果消息单独调用 saveAssistantMessage()；异常目前仅 debugPrint，UI 没有明确显示“结果已显示但历史保存失败”。#58 已合并的成功轮次原子保存不覆盖此处。

以上是当前代码边界，不代表已观察到错误计算或数据损坏。

### 8.4 已核对测试与证据边界

- test/assistant_tool_result_test.dart 已覆盖 UNKNOWN、请求参数与实际参数不一致、缺失实际参数、旧式 String 的参数缺失状态、source ID 显示 MISSING、NO_RESULT 与 CANCELLED 区分。
- #46 的 Flutter regression 和 Android arm64 CI 在对应 PR head 上通过；这不是 Find N2 真机执行证据。
- test/assistant_tool_result_handoff_test.dart 覆盖五运六气结果回传、统一时间线与 Native 上下文同步，以及易经双层页面回传；不能代表 23 个页面全部真实执行。
- test/assistant_tool_router_test.dart 覆盖注册表唯一性、路由模式、动作词、歧义、多工具匹配和参数校验。
- 本轮未执行 23 个页面的设备端真实操作；Executed Capability 和 Find N2 TRACE 仍为 UNKNOWN。

### 8.5 D-03 下一步（自动续接）

1. 为“成功但无 sourceIds”补齐状态语义：区分本地计算器的 engine/version provenance、知识检索来源和真正无来源；不得统一伪造一个 source ID。
2. 为旧 String 回传补负向测试：带参数必须 UNKNOWN/阻断；无参数旧页面应显示 LEGACY/UNKNOWN，而不是默认 SUCCEEDED。该调整需先评估现有页面兼容性。
3. 为工具结果单独持久化失败增加 UI 可见状态与重试/恢复策略；不要与 #58 的 user+assistant 成功轮次原子写入混为一谈。
4. 逐个核对 23 个页面的实际参数消费、取消、失败、输出验证、sourceIds 和持久化；不能用路由注册表测试代替业务执行测试。
5. 仅从非医疗、非个人敏感数据工具评估最小 Headless adapter；先锁定输入/输出黄金行为，再抽取一个工具，不做 23 项批量迁移。


## 9. 2026-11-13 D-03 集成后状态复核（PR #139）

### 9.1 结果持久化错误可见性：已关闭

- 旧问题（第 8.3 节第 7 项）：`LocalAiInterviewScreen._openTool()` 对 Page Tool 结果单独调用 `saveAssistantMessage()`；持久化异常只 `debugPrint`，当前对话没有可见的“历史保存失败/状态未知”提示。
- PR #139 已合并，master merge SHA：`04de8e52abdc88d3c6f99d4b0db836721564acf4`。
- 现在保存失败时，当前对话继续保留已通过业务结果契约的工具结果，并显示持久化警告；当前会话不可用与写入异常使用不同提示。
- 写入异常保留 `persistence=UNKNOWN` 和 `persistedState=UNKNOWN`，不伪报历史保存成功，也不自动重跑工具。该处理尊重“请求可能已提交但响应丢失”的不确定状态，避免重复执行。
- 故障注入 test 验证：单条结果消息保存抛错、可见结果保留、UI warning 出现、历史中不伪报保存、工具结果回传一次，以及两个 TRACE 持久化状态均 UNKNOWN。
- PR #139 full run `43432900614`：Flutter regression 和 Android arm64/Native verification 均 SUCCESS。合并后 master runs `43434084780` / `43434084865` 在本节更新时仍 IN_PROGRESS。

### 9.2 能力分类没有随修复升级

- Page Tool 仍由用户进入页面完成操作；结果返回并在对话中解释，不等于后台执行。
- 24 项注册能力中，当前已具备 Headless executor 的仍为 `yunqi / almanac / bazi`；本次未增加 executor。
- 结果持久化缺口关闭，不代表 23 个 Page Tool 均已有完整参数消费、取消、来源、幂等和真机执行证据。
- 本次不修改模型解释提示、工具计算或业务规则，不把页面回传来源伪装成底层计算引擎来源。

### 9.3 下一步

- 只在发现明确用户场景、既有确定性业务函数和可验证输入/输出契约时，才选择一个 Page Tool 评估 Headless 适配；不以数量为目标。
- 对无真实来源的成功结果、旧式 String 回传和带副作用操作的取消/重试，继续保留 MISSING/UNKNOWN，不伪造来源或自动重放。
- Find N2 真机执行和跨轮 TRACE 仍 UNKNOWN；CI 不替代设备验证。
