# AI-MODEL-GATEWAY-20261128 — Stage 2 统一门禁与 Model Gateway

> 状态：REGISTERED / IMPLEMENTATION NOT STARTED
> Master 基线：56baacebd08e8e90e818471ba558ceff209b9ca7
> Owner：Remote（运行时实现）；Integration（台账与 Fork License inventory 单写）
> 依据：完整模型开发方案 §5.3、§5.5、§10、§14、§15、§16

## 1. 任务目标

在 Stage 1 已合入的 ProviderConfig、ModelConfig、TaskModelSelection、Credential Vault 与 schema v9 之上，实现唯一 AI 总开关、运行时授权协调器、五类 taskKey 配置解析和统一 Gateway/HTTP transport 安全边界。

本阶段只建立可验证的门禁与请求编排基础，不宣称已有真实 Cloud Provider Adapter 或云端模型调用。Stage 3 才实现第一个真实文本 Provider Adapter/SSE。

## 2. 前置依赖

- Stage 1 已合并：master 基线 56baacebd08e8e90e818471ba558ceff209b9ca7，PR #629 与 post-merge Push CI 已闭环。
- Native Gate enable 时序修复 PR #633 必须先在最新 master 合并并通过五项门禁。PR #633 单独拥有 MainActivity.kt 与 native_ai_access_gate_architecture_test.dart；Stage 2 不得并行修改这些文件或 AiModelAccessGate.kt。
- 实施代码分支必须在 PR #633 合并后重新读取最新 master，并 fast-forward/rebase 到新 SHA；当前登记基线不是未来代码分支的永久基线。
- Architecture 负责五层架构规范；Audit 负责 AI 能力审计规范；Integration 单写执行台账。

## 3. 文件所有权

Remote 允许范围（实施前全仓检索并复用，不机械建文件）：
- 新增候选：lib/services/ai_runtime_access_coordinator.dart
- 新增候选：lib/services/ai_task_model_resolver.dart
- 新增候选：lib/services/ai_model_gateway.dart
- 新增候选：lib/services/ai_http_transport.dart
- 修改：lib/services/entitlement_service.dart（收敛为授权事实源，避免和 Coordinator 双写 Native Gate）
- 修改：lib/data/settings_repository.dart（复用 user_settings，新增 ai_enabled 偏好）
- 修改：lib/main.dart（Coordinator 唯一装配入口）
- 修改：lib/screens/settings_screen.dart（唯一 AI 总开关）
- 新增/修改 Coordinator、Resolver、Gateway、transport、Entitlement、Settings 相关测试。

明确不允许：
- 不修改 MainActivity.kt、AiModelAccessGate.kt、AiModelAccessPlatform 的公共通道合同；Native Gate 修复由 PR #633 单独完成。
- 不修改 DatabaseHelper schema/version，不新增数据库或第二份模型配置库；ai_enabled 使用现有 user_settings。
- 不改变 Stage 1 DTO、taskKey、credentialRef、License Token wire format；不新增 cloud_ai_access 或其他独立 Feature。
- 不实现供应商专属 Adapter、SSE 解析和真实模型请求；这些属于 Stage 3/4。
- 不接入本地 Embedding/Reranker runtime、VectorIndexStore、IndexGeneration 或 AssistantKnowledgeContext；Local #626 只读审计继续独立推进。
- 不修改 Native E4B 业务 prompt、历史投影、业务工具和确定性 TCM 逻辑。

## 4. 必须保持的数据与授权语义

有效 AI 访问必须同时满足：verified ai_access AND EntitlementService.status == active AND user ai_enabled == true。
- ai_enabled 是用户偏好，不是 License Feature，也不能写入/伪造 EntitlementSnapshot。
- 为兼容 Stage 1 前已获授权且已使用 AI 的用户，ai_enabled 在数据库缺失时按 true 解释；不得迁移时批量写入 false。无有效 ai_access 时 effective access 仍为 false。
- Coordinator 是唯一负责把 effective access 同步到既有 AiModelAccessPlatform 的 Dart 写入者。EntitlementService 只提供经验证的授权事实；不得与 Coordinator 双写 Native Gate。
- 启动、授权刷新、AI 开关变化、应用恢复/重试时都要处理 checking/timeout/storageUnavailable/invalid/unknown；除明确 active 且开关开启外一律 fail-closed。
- disable 必须先同步撤销新请求入口，再等待 Native 返回真实 released=true；release 未确认不得报告资源已释放。
- generation/epoch 防止旧异步 enable 覆盖新的 disable；enable acknowledgement timeout 或状态不确定时，尝试关闭并将状态保留 UNKNOWN/temporarilyUnavailable。
- 用户关闭 AI 不删除授权 Token、Provider/Model 配置、凭证、模型文件、索引、历史或 TRACE 数据。

