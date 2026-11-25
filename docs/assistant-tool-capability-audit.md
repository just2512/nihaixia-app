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
4. **旧式 String 回传边界已关闭（本 PR 待验收）。** 非空 String 不再默认包装为 SUCCEEDED，也不再生成 `local-page-tool:<toolId>` 合成来源；统一标记 UNKNOWN，保留在用户可见时间线，但从当前和恢复后的模型上下文排除。当前对话中所有非 SUCCEEDED 结果均不回放给模型；历史工具结果只有状态为 SUCCEEDED、sourceIds 非空且没有 `local-page-tool:` 合成标识时才进入模型上下文；`AWAITING_PARAMETERS` 等待补参的澄清消息继续保留，避免恢复后丢失追问上下文。旧历史中的页面路由来源同样不回放给模型。
5. **成功结果来源约束已收紧（本 PR 待验收）。** `validateFor()` 要求 SUCCEEDED 必须有非空 sourceIds，并拒绝将 `local-page-tool:` 页面路由标识当作业务来源。现有本地确定性 executor 的成功分支均提供实际 engine/data/rule 来源标识；失败、未执行、取消及 UNKNOWN 不要求伪造来源。
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

1. **已在独立切片实现，待 CI：** SUCCEEDED 必须携带真实 engine/data/rule/knowledge sourceId；页面路由 ID 不算业务来源。
2. **已在独立切片实现，待 CI：** 旧 String 回传标记 UNKNOWN；保持用户可见，但不自动解释、不进入当前或恢复后的模型 transcript；补一条真实页面回传 widget 回归。
3. 为工具结果单独持久化失败增加 UI 可见状态与重试/恢复策略；不要与 #58 的 user+assistant 成功轮次原子写入混为一谈。
4. 不批量审计/迁移 23 个页面。只有出现明确用户场景、可复现断点和既有确定性业务函数时，才单独选一项处理。
5. Headless adapter 不作为数量目标；只有具体能力存在可验证断点时再单独评估。


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


## 10. 2026-11-16 业务结果来源门禁与旧页面回传隔离

### 10.1 复核发现
- `AssistantToolResult.validateFor()` 原来允许 `status=SUCCEEDED` 且 `sourceIds=[]`；结构化字段存在并不证明结果经过 App 业务执行或能追溯来源。
- `LocalAiInterviewScreen._openTool()` 原来把非空 legacy `String` 返回值包装成 SUCCEEDED，并生成 `local-page-tool:<toolId>`。这是页面路由来源，不是确定性计算/业务数据来源。
- 该旧结果可能被 `canInterpret` 判定为可解读，并在后续轮次通过可见 transcript 再次进入模型上下文。

### 10.2 本次最小修复（独立分支，CI 待验）
- SUCCEEDED 必须有非空 `sourceIds`；拒绝 `local-page-tool:` 前缀作为来源。
- Legacy String 回传保留可见文本，但标记 UNKNOWN，不产生合成 sourceId，不显示 AI 解读按钮。
- 当前对话 transcript 按消息 `includeInModelContext` 过滤；只有通过结果契约校验的 SUCCEEDED + 真实来源可进入模型上下文。FAILED / CANCELLED / NO_RESULT / UNKNOWN 仍可见，但不回放给模型；`AWAITING_PARAMETERS` 澄清消息保留为对话上下文。历史恢复采用相同门禁。
- 不修改任何排盘、历法、五运六气、规则问诊、剂量换算或方剂计算逻辑，不改数据库 schema，不重写 ToolRouter / Orchestrator / KnowledgeContextBuilder。
- 现有 deterministic executor 成功分支提供 engine/data/rule 来源标识；未来若有真实成功执行但没有可追溯来源，应先补真实来源定义，不能以页面 ID 或通用占位来源绕过门禁。

### 10.3 针对性验收
- `test/assistant_tool_result_test.dart`：source-less SUCCEEDED 被拒绝；page-route-only source 被拒绝；真实 engine source 保持通过。
- `test/assistant_tool_result_handoff_test.dart`：真实 legacy 页面返回文本显示 UNKNOWN，来源 MISSING，不触发模型解释，并且不写入 Native transcript。
- 以上只针对本次识别的结果契约断点；不扩充 23 个 Page Tool 的泛化测试矩阵。


## 11. 2026-11-16 当前主线能力复核（以代码和本节为准）

本节覆盖前面 D-01/D-02 中已被后续实现改变的历史快照。历史章节保留作为决策轨迹，不再用其中旧的“没有 Headless 接口 / 只有 3 个 Headless”结论描述当前主线。

