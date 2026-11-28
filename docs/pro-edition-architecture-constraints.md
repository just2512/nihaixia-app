# 研纪专业版架构约束（v1.4）

> **状态：v1.3 专业版授权约束 + v1.4 本地/云端统一 AI 配置修订；后续授权与模型接入必须遵守。**  
> 修订日期：2026-11-28  
> 适用仓库：`just2512/nihaixia-app`  
> 本轮文档基线：`master@8f947cdb481c31c86d607c0d4683f8dc69f85272`  
> v1.4 仅增加统一 AI 开关、本地/云端双运行时及任务模型配置决策；不代表相关运行时代码、Embedding/Reranker 本地引擎或 Find N2 实测已经完成。后续实施必须重新读取届时最新 `master` SHA。

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

1. 单一 `ai_access` 权益与 Native LiteRT 模型访问总门禁；
2. AI 调用与确定性业务执行的边界；
3. Headless Dispatcher、完整执行计划及来源/结果校验；
4. ContextResolutionGateway 的来源与锚点完整性；
5. Key Ring、发行者密钥与协议兼容；
6. Android Keystore、设备密钥和原子 Token 存储；
7. EntitlementService、异步 AI 权益判断与降级；
8. Token 替换、发行者轮换及撤销影响；
9. 批次依赖、自动化和设备验收。

本文件不决定支付渠道、定价、退款规则、商业运营流程或版权合规结论；这些事项不能反向改变本文中的安全和业务边界。

### 0.3 与既有文档及 PR 的关系

- 本文件是**专业版授权架构和实施边界的权威约束**。
- 专业版协议细节文档负责记录具体字段、编码、向量和实现细节；它必须与本文保持一致。
- PR #416 当前分支中的 `docs/pro-edition-license-protocol.md` v1.1 是早期评审稿，其中的独立 SQLite 授权库、客户端 pending request 匹配、最终 Token 回显 nonce、`product_revision` 等设计，若与本文冲突，以本文 v1.3 决策为准，必须在后续协议整理中修正，不能同时保留两套相反规则。
- PR #416 仍是独立实现交付，不因本文保存而自动获得合并许可；其代码、测试和 CI 仍须按本文及项目现行集成流程验收。
- AI 相关实现仍须遵守项目现有的 AI 能力审计规范、情境提问规范和并行执行协议。本文只补充专业版权益边界，不替代这些文件。

## 1. 核心架构与单一事实源

### 1.1 架构组成

专业版授权由以下职责边界组成：

| 组件 | 唯一职责 | 禁止承担的职责 |
|---|---|---|
| `LicenseVerifier` | 验证发行者签名、协议字段、设备绑定和凭证真实性 | 不决定 UI 表现，不执行业务工具 |
| `LicenseKeyRing` | 根据 `issuer_key_id` 提供受信任公钥和信任状态 | 不包含测试密钥于正式 Release 信任环 |
| `LicenseTokenStore` | 读取、原子写入和删除单份当前 Token | 不独立决定 `aiAccess` |
| Android Keystore Plugin | 设备密钥生成、get-only 读取、签名和密钥可用性检查 | 不处理业务 Feature 权益 |
| `EntitlementService` | 验证 Token 并发布单一 `aiAccess` 决策快照 | 不持久化 `is_pro`、上次决策或可脱离 Token 的授权状态 |
| `AiModelAccessGate` | 在 Native LiteRT 模型加载和推理边界统一检查 `ai_access` | 不按业务页面、工具、模式或调用来源拆分收费权限 |
| `HeadlessToolDispatcher` | 唯一实际调用 Headless Executor 的执行入口，校验完整计划和工具能力映射 | 不承担 AI 收费判断，不依赖 `BuildContext` 或直接负责导航 |
| `ContextResolutionGateway` | 唯一受保护的上下文解析入口，校验来源引用、锚点和解析结果完整性 | 不承担付费 Feature 判断，不复制或替代现有 Resolver |
| UI | 展示授权状态、解释拒绝原因、发起用户明确操作 | 不成为唯一授权安全边界 |

### 1.2 单一授权事实源

- 本地当前授权事实只有一份经过验证的签名 Token。
- `aiAccess` 必须从签名 Token、当前协议修订兼容规则和设备绑定验证结果重新推导。
- 不保存 `is_pro`、`last_is_pro`、持久化 `granted_features` 或其他可以脱离 Token 独立授予权益的字段。
- 内存可以缓存当前进程已经验证的不可变 `EntitlementSnapshot`；进程重启后必须重新验证。
- 设置页面、会话记录、数据库字段或本地缓存都不能独立授予专业权益。


## 2. 唯一 AI 权益与协议 Feature

### 2.1 唯一运行时付费权益

当前及后续版本的运行时收费权益只有：

| Feature ID | 含义 | 实施门禁 |
|---|---|---|
| `ai_access` | 允许使用全部 Native LiteRT 本地模型能力 | 仅 Native `AiModelAccessGate` |

以下 ID 是协议修订 1 的历史兼容值，不再作为独立运行时权益，也不得在业务入口分别判断：

- `ai_advanced`
- `contextual_assistant`

`advanced_learning`、`advanced_export` 不属于当前 AI 访问权益，不因本次调整自动开放或收费；纯确定性学习、检索、排盘、辨证、换算和业务执行继续按其原有产品范围处理。

### 2.2 单一权益判断

客户端运行时只推导一个结果：

```text
aiAccess =
  Token 签名有效
  AND issuer / protocolRevision / appId / productId / deviceBinding 有效
  AND Token 对应协议修订声明了有效的 AI 权益
```

- 新协议修订 2 只使用 `ai_access`。
- 修订 1 的历史 Token 按协议兼容表映射：只要签名有效的 Token 声明了 `ai_advanced` 或 `contextual_assistant` 中至少一个，即映射为单一 `ai_access`。这是明确的向前兼容/权益合并规则，不再保留原来的局部功能限制。
- 未声明任何历史 AI Feature 的修订 1 Token 不授予 AI 访问。
- 未知 Feature 继续只作诊断，不授予；不因一个额外未知 Feature 拒绝其他合法 Token。
- 字段类型错误、Feature 列表损坏或重复 ID 仍拒绝 Token。
- 发行端从协议修订 2 起只签发 `ai_access`，不再签发 `ai_advanced` 或 `contextual_assistant`。

### 2.3 免费与专业版边界

需要专业版授权的是**所有实际调用 Native LiteRT 模型进行推理的行为**，不区分入口、模式、调用来源、调用次数或工具数量：

- 普通对话、问诊理解、症状整理、问诊选项理解；
- 学习解释、经典解读、情境提问和结果解释；
- 工具意图识别、参数语义抽取、AI 自动计划生成；
- 文本、图片、语音及后续新增的模型推理模态；
- 用户手动触发但实际调用模型的任何操作。

不需要 AI 权益的确定性操作继续免费，包括规则问诊/辨证、排盘、历法、剂量换算、纯本地查询、书签、阅读、确定性工具手动执行，以及不调用模型的本地数据管理操作。

本产品 Token 是永久 AI 使用授权，不是按请求、Token 数或模型耗时计量的在线用量计费系统。


## 3. Native LiteRT 模型访问统一门禁

### 3.1 唯一收费控制点

`AiModelAccessGate` 是应用唯一的 AI 付费控制点，位于 Android Native LiteRT 模型访问边界。Dart UI、Dispatcher、Gateway、Orchestrator、具体工具或具体 AI 模式均不得另行实现收费规则。

Native 应用进程中的 AI 权益状态默认是关闭；只有 `EntitlementService` 完成 Token 验证并通过内部授权桥同步有效 `aiAccess` 决策后，Native Gate 才允许模型加载和推理。该状态只保存在当前进程内存，不持久化为 `is_pro` 或其他独立授权事实。

### 3.2 必须受保护的模型访问

以下操作必须在 Native 边界经过同一个 Gate：

1. LiteRT Engine 初始化/模型加载；
2. 普通文本推理；
3. 图片和语音推理；
4. 意图识别、参数理解、症状整理、问诊理解；
5. 历史会话恢复中实际触发的模型推理；
6. 后续新增的任何 `Engine`、`Conversation` 或 LiteRT 推理调用。

当前 MethodChannel 的模型调用包括 `loadModel`、`sendMessage`、`sendImage`、`sendAudio`、`resolveAssistantIntent`、`extractBaziSlots`、`extractSymptoms`、`understandTcmInterviewAnswer` 和会执行推理的 `restoreConversation`。新增加的模型方法默认必须受 Gate 保护，不能依赖开发者自行记住某个 Feature ID。

以下不产生模型推理的维护操作不应被误锁：模型状态读取、模型文件导入、backend 偏好设置、Conversation/Engine 释放、运行时缓存清理。它们不得借此重新加载模型或发起推理。

### 3.3 状态与失效处理

- `checking`、无 Token、签名无效、设备不匹配、Key Ring 不可信、`temporarilyUnavailable` 均不得开放模型加载或推理。
- Gate 在进程启动时默认关闭；必须先完成授权验证，再开放模型访问。
- 授权从有效变为无效或暂不可用时，立即拒绝新的模型操作，并按 Native 串行生命周期安全释放 Engine/Conversation；不得遗留可继续接收新推理请求的已加载模型。
- 已经开始的单次推理可按 Native 串行任务的安全收尾策略完成；状态变化之后发起的新请求必须被拒绝。不得重放状态未知的请求。
- 授权错误必须以稳定、可识别的状态返回 Flutter；不能伪装成模型推理错误或空回复。
- UI 可以读取同一权益状态以展示说明，但 UI 禁用按钮不是安全门禁；Native Gate 是最终执行边界。

### 3.4 与确定性业务执行的边界

模型调用完成后，App 仍按现有确定性业务函数执行排盘、辨证、剂量计算和工具操作。没有模型参与的手动确定性操作不需要 AI 权益。

`ToolExecutionPlan`、必填 `InvocationOrigin`、工具 ID / capabilityId 注册映射、参数校验、结果身份/来源验证和 TRACE 继续保留。这些结构用于执行安全、审计和可追溯性，不再决定是否收费。

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
- F0 不引入 AI 收费门禁，不改变既有工具执行行为。
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


## 5. F1：Headless Tool 单一执行分发与计划安全

### 5.1 唯一实际执行入口

所有注册的 Headless Executor 必须只能通过 `HeadlessToolDispatcher` 实际调用。Dispatcher 负责工具注册、完整计划校验、参数/能力映射检查、结果回传与异常规范化；它不再调用 `FeatureAuthorizer`，也不按 `InvocationOrigin`、capability 数量或工具调用次数实施收费。

完整计划仍须在第一个业务副作用前形成并完成全部确定性校验，防止部分执行、伪造工具参数或未注册能力绕过。

### 5.2 执行计划与来源

`ToolExecutionPlan` 保留：

- 稳定 `planId`；
- 必填 `InvocationOrigin`；
- 每个 Step 的工具 ID、业务 `capabilityId` 和经过验证的参数；
- 不可变步骤和参数快照；
- 对全部 Step 的注册、来源、参数与业务前置条件预检。

`InvocationOrigin` 继续用于调用来源、审计、TRACE 和执行语义，不用于收费：
- 用户手动触发确定性操作：`userManual`；
- AI 产生的计划：`aiDispatch`；
- AI 启动的后台延续任务继承 `aiDispatch`。

AI 计划生成时已经调用 Native LiteRT，必须在模型入口通过 `ai_access`；计划一旦形成，Dispatcher 只执行安全校验，不重复收费判断。

### 5.3 结构化拒绝

无效计划、未知工具、能力映射不匹配、参数无效、结果来源错误或执行异常，继续返回结构化拒绝/失败结果。不得将这些业务错误伪装成“未购买专业版”。

### 5.4 其他调用路径审计

继续审计所有 Headless Executor、Page-only 工具、`structured_diagnosis` 内联执行、深链接、Activity 生命周期、后台任务和直接业务 Executor 调用。架构测试继续保证 Executor 只能经 Dispatcher 访问。收费判断不再出现在这些业务入口。


## 6. 情境上下文：来源与锚点完整性，不承担收费

### 6.1 保留 Gateway，不重复实现 Resolver

继续复用既有 `AiContextRef` 和 `AiContextResolver`。所有业务代码仍必须经 `ContextResolutionGateway` 调用 Resolver。Gateway 负责：
- typed/persisted 引用结构和来源类型白名单；
- 请求锚点与当前页面/结果锚点匹配；
- stale、malformed、unsupported source 检查；
- Resolver 返回值与请求来源锚点一致性验证；
- Resolver 异常与来源缺失的独立分类。

Gateway 不再注入 `FeatureAuthorizer`，不再检查 `contextual_assistant`，也不负责判断用户是否购买专业版。

### 6.2 新建、恢复与后续轮次

新会话、恢复历史会话和后续轮次需要重新解析上下文时，仍统一通过 Gateway，防止跨页面、跨结果或过期快照污染模型上下文。Gateway 完成数据完整性验证后，是否允许模型使用由 Native `AiModelAccessGate` 在实际模型加载/推理处统一决定。

无 AI 权益时可以保留本地阅读、历史查看和确定性结果查看；任何模型推理仍会在 Native Gate 被拒绝。不能用 UI 入口、旧会话或直接 Resolver 调用绕过 Native 模型门禁。


## 7. EntitlementService 与单一 AI 权益判断

### 7.1 单一授权接口

不再提供面向多个业务 Feature 的通用收费查询。运行时只需要一个语义明确的异步判断：

```dart
abstract interface class AiModelAccessAuthorizer {
  Future<AiModelAccessDecision> authorizeModelAccess();
}
```

决策状态仍区分：
- `allowed`
- `denied`
- `temporarilyUnavailable`

生产实现继续使用共享初始化 Future 和有界等待（当前上限 2 秒）。超时返回 `temporarilyUnavailable`，不得伪装为永久未授权，不持久化临时拒绝。

### 7.2 单一快照

`EntitlementService` 验证签名 Token、发行者 Key Ring、协议修订、产品/App ID、设备绑定和旧协议兼容映射，发布不可变快照。快照核心权限只保留 `aiAccess` 布尔决策及授权验证状态/失败原因；历史 Feature ID 可作为协议兼容诊断信息，但不得作为多个业务门禁。

不保存 `is_pro`、`last_is_pro` 或可脱离 Token 独立授予权益的持久化状态。

### 7.3 免费降级与生命周期

授权初始化不得阻塞 `runApp()`。启动时 Native AI Gate 默认关闭，基础确定性功能继续启动。激活或 Token 替换成功后更新内存快照并同步 Native Gate，无需重启。授权失效时关闭新模型访问并安全释放 Native 资源。

### 7.4 依赖注入与信任边界

`EntitlementService` 只负责验证凭证与计算 `aiAccess`；内部授权桥将结果同步给唯一 Native Gate。不得让 Screen、Dispatcher、Gateway 各自重复读取 Token 或自行推断权益。测试使用 Fake `AiModelAccessAuthorizer`，Native Gate 默认拒绝。

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
  → Feature 字段结构与协议修订兼容映射验证
  → 当前设备公钥指纹验证
  → 计算单一 `aiAccess`
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
- 新 Token 验证通过且有效 `aiAccess` 不发生 true→false 降级：按用户明确导入操作执行原子替换；
- 只有旧 Token 有效映射为 `aiAccess=true`、新 Token 映射为 `aiAccess=false` 时，才显示失去 AI 访问的提示并要求再次确认；
- 修订 1 的 `ai_advanced` / `contextual_assistant` Token 升级为修订 2 的 `ai_access`，若两者均映射为 `true`，不构成权益降低，也不得仅因 Feature ID 改名要求降级确认；
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
supportedProtocolRevisions = {1, 2}
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

保留授权验证状态：

| 状态 | 说明 | Native LiteRT 模型访问 |
|---|---|---|
| `checking` | 初始化或重新检查中 | 禁止 |
| `active` 且 `aiAccess=true` | Token、发行者、修订和设备绑定通过 | 允许 |
| `unlicensed` | 没有 Token 或没有 AI 权益 | 禁止 |
| `temporarilyUnavailable` | 检查超时或暂时无法确认 | 禁止 |
| `invalid` | 凭证或设备验证失败 | 禁止 |

保留具体失败原因：`storeCorrupt`、`storageUnavailable`、`issuerUnknown`、`signatureInvalid`、`unsupportedRevision`、`deviceMismatch`、`keyMissing`、`keyInvalidated`、`keystoreUnavailable`、`providerError` 等。不能将所有失败混为“未激活”。

### 12.2 UI 与历史数据

- 设置页是激活和状态展示入口，不是收费安全边界。
- 无有效 `ai_access` 时，所有会触发 Native LiteRT 模型推理的操作统一提示需要专业版。
- 无授权不影响确定性业务引擎、阅读、查询、书签和既有本地数据。
- 授权失效不得删除或隐藏助手会话、情境历史、消息或业务结果；历史可以阅读，但不能继续触发模型推理。
- 不得因 AI 门禁失败而伪造空回复、业务失败结果或删除会话。
- 已开始的确定性执行计划不因授权刷新而回滚；新发起的模型推理必须重新检查 Native Gate。


## 13. 实施批次与依赖关系

接口冻结后，允许无依赖工作并行，但必须使用独立工作分支、小批量集成和自动验收。

| 批次 | 范围 | 前置条件 | 合并原则 |
|---|---|---|---|
| A | 冻结协议修订 2、唯一 `ai_access`、旧 Token 映射、Native Gate 状态同步接口 | 无 | 先冻结接口 |
| B | Verifier、Issuer、Fixture、协议修订 1/2 兼容与 Release Key Ring 测试 | A | 合法/非法向量通过 |
| C | Android Keystore Plugin、get-only/create 分离、原子 Token 文件 | A | 原生单测和平台接口通过 |
| D | TokenStore、异步 EntitlementService、单一 AI 权益快照 | A；可先用 Fake Bridge | 独立服务测试通过 |
| F0 | 特征测试、Headless 纯执行分发和 import 图约束，不含收费逻辑 | 当前执行链审计 | 行为不变后独立合并 |
| F1 | 完整 ToolExecutionPlan、确定性执行和结果/来源校验 | F0 | 不承担收费判断 |
| G | ContextResolutionGateway 来源/锚点完整性 | 现有 Resolver | 所有 Resolver 路径通过 |
| E | 专业版设置页、激活导入、单一 AI 状态展示 | D | UI 只消费服务状态 |
| I | Native LiteRT 统一访问门禁、所有模型方法覆盖、Gate 状态同步和释放 | B、C、D | Native 默认关闭，逐入口覆盖 |
| H | 集成、全量回归、Release 和设备验收 | B、C、D、E、F1、G、I | 全部硬门槛满足 |

依赖约束：
- C、D、F0 可并行；
- D 可先用 Fake Bridge，不必等待真实 Android 插件；
- F1/G 不再依赖任何 Feature 收费门禁；
- Native Gate 必须先于所有模型加载/推理，不能只依赖 UI 状态；
- 后续任务必须先读取最新 master、本文和相关子系统约束。

## 14. 验收门槛

### 14.1 协议与签名

- 合法固定向量在 Python Issuer 和 Dart Verifier 均通过；
- 未知发行者返回 `issuerUnknown`；
- 错误签名拒绝；
- 不支持修订拒绝；
- 修订 1 含 `ai_advanced`、`contextual_assistant` 任一项时，兼容映射为 `aiAccess=true`；两者均无则为 false；
- 修订 2 只接受 `ai_access`，发行端也只签发该 ID；
- 修订 2 不得通过旧 ID 自动取得 AI 访问；
- 未知 Feature 忽略且不授予；
- 已知但当前协议修订不允许的 Feature 不授予、记录诊断，不拒绝整份签名有效 Token；
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


### 14.3 Native AI 模型访问门禁

- 无 Token、无 AI 权益、checking、temporarilyUnavailable、签名/设备/Key Ring 错误时，Native LiteRT Engine 不得加载，任何推理方法不得执行；
- 有效 `ai_access` 时允许全部 Native LiteRT 模型推理，不按文本/图片/语音、AI 模式、单工具/多工具、手动/自动调用区分；
- 当前所有 Native 推理方法均通过同一个 `AiModelAccessGate`；
- 新增 Native 推理方法默认被门禁拒绝，必须纳入 Gate 和测试；
- 模型状态、模型导入、backend 偏好、Engine 释放和运行时缓存清理不因未授权而被阻断，但不能绕过 Gate 加载或使用模型；
- 授权失效后拒绝新的推理请求并安全释放模型资源；
- Headless Dispatcher 只负责执行安全校验，手动确定性工具不收费；
- UI 按钮状态不作为授权通过证据，Native Gate 测试才是收费边界验收。


### 14.4 情境上下文来源完整性

- 所有 Resolver 调用只能经 Gateway；
- Gateway 校验引用结构、来源类型、请求锚点、历史快照和解析结果锚点；
- Gateway 不再检查 `contextual_assistant` 或任何付费 Feature；
- 新会话、历史恢复和后续轮次均须验证上下文完整性；
- 所有模型推理仍统一由 Native Gate 决定是否允许。

### 14.5 Release 和升级

- Release 不包含测试公钥原始字节、Base64、Hex 或测试 issuer ID；
- Release Key Ring 工厂行为测试拒绝测试 Token；
- 正式分发 Release 没有生产信任锚时，发布流水线阻断；
- 原版本 APK 可直接升级，不要求卸载；
- 用户数据库、知识库和助手历史不受授权模块升级破坏；
- 授权初始化失败不阻止 App 进入免费功能。


## 15. 当前必须保留为 UNKNOWN 的核验事项

| 事项 | 需要的证据 |
|---|---|
| 所有 Native LiteRT Engine/Conversation 创建和推理调用是否都经过统一 Gate | 全部源码调用点、Analyzer/AST 审计和 Native 方法覆盖测试 |
| Flutter/Dart 是否存在绕过 `LocalAiService` 直接调用 Native AI Channel 的路径 | 全仓 import/channel 搜索及 AST 架构测试 |
| 授权检查结果能否在启动、激活、替换、刷新、失效时正确同步 Native | Dart/Native 集成测试及状态转换回归 |
| 授权失效时已加载 Engine/Conversation 的安全释放和并发处理 | 串行队列测试、Activity recreation 和进程恢复证据 |
| 修订 1 旧 Token 的历史兼容映射 | 固定协议向量、Issuer/Verifier 双向测试 |
| 后台独立 Isolate / FlutterEngine 是否需要单独 AI Gate 同步 | 源码调用链、Engine 创建与任务恢复路径 |
| Find N2 Keystore / StrongBox / AtomicFile 与 Gate 状态同步行为 | 真实设备步骤、日志和 TRACE |
| 生产发行者公钥与真实备用 Key 是否已配置 | Key Ring 内容及发行/备份记录 |
| Release 是否具备非空生产 Key Ring | Release 工厂测试与产物检查 |

没有证据时保持 `UNKNOWN` 或 `MISSING`。不得把 Fake Bridge、Widget 测试、模拟器或设计说明当作 Find N2 真机证据。

## 16. 风险、优势与回滚

| 设计 | 优势 | 风险 / 代价 | 回滚原则 |
|---|---|---|---|
| F0 纯重构与 F1 授权分离 | 行为变化与授权变化可独立定位 | 抽取可能暴露 Screen UI 耦合 | F1 出问题只回滚 F1；保留已验证 F0 |
| 单一 Dispatcher | 执行分发和副作用边界统一，结果可审计 | 现有直接调用必须先收拢 | 恢复到 F0 之前的可验证执行入口 |
| 完整执行计划校验 | 防止无效计划导致部分业务副作用 | 调度协议需要形成完整可验证计划 | 继续校验工具、参数和结果，不引入收费判断 |
| 单 Token 原子文件 | 无数据库迁移，状态简单 | 不适合授权历史/多席位查询 | 保留旧 Token，失败不覆盖 |
| Key Ring 注入与轮换 | 测试/生产信任隔离 | 吊销导致该 Key 全部客户重新签发 | 通过新版信任策略与重新签发恢复 |
| 异步授权状态 | 不阻塞启动，不误判 checking | 初始化超时期间专业操作暂不可用 | 基础免费功能始终可用 |
| Resolver Gateway | 来源引用、锚点和解析结果完整性统一 | 需要收拢所有直接 Resolver 调用 | 保留历史数据，回滚入口而非删除会话 |

离线永久授权无法即时远程撤销；客户端门禁不能阻止有能力修改/重打包 APK 的攻击者。不得用过度混淆代替真实业务边界，也不得将本地挑战签名描述为远程硬件证明。

## 17. 后续执行纪律

1. 每个批次先核对最新 `master`、本文件、相关协议和实际代码调用链。
2. F0 必须先行为测试、后纯重构、再单独合并；不在 F0 中实现收费逻辑。
3. C、D、F0 可以独立分支并行；F1/G 只实现执行安全和来源完整性；Native Gate 使用 Fake 先行。
4. 不能因一个 PR 的 CI 通过，就推定 Find N2、后台 Engine、Keystore 或 Release 信任环验收通过。
5. 不得删除失败测试、降低验收阈值、把 UNKNOWN 改成 PASS 或用模拟数据代替设备实测。
6. 收费边界固定为单一 `ai_access`，门禁只位于 Native LiteRT 模型访问处。若要修改协议字段、旧 Token 兼容映射、门禁位置、存储方案或发行者信任策略，必须先提交设计变更说明，列出兼容影响、风险和回滚方案。
7. 每个实现 PR 必须引用本文对应章节，记录分支基线 SHA、head SHA、文件范围、测试、CI 和未闭环项目。
8. 本文件冻结的是设计约束，不是完成声明；只有实现证据满足第 14 节后，才可将对应任务标记为 PASS。

---

**v1.3 取代 v1.2 中多 Feature 业务收费门禁的设计；v1.2 仍作为历史决策记录。本文是研纪专业版授权后续工程实施的架构约束依据。**


## 18. 2026-11-28 本地/云端统一模型配置与专业版 AI 总开关（v1.4）

> **本节是 v1.3 的正式架构修订。** 若本节与 §1–§17 中“AI 权益仅代表 Native LiteRT”或“唯一收费门禁只能覆盖 Native LiteRT”的表述冲突，以本节为准。旧章节保留为 v1.3 决策记录，不代表本地/云端统一 AI 产品边界。协议 Token 的字段、签名格式、协议修订号和旧 Token 兼容规则均不因本节自动改变。

### 18.1 产品和运行时边界

研纪 AI 采用**本地与云端双运行时**。用户在设置中决定是否启用 AI、配置本地模型或云端供应商，并按任务能力指定模型。App 忠实使用用户保存的配置；不根据模型名称推断能力，不执行能力探测，不擅自寻找替代模型。

本架构不按问诊、学习、工具、玄学等助手角色绑定不同模型。助手场景共享任务能力配置；场景级模型覆盖属于后续独立需求，不进入首期范围。

本地与云端是同级可选运行时，不存在“云端优先”或“本地优先”的全局自动策略：
- 本地模型通过对应本地运行时 Adapter 执行。现有 Gemma 4 E4B 仍使用 LocalAiService、Android Native LiteRT-LM Engine/Conversation、现有 GPU/CPU 选择和串行生命周期；不得将云端 HTTP 调用并入 Native E4B 队列。
- 云端模型通过供应商 Adapter 发送 HTTP 请求；不调用 Native LiteRT，也不借用 AiModelAccessGate 作为云端 HTTP 实现。
- ReasoningRequest、ReasoningResponse、现有严格 Codec、来源校验、会话记忆和确定性业务执行边界继续作为统一推理合同。具体 Adapter 负责供应商载荷转换，不改变 App 的来源与执行权威边界。
- 五层仍是职责边界，不因增加模型运行时而新建 Agent、DAG、第二套会话库或替代业务规则。

### 18.2 一个专业版权益 + 一个用户 AI 总开关

运行时仍只有一个签名授权权益 ai_access，不新增 cloud_ai_access、embedding_access、reranker_access 或按任务拆分的付费 Feature。

设置页提供统一的“启用 AI 功能”开关。它是用户偏好，不是授权事实，也不能自行授予专业权益。

统一可用条件：

    aiEnabledForRuntime =
      EntitlementService.snapshot.aiAccess == true
      AND userAiEnabled == true
      AND entitlementStatus is currently usable

强制规则：
1. 非专业版、授权检查中、授权无效、授权存储/验签暂不可用时，用户不能开启 AI；所有本地和云端模型调用都必须 fail-closed。
2. 专业版有效但用户关闭 AI 时，禁止发起新的本地模型、云端 LLM、多模态模型、Embedding 和 Reranker 调用。
3. 专业版有效且用户开启 AI 后，才允许按照模型配置发起上述调用。
4. 新安装或缺少已保存偏好时，AI 总开关默认关闭；升级安装保留已保存设置。专业版授权恢复不自动把用户开关改为开启。
5. 关闭 AI 不删除模型文件、供应商配置、API Key、索引、会话或历史数据。Native 已加载模型按现有串行队列安全释放；对已经发出且供应商可能已接收的 HTTP 请求，不谎称可以撤回，阻止后续请求并保留实际结果状态。
6. 授权失效与用户关闭开关都保留用户配置。恢复授权后仍遵守用户最后保存的开关状态。
7. 确定性业务、阅读、书签、本地资料浏览，以及未启用模型检索时的既有确定性知识召回/排序，不因 AI 开关关闭或专业版失效而被禁用。

职责边界：
- EntitlementService 继续是专业版授权唯一事实来源；不得在 SettingsRepository、SQLite、Provider Repository 或 UI 中保存可独立授予专业版的 is_pro / cloudAccess。
- 用户 AI 开关只保存为普通用户偏好；其值必须与授权结果取逻辑 AND，不能绕过授权。
- Android AiModelAccessGate 保留为 Native LiteRT 模型加载/推理的最终边界，并由统一 AI 状态同步。它不处理云端 HTTP，也不替代 Dart 层的云端调用前检查。
- 统一模型 Gateway/任务入口必须在每次 AI 调用前检查同一 aiEnabledForRuntime。云端 Adapter 不得成为绕过该检查的可直接调用入口。
- Headless Dispatcher、工具参数校验和确定性业务执行仍按既有合同执行；AI 开关不收费或重写纯确定性工具，但关闭 AI 后不得再让模型生成动作提案。

### 18.3 供应商、模型与任务能力配置

设置页配置分为供应商/模型管理、默认推理模型、任务能力模型和 AI 总开关。模型由用户选择，不显示每次调用的路由原因或额外的 ResolvedRoute 详情。

首期任务能力键固定为：

| 任务键 | 模型类型 | 配置规则 | 未单独配置时 |
|---|---|---|---|
| text_reasoning | 生成式语言模型 | 必须配置一个默认推理模型（可选本地或云端） | 没有默认模型时明确提示未配置，不自动找模型 |
| image_understanding | 支持图像输入的生成式模型 | 可指定本地或云端模型 | 跟随默认推理模型；实际接口不支持时明确提示 |
| audio_understanding | 支持音频输入的生成式模型 | 可指定本地或云端模型 | 跟随默认推理模型；实际接口不支持时明确提示 |
| embedding | 向量嵌入模型 | 可指定本地或云端专用模型 | 不调用模型，保持现有确定性召回 |
| reranking | 候选重排模型 | 可指定本地或云端专用模型 | 不调用模型，保持现有确定性排序 |

约束：
- 每种任务模型都允许选择已配置的本地模型或云端模型；Embedding 和 Reranker 必须同时建设本地模型与云端模型的配置、存储和实际调用路径，不得只完成云端。
- 图片和音频任务默认继承默认推理模型。继承只表示按用户配置向同一模型发起该模态请求，不表示 App 已验证它支持该模态。供应商或本地运行时返回不支持时，明确向用户提示；不自动改用 E4B、不切换其他云端供应商。
- Embedding/Reranker 是独立任务，不继承普通文本推理模型；不得把普通聊天模型默认当作向量模型或重排模型。
- 用户选择的具体模型及其任务配置由设置页持久化；模型列表 API 只用于获取供应商实际返回的模型 ID/展示名。不能把模型列表存在当成能力声明。
- 不建设模型能力探测、探针、内置模型能力表、基于模型名称的自动判断或自动确权流程。模型不支持时，以实际调用返回的错误为准。
- 不显示每轮实际模型路由明细、路由原因或能力证据面板；普通错误只说明当前任务配置的模型不能完成该任务及相应错误。
- 按助手场景绑定不同 LLM 延后，不在首期设置中开放。

### 18.4 默认模型、显式任务模型与失败行为

ModelCapabilityResolver 只解析用户配置，不探测模型能力，不根据模型元数据或名称改写用户选择。

静态配置解析：
1. text_reasoning 使用用户配置的默认推理模型；未配置则返回“默认推理模型未配置”。
2. image_understanding / audio_understanding 有专用任务模型时使用专用模型；未配置时使用默认推理模型。
3. embedding / reranking 有专用任务模型时使用所选模型；未配置时分别维持既有确定性召回/排序。
4. 配置引用的供应商、凭证或本地模型文件不存在时，返回可操作的配置错误；不得静默改指向默认模型或其他供应商。用户主动将任务设为“跟随默认”属于配置继承，不是运行期自动降级。
5. 模型被删除或凭证丢失后，相关任务显示未配置/凭证缺失，不能崩溃，也不能自动选取另一模型。

运行期行为：
- 一旦按配置选定模型并发起请求，HTTP/Native 调用失败、模型不支持、鉴权失败、配额不足、参数不兼容或结构化输出解析失败，均返回明确错误，不在异常处理分支自动切换到其他模型。
- 禁止云端供应商 A 自动切换到云端供应商 B；禁止云端失败后静默切回本地；禁止本地失败后自动上传云端。
- 不自动执行第二次推理来修复 JSON/Codec 失败。确需重新请求时必须由用户主动再次发送；不得重复计费或将失败载荷写入成功 transcript。
- 请求已发出但连接中断、超时或客户端未收到最终响应，可能已被供应商处理时标记 UNKNOWN；不自动重放，不自动换模型。
- HTTP 响应明确表示任务不支持时，给出任务/模型不支持提示。实际 API 错误才是反馈，不提前探测或保证供应商能力。
- 现有 ReasoningResponseCodec 继续严格校验；结构化响应不合格时拒绝提交成功回合，维持现有 finalizeReasoningTurn / rejectReasoningTurn 双阶段提交语义。

### 18.5 Embedding：本地与云端均为首期任务能力

Embedding 必须作为知识召回层的真实可配置模型能力实现，不是仅在设置页增加下拉框。

调用链：
    Knowledge query / source chunk
      -> configured local or cloud Embedding Adapter
      -> numeric vector + model identity/version/dimension
      -> App-owned local embedding index
      -> CandidateEvidence with existing sourceId/chunkId/locator
      -> existing multi-source aggregation and evidence validation

数据和索引约束：
- 查询向量和文档向量必须来自同一兼容的模型身份、模型版本、向量维度、归一化/距离配置；不允许将不同模型空间的向量混用。
- 每个 Embedding 索引必须记录至少：provider/runtime、模型配置 ID、模型 ID 或本地模型指纹、模型版本/修订、向量维度、归一化策略、索引 schema 版本、被嵌入内容的稳定 source/chunk ID、内容哈希和索引 generation。
- 切换 Embedding 模型或改变维度/归一化策略时，建立新 generation 并重新嵌入对应资料。新 generation 完整构建并通过一致性检查后再原子切换活动索引；旧 generation 在切换成功前保留，失败不得破坏现有可用检索。
- 索引数据是派生缓存，不是来源事实。原始知识正文、sourceId、verificationStatus、locator 和资料版本仍由 App 原数据层管理。
- 模型输出向量必须校验有限数值、维度、空向量和协议返回结构；向量相似度只代表当前检索相关性信号，不代表医学正确性、来源权威或事实置信度。
- Embedding 命中只能形成 CandidateEvidence，必须继续进入现有来源身份检查、证据聚合和排序边界；模型不得生成 sourceId 或伪造本地条目。
- 没有 Embedding 配置时，现有关键词、实体、别名和结构化本地检索行为保持不变。显式配置后实际调用所选 Embedding；该模型调用失败必须如实报告召回失败，不伪装成 Embedding 成功，也不静默切换到其他 Embedding。
- 向量索引存储/检索方案先在现有 SQLite/本地存储边界内测量数据规模、构建耗时、查询耗时、内存和文件体积；只有测试证明现有存储/检索结构不足，才单独提出引入额外向量数据库/索引依赖的决策。不能因已允许 Embedding 就自动引入新数据库。

### 18.6 Reranker：本地与云端均为首期任务能力

Reranker 必须作为知识证据排序层的真实可配置模型能力实现。

调用链：
    existing retrieval channels
      -> bounded CandidateEvidence list
      -> configured local or cloud Reranker Adapter
      -> ordered candidate IDs
      -> App verifies IDs against input candidate set
      -> RankedEvidenceSet
      -> existing source resolution and context builder

约束：
- Reranker 只能重排本轮实际召回且已提供给它的候选；不能创建候选、添加 sourceId、改写正文、修改来源版本、来源类别或 verificationStatus。
- App 必须校验返回候选 ID 全部属于本轮输入集合、没有重复/未知 ID、排序输出符合合同；不接受模型自报的来源可信度或医学正确性分数。
- Reranker 的排序结果只决定当前候选的相对顺序；不得替代来源校验，也不得把相关性分数展示/解释成事实置信度。
- 没有 Reranker 配置时，继续现有 SourceAwareLegacyEvidenceRanker 确定性排序和黄金行为；显式配置后调用所选本地/云端 Reranker。所选模型失败或输出不符合合同，记录该次排序失败并提示用户，不自动切换另一个 Reranker 或将失败伪装为成功。
- 现有 CandidateEvidence、MultiSourceEvidencePipeline、RankedEvidenceSet 和 source resolver 是复用基础；不得为 Reranker 重建新一套知识库、来源体系或排序状态库。

### 18.7 本地 Embedding / Reranker 模型运行时

本地 Embedding 与本地 Reranker 必须作为真实任务模型配置和本地运行时接入，不得因为 E4B 已接入 LiteRT-LM 就假定这两类模型可以使用同一引擎。

- 本地模型目录应能区分 LLM、IMAGE/AUDIO（若由独立本地模型承担）、EMBEDDING、RERANKER 等模型用途；同一模型文件可以被多个任务引用，但实际运行时必须通过该模型格式对应的 Adapter 加载。
- 每种本地模型需明确模型格式、运行库、Tokenizer/预处理、输入长度、输出维度/排序合同、设备后端、内存占用、关闭/释放方式和模型文件完整性验证。未被真实 runtime 支持的文件类型不能仅因导入成功就标记可用。
- 现有 LocalAiService / Native E4B Engine 仍只承担当前 E4B 已实现的推理路径；不要把 Embedding/Reranker 请求送入 E4B 的普通聊天接口。
- 当前 master@8f947cdb 的目录/源码审计没有找到可确认的独立本地 Embedding 或 Reranker 运行时调用链。此项当前状态为 MISSING / NEEDS LOCAL AUDIT，不能写成已实现；由独立 Local 工作流核对 LiteRT-LM/其他兼容运行库、模型格式、Find N2 资源和性能后，形成最小实现方案。
- 本地 Embedding/Reranker 的模型导入、文件存储与 SHA 校验、模型配置选择、运行时创建/释放、索引构建/查询、错误状态和测试必须与云端 Adapter 分开验收；不得将云端 Mock 测试作为本地模型实际运行证据。
- 新增依赖、独立模型目录、数据库 schema/index、下载或模型分发服务均须按仓库规则先给出收益/风险、数据规模与设备资源证据、替代方案和回滚路径；没有用户决策前不得扩张基础设施。

### 18.8 生成模型上下文窗口配置

默认推理、独立图片理解和独立音频理解若属于生成式模型，每个模型配置可保存用户声明的 contextWindowTokens，并可设置 maxOutputTokens。Embedding/Reranker 不使用生成模型上下文窗口设置。