## 5. 五类 taskKey 解析合同

| taskKey | 允许选择 | 未配置语义 |
|---|---|---|
| text_reasoning | explicit | MODEL_NOT_CONFIGURED |
| image_understanding | explicit / inherit_text_reasoning | 继承时重新解析默认文本模型 |
| audio_understanding | explicit / inherit_text_reasoning | 继承时重新解析默认文本模型 |
| embedding | explicit / deterministic_unconfigured | 走既有确定性召回，不假装有向量模型 |
| reranking | explicit / deterministic_unconfigured | 走既有确定性排序，不假装有模型重排 |

显式模型请求前必须核验 taskKind 一致、ModelConfig enabled、Provider enabled、credentialRef 存在且 Vault.exists 为 true；Local 资产必须 installStatus=installed。缺失、禁用、错误或 UNKNOWN 一律返回稳定错误码，不静默换模型。

## 6. Gateway 与 HTTP transport 范围

- Gateway 每次请求重新执行 entitlement + 用户 AI 开关 + taskKey/ModelConfig/Provider/Credential/Local asset gate；UI 状态不能替代调用层门禁。
- Gateway 不直接暴露 SQL、文件、License Token、Native Engine 或业务执行器；凭证明文仅作为调用期参数，不存单例/状态/日志。
- 为适配器注册与请求/响应类型建立明确接口；未注册的 Provider/任务返回 ADAPTER_NOT_REGISTERED，不得返回伪造成功。
- HTTP transport 建立 HTTPS only、禁 URL userinfo、TLS verification on、拒绝跨 Origin/降级重定向、连接/请求超时、响应体/上传体大小上限和安全错误映射；不加入自动重试。
- 本阶段不发送真实供应商请求、不在配置保存时 ping、不拉取供应商模型清单。真实文本 Provider/SSE 在 Stage 3 单独做端到端任务。

## 7. 自动验收

1. ai_enabled 缺失默认 true；false/true 持久化和重启恢复；用户关闭不会被授权 refresh 自动打开。
2. 无 Token、invalid、checking、timeout、storageUnavailable、unknown、缺少 ai_access 均 fail-closed。
3. entitlement active + AI 开启时 Gate enable 同步成功；关闭时先 revoke，再等待 Native release；过期 enable 不覆盖新状态。
4. 并发开关、授权刷新、启动初始化按 epoch/generation 串行化；Native ack 丢失/超时不发布已开启。
5. 五个 taskKey 每一种 explicit/inherit/deterministic/unconfigured 的正反向矩阵。
6. Provider disabled、credentialRef missing/unknown、Vault read/exists failure、Model disabled、Local asset missing/uninstalled、taskKind mismatch 均 fail-closed。
7. Gateway 不存在 adapter 时返回 NOT_CONFIGURED/ADAPTER_NOT_REGISTERED；配置/打开页面不发生网络请求。
8. HTTP transport 拒绝 HTTP、userinfo、跨 Origin 重定向、降级重定向；覆盖 timeout、响应体上限和错误脱敏。
9. 关闭 AI 不删除数据库配置、凭证、模型文件、索引、会话和 License Token。
10. 既有 Native E4B、授权生命周期和设置行为回归通过；无测试删除、无 SKIPPED 替代 PASS。

PR 最终 HEAD 五项门禁必须全部 SUCCESS：Branch validation、Flutter regression、Android arm64/JVM、PR required gate、Fork License。合并后独立核验最新 master Push CI。

## 8. 回滚边界

- 回滚 Coordinator/Gateway 代码时保留 user_settings.ai_enabled 用户偏好和 Stage 1 配置/凭证；不得把偏好重置为 false。
- 先关闭新 Gateway 请求入口，再回退 adapter registry/transport；Native Gate 仍由既有授权机制和 PR #633 修复保护。
- 不清除 Provider/Model/Selection、Vault secrets、模型资产、历史、索引或 License Token。
- 若授权/Native 同步结果 UNKNOWN，维持关闭状态，不重放请求。

## 9. 当前状态

REGISTERED / IMPLEMENTATION NOT STARTED。PR #633 合并前不得修改 Native Gate 所有权文件；PR #633 合并后从最新 master 建立 Stage 2 实施分支，并在每个小批量 PR 上重新运行五项门禁。