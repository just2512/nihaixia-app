# AssistantToolRouter 能力目录审计（D-01）

> 审计类型：只读源码盘点；不改变业务行为、不抽取 Headless adapter。
> 基线：master `c7a12ed32140fb2e8e97ea406e5fdc6504216907`（2026-11-11）。
> 核心源码：`lib/screens/assistant_tool_router.dart`（blob `eca8e0d6787274811796d174ec16ff29ccef4ed7`）；测试：`test/assistant_tool_router_test.dart`（blob `f266d827f4d5a4e5b758366de0bc799550ead909`）。

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
| huangdi_siji | 黄帝四季歌 | tools/learning/metaphysics | 打开资料页面 | Page Tool |
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