### 11.1 当前注册表分类

以 `lib/screens/assistant_tool_router.dart` 当前实际注册项为准，共 24 个 `toolId`：

| 类别 | 数量 | 内容 |
|---|---:|---|
| Headless deterministic/data executor | 18 | App 原有计算/数据能力，可在当前对话调用 |
| Page-only | 5 | 仅负责知识/历史页面浏览，不代表后台执行 |
| Inline deterministic workflow | 1 | `structured_diagnosis`，走现有 `TcmInterviewConversationController / DiagnosticEngine`，不是 ToolRouter Headless |

当前已经注册 Headless 的 18 项：
- 排盘/起卦：`ziwei`、`bazi`、`yijing`、`xiaoliuren`、`meihua`；
- 历法/术数：`yunqi`、`almanac`、`ziwu_liuzhu`、`chenggu`、`huangdi_siji`、`sanshan_lingqian`、`shousheng_debt`；
- 单位换算/知识数据：`dosage`、`solar_terms`、`dream`、`guansha`、`saved_charts`、`yuxiaji_omen`（仅当前本机时辰文本查询）。

仍为 Page-only 的 5 项：
`guji_library`、`knowledge_hub`、`medical_cases`、`diagnosis_history`、`critical_illness`。
`yuxiaji_omen` 同时保留原页面：当前本机时辰文本查询由 Headless executor 执行；“鸦鸣鹊噪方向”“占灯花法”等需要用户实际观察的特殊占法仍走原页面，不由 AI 猜测观察输入。分类按已注册 Headless executor 计 18 项，不把特殊页面入口重复计为第二个工具。

Page-only 并不是全部都需要改为 Headless：
- 古籍、知识库、医案是可浏览的知识资料入口；学习助手及问诊助手的资料检索复用 `AssistantKnowledgeContextBuilder`，不靠跳转页面代替检索。
- 诊断历史、重症资料属于用户主动浏览的页面能力，不是应由模型自动打开的业务计算器。
- 不以 Headless 数量作为目标；只把已有纯函数/本地数据查询且参数与来源可验证的能力放入当前对话。

### 11.2 当前对话执行链已经存在

核心代码：
- `lib/services/assistant_conversation_orchestrator.dart`：规则优先识别工具意图、提取已声明参数、保留未知值并在歧义/缺项时澄清；E4B 候选工具筛选只允许 `headlessExecutor != null` 的能力，不把 Page Tool 路由给模型执行。
- `lib/screens/local_ai_interview_screen.dart::_requestTool`：收集槽位、追问、保持待补参数状态；只有明确页面意图才走页面导航。
- `lib/screens/local_ai_interview_screen.dart::_executeHeadlessTool`：执行前参数校验和红旗边界检查，调用 App executor，验证 toolId、结构化输出、实际参数和 sourceIds，写 TRACE、持久化并按结果状态决定是否交给 AI。
- `lib/models/assistant_tool_result.dart`：SUCCEEDED 必须有结构化字段和真实来源；拒绝 `local-page-tool:` 合成路由来源。
- `lib/screens/local_ai_interview_screen.dart::_restoreVisibleConversationToModel`：UNKNOWN/FAILED/CANCELLED/NO_RESULT 或旧式页面 String 结果可供用户查看，但不回放为模型事实；待补参数 `AWAITING_PARAMETERS` 消息仍保留。

只有同时满足以下条件的结果才交给 AI 解读：
1. App 原有确定性代码或受控本地数据 executor 已实际执行；
2. 返回 `AssistantToolResult.status == SUCCEEDED`；
3. 有结构化 `values`、可核实的实际参数（若该工具有参数）和真实 `sourceIds`；
4. 通过 `validateFor()` 与 `validateArgumentsMatch()`。

失败、取消、没有结果或来源/参数不完整时不由模型补造结果。医学诊断性内容除有 App 规则实际执行结果外，还必须由本地知识库可追溯条目支持；民俗/命理来源只能支持文化解释，不能升级为医学诊断。

### 11.3 玉匣灵兆：Headless 当前时辰查询与特殊页面入口