- 设置页可提供常见预设及自定义整数 Token 数（例如 16K、32K、64K、128K、200K、256K、512K、1M）；预设只是方便输入的配置值，不是 App 对供应商能力的保证。
- 用户按所购模型供应商的规格填写；App 不读取模型名称推断窗口、不主动探测，也不在供应商不支持时静默改小、改模型或换供应商。
- 云端 Adapter 必须按配置的上下文预算组装本轮输入：系统提示、当前输入、已选完整会话历史、检索证据和工具结果都属于同一预算；输出预留单独计入 maxOutputTokens。超出用户配置预算时按完整轮次/证据块边界裁剪并明确记录遗漏，不得任意切断来源或把字符数冒充 Token 数。
- Token 计数必须使用对应模型/供应商可用的 Tokenizer 或实际运行时 token 统计。若当前无法准确取得 Token 数，显式记录 UNKNOWN；不得以固定字符比例宣称精确 Token 预算。请求因上下文超限被供应商拒绝时，明确返回错误，不偷偷换模型或重放。
- 对本地模型，用户输入值不得超过模型声明、Native Runtime 限制和设备实测可用预算中的实际边界。现有 E4B 的 ModelInfo.maxContextTokens() 与 KV Cache token 数只是只读观测，不代表 Find N2 可稳定使用的 App 输入预算；在真实设备校准前继续保留 NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED，不将 1M 设置强加给 E4B。
- 模型上下文窗口不等于长期记忆。会话持久化、跨进程 transcript 恢复、SessionState provenance 和既有会话边界继续由现有会话体系管理；不能因云端模型声明 1M 就无限重放 SQLite 历史或放宽用户确认/执行状态约束。
- 当前本地 Native 成功 transcript 的 12 个完整轮次/10,000 UTF-16 限制属于 E4B 恢复合同，不能无测试地套用或删除；云端长上下文需单独实现模型 token budget 下的完整轮次投影和证据预算。

### 18.9 供应商和凭证的最小边界

- 一个供应商可以有多个独立连接配置；每个连接包含用户填写的 Base URL、协议适配类型、脱敏显示名称、模型 ID 清单和凭证引用。模型目录仅表示供应商返回了哪些 ID，不代表模型支持何种输入能力。
- 支持供应商模型列表接口时自动获取模型 ID；不支持时允许手动填写模型 ID。连接测试只验证 API Key/地址/接口连通，不调用图片、音频、Embedding、Reranker 探针，也不产生隐式模型推理费用。
- API Key 不得明文存入 user_settings/SQLite、日志、TRACE、异常或 PR；凭证由独立 ProviderCredentialVault 保护，不复用 LicenseKeystore 的设备签名私钥。
- Android 侧优先采用 Android Keystore 保护的独立加密密钥与 authenticated encryption（例如 AES-GCM），密文保存在 App 私有存储；凭证文件排除 Android Auto Backup。备份恢复后若密文无法解密，显示凭证缺失并允许用户重新输入，不删除供应商元数据。
- 云端请求强制 HTTPS；自定义 Base URL 由用户自行填写时，清楚提示该 API Key 将发送到该地址。重定向到不同 origin 时不得转发 Authorization / api-key 凭证头。禁止记录密钥、完整认证请求头或敏感正文。
- 不增加供应商逐家隐私确认、每种数据的隐私开关或每轮隐私确认弹窗；用户配置云端供应商本身即选择云端服务。供应商和模型名称由设置页管理，不在每轮对话额外展示路由原因。
- 用户删除供应商或模型时，必须处理被默认模型/任务模型引用的配置关系；先解除引用并将对应任务置为未配置，再清除凭证，不得留下崩溃性悬空引用。

### 18.10 模型配置数据与变更兼容

配置数据只存储模型选择和运行所需的非敏感元数据；凭证密文走 Credential Vault。建议最小逻辑实体如下，不要求机械采用同名 SQL 表：

- ProviderConfig：providerConfigId、provider/protocol 类型、displayName、baseUrl、credentialRef、模型目录缓存、创建/更新时间。
- ModelConfig：modelConfigId、local/cloud runtime、providerConfigId（本地为空）、modelId/modelFileFingerprint、task family、userContextWindowTokens（仅生成模型）、maxOutputTokens、必要的本地模型格式/版本元数据。
- TaskModelSelection：taskKey、modelConfigId 或显式 FOLLOW_DEFAULT / UNCONFIGURED。text_reasoning 必须指向默认模型；图片/音频可跟随默认；Embedding/Reranker 未配置时保持确定性路径。
- Embedding index metadata：模型空间指纹、维度、归一化、schema/generation 和 source/content hash；向量正文是派生索引数据，不是来源权威信息。

存储实现须沿用现有数据库迁移纪律，迁移可重复、可回滚；不得创建第二套用户设置库或专业版授权库。模型/供应商删除、改名、API Key 替换和模型变更必须分别测试；已有有效配置不能被一次失败的连接测试或模型列表刷新覆盖。

### 18.11 本地—远程双工作流和实施分工

该能力必须按仓库 docs/parallel-execution-and-integration-spec.md 与 docs/ai-parallel-execution-protocol.md 执行；master 是唯一集成基线，Local 与 Remote 可以并行，但单个文件/缺陷只有一个写入 Owner。

| 工作流 | 本任务责任 | 明确不负责 |
|---|---|---|
| Local | 本地 Embedding/Reranker 运行库、模型文件格式、Tokenizer/预处理、Find N2 内存/耗时/后台索引和真实模型运行验证；E4B 本地多模态设备场景 | 不修改远端共享架构/执行台账文件；不把模拟结果写为设备 PASS |
| Remote | Provider API、Credential Vault、默认与任务模型设置、统一 Gateway、云端 Embedding/Reranker Adapter、SQLite 配置/索引方案与自动化测试 | 不宣称本地模型运行时或 Find N2 通过；不替代 Local 的设备 TRACE |
| Architecture | 冻结公共任务键、配置 DTO、错误语义、授权状态和本地/云端 Adapter 接口；审查五层边界 | 不直接把规范文本当成运行时代码完成 |
| Integration | 从最新 master 分支基线、文件所有权、PR 顺序、CI、合并后主线同步和执行台账 | 不在多个分支同时写同一共享文件 |

依赖与并行：
1. 公共 Task Capability、Provider/Model 配置 DTO、Credential Vault 接口、AI 总开关状态合同先冻结；随后 Local 与 Remote 可在不同文件所有权范围内并行实现。
2. Local Embedding 与 Local Reranker 可分别拆独立任务/分支，但若共享模型加载器、文件导入、索引 Schema 或同一 Native 模块，必须先指定单一 Owner 并按接口串行。
3. Cloud provider adapters 与设置 UI 可在公共 DTO 冻结后并行；Cloud Embedding/Reranker 与本地执行不共享运行时生命周期。
4. Embedding 索引建造与 Reranker 可分支开发，但 Reranker 的输入合同必须消费既有 CandidateEvidence；Embedding 的向量候选必须能够回到既有 sourceId/chunkId。
5. 任一 Local 设备任务阻塞，不冻结无依赖的供应商管理、设置 UI、配置持久化、云端 Adapter 和 Dart/Kotlin 自动化工作。
6. 任何 PR 必须以完整 SHA 为基线，并对最终 HEAD 执行仓库 required checks；分支级 changed tests 不替代 Flutter 全回归、Android arm64/JVM 或 Fork License。
7. 共享架构文档由 Architecture 单写，执行台账由 Integration 单写，设备验收交接单由 Local 单写。普通实现 PR 不顺手改共享治理文件。

### 18.12 实施切片和验收门槛

按小批量、可独立回滚实施，不以设置页面出现选项作为能力完成：

