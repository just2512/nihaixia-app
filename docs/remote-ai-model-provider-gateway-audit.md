# Remote 云端模型 Provider / Gateway 现状审计

> **Task ID:** REMOTE-MODEL-PROVIDER-AUDIT-20261128
>
> **Workstream:** Remote
>
> **审计基线：** master@9017388415e3744485c212340957c5f01c410d43（2026-11-28）
>
> **状态：** SOURCE AUDIT COMPLETE / IMPLEMENTATION NOT STARTED
>
> **范围：** 只读盘点 Flutter 依赖、配置持久化、Native 授权桥接、现有本地模型接口和云端 Provider/Gateway 接入缝隙；本报告不声称云端模型已实现，也不包含 Find N2 真机验收。

---

## 1. 审计结论

| 领域 | 主线证据 | 审计状态 |
|---|---|---|
| HTTP 传输依赖 | \`pubspec.yaml\` 声明 \`http: ^1.2.0\`；\`pubspec.lock\` 已锁定 \`http\` | EXISTS / CALL-SITE NEEDS CONFIRMATION |
| JSON/哈希/加密原语 | \`dart:convert\`、\`crypto\`、\`cryptography\` 已在依赖或代码中使用 | EXISTS / NOT A CREDENTIAL VAULT |
| 安全凭证存储 | 未发现 Flutter secure storage / Windows credential manager 依赖；现有 License Keystore 只负责签名密钥 | MISSING |
| Provider/Model 配置 DTO | 未发现通用 ProviderConfig、ModelConfig、TaskModelSelection | MISSING |
| 配置 Repository | \`SettingsRepository\` 只读写 \`user_settings\` 简单键值偏好 | PARTIAL / NOT MODEL CONFIG |
| 数据库 migration | \`DatabaseHelper\` 当前 schema version 8，旧版本迁移至 8 | EXISTS / AI TABLES MISSING |
| 专业版授权 | \`EntitlementService\` 验证单一 \`ai_access\` 并调用 Native gate | EXISTS / NATIVE-ONLY GATE |
| Native License Keystore | 当前 ECDSA P-256 SIGN/VERIFY 设备密钥 | EXISTS / NOT API SECRET STORAGE |
| 本地 E4B | \`LocalAiService\` 通过 \`com.nihaisha.app/local_ai\` MethodChannel 对接 Native Gemma 4 E4B | EXISTS / LOCAL GENERATION PATH ONLY |
| Cloud Model Gateway | 未发现模型 Provider、统一 HTTP Gateway、云端 task Adapter | MISSING |
| AI 总开关 | \`SettingsRepository\` 与 \`SettingsScreen\` 当前没有统一 AI 总开关 | MISSING |
| 真实云端模型调用 | 没有被确认的 Provider 请求链路和契约测试 | NOT_STARTED |

**核心判断：** 不能直接把已有 \`http\` 依赖、Native License 插件或 E4B MethodChannel 包装成“云端模型已经有基础实现”。云端首个代码批次必须先补齐模型配置持久化、独立凭证安全存储和统一授权调用边界，再增加具体 Provider Adapter。

## 2. 当前可复用模块与准确边界

### 2.1 HTTP / 传输

- \`pubspec.yaml:10-32\` 已声明 \`http: ^1.2.0\`，无需在首个批次再添加 Dio 或第二套 HTTP 客户端。
- \`pubspec.lock\` 中存在 \`http\` 包条目。
- 当前代码树路径盘点未找到独立 CloudModelProvider、ModelGateway、ProviderRegistry 或云端模型 Adapter。
- **未确认项：** 已声明 \`http\` 是否在其他业务请求中已有使用，以及其现有调用能否满足 SSE/流式解析、取消和连接池要求。必须在 Gateway 实施 PR 中对实际调用点做全仓检索，不能因为依赖存在就推断已有可复用 SSE 实现。

结论：首期优先评估并复用 \`package:http\` 的注入式 \`http.Client\` / \`Client.send\` 流能力；只有真实协议测试证明不足时才增加依赖。不得让 Widget 或助手场景直接创建 HTTP 请求。

### 2.2 配置与数据库

- \`lib/data/settings_repository.dart:6-9,42-95,163-170\`：当前 Repository 是单例 ChangeNotifier，只读取 \`user_settings(key,value)\` 并持久化一般用户偏好。
- \`lib/data/database_helper.dart:19-39\`：SQLite 打开版本为 8。
- \`database_helper.dart:208-309\`：当前迁移链按 oldVersion 顺序升级到 version 8；version 8 增加 \`assistant_messages.invocation_key\` 和唯一索引。
- \`user_settings\` 是键值表，不适合承载多 Provider、多模型、任务映射、模型资产或向量记录，也不得将 API Key 写入该表。

结论：配置实现应以新 Repository 和结构化表为主；数据库迁移从最新 master 的 version 8 顺序增加下一版，不清空现有用户数据库、不重建独立 SQLite 库。配置 migration 和后续索引 migration 必须由不同阶段顺序完成，不能多个并行分支同时改 DatabaseHelper 版本号。

### 2.3 专业版授权与现有 Native Gate

- \`lib/services/entitlement_service.dart:18-44,71-89,124-185\`：\`EntitlementSnapshot\` 只保留单一 \`aiAccess\`；EntitlementService 在验证前先关闭 Native gate，只有 Token 有效且包含 ai_access 才重新打开。
- \`lib/licensing/ai_model_access_platform.dart:3-50\`：\`AiModelAccessPlatform.setEnabled\` 通过 MethodChannel 向 Native 同步访问状态，并要求关闭操作确认资源已释放。
- \`android/app/src/main/kotlin/com/nihaisha/nihaisha_app/AiModelAccessGate.kt:3-43\`：该 Gate 保护 Native LiteRT 操作。
- \`MainActivity.kt:139-146\`：Flutter Engine 手动注册 \`LicensePlugin\`，同时由 MainActivity 管理本地 AI MethodChannel。

结论：现有授权基础可复用，但其 Native Gate 不拦截 Flutter HTTP 请求。云端必须有 \`AiRuntimeAccessCoordinator\` / \`AiModelGateway\`，每次实际发送前重新校验 EntitlementService 当前状态与 AI 总开关。Provider Adapter 不对业务层公开可绕过 Gateway 的发送入口。

### 2.4 License Keystore 不是凭证保险库

- \`android/.../LicensePlugin.kt:18-35,43-85\`：插件管理设备密钥申请签名和 License TokenStore。
- \`android/.../LicenseKeystore.kt\`：设备密钥使用 AndroidKeyStore EC / secp256r1，并以 SHA256withECDSA 执行签名与验证。
- \`LicenseTokenStore\` 存储的是已验签授权 Token，不是供应商 API Key。

结论：不能复用 License 私钥、License TokenStore 或 \`licensing\` channel 保存供应商 API Key。API Key 必须进入独立 Credential Vault；首期实现需明确 Android KeyStore AES-GCM 或经过审计的跨平台系统凭证方案，且凭证密文不得进入 SQLite、日志、导出或备份。若首批只支持 Android，非 Android 平台必须返回明确的 UNSUPPORTED_PLATFORM / CREDENTIAL_VAULT_UNAVAILABLE，不能明文降级。

### 2.5 本地 E4B 与五层 Reasoning DTO

- \`lib/services/local_ai_service.dart:24-80,123-180,294-350,697-705\`：本地服务通过 \`com.nihaisha.app/local_ai\` MethodChannel 调用 Native E4B，包含加载、推理、附件、完成确认和资源释放。
- \`lib/models/reasoning_request.dart\`：现有 ReasoningRequest 是 App 拥有的不可变业务输入 DTO，含 session、证据引用和确定性执行结果。
- \`lib/models/reasoning_response.dart\` / \`reasoning_response_codec.dart\`：已有严格结构化输出解析边界。

结论：云端生成模型应复用 ReasoningRequest/Response 作为语义合同，通过 Cloud Adapter 映射具体协议；不得复制一套不同的业务请求 DTO，也不得把远端 JSON 未校验内容直接传入工具执行。Local E4B MethodChannel 继续独立，不重写成 HTTP。

## 3. 首期设计约束

1. ProviderConfig、ModelConfig、TaskModelSelection 作为结构化配置，字段以 \`docs/ai-local-cloud-model-development-plan.md\` §4 为准。
2. API Key 仅保存于独立 Credential Vault；SQLite 仅保存不透明 credentialRef。
3. 五类 taskKey 使用同一 task resolver，但按 taskKind 独立 DTO 与 Adapter。
4. 图片/音频可按 v1.4 继承 text_reasoning；Embedding/Reranker 必须独立选择。
5. 每次模型调用经统一 Gateway 执行 \`ai_access AND AI 总开关\` 门禁；checking/invalid/unknown 均 fail-closed。
6. 使用明确 Provider 协议版本；不自动探测供应商模型、不按模型名称推断能力、不自动切换 Provider/本地/云端。
7. HTTP 仅允许 HTTPS；跨 Origin 重定向不得转发凭证；默认不重放模型 POST；响应不确定标 UNKNOWN。
8. 先做配置 Repository + migration + Vault 合同与测试，再做 Gateway/HTTP transport，再做 Text Reasoning Adapter，随后多模态与 Embedding/Reranker Adapter。
9. 不先做向量索引。Index generation 在至少一个 Embedding Adapter 具有真实返回维度/指纹合同后再实施。
10. 运行时失败不能伪造成默认排序、空向量、完整回复或成功状态。

## 4. 后续 Remote 任务拆分

| 顺序 | Task ID | 代码边界 | 退出条件 |
|---|---|---|---|
| R0（本任务） | REMOTE-MODEL-PROVIDER-AUDIT-20261128 | 只读盘点依赖、配置、数据库、授权、Native/Reasoning 入口 | 本报告入库；未知项明确记录 |
| R1 | AI-MODEL-CONFIG-20261128 | Provider/Model/Task DTO、Repository、schema migration、Credential Vault 和相关测试 | 字段/事务/旧库迁移/Vault 成功失败合同通过 |
| R2 | AI-MODEL-GATEWAY-20261128 | RuntimeAccessCoordinator、ModelGateway、HTTP transport、错误码/超时/SSE 基础 | 五类任务共用门禁；跨域凭证安全和 UNKNOWN 测试通过 |
| R3 | AI-CLOUD-TEXT-REASONING-20261128 | 首个明确协议 Cloud Text Adapter，映射 ReasoningRequest/Response | 真实供应商调用与契约测试通过 |
| R4 | AI-CLOUD-MULTIMODAL-20261128 | 图片/音频 Adapter | 任务配置/继承、载荷限制和供应商实测通过 |
| R5 | AI-CLOUD-EMBEDDING-20261128 + AI-CLOUD-RERANKER-20261128 | 两个独立 Cloud Adapter | 维度/指纹与候选 ID 校验的真实调用通过 |
| R6 | AI-EMBEDDING-INDEX-20261128 | SQLite generation、VectorIndexStore、Core-2 接线 | 原子切换、旧索引保留、来源黄金集通过 |
| R7 | AI-MODEL-SETTINGS-UI-20261128 | Provider/Model/Task 设置 UI | 配置可编辑、状态准确、无探针/自动路由 |

## 5. 当前阻塞和决策项

- **Vault 平台范围：** 当前仓库未发现通用系统凭证插件。实现 PR 必须先明确首批目标平台；Android 使用独立 AES-GCM Keystore key 或经审核的系统 Vault；其他支持平台未实现前明确 BLOCKED，不可保存明文。
- **HTTP 现有使用：** \`http\` 已声明但本次未确认其业务调用点与 SSE 能力；Gateway 任务开始时须全仓检索并注入复用，避免平行 HTTP 客户端。
- **授权偏好：** 当前尚无统一 AI 总开关。迁移必须保留旧用户已授权 E4B 的可用行为，不得默认写 false。
- **DB migration：** 当前 schema 8，R1 才增加配置表；R6 的索引表必须在 R1 后单独 migration。
- **本地验收：** 本任务不运行 Find N2 设备测试，也不更改任何本地模型状态。云端代码、自动化、文档和 CI 全部完成后，再集中安排 Find N2 本地验收；此前所有本地 Embedding/Reranker 保持 MISSING / LOCAL ONLY / UNKNOWN。

## 6. 禁止事项

- 不修改 \`docs/ai-layered-runtime-architecture.md\`、\`docs/ai-capability-audit.md\`、\`docs/ai-modernization-execution-ledger.md\` 或 \`docs/local-real-device-acceptance-handoff.md\`；这些文件分别由 Architecture、Integration、Local 单写。
- 不在本审计 PR 中修改运行时代码、数据库、依赖、测试或 Native E4B。
- 不复用 License ECDSA 私钥/TokenStore 作为 API Key Vault。
- 不把 \`http\` 依赖存在视为 Provider Adapter 已实现。
- 不把 PR/CI 成功解释为真实供应商 E2E 或 Find N2 设备 PASS。
