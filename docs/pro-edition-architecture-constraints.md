# 研纪专业版架构约束（v1.2）

> **状态：架构冻结稿；后续专业版授权实现必须遵守。**  
> 冻结日期：2026-11-23  
> 适用仓库：`just2512/nihaixia-app`  
> 当前文档分支基线：`master@8f5091c08f10743e7ef3322c86f50fc2e296fd78`  
> 实施时必须重新读取当时的 `master` HEAD；本文记录的 2026-11-23 初始核验基线不替代后续实施分支基线。  
> 本文只冻结设计和验收约束，不代表任何尚未实施的能力已经通过测试。

## 0. 目的、范围与规范效力

本文件将研纪专业版永久授权的架构决策固化为后续实现、评审、测试和集成的共同约束。后续任务不得仅凭聊天记录、旧 PR 描述或代码已经存在，就改变本文确定的架构边界。

### 0.1 规范用语

- **必须 / MUST**：实现和验收的硬性条件。
- **禁止 / MUST NOT**：不得采用的设计或行为。
- **建议 / SHOULD**：默认采用；如需偏离，必须先给出具体原因、替代方案、风险和回滚路径，并取得明确决策。
- **UNKNOWN**：没有足够代码、测试、CI 或设备证据，不得推测为 PASS。
- **MISSING**：规范要求的实现或证据尚不存在。
- **PASS / FAIL**：只能由实际执行结果判定，不得根据方案、类名或文件存在推定。

### 0.2 约束范围

本文覆盖：

1. Feature 权益及收费边界；
2. AI 工具执行来源、执行计划和单一门禁；
3. F0 行为不变重构与 F1 授权接入；
4. 情境上下文解析门禁；
5. Key Ring、发行者密钥与协议兼容；
6. Android Keystore、设备密钥和原子 Token 存储；
7. EntitlementService、异步授权判断与降级；
8. Token 替换、发行者轮换及撤销影响；
9. 批次依赖、自动化和设备验收。

本文件不决定支付渠道、定价、退款规则、商业运营流程或版权合规结论；这些事项不能反向改变本文中的安全和业务边界。

### 0.3 与既有文档及 PR 的关系

- 本文件是**专业版授权架构和实施边界的权威约束**。
- 专业版协议细节文档负责记录具体字段、编码、向量和实现细节；它必须与本文保持一致。
- PR #416 当前分支中的 `docs/pro-edition-license-protocol.md` v1.1 是早期评审稿，其中的独立 SQLite 授权库、客户端 pending request 匹配、最终 Token 回显 nonce、`product_revision` 等设计，若与本文冲突，以本文 v1.2 决策为准，必须在后续协议整理中修正，不能同时保留两套相反规则。
- PR #416 仍是独立实现交付，不因本文保存而自动获得合并许可；其代码、测试和 CI 仍须按本文及项目现行集成流程验收。
- AI 相关实现仍须遵守项目现有的 AI 能力审计规范、情境提问规范和并行执行协议。本文只补充专业版权益边界，不替代这些文件。

## 1. 核心架构与单一事实源

### 1.1 架构组成

专业版授权由以下职责边界组成：

| 组件 | 唯一职责 | 禁止承担的职责 |
|---|---|---|
| `LicenseVerifier` | 验证发行者签名、协议字段、设备绑定和凭证真实性 | 不决定 UI 表现，不执行业务工具 |
| `LicenseKeyRing` | 根据 `issuer_key_id` 提供受信任公钥和信任状态 | 不包含测试密钥于正式 Release 信任环 |
| `LicenseTokenStore` | 读取、原子写入和删除单份当前 Token | 不独立决定用户是否拥有 Feature |
| Android Keystore Plugin | 设备密钥生成、get-only 读取、签名和密钥可用性检查 | 不处理业务 Feature 权益 |
| `EntitlementService` | 通过 Token 验证结果构造内存权益快照、发布状态变化 | 不持久化 `is_pro` 或上次授权结果 |
| `FeatureAuthorizer` | 异步回答某个 Feature 是否允许当前操作 | 不使用全局静态单例门禁 |
| `HeadlessToolDispatcher` | 唯一实际调用 Headless Executor 的执行入口 | 不依赖 `BuildContext` 或直接负责导航 |
| `ContextResolutionGateway` | 唯一受保护的上下文解析入口，在调用 Resolver 前检查权益 | 不复制或替代现有 Resolver |
| UI | 展示授权状态、解释拒绝原因、发起用户明确操作 | 不成为唯一授权安全边界 |

### 1.2 单一授权事实源

- 本地当前授权事实只有一份经过验证的签名 Token。
- Feature 权益必须从 Token、当前协议支持范围和当前 App 已实施的门禁范围重新推导。
- 不保存 `is_pro`、`last_is_pro`、持久化 `granted_features` 或其他可以脱离 Token 独立授予权益的字段。
- 内存可以缓存当前进程已经验证的不可变 `EntitlementSnapshot`；进程重启后必须重新验证。
- 设置页面、会话记录、数据库字段或本地缓存都不能独立授予专业权益。

## 2. Feature 清单与免费/专业版边界

### 2.1 Feature 分层

必须区分以下集合：

- `knownFeatureIds`：协议能够识别的 Feature ID；
- `protocolAllowedFeatureIds`：指定协议修订允许出现的 Feature ID；
- `enforcedFeatureIds`：当前 App 已实现并实际接入门禁的 Feature ID；
- 签发端另有 `issuableFeaturesByRevision`，负责阻止发行端超范围签发。

当前已知 Feature：

| Feature ID | 协议已知 | 首期允许签发 | 首期实施门禁 |
|---|---:|---:|---:|
| `ai_advanced` | 是 | 是 | 是 |
| `contextual_assistant` | 是 | 是 | 是 |
| `advanced_learning` | 是 | 否 | 否 |
| `advanced_export` | 是 | 否 | 否 |

首期默认签发集合仅为：

```text
ai_advanced
contextual_assistant
```

学习模式、基础阅读、搜索、书签、用户数据备份/导出/恢复和既有确定性业务引擎不因本专业版授权设计而收费。

### 2.2 客户端权益交集规则

客户端最终授予集合：

```text
GrantedFeatures =
  ClaimedFeatures
  ∩ KnownFeatureIds
  ∩ ProtocolAllowedFeatureIds
  ∩ EnforcedFeatureIds
```

处理规则：

| Token 声明情况 | 客户端处理 |
|---|---|
| Feature ID 不在 `knownFeatureIds` | 忽略，不授予，记录诊断；不因此拒绝整份合法 Token |
| ID 已知，但当前协议修订不允许签发 | 不授予，记录诊断；不因此拒绝整份合法 Token |
| 协议允许，但当前 App 尚未实施门禁 | 不授予 |
| 已知、协议允许且当前 App 已实施门禁 | 可以授予，前提是 Token 签名和设备绑定均有效 |
| 字段类型错误、Feature 列表结构损坏或重复 ID | 拒绝 Token |

发行端必须严格限制签发范围。客户端对未开放 Feature 不授予权益，但不应因发行端误带一个已知 Feature 而拒绝整份签名有效的授权，导致客户已购权益整体不可用。

## 3. `ai_advanced`：跨工具自动编排权益

### 3.1 收费边界

`ai_advanced` 只覆盖 **AI 自主编排两个或更多不同业务能力的跨工具计划**，不等同于所有 AI 自动工具调用。

以下行为免费：

- 普通 AI 对话；
- AI 自动调用一个 Headless Executor；
- 同一业务能力的多步骤或重复调用；
- 用户手动执行一个或多个工具；
- `structured_diagnosis` 单独运行；
- 既有确定性辨证引擎及其单工具 AI 引导；
- 普通阅读、搜索、书签和基础学习。

以下行为需要 `ai_advanced`：

- AI 自动计划包含两个或更多不同的业务 `capabilityId`；
- `structured_diagnosis` 与其他业务能力组合形成跨工具计划；
- AI 在多个不同业务能力之间自主安排顺序、传递结果或组合执行。

计数依据是不同业务能力 `capabilityId`，不是工具调用次数、步骤数或页面数量。同一能力重复调用仍属于单一能力。业务能力 ID 必须稳定、明确，不能通过临时字符串或 UI 页面名推断。

### 3.2 完整执行计划先授权、后副作用

跨工具计划必须在第一个 Executor 产生业务副作用之前形成完整的 `ToolExecutionPlan` 并完成权益判断。

建议模型：

```dart
class ToolExecutionPlan {
  final String planId;
  final InvocationOrigin origin;
  final List<ToolExecutionStep> steps;
}

class ToolExecutionStep {
  final String toolId;
  final String capabilityId;
  final Map<String, dynamic> arguments;
}
```

实际实现可复用现有类型，但语义必须满足：

1. 每个计划有稳定的 `planId`；
2. 每个 Step 有工具 ID、业务能力 ID 和经过验证的参数；
3. `InvocationOrigin` 必填；
4. 所有 Headless Step 只能通过 Dispatcher 执行；
5. 跨工具计划在开始前一次性完成 Feature 判断；
6. 未授权时拒绝整个跨工具计划，不能先执行工具 A，再发现工具 B 需要专业版；
7. 计划开始并通过授权后，不因授权状态随后变化而取消正在执行的计划；新的计划必须重新检查。

若现有模型/调度协议逐个动态发出工具请求，无法预先形成完整计划，则 F1 不能用“执行第二个工具时再检查”作为替代方案。必须先补齐计划边界和副作用前授权能力。

### 3.3 `InvocationOrigin` 必须显式

定义至少包含：

```dart
enum InvocationOrigin {
  userManual,
  aiDispatch,
}
```

执行入口参数必须是 required，不允许默认值。禁止根据 `traceContext == null`、线程、页面或调用栈推断来源。

- 用户从工具页主动操作：`userManual`。
- 用户从其他页面主动发起业务工具操作：`userManual`。
- AI 自动调度计划：`aiDispatch`。
- AI 自动调度启动的后台延续任务：继承 `aiDispatch`，不能在恢复后改成手动来源。
- 与 AI 工具调度无关的后台维护任务不应进入该工具执行路径。

## 4. F0：行为不变的纯重构

F0 必须先于 F1 独立合并。F0 不实现授权逻辑，也不改变当前工具执行行为。

### 4.1 先建立特征测试

以当前真实执行入口为基线，先覆盖：

- 工具 ID 和参数校验；
- Executor 实际调用与结果；
- 成功、业务失败和异常处理；
- 执行前后的会话状态；
- 工具结果回写及消息顺序；
- 导航或页面交互的返回行为；
- 同一工具重复、连续执行时的状态一致性；
- 取消、超时及执行状态不确定时的处理。

测试必须捕获当前真实行为，不得先假定抽取后的行为。

### 4.2 Dispatcher 抽取边界

F0 从当前页面/State 中抽取纯执行分发逻辑，形成独立 `HeadlessToolDispatcher`。

| 模块 | 责任 |
|---|---|
| Screen / State | 页面状态、消息展示、导航、用户交互 |
| `AssistantToolRouter` | 工具定义、参数约束、工具发现和注册元数据 |
| `HeadlessToolDispatcher` | 执行分发、调用 Executor、规范化结构化结果 |
| Headless Executor | 实际业务动作 |
| UI Result Handler | 将结构化结果转换为消息、导航意图或 UI 状态 |

约束：

- Dispatcher 不持有 `BuildContext`，不直接调用 Navigator。
- 导航需要由执行结果表达为结构化意图，再由 Screen 处理。
- 不得把页面 State、导航和 UI 回写整体搬进 Dispatcher。
- F0 不加 `FeatureAuthorizer`，不改变 Origin 和授权结果语义。
- F0 完成后必须能够独立回滚，不影响后续 F1。

### 4.3 Executor 可访问性和 import 图

Dart 没有传统 package-private。必须通过库私有和 import 图约束执行器访问：

- Executor 实现放在独立 Dart library；
- Dispatcher 是唯一导入 Executor 实现库的业务库；
- 其他业务库不得直接 import Executor 实现库；
- Router 暴露工具定义/元数据，不向任意页面暴露可直接调用的 Executor 实例；
- 架构测试使用 Dart AST / Analyzer 解析 import 图，不只使用函数名字符串搜索；
- 测试覆盖相对路径、包路径、别名 import 和条件 import 的实际项目使用形式。

F0 合并门槛：

| 项目 | 要求 |
|---|---|
| 重构前特征测试 | PASS |
| 重构后同一特征测试 | PASS |
| Executor 行为变化 | REJECT |
| Screen 直接调用 Executor 实现 | REJECT |
| Dispatcher 依赖 BuildContext | REJECT |
| Dispatcher 以外业务库 import Executor 实现库 | REJECT |
| F0 混入授权判断 | REJECT |

## 5. F1：Headless Tool 单一门禁

### 5.1 唯一实际执行入口

所有注册的 Headless Executor 必须只能通过 `HeadlessToolDispatcher` 实际调用。不能只按类名选择门禁位置，也不能把权限检查分散到各个 Executor。

Dispatcher 在以下步骤之后、业务副作用之前执行授权：

```text
收到完整执行计划
  → 工具与参数校验
  → 检查 InvocationOrigin
  → 计算不同 capabilityId 数量
  → 若为跨工具 aiDispatch，异步检查 ai_advanced
  → 允许后执行计划
```

手动工具页调用不受 `ai_advanced` 门禁影响。

### 5.2 结构化拒绝

不能静默失败、抛出未处理异常或伪装成 Executor 业务失败。建议返回结构化结果，至少包含：

- `featureId`；
- `planId`；
- 关联的工具或能力标识；
- `manualToolRoute`（如果存在）；
- 可展示的拒绝原因。

AI 应向用户说明该跨工具操作需要专业版，并提供：

1. 前往专业版授权设置；
2. 打开对应工具页手动执行。

基础对话必须继续可用，不因一次工具被拒绝而破坏会话。

### 5.3 其他调用路径审计

F1 必须审计：

- 所有注册 Headless Executor；
- Page-only 工具（不得误标成 Headless）；
- `structured_diagnosis` 内联执行；
- 深链接和跨页面工具入口；
- MainActivity 生命周期相关任务；
- 后台任务创建、延续、恢复和取消路径；
- 任何其他直接调用业务 Executor 的路径。

行为测试必须证明：单一自动能力免费；相同 capability 重复步骤免费；跨不同能力的自动计划受门禁；手动多工具操作免费；拒绝跨工具计划时没有任何 Step 先产生业务副作用。

## 6. 情境提问：Resolver 调用边界门禁

### 6.1 不改造既有 Resolver

继续复用既有 `AiContextRef` 和 `AiContextResolver`，不重复建设 ContextRef、Resolver、会话表或聊天体系。

新增受保护的 `ContextResolutionGateway`。所有业务代码必须经过 Gateway 才能调用 Resolver。Resolver 自身保持纯解析职责，不内置授权 UI 或 Feature 判断。

### 6.2 新会话和后续轮次统一

`ContextualAskCoordinator` 负责情境业务入口和会话组织，但不能只在首次入口检查。

所有实际调用 Resolver 的位置——新建会话、恢复旧会话、后续每轮需要重新解析上下文——都必须通过 Gateway：

```text
准备解析 AiContextRef
  → FeatureAuthorizer.authorize(contextual_assistant)
  → allowed：调用 AiContextResolver
  → denied / temporarilyUnavailable：不调用 Resolver
```

约束：

- 轻量引用结构白名单检查可以在授权前执行，但不得提前读取受保护的真实上下文内容。
- 未授权的新情境提问不得调用 Resolver，也不得创建空会话。
- 未授权的旧情境会话后续轮次不得重新调用 Resolver，不得获取或注入新上下文。
- 免费用户继续旧会话时可以阅读历史并进行普通文字对话，但必须跳过上下文重新解析和新上下文注入。
- 重新激活后，下一次情境解析可以恢复。
- Resolver 解析失败与授权拒绝必须分别报告，不能混为一类错误。
- Gateway 是唯一 Resolver 调用边界；架构测试必须约束其他业务库不得直接 import Resolver 实现库。

最低回归场景：

| 场景 | 预期 |
|---|---|
| 未授权新建情境会话 | 不调用 Resolver、不创建空会话 |
| 未授权继续已有情境会话 | 不调用 Resolver |
| 授权失效后继续旧会话 | 历史可读、普通对话可用 |
| 授权失效后继续旧会话 | 不注入新上下文 |
| 重新激活后继续旧会话 | 下一次解析恢复 |
| Resolver 自身失败 | 返回解析错误，不误报未授权 |

## 7. FeatureAuthorizer 与 EntitlementService

### 7.1 异步授权接口

授权状态包含真实的 `checking` 阶段，故授权接口必须异步：

```dart
abstract interface class FeatureAuthorizer {
  Future<AuthorizationDecision> authorize(String featureId);
}
```

生产实现采用共享初始化 Future。若状态为 checking，调用方有界等待；建议统一等待上限为 2 秒：

- 2 秒内初始化完成：按最新状态判断；
- 超时：返回 `temporarilyUnavailable`，原因记录为 `initializationTimeout`；
- 超时不得将真实状态改为 `unlicensed`；
- 超时结果不持久化、不作为永久拒绝缓存；
- 后续请求可重新读取最新内存状态。

禁止使用磁盘上的上次 `is_pro` 或上次权益集合消除启动等待窗口。

### 7.2 决策结果与失败原因分层

决策结果：

- `allowed`
- `denied`
- `temporarilyUnavailable`

失败原因至少覆盖：

- `initializationTimeout`
- `storeCorrupt`
- `storageUnavailable`
- `issuerUnknown`
- `signatureInvalid`
- `unsupportedRevision`
- `unsupportedFeatureClaim`（仅作诊断时使用，不因此拒绝整份合法 Token）
- `deviceMismatch`
- `keyMissing`
- `keyInvalidated`
- `keystoreUnavailable`
- `providerError`

`temporarilyUnavailable` 是决策层结果；`keystoreUnavailable` 是失败原因，不能将二者作为同一层枚举混合。

### 7.3 状态快照与免费降级

`EntitlementService` 必须可监听，使用 `ChangeNotifier`、`ValueListenable` 或等价机制发布不可变快照。快照至少包含：

- 当前授权验证状态；
- 当前可授予 Feature 集合；
- 最近检查完成时间（仅诊断，不作为时间有效性依据）；
- 失败原因。

建议的服务状态：

- `checking`
- `active`
- `unlicensed`
- `temporarilyUnavailable`
- `invalid`（具体原因放 failureReason）

授权初始化不得阻塞 `runApp()`。服务内部捕获异常；超时或失败不阻止免费功能启动。专业功能在授权状态未确认时暂不开放，基础功能继续可用。

### 7.4 注入，不使用全局静态门禁

`HeadlessToolDispatcher` 和 `ContextResolutionGateway` 必须注入 `FeatureAuthorizer`。测试使用 Fake，不依赖全局静态 `FeatureGate.require`。

激活成功后更新内存快照并通知 UI，无需重启。授权变化不取消已经开始的普通会话或已开始的执行计划；新的专业操作重新检查。

历史助手会话和情境历史不得因授权失效而删除、隐藏或重置。

## 8. Android Keystore 与平台接口

### 8.1 插件隔离

授权平台能力封装在独立的 FlutterPlugin，例如：

```text
android/app/src/main/kotlin/.../licensing/
  LicensePlugin.kt
  LicenseKeystore.kt
  LicenseKeyStatus.kt
  LicenseTokenStore.kt
```

建议 MethodChannel：

```text
com.nihaisha.nihaisha_app/licensing
```

`MainActivity` 只负责插件注册，不将 Keystore、Token 文件和权益业务逻辑塞入现有复杂生命周期文件。

Keystore 操作在后台线程执行，结果回到主线程。原生异常必须映射为稳定错误码，不得未经处理冒泡到 Dart。

### 8.2 API 必须区分 get-only 与 create

禁止使用含糊的 `getOrCreateDeviceKey` 供所有调用场景复用。

平台接口至少区分：

| 接口 | 行为 |
|---|---|
| `getDeviceKey()` | 只读取已有密钥；不存在返回 `keyMissing` |
| `createDeviceKeyForActivation()` | 仅用户明确生成激活申请时调用 |
| `signActivationRequest()` | 只使用已有密钥；缺失时失败，不自动创建 |
| `checkPrivateKeyUsability()` | 只使用已有密钥执行本地挑战签名；不得创建或替换密钥 |

启动验证、授权 Token 导入、激活校验和后台状态检查一律 get-only。

只有用户主动进入生成激活申请流程，并明确触发创建设备密钥时，才允许创建密钥。创建方法不得覆盖已有 alias；遇并发创建/别名冲突应重新读取并处理，不能生成第二把密钥覆盖第一把。

### 8.3 密钥算法和保护级别

- 设备密钥：P-256 / secp256r1；
- 签名：ECDSA + SHA-256；
- 公钥：完整 SPKI DER；
- 设备指纹：对 SPKI DER 计算 SHA-256；
- 私钥：Android Keystore 保存，不导出；
- ECDSA 签名：DER 编码；
- 不设置用户认证要求，不依赖指纹、人脸或锁屏认证；
- 不因日常锁屏变化主动触发密钥重建。

StrongBox 策略：

1. API 28+ 优先尝试 StrongBox；
2. 仅遇到明确的 StrongBox 不可用/不支持异常时回退到 TEE；
3. 其他 Provider/Keystore 错误必须返回真实原因，不得一律当作 StrongBox 不可用；
4. 已有密钥不因单次检查失败就自动重建。

保护级别：

- API 31+ 使用 `KeyInfo.getSecurityLevel()`；
- API 24–30 使用 `isInsideSecureHardware()`；
- 旧 API 不能可靠区分 TEE 与 StrongBox，不得伪造精确硬件等级；
- 可报告 `SOFTWARE`、`TRUSTED_ENVIRONMENT`、`STRONGBOX`、`UNKNOWN`；
- 该级别只是客户端报告元数据，不是硬件远程证明。

### 8.4 本地挑战签名的语义

启动后台挑战只用于检查当前私钥能否执行签名，并能否通过对应公钥验证。建议命名为 `checkPrivateKeyUsability`。