| 切片 | 工作内容 | 主要验收 |
|---|---|---|
| A. 统一 AI 状态 | 专业版 ai_access + 用户 AI 开关；Native Gate 同步；云端 Gateway 调用前门禁 | 非专业版/关闭开关时，本地与云端、Embedding/Reranker 都 fail-closed；确定性功能继续可用；关闭后本地资源按队列释放 |
| B. 供应商与本地模型配置 | Provider Repository、Credential Vault、模型列表/手动添加、本地模型注册与文件校验 | Key 无明文泄漏；多个供应商可独立保存/编辑/删除；失效凭证可恢复；已有配置不丢失 |
| C. 默认推理与上下文预算 | 默认文本模型、图片/音频跟随默认或专用模型、每个生成模型 context/output Token 配置 | 配置真实进入请求组装和会话历史预算；不把 1M 当作本地 E4B 的可用值；超限显式失败/裁剪记录 |
| D. 云端文本/图片/音频 | 供应商 Adapter、统一 ReasoningRequest/Response、附件输入和 Codec 校验 | 用户选哪个就发哪个；供应商不支持时提示；无自动换供应商/本地、无 UNKNOWN 重放 |
| E. 本地 Embedding | 本地模型导入/校验/运行、向量构建/查询、本地索引版本切换 | Find N2 真实模型加载、向量维度、查询、重建和稳定性 TRACE；旧索引可回滚 |
| F. 云端 Embedding | API Adapter、向量缓存/索引元数据、失败状态 | query/document 使用兼容模型空间；超时 UNKNOWN 不自动重发；来源 ID 回链完整 |
| G. 本地 Reranker | 本地模型文件、Tokenizer、打分/排序执行、候选 ID 回校验 | Find N2 真实运行和资源 TRACE；输出仅重排输入候选 |
| H. 云端 Reranker | Provider Adapter、候选片段请求、排序输出校验 | 只返回本轮候选 ID 排序；供应商错误明确失败，不自动回退 |
| I. 集成回归 | 本地/云端组合、开关状态、授权失效、删除供应商、索引迁移、来源完整性 | 单位/状态清晰；无 AI 绕过、无悬空引用、无来源丢失；所有 required checks 按最终 HEAD 通过 |

关键负向验收：
- 非专业版不能开启 AI；仅 UI 禁用不够，调用入口与 Native Gate 必须 fail-closed。
- AI 关闭时，直接调用 Dart Cloud Adapter、Embedding/Reranker Adapter 或 Native LiteRT 的尝试均被拒绝。
- 删除供应商、清除 API Key、删除本地模型或切换模型不允许让设置页/推理页崩溃。
- 未配置 Embedding/Reranker 走既有确定性路径；配置后不支持/接口失败，显示明确失败，不偷偷当作旧模型成功。
- 模型调用结果 UNKNOWN 不自动重放；失败响应不写入成功会话轮次。
- Embedding 模型切换后不能混用旧向量；重建未完成时保留最后一个完整索引。
- Reranker 返回未知/重复/伪造候选 ID 必须拒绝。
- 1M context 配置不能绕过模型/运行时/设备硬上限，也不能把字符计数称为 Token 计数。
- UI 场景模型绑定、供应商能力探针、用户每轮隐私确认、逐数据隐私开关和自动切换均不进入首期。

### 18.13 优势、风险与回滚

| 方案 | 优势 | 风险/代价 | 回滚边界 |
|---|---|---|---|
| 一个 AI 开关 + 一个 ai_access | 本地/云端收费边界一致，避免重复权益 | 需把现有授权—Native Gate 同步扩展为统一可用状态 | 回滚统一调用层；保留 Token 格式和旧授权兼容 |
| 用户按任务配置模型 | 贴合真实购买/API 能力，配置直观 | 不支持的模型由用户自行更换 | 保留配置，返回明确能力错误 |
| 本地/云端双 Embedding/Reranker | 设备离线与云端质量/算力选择可控 | 本地模型格式、耗时、内存、索引重建需设备实测 | 新索引失败保留旧 generation；模型 Adapter 独立回滚 |
| 用户配置上下文窗口 | 能把长上下文模型的能力用于长对话 | Tokenizer 差异、费用、输入预算和本地设备限制 | 回滚到既有有界 transcript 行为，不丢历史 |
| 不做探测/自动切换 | 避免模型能力假设、意外数据外发和重复扣费 | 用户可能选择不支持任务的模型 | 显示真实错误，不需要恢复自动策略 |

### 18.14 本轮文件基线与当前未完成状态

- **规范修订基线：** master@8f947cdb481c31c86d607c0d4683f8dc69f85272。本节由独立 Architecture 文档 PR 承载，不在 master 上直接修改。
- **当前已确认的代码锚点：** SettingsScreen、LocalAiBackendSettingsTile、LocalAiService、EntitlementService、AiModelAccessGate、ReasoningRequest、ReasoningResponse、ReasoningResponseCodec、AssistantKnowledgeContextBuilder、MultiSourceEvidencePipeline、SourceAwareLegacyEvidenceRanker、LocalAiModelImportRecovery。
- **当前已确认限制：** 仓库现有本地模型运行时明确对应 Android Gemma 4 E4B LiteRT-LM；当前 master 源码树未发现可确认的独立本地 Embedding 或 Reranker Adapter 和调用链，因此保持 MISSING / NEEDS LOCAL AUDIT，不能写成已实现；云端模型、Credential Vault、统一 Model Gateway、任务模型配置、1M context 端到端预算、Embedding index 和 Reranker Adapter 也都尚未实现。
- **开放 PR 文件冲突：** PR #539 修改 ai-capability-audit.md、ai-layered-runtime-architecture.md 和 ai-modernization-execution-ledger.md；PR #416 修改 pro-edition-license-protocol.md。依据仓库单写者规则，本 PR 不覆盖这些文件、不擅自关闭/重写在途 PR。待 Integration 完成两个 PR 的逐文件归属/处置后，分别由 Architecture 与 Integration 以当时最新 master 同步本节到五层规范、审计规范、授权协议和执行台账。
- **远端任务登记：** PR #625（Task ID DOC-CLOUD-MODEL-ARCH-20261128），允许文件仅 docs/pro-edition-architecture-constraints.md。
- **本地任务登记：** PR #626（Task ID LOCAL-MODEL-EMBED-RERANK-AUDIT-20261128），Local 工作流负责只读核查本地 Embedding/Reranker 模型格式、运行库、Find N2 资源和设备能力；无设备证据保持 MISSING / UNKNOWN / LOCAL ONLY。
- **本节状态：** 架构决策已冻结；所有实现任务仍为 NOT_STARTED / MISSING，不得把本规范文本或 Draft PR 任务登记卡视为代码/设备完成。

---

**v1.4 在保留 v1.3 授权 Token 与 ai_access 唯一性基础上，正式扩展 AI 可用范围到本地/云端推理及按任务配置的 Embedding/Reranker；不新增签名 Feature，不改变既有 Token wire format。**