- 原页面 `YuxiajiOmenScreen` 的常规“当前时辰”数据只依赖 App 本机时间、`shiChenIndexOf` 和 `kYuXiaJiShiChenOmens` 本地表，不需要额外用户参数。
- 本 PR 把当前时辰查询抽为共享纯时间 helper 与 `YuxiajiOmenToolExecutor`；页面复用同一 helper，避免两个时辰算法漂移。
- 助手对话默认调用本地 executor，保存真实本机时间、UTC 偏移、时辰、对应文本和 `local-data:yuxiaji-omen` sourceId。
- “方向/形态”特殊占法仍留在原页面，因为它们需要用户提供额外观察信息；不把无法验证的观察默认成已知值。
- 解释提示明确规定：只解释本地民俗文本，不得把面热、眼跳、耳鸣、心惊、肉颤等条目包装为疾病、病因或健康风险；不输出诊断或治疗建议。
- 针对性测试：`test/yuxiaji_omen_tool_executor_test.dart` 验证时辰边界、数据与来源；`test/assistant_tool_result_handoff_test.dart` 验证当前对话真实执行、无页面跳转、来源持久化和民俗解释边界。

### 11.4 结果真实性门禁已进入 master（PR #196）

PR [#196](https://github.com/just2512/nihaixia-app/pull/196) 已合入，merge commit `2ab2d9e68d125feb8b0d0ef1b35aef6cc1e97afe`。
- `AssistantToolResult.validateFor()` 拒绝没有来源的 SUCCEEDED。
- `local-page-tool:` 不能冒充业务执行来源。
- Legacy String 页面回传变成 UNKNOWN，保持用户可见，但不进入模型 transcript，也不触发自动解释。
- 历史恢复同样过滤 UNKNOWN/合成页面来源；参数澄清的等待状态继续保留。
- PR CI：run [43787526563](https://github.com/just2512/nihaixia-app/actions/runs/43787526563) Flutter regression + Android arm64 均 SUCCESS；run [43787521411](https://github.com/just2512/nihaixia-app/actions/runs/43787521411) 静态分析、changed tests 和 test-pairing SUCCESS。

### 11.5 本节未声称已完成的项目

- 本地 OPPO Find N2 的 E4B GPU/CPU 多轮、权限/取消、Activity recreation、force-stop/restart、AI 数据清除与 TRACE 实测仍为 `UNKNOWN`；GitHub CI 不能替代设备证据。
- 经典/本草现代讲稿已按 upstream/main 增量集成（PR #198/#199/#202）；来源、许可口径及不设整批考据阻塞的结论见 `docs/upstream-sync-ledger.md` §§17—21。本附录此处旧 HOLD 是历史快照，不代表当前阻塞或待办。
- 不新增 Agent/DAG、第二套 ToolRouter、第二套知识检索系统或新的 SQLite schema。


---

## 12. 2026-11-25 Core-4 现有执行边界复核（master `a43989636101d267cd2ab96fe6a4eee1a89ba522`）

本节以当前代码路径静态复核，不把“已注册 executor”扩大解释为“模型可自动编排”或“获得跨领域授权”。

### 12.1 当前分层数量与两个不同的白名单

- `AssistantToolRouter` 仍有 24 项：18 个 Headless deterministic/data executor、5 个 Page-only、1 个 inline deterministic workflow（`structured_diagnosis`）。历史章节 §1～§10 是演进记录，当前分类以 §11.1 和本节源码为准。
- `HeadlessToolDispatcher` 注册的 18 项只能说明 App 有可调用的确定性/本地数据执行器；它不意味着 18 项都允许进入多步骤自动计划。
- `AssistantToolExecutionPlanBuilder.planEligibleToolIds` 当前仅允许四项：`dosage`、`solar_terms`、`yuxiaji_omen`、`sanshan_lingqian`；计划最多 3 步，候选最多 6 项。其余 14 个 Headless 工具不得据“有 executor”推定可用于多步骤计划。
- `structured_diagnosis` 仍走既有 `TcmInterviewConversationController / DiagnosticEngine`，不是 Headless plan step。

### 12.2 当前 E4B 意图选择不是 Core-3 ReasoningResponse 协议

- `AssistantConversationOrchestrator._boundedCandidates` 只保留 2～6 个唯一候选，并要求每个候选均已注册 Headless executor；Page-only 不进入模型候选集合。
- `LocalAiInterviewScreen` 仅在候选数至少 2、有效模式为 tools/metaphysics、输入未命中症状/个人情境排除规则、Native 模型 ready 且本轮有 TRACE ID 时，调用 `LocalAiService.resolveAssistantIntentWithTrace`。
- Native `resolveAssistantIntent` 建立独立的短生命周期意图分类 Conversation。提示要求严格 JSON：`select / plan / clarify / none`；只能选择 App 提供的精确 ID；不得新建能力、生成参数、计算业务结果或执行工具；plan 必须是用户明确要求的 2～3 项互相独立步骤、不得跨步骤传递结果，且每项 `plan_eligible=true`。
- 模型输出仅给出 tool ID / 有序 ID。参数由 `AssistantConversationOrchestrator.argumentsFor` 按用户原文确定性抽取；`AssistantToolExecutionPlanBuilder` 再对候选集合、能力元数据、计划长度、重复 ID、白名单、必填字段及参数格式进行整计划预检。任一错误时不向 Dispatcher 暴露部分计划。
- 当前代码路径未在模型 plan 解析后增加第二次确认 UI；它依赖用户原始请求的显式执行意图、意图分类提示约束、App 白名单和参数预检。此边界不能被误写成“模型提出动作后已获单独确认”。Core-3 的 `ACTION_PROPOSAL` 未来接线不得继承这个历史假设，必须新增单独的 App 授权/确认决策。

### 12.3 执行与结果终态

- `HeadlessToolDispatcher.executePlan` 对整份计划先校验 tool ID、registered capability ID 和 executor；随后按顺序调用，只有当前步骤 SUCCEEDED 才进入下一步。
- executor 抛异常时保留先前已验证结果，将当前步骤记为 UNKNOWN 并停止后续步骤；不重试、不重放、不推测补偿。
- `HeadlessToolResultHandler` / `HeadlessToolPlanResultHandler` 对 tool ID、结构化 values、实际 arguments、真实 sourceIds 做结果契约检查；只有全部步骤 SUCCEEDED 且所有结果合同有效时才允许汇总解释。部分失败、无结果、取消、UNKNOWN 或来源无效时，不把失败输出包装为成功事实。
- 当前业务结果主载体仍为 `AssistantToolResult` / `HeadlessToolPlanExecutionResult`。PR #520 的 `BusinessActionProposal` 仅为严格解码后的未可信提案；PR #524 的 `ReasoningExecutionResult` 是输入 DTO 形状，尚未由实际执行结果投影，也没有与 dispatcher/result handler 建立映射。

### 12.4 能力级参数/授权缺口

- `AssistantToolParameterType` 目前为 `text / date / time / integer / choice`；验证包含 tool ID 匹配、未声明参数拒绝、必填项、日期/时间格式、整数解析和 choice 白名单。
- 尚未形成统一、版本化 capability schema：泛化数值上下限/精度、单位类型、嵌套对象/数组、字段间约束、输入来源/敏感级别、可取消/副作用/幂等等级、单独授权确认策略均没有被该参数模型统一表达。个别 executor 的业务校验不能替代通用 schema。
- `BusinessActionProposal` 不能直接转换成 `ToolExecutionPlan`：必须先验证提案 requestId、capability ID 是否在本轮 App 候选和允许列表中；将模型参数解析为严格 typed args（拒绝额外字段、缺省猜值和单位不明）；对敏感数据/副作用能力执行 App-owned 权限与显式确认；最后才调用现有 `_requestTool` / Dispatcher，禁止让模型直接调用 executor。
- 唯一 Native 模型访问 Gate、队列和 GPU/CPU fallback 保持原样，不建立第二套模型入口。

### 12.5 测试证据与仍未知项

- `test/headless_tool_dispatcher_test.dart` 覆盖 registered 单步计划、AI origin、Page-only 阻断、未知工具/能力 ID 不匹配、失败后停止、抛异常转 UNKNOWN、同步/异步适配边界。
- `test/assistant_tool_execution_plan_builder_test.dart` 覆盖仅从候选 ID 构建、Page-only 拒绝、不支持多步的工具拒绝、候选外/重复 ID 拒绝、计划大小和所有步骤参数预检。
- `test/headless_tool_plan_result_handler_test.dart` 覆盖逐步骤来源隔离、前序非成功步骤后后续未执行、UNKNOWN 不触发聚合解读、错误结果被抑制。
- 以上是已存在的代码和自动化测试覆盖，不等于本轮重新执行所有测试，也不等于 Find N2 真机执行。真实设备取消、进程恢复、TRACE 和跨轮结果回流继续 UNKNOWN / LOCAL FINAL ACCEPTANCE。
- **结论：** Core-4 已具备受限的确定性执行底座，但提案协议、能力级 schema、App 授权确认及 `ExecutionResult` 真实回流未闭环，状态 PARTIAL。继续复用当前 Router / Builder / Dispatcher，不为追求架构完整度重建通用执行平台。