它不是硬件持有证明，不证明密钥不可复制、App 未被补丁、设备未被克隆或硬件安全级别可信。真正的 Token 设备绑定依赖 Token 中的设备公钥指纹与当前 Keystore 公钥指纹比较。

挑战结果可缓存在当前进程内存，不得跨进程或重启作为永久授权事实。

### 8.5 后台 Isolate / FlutterEngine

Dart Isolate 不共享普通静态变量或单例内存状态；独立 FlutterEngine 也有独立插件注册环境。

必须先审计实际后台任务运行方式，不能仅凭 MainActivity 中存在生命周期代码就推断执行环境。

| 环境 | 要求 |
|---|---|
| 主 Isolate | 使用本实例的 EntitlementService |
| 独立 Isolate | 单独初始化并验证，不复用其他 Isolate 的内存状态 |
| 新 FlutterEngine | 注册 LicensePlugin，并单独初始化 EntitlementService |
| 原生 Android 任务 | 不得把未经验证的 Dart 内存状态当成授权通过 |

后台恢复任务必须保留原始 `InvocationOrigin`，AI 自动调度任务恢复后仍为 `aiDispatch`。

具体后台运行方式、Engine 注册和任务恢复路径在完成源码审计前保持 `UNKNOWN`。

## 9. 授权存储：单 Token 原子文件

### 9.1 位置与数据库边界

第一版采用一个签名 Token 文件，不使用独立 SQLite 授权库：

```text
context.noBackupFilesDir/
  yanji_license/
    active_license.token
```

- 路径由 Android Context 动态取得，不硬编码绝对路径；
- 目录和文件权限按应用私有数据处理；
- 主数据库 `nihaisha.db` 保持 version 7，不增加授权表，不做 v8 迁移；
- 不引入 `is_pro` 或可独立授予权益的数据库字段；
- 当前没有授权历史、多席位或本地多订单查询需求，不为单份 Token 引入 SQLite。

### 9.2 持久化内容

只持久化当前完整 signed Token。Token 至少包含：

- `protocol_revision`；
- `license_id`；
- `order_id`（不含姓名、手机号等个人信息）；
- `product_id`；
- `app_id`；
- `perpetual`；
- `features`；
- `device_public_key_sha256`；
- `request_id`（发行记录关联）；
- `issuer_key_id`；
- `issued_at`（审计用途）。

最终授权 Token 不包含申请侧的 `nonce`。申请 nonce 由发行端验证和去重；客户端不做 pending request nonce 匹配。

不另外重复存储能从签名 Token 解析或重算得到的字段。内存诊断不成为独立权益来源。

### 9.3 原子写入

使用 Android `AtomicFile` 或同目录临时文件 + flush/fsync + 原子替换等价实现。

```text
接收新 Token
  → 格式与长度校验
  → 发行者签名验证
  → 协议修订验证
  → Feature 结构验证
  → 当前设备公钥指纹验证
  → 私钥可用性检查
  → 写临时文件
  → flush / fsync
  → 原子替换 active_license.token
  → 重新读取并验证
  → 更新 EntitlementSnapshot
```

失败规则：

- 新 Token 验证失败，不覆盖旧 Token；
- 原子写入失败，保留旧 Token；
- 不得先删除旧 Token 再写新 Token；
- 文件不存在表示 `unlicensed`；
- 文件损坏、签名错误、发行者未知和设备不匹配必须使用不同诊断原因。

### 9.4 Token 替换策略

新 Token 是一份完整授权，验证成功后替换旧 Token；不做 Feature 并集，不通过 `issued_at` 自动判断新旧。

- 新 Token 无效或设备不匹配：拒绝，旧 Token 不变；
- 新 Token 验证通过且权益不减少：按用户明确导入操作执行原子替换；
- 新 Token 权益少于旧 Token：显示将失去的 Feature，用户再次确认后替换；
- 用户取消：保留旧 Token；
- 写入失败：保留旧 Token；
- 旧 Token 与新 Token 的权益永不合并。

### 9.5 设备清除组合

不得凭记忆声明 Android 清除应用数据、卸载或重装一定会如何处理 Keystore alias。必须在 OPPO Find N2 真实验证：

| Token 文件 | Keystore 密钥 | 预期 |
|---|---|---|
| 不存在 | 不存在 | 免费状态；仅主动激活可创建新密钥 |
| 不存在 | 存在 | 免费状态；激活申请可复用已有密钥 |
| 存在 | 存在且指纹匹配 | 正常验证 |
| 存在 | 不存在 | `keyMissing`；不能自动创建替代密钥 |
| 存在 | 存在但指纹不匹配 | `deviceMismatch`；不能覆盖原 Token |

系统设置清除应用数据、卸载重装、仅删除 Token、模拟 alias 丢失等场景分别记录 OS/ColorOS/App 版本、步骤和结果。未实测前保持 `UNKNOWN`。

## 10. 授权协议与签名规则

### 10.1 字段命名和产品修订

生产 Token 尚未签发，协议字段现在统一：

- 使用 `protocol_revision` / `protocolRevision`，不使用含义模糊的 `product_revision` 表示验签规则版本；
- `product_id` 仍表示商品；
- `app_id` 表示应用；
- `issuer_key_id` 标识签发者公钥；
- `device_public_key_sha256` 必须存在并纳入签名；
- `request_id` 保留用于发行记录关联；
- `nonce` 仅属于设备申请，不进入最终 Token；
- `issued_at` 只用于审计，不决定永久授权有效性；
- 首期不设置 `expires_at`。

若未来已有生产 Token，再变更字段语义必须设计显式兼容迁移；当前未发行生产 Token，不保留错误字段语义的兼容包袱。

### 10.2 修订支持策略

客户端采用显式支持集合和最低受支持修订：

```text
supportedProtocolRevisions = {1}
minimumSupportedProtocolRevision = 1
```

验证同时要求：

1. 修订号不低于最低受支持修订；
2. 修订号属于当前 App 明确支持的集合。

禁止只使用 `revision >= currentRevision` 自动接受未来协议。

正常 App 版本升级不应使仍在支持范围内的旧 Token 失效。新增 Feature 不自动写入旧 Token。只有协议存在明确安全缺陷并提高最低支持修订时，才允许淘汰旧格式。

### 10.3 Token 外层格式与规范化

建议保持文本可复制格式：

```text
YANJI1.<base64url(canonical_payload)>.<base64url(ed25519_signature)>
```

Payload 使用 RFC 8785 JCS 规范化 JSON，UTF-8、无 BOM。签名输入固定为：

```text
UTF8("YANJI-PRO-LICENSE-V1\0")
    || canonicalPayloadBytes
```

规范化约束：

- 所有字段类型固定；
- `features` 生成时排序并去重，验签端拒绝重复 ID；
- 不使用不必要浮点数；
- 不在验签时解析再以另一套规则重序列化后验证；
- Python Issuer 与 Dart Verifier 必须使用同一批合法/非法测试向量；
- 任何签名输入、域前缀、编码或规范化规则变更，都必须增加新的 protocol revision。

设备申请使用独立的请求域前缀和设备签名规则，不能与发行者 Ed25519 Token 签名混用。具体字节级向量必须在协议实现文件中固定，不能仅以“JSON 等价”作为签名规则。

### 10.4 发行端请求签名和防重放

客户端不保存 pending request，不做本地 request/nonce 匹配。发行端必须：

1. 校验申请格式、产品/应用标识、SPKI 曲线和长度；
2. 使用申请携带的设备公钥验证 P-256 ECDSA + SHA-256 请求签名；
3. 重算公钥指纹并与申请声明比较；
4. 校验 `request_id`、`nonce` 和完整申请内容摘要；
5. 在发行端持久化已处理 request_id / nonce / request hash，并设置唯一约束；
6. 完全相同的申请重复提交应幂等返回原签发结果或原处理状态；
7. 同一请求标识对应不同内容必须拒绝；
8. 同一订单换设备必须由明确的 reissue 流程处理，不能把重复请求与换设备混为一谈。

申请 nonce 是客户端生成的随机值，不是服务器在线挑战。防止重复处理依赖发行端去重记录，不依赖客户端把 nonce 回显到最终 Token。

### 10.5 时间规则

永久授权不能依赖客户端系统时钟：

- 不因 `issued_at` 晚于设备当前时间而拒绝；
- 不因设备时间回拨而拒绝；
- 不用 `issued_at` 判断签发前后或授权期限；
- 不以系统时间推导 Token 已过期；
- 首期不设置 `expires_at`；
- `issued_at` 仅作为签发审计字段。

## 11. Key Ring、密钥轮换与 Release 安全

### 11.1 Key Ring 注入

`LicenseVerifier` 必须通过构造注入 `LicenseKeyRing`，禁止在 Verifier 内硬编码特殊测试分支。

- Unit Test：动态测试公钥通过注入进入测试 Key Ring；
- Debug：如需要 App 内调试激活，使用独立 Debug Key Ring 装配；
- Release：只装配正式生产发行者公钥；
- 测试 issuer ID / 公钥不得通过生产默认装配加载。

修复动态测试公钥时，测试 Payload 的 `issuer_key_id` 必须与注入 Key Ring 中的 ID 完全一致。不得放宽未知发行者拒绝规则。

Fixture Builder 应统一生成所有字段合法的凭证；每个负向测试只修改一个目标字段。必须断言未知发行者返回 `issuerUnknown`，而不是后续阶段的签名错误或字段错误。

### 11.2 Key Ring 信任状态

至少支持：

| 状态 | 验证行为 | 签发行为 |
|---|---|---|
| `active` | 接受该 Key 签名 | 可用于新签发 |
| `standby` | 当前 App 已信任该公钥，可接受其新 Token | 私钥未启用时不签发；启用后可提升为 active |
| `retired` | 继续验证其历史合法 Token | 不用于新签发 |
| `revoked` / `compromised` | 拒绝该 Key 签过的所有 Token | 禁止签发 |

备用公钥必须是真实生成并预置在 App 中的公钥，私钥离线保管。一个没有实际公钥的空槽位不构成轮换能力。

备用公钥只让当前版本能够接受备用发行者签出的新 Token；它不会自动让当前版本拒绝旧发行者。拒绝旧发行者需要更新客户端的 Key Ring 信任策略。

### 11.3 吊销的全量影响

吊销一个发行者 Key 会使该 Key 签过的所有合法 Token 同时失效。离线客户端没有可信时间戳，不能区分泄露前签发和泄露后伪造的 Token；攻击者同样可以填写 `issued_at`。

因此：

- 吊销意味着受影响客户需要重新签发；
- 重新签发可在原设备密钥仍可用时复用该密钥；
- 客户端新版更新 Key Ring 后才会执行吊销；
- 旧版本、长期离线设备无法即时收到撤销；
- 不得宣称备用 Key Ring 支持实时远程撤销。

发行流程应按批次/年份轮换 issuer key，例如 `issuer-2026-01`、`issuer-2026-02`，缩小单把私钥泄露的影响范围。订单/签发记录必须保留每张 Token 对应的 issuer_key_id。

### 11.4 Release fail-closed 与发布阻断

正式生产公钥尚未生成时：

- Debug/Test 可以注入测试 Key Ring；
- Release Key Ring 可以在开发构建阶段为空；
- 空 Key Ring 对所有 Token 返回 `issuerUnknown`；
- 绝不允许为方便测试而让 Release 信任测试密钥；
- 正式分发 Release 必须配置至少一个真实生产信任锚，否则发布流水线必须阻断发布。

Release CI 必须同时包含：

1. 扫描测试公钥原始字节；
2. 扫描测试公钥 Base64 编码；
3. 扫描测试公钥 Hex 编码；
4. 检查 Release Key Ring 不含测试 issuer ID；
5. 使用测试私钥签发 Token，调用 Release 实际 Key Ring 工厂验证，必须得到 `issuerUnknown`；
6. 正式发布任务检查生产 Key Ring 非空且至少存在有效可信条目；
7. revoked Key 不能作为唯一有效生产信任锚。

仅做字符串扫描不足以验收；仅做行为测试也不能替代对构建产物的检查。

## 12. 状态、错误和用户体验

### 12.1 关键状态

建议统一服务状态：

| 状态 | 说明 | 专业能力 |
|---|---|---|
| `checking` | 初始化或重新检查中 | 暂不允许，按有界等待规则处理 |
| `active` | Token、发行者、修订和设备绑定均通过 | 按 GrantedFeatures 允许 |
| `unlicensed` | 没有 Token | 拒绝专业能力 |
| `temporarilyUnavailable` | 检查超时或暂时无法确认 | 暂不允许专业操作，基础功能可用 |
| `invalid` | 凭证或设备验证失败 | 拒绝专业能力，按原因展示处理建议 |

失败原因至少区分：

- `storeCorrupt`
- `storageUnavailable`
- `issuerUnknown`
- `signatureInvalid`
- `unsupportedRevision`
- `deviceMismatch`
- `keyMissing`
- `keyInvalidated`
- `keystoreUnavailable`
- `providerError`

不能把所有失败合并成“未激活”。尤其不能把 Keystore 暂时不可用误判为永久未授权。

### 12.2 UI 和历史数据

- 设置页是激活和状态展示入口，不是门禁唯一位置。
- 专业操作被拒绝时，提供可理解的原因和可行替代路径。
- 授权失效不得删除或隐藏助手会话、情境历史、消息或业务结果。
- 免费状态下普通对话继续可用。
- 未授权情境会话不再注入新上下文，但既有历史可以阅读。
- 进行中的普通会话和已获准启动的执行计划不因授权状态变化被强制销毁。

## 13. 实施批次与依赖关系

接口冻结后，允许无依赖工作并行，但必须使用独立工作分支、小批量集成和自动验收。

| 批次 | 范围 | 前置条件 | 合并原则 |
|---|---|---|---|
| A | 冻结协议字段、Feature、Origin、执行计划、Key Ring、Token 存储、状态和平台 API | 无 | 先冻结接口 |
| B | Verifier、Issuer、Fixture、协议修订、Release Key Ring 测试 | A | 独立验签与签发测试通过 |
| C | Android Keystore Plugin、get-only/create 分离、原子 Token 文件 | A | 原生单测和平台接口测试通过 |
| D | TokenStore、异步 EntitlementService、FeatureAuthorizer | A；可先用 Fake Bridge | 独立服务测试通过 |
| F0 | 特征测试、执行逻辑纯重构、Dispatcher 和 import 图约束，不含授权 | 当前执行链审计 | 行为不变后独立合并 |
| F1 | 完整 ToolExecutionPlan、跨工具门禁、结构化拒绝结果 | A、D 接口、F0 | 先授权再副作用 |
| G | ContextResolutionGateway，新会话和后续轮次共同门禁 | A、D 接口 | 所有 Resolver 调用路径通过 |
| E | 专业版设置页、激活导入、状态展示 | D 的状态接口 | UI 只消费服务状态 |
| H | 集成、全量回归、Release 和设备验收 | B、C、D、E、F1、G | 全部硬门槛满足 |

依赖约束：

- C、D、F0 可并行；
- D 可先用 Fake Bridge，不必等待真实 Android 插件；
- F1、G 可先用 Fake FeatureAuthorizer 完成业务测试；
- F1、G 不需要等待 E 的 UI；
- F1 必须先确认调度层能形成完整跨工具计划；
- 后续任务必须先读取最新 master、本文和相关子系统约束，不沿用过期 SHA、PR 状态或旧 CI 结果。

## 14. 验收门槛

### 14.1 协议与签名

- 合法固定向量在 Python Issuer 和 Dart Verifier 均通过；
- 未知发行者返回 `issuerUnknown`；
- 错误签名拒绝；
- 不支持修订拒绝；
- 未知 Feature 忽略且不授予；
- 已知但当前协议不允许的 Feature 不授予、记录诊断，不拒绝整份签名有效 Token；
- 格式错误、重复 Feature ID 和字段类型错误拒绝；
- 不因系统时钟快进、回拨或 `issued_at` 未来值拒绝永久授权；
- 测试发行者 Token 在 Release Key Ring 工厂中返回 `issuerUnknown`。

### 14.2 设备与存储

- 申请流程可创建 P-256 Keystore 密钥；
- 启动检查和 Token 导入只 get-only；
- 强制覆盖 StrongBox 不可用与 TEE 回退；
- 已有密钥升级后保持连续；
- Token 与当前设备公钥指纹匹配；
- 密钥丢失返回 `keyMissing`，不能自动生成替代密钥；
- Provider 暂时异常不误判永久未授权；
- Token 原子替换失败不破坏旧 Token；
- 主数据库始终保持 version 7；
- 授权 Token 位于 `noBackupFilesDir`；
- Find N2 上记录清除应用数据、卸载重装、Token/KeyStore 两种不一致组合的真实表现。

### 14.3 工具门禁

- 免费基础 AI 对话可用；
- 单一 Headless 能力自动调用免费；
- 同一 capability 的多步骤执行免费；
- `structured_diagnosis` 单独执行免费；
- 手动单工具和手动多工具执行免费；
- 两个不同 capability 组成自动计划时受 `ai_advanced` 控制；
- 未授权时跨工具计划在第一个业务副作用之前整体拒绝；
- 后台延续任务不能改变原始 InvocationOrigin；
- 所有实际 Executor 调用只能经 Dispatcher；
- Page-only 工具不被误标为 Headless。

### 14.4 情境上下文门禁

- 所有 Resolver 调用只能经 Gateway；
- 新建情境会话受 `contextual_assistant` 控制；
- 已有情境会话每一轮需要重新解析上下文时也受同一门禁；
- 授权失效后旧会话仍可读、可普通对话，但不得重新解析或注入新上下文；
- 未授权情境入口不创建空会话；
- Resolver 错误与授权错误分别报告。

### 14.5 Release 和升级

- Release 不包含测试公钥原始字节、Base64、Hex 或测试 issuer ID；
- Release Key Ring 工厂行为测试拒绝测试 Token；
- 正式分发 Release 没有生产信任锚时，发布流水线阻断；
- 原版本 APK 可直接升级，不要求卸载；
- 用户数据库、知识库和助手历史不受授权模块升级破坏；
- 授权初始化失败不阻止 App 进入免费功能。

## 15. 当前必须保留为 UNKNOWN 的核验事项

以下问题必须由实际源码、自动化或设备证据解决；本文不把它们预设成 PASS：

| 事项 | 需要的证据 |
|---|---|
| 后台延续任务是否使用独立 Isolate / FlutterEngine | 源码调用链、Engine 创建与任务恢复路径 |
| 每个独立 Engine 是否注册 LicensePlugin | 注册代码与实际 Engine 测试 |
| 当前 Screen 执行逻辑能否无行为变化抽取 | F0 前后特征测试 |
| 当前调度器是否能提前形成完整跨工具计划 | 真实调度协议和副作用前测试 |
| 除已盘点 Headless Executor 外是否存在其他业务执行路径 | 全部调用点、深链接、生命周期和后台入口审计 |
| Find N2 清除应用数据/卸载后 Keystore alias 行为 | 真实设备步骤与记录 |
| StrongBox/TEE 回退及各厂商 Provider 错误 | 目标设备和错误路径测试 |
| 生产发行者公钥与真实备用 Key 是否已配置 | Key Ring 内容及发行/备份记录 |
| Release 是否具备非空生产 Key Ring | Release 工厂测试与产物检查 |

没有证据时保持 `UNKNOWN` 或 `MISSING`。不得将模拟器、Fake Bridge 或设计说明当作 Find N2 真机证据。

## 16. 风险、优势与回滚

| 设计 | 优势 | 风险 / 代价 | 回滚原则 |
|---|---|---|---|
| F0 纯重构与 F1 授权分离 | 行为变化与授权变化可独立定位 | 抽取可能暴露 Screen UI 耦合 | F1 出问题只回滚 F1；保留已验证 F0 |
| 单一 Dispatcher | 工具门禁统一，执行可审计 | 现有直接调用必须先收拢 | 恢复到 F0 之前的可验证执行入口 |
| 完整执行计划预授权 | 防止跨工具任务部分执行 | 调度协议可能需要结构化计划 | 保留原有免费单工具执行，不绕过计划校验 |
| 单 Token 原子文件 | 无数据库迁移，状态简单 | 不适合授权历史/多席位查询 | 保留旧 Token，失败不覆盖 |
| Key Ring 注入与轮换 | 测试/生产信任隔离 | 吊销导致该 Key 全部客户重新签发 | 通过新版信任策略与重新签发恢复 |
| 异步授权状态 | 不阻塞启动，不误判 checking | 初始化超时期间专业操作暂不可用 | 基础免费功能始终可用 |
| Resolver Gateway | 新会话和后续轮次边界一致 | 需要收拢所有直接 Resolver 调用 | 保留历史数据，回滚入口而非删除会话 |

离线永久授权无法即时远程撤销；客户端门禁不能阻止有能力修改/重打包 APK 的攻击者。不得用过度混淆代替真实业务边界，也不得将本地挑战签名描述为远程硬件证明。

## 17. 后续执行纪律

1. 每个批次先核对最新 `master`、本文件、相关协议和实际代码调用链。
2. F0 必须先行为测试、后纯重构、再单独合并；不在 F0 中实现授权。
3. C、D、F0 可以独立分支并行；F1/G 使用稳定接口和 Fake 先行。
4. 不能因一个 PR 的 CI 通过，就推定 Find N2、后台 Engine、Keystore 或 Release 信任环验收通过。
5. 不得删除失败测试、降低验收阈值、把 UNKNOWN 改成 PASS 或用模拟数据代替设备实测。
6. 修改本文已冻结的协议字段、收费边界、门禁位置、存储方案或发行者信任策略，必须先提交单独的设计变更说明，列出兼容影响、风险、替代方案和迁移/回滚方案，并取得明确决策。
7. 每个实现 PR 必须引用本文对应章节，记录分支基线 SHA、head SHA、文件范围、测试、CI 和未闭环项目。
8. 本文件冻结的是设计约束，不是完成声明；只有实现证据满足第 14 节后，才可将对应任务标记为 PASS。

---

**本文件是研纪专业版授权后续工程实施的架构约束依据。未按本文完成设计变更评审，不得自行改变本文冻结的方案。**
