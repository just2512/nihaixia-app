# 本地与云端 AI 模型完整开发方案

> **文档性质：** AI 模型运行时实施总方案 / 后续 Local、Remote、Architecture、Integration 的共同执行基线。
>
> **方案版本：** 1.0（2026-11-28）
>
> **架构前提：** 遵循专业版架构 v1.4（docs/pro-edition-architecture-constraints.md §18）、五层运行时规范（docs/ai-layered-runtime-architecture.md §10）、AI 审计约束（docs/ai-capability-audit.md §18）和授权协议 v1.3（docs/pro-edition-license-protocol.md §9）。
>
> **实施基线：** 本方案登记时 master = c0dbf72cebc8345fc58163b9fe4cf30ee353820d；五层运行时代码锚点 = 805f006ed502c5cbf10dba4ad30428ee9761eb42。每个后续任务必须重新读取最新 origin/master，不得把这两个 SHA 当作未来任务的永久基线。
>
> **当前状态：** 方案已定义；云端及本地 Embedding/Reranker 运行时代码尚未因此开始或完成。所有实现状态按执行台账逐项记录。

---

## 0. 本方案的约束效力

本文件把 v1.4 的架构原则拆解为可实施的数据结构、模块职责、调用流程、配置界面、持久化、迁移、失败语义、任务顺序与验收门槛。

发生冲突时按以下规则处理：

1. 产品定位与边界文件决定 App 的用途。研纪是辅助学习与研习工具，不是诊疗软件；AI 负责理解、归纳、解释和辅助学习，不替代 App 的确定性计算、规则判断或业务状态。
2. 专业版架构 v1.4 决定本地/云端双运行时、任务键、统一 ai_access 与用户 AI 总开关等不可变架构事实。本文件不得改变 Token 格式、协议修订或权益集合。
3. 本文件规定模型配置、运行时适配、索引和开发落地方式。
4. ai-capability-audit.md 规定来源、UNKNOWN、测试、TRACE、隐私和设备证据标准。
5. ai-modernization-execution-ledger.md 记录任务 Owner、分支、PR、CI、主线集成和剩余证据。台账状态高于任何计划中的“预计完成”描述。
6. local-real-device-acceptance-handoff.md 是 Find N2 唯一设备证据入口。CI、Mock、代码存在、配置保存或 Android APK 编译均不能代替真机 PASS。

此文件未明确批准的功能不得自行扩张。任务实施中若必须改变公共 DTO、任务键、模型选择规则、来源语义、授权或失败语义，先提交 Architecture 变更，不得由某个代码 PR 临时决定。

## 1. 目标和明确不做的事

### 1.1 交付目标

形成一套可由用户明确配置、可审计、可替换的本地与云端模型系统：

- 文本推理：用户为 text_reasoning 选择一个本地或云端生成模型。
- 图片理解：用户可为 image_understanding 单独选择模型；未单独配置时继承 text_reasoning。
- 音频理解：用户可为 audio_understanding 单独选择模型；未单独配置时继承 text_reasoning。
- 向量嵌入：用户为 embedding 独立选择本地或云端 Embedding 模型；没有配置时不调用模型，保留现有关键词、实体和结构化召回。
- 候选重排：用户为 reranking 独立选择本地或云端 Reranker 模型；没有配置时保留现有确定性 SourceAwareLegacyEvidenceRanker。
- 所有模型请求由同一配置解析、授权门禁、调用网关和错误处理流程管理。
- 本地向量与云端 Embedding 返回的向量都保存在用户设备的本地索引中；首期不把知识库正文或向量索引托管到云端数据库。
- 本地 Embedding、端侧 Reranker 与 E4B 生成式模型是三个独立任务配置，允许使用不同运行库、模型文件、Tokenizer 和资源策略。

### 1.2 不做事项

- 不建设通用 Agent 平台、自治多 Agent、DAG 或另一个会话数据库。
- 不按问诊、学习、工具、玄学等助手场景分别保存模型；模型配置只按 taskKey 管理。
- 不做模型能力探针、自动模型列表拉取、基于模型名称推断能力、自动路由或自动切换。
- 不在本地模型失败时自动上传云端；不在云端失败时自动切换本地或另一供应商。
- 不把 E4B 普通聊天接口当作 Embedding 或 Reranker API；不因共用 LiteRT 产品名而推断运行时兼容。
- 不新增 cloud_ai_access、embedding_access、reranker_access 等权益，不修改 YANJI1 Token wire format。
- 不在配置时自动下载模型，不把大模型文件打包进 APK。
- 不以云端 Mock、配置页面、CI 或静态源码存在宣称真实供应商 E2E 或 Find N2 本地模型通过。
- 不改写 CandidateEvidence 的来源身份、原文、核验状态、版本或定位；不把相似度/重排顺序当作资料真实性、经典权威性或医学正确性。

## 2. 当前代码基线和真实缺口

以下定位来自 master@c0dbf72 的源码核对，是后续实现的起点，不等于新能力已存在。

| 领域 | 当前可复用代码/事实 | 当前不能宣称的能力 |
|---|---|---|
| 本地生成模型 | LocalAiService；Android MainActivity Native Engine；LiteRT-LM 0.18.0；Gemma 4 E4B 固定模型文件、SHA-256 导入校验和 GPU/CPU 偏好 | E4B 已支持通用 Embedding/Reranker；本地模型运行时可直接装载任意文件 |
| 模型设置 | SettingsScreen、SettingsRepository、LocalAiBackendSettingsTile；现有设置保存到 nihaisha.db 的 user_settings 键值表 | 已有 Provider 管理、模型注册表、任务模型选择或云端凭证库 |
| 授权 | EntitlementService、EntitlementSnapshot、AiModelAccessPlatform、Android AiModelAccessGate | 云端 HTTP 已被统一 Gateway 门禁保护；用户 AI 总开关已接入所有本地/云端任务 |
| 知识召回 | AssistantKnowledgeContextBuilder、CandidateEvidence、MultiSourceEvidencePipeline | 已有向量索引、Embedding 模型调用或增量索引生成 |
| 确定性排序 | SourceAwareLegacyEvidenceRanker、RankedEvidenceSet、EvidenceRankingDecision | 现有排序是语义 Reranker；不能不经黄金行为验证直接改变其默认顺序/限额 |
| 对话推理 | ReasoningRequest/ReasoningResponse v1、LocalAiService、AssistantReasoningTurnLedger | 已有通用远端 Provider、SSE 网关或云端上下文 Token 预算端到端接线 |
| 存储 | DatabaseHelper 当前 schema version 为 8；SettingsRepository 只承载较简单的用户偏好 | 可以在旧版本 DB schema 上直接追加而不核对最新 migration |
| 本地审计 | PR #626 登记 Local Embedding/Reranker 只读审计任务 | PR #626 任务卡或云端源码检索能证明 Find N2 runtime 通过 |

当前端侧 E4B 模型信息、固定文件格式与 Find N2 未实测边界详见 docs/local-ai-e4b.md。后续 Local 审计必须以最新 master 重跑依赖和源码扫描；PR #626 只是一张任务登记卡，不是审计结论。

## 3. 目标结构与请求链路

### 3.1 模块职责

| 模块 | 单一职责 | 禁止越界 |
|---|---|---|
| AiModelConfigRepository | 读取/保存 ProviderConfig、ModelConfig、TaskModelSelection 和模型资产元数据 | 不持有明文凭证；不发 HTTP；不加载模型 |
| AiCredentialVault | 存取 API Key 等秘密，返回不透明 credentialRef | 不把秘密写 SQLite、user_settings、日志、异常或备份 |
| AiTaskModelResolver | 按固定 taskKey 解析精确 ModelConfig；处理 v1.4 规定的 image/audio 继承 | 不探测能力、不自动选择、不跨任务继承 Embedding/Reranker |
| AiRuntimeAccessCoordinator | 组合有效 ai_access 和用户 AI 总开关，输出唯一有效调用状态 | 不修改签名权益、不在授权未知时 fail-open |
| AiModelGateway | 所有本地/云端任务的统一入口；执行访问门禁、解析、调用、超时、状态归档和错误映射 | 不允许 UI 或 Provider Adapter 绕过 Gateway 直接发起模型请求 |
| CloudProviderAdapter | 将明确配置的协议和 ModelConfig 转换为供应商 HTTP 请求/响应 | 不自作主张探测模型能力；不保存凭证 |
| LocalTaskRuntimeAdapter | 对接指定本地模型格式、Tokenizer、Native/Flutter 推理 runtime | 不将 E4B Chat Engine 冒充 Embedding/Reranker runtime |
| AiEmbeddingIndexService | 建立、增量更新、查询和切换本地向量索引 generation | 不改变来源元数据；不在模型空间不兼容时混合向量 |
| AiRerankingService | 将已召回且有界的 CandidateEvidence 交给用户选择的 Reranker，并验证返回 ID | 不让模型创建候选、改正文或提升来源状态 |

### 3.2 统一调用链

所有模型请求必须走：

用户操作
→ taskKey
→ AiTaskModelResolver 精确读取用户选择
→ AiRuntimeAccessCoordinator 检查授权与总开关
→ 构建任务专属的有界输入
→ AiModelGateway
→ LocalTaskRuntimeAdapter 或 CloudProviderAdapter
→ 严格解析返回值
→ App 验证响应和来源关联
→ 写入不含秘密和不必要正文的状态/TRACE
→ 向 UI 返回真实结果或真实失败。

对话任务、Embedding 和 Reranker 都使用同一授权与配置入口，但使用各自的输入输出 DTO、预算和 runtime 生命周期。Gateway 只负责调用治理，不得把三个任务强行套用同一种模型 API。

### 3.3 五类 taskKey 的确定性解析

| taskKey | 必须独立配置 | 继承规则 | 未配置的行为 |
|---|---|---|---|
| text_reasoning | 是 | 无 | 显示默认推理模型未配置，不擅自挑选模型 |
| image_understanding | 否 | 仅在该任务无单独选择时继承 text_reasoning | 若继承模型不支持，显示该模型实际返回的错误 |
| audio_understanding | 否 | 仅在该任务无单独选择时继承 text_reasoning | 若继承模型不支持，显示该模型实际返回的错误 |
| embedding | 是独立配置槽 | 不继承 text_reasoning，也不继承其他任务 | 不调用模型，使用已有确定性召回 |
| reranking | 是独立配置槽 | 不继承 text_reasoning，也不继承 embedding | 不调用模型，使用已有确定性排序 |

“独立配置槽”不表示必须马上有本地或云端模型可选；模型运行时审计未通过时，界面必须如实显示 MISSING/NOT AVAILABLE，不得展示虚假的 Ready。用户可以为不同 taskKey 选择同一供应商下的不同 ModelConfig；一个聊天模型是否支持图片/音频，只以用户是否显式选择和实际接口响应为准，不做自动能力推断。

## 4. 配置数据模型

字段名是公共语义合同；具体 Dart/SQL 类型可在 Architecture 任务中做一次字段级冻结。未经 Architecture 审核，不得改名、合并或新增第二套配置来源。

### 4.1 ProviderConfig：供应商连接配置

| 字段 | 含义/约束 |
|---|---|
| providerId | App 内稳定 UUID，不承载供应商或权限语义 |
| displayName | 用户自定义显示名 |
| protocolAdapterId | 明确选择的协议适配器版本，例如 chat-completions、embeddings 或 rerank 的具体协议实现 |
| baseUrl | HTTPS 根地址；禁止 URL 内嵌用户名/密码/Key |
| credentialRef | 指向 AiCredentialVault 的不透明引用；可以为空，仅在该 Provider 明确无需凭证时允许 |
| enabled | 用户是否允许该 Provider 被选中 |
| createdAt / updatedAt | UTC 时间戳 |
| configSchemaVersion | 配置迁移版本 |

不在 ProviderConfig 保存 model capabilities、自动同步模型列表、供应商模型价格推断或探针结果。模型 ID 由用户在 ModelConfig 中明确填写。Provider 协议和实际端点不一致时按真实 HTTP/解析错误失败。

### 4.2 ModelConfig：具体模型配置

共同字段：

| 字段 | 含义/约束 |
|---|---|
| modelConfigId | 稳定 UUID |
| displayName | 用户自定义名称 |
| taskKind | 五类 taskKey 之一；一个具体配置只声明一个任务类型 |
| runtimeKind | local 或 cloud |
| modelIdentifier | 云端供应商模型 ID，或本地 manifest 声明的模型 ID |
| providerId | cloud 必填并关联 ProviderConfig；local 必须为空 |
| localAssetId | local 必填并关联已校验本地模型资产；cloud 必须为空 |
| apiProtocolId | cloud 必填；local 为空 |
| enabled | 用户是否允许此配置被任务选择 |
| modelRevision / fingerprint | 供应商/本地文件真实可取得的版本与指纹；未知必须 UNKNOWN |
| createdAt / updatedAt | UTC 时间戳 |
| configSchemaVersion | 配置字段版本 |

生成模型专用字段：

- contextWindowTokens：用户配置或可追溯声明的上下文窗口整数。
- maxOutputTokens：用户配置的最大输出 Token 数，必须小于 contextWindowTokens。
- tokenizerId、tokenizerRevision：用于估算/统计的精确 Tokenizer 标识；无法可靠识别时 tokenCount 记 UNKNOWN。
- maxInputTokens：若供应商或本地 Runtime 有明确输入上限，单独保存；不得用字符数填充。

Embedding 专用字段：

- embeddingDimension：正整数，必须与模型真实输出维度完全一致。
- normalization：明确为 none 或 l2；查询与文档必须一致。
- maxInputTokens：Embedding 模型的独立输入长度合同。
- maxBatchItems：单次 encode 批次上限。
- tokenizerId / revision：按模型实际输入预处理配置。

Reranker 专用字段：

- maxCandidates：单次送入模型的候选条数上限。
- maxInputTokens：查询 + 候选文本的任务预算。
- maxCandidateTokens：单个候选文本的截断上限。
- outputProtocolId：明确的有序候选 ID 返回协议；不把自由文本或相似度数组自动当作合法排序。

### 4.3 TaskModelSelection：任务到模型的映射

每个 taskKey 只有一条有效选择记录：

- taskKey：五类任务键之一，唯一键。
- modelConfigId：精确指向 ModelConfig；为空时仅允许 v1.4 规定的继承或确定性行为。
- selectionMode：explicit / inherit_text_reasoning / deterministic_unconfigured。
- updatedAt：UTC 时间戳。

校验规则：

1. text_reasoning 只允许 explicit；没有可用 ModelConfig 时请求失败为 MODEL_NOT_CONFIGURED。
2. image_understanding/audio_understanding 可 explicit，也可 inherit_text_reasoning。
3. embedding/reranking 可 explicit 或 deterministic_unconfigured；不得出现 inherit_text_reasoning。
4. 配置保存时校验 taskKind 和 ModelConfig.taskKind 完全一致。
5. Provider 被禁用、凭证引用缺失、本地文件缺失或模型配置无效时，不偷偷选用另一个配置。
6. 多条同 taskKey 配置不能同时生效；历史模型配置可以保留供用户切换和回滚。

### 4.4 AiLocalModelManifest：本地模型资产清单

本地模型不以文件名或扩展名推断能力。经 Local 审计确认后，采用受控 manifest 或等价的明确注册信息，至少包含：

- manifestSchemaVersion、modelIdentifier、revision；
- taskKind（只能为 embedding 或 reranking；E4B 旧配置走兼容注册）；
- runtimeAdapterId、modelFormat；
- modelFileName、byteLength、sha256；
- tokenizer 文件/资源标识与指纹；
- maxInputTokens；
- Embedding 的 dimension、normalization；
- Reranker 的输入/输出协议、maxCandidates；
- licenseId / licenseUrl / notice；
- 导入来源与安装时间。

manifest 是运行时配置输入，不是模型真实能力的自动证明。应用必须校验格式字段在已编译支持的 Adapter allowlist 内、哈希和字节长度正确、字段完整、任务类型一致。SHA-256 证明文件与 manifest 记录一致，不证明模型作者身份、许可证真实性或模型行为正确。

### 4.5 关系和持久化原则

- user_settings 继续保存简单用户偏好，新增一个 AI 总开关键；不得把所有 Provider、Model 或向量数组塞入单个 JSON 字段。
- 结构化 Provider/Model/Task selection/Local asset/Index generation 元数据使用 nihaisha.db 内受控表和事务。
- API Key、Secret、Bearer Token 等只进入平台安全 Credential Vault；SQLite 只保存 credentialRef。
- 向量数据存本地索引表/索引存储；不写入会话历史、聊天正文或云端同步层。
- 当前 master 的 DatabaseHelper schema version 为 8。实现任务开始时必须再次检查最新版本，并将 migration 纳入现有 onUpgrade/onCreate 路径；版本号不能机械地假定仍为 8。禁止开第二个独立 SQLite 授权/配置库。

建议表职责（具体列类型和索引在持久化任务的 PR 中冻结）：

| 表 | 主键/作用 | 最少字段 |
|---|---|---|
| ai_provider_configs | providerId | protocolAdapterId、displayName、baseUrl、credentialRef、enabled、schemaVersion |
| ai_model_configs | modelConfigId | taskKind、runtimeKind、modelIdentifier、providerId/localAssetId、apiProtocolId、task-specific constraints、fingerprint、enabled |
| ai_task_model_selections | taskKey | modelConfigId、selectionMode、updatedAt |
| ai_local_model_assets | localAssetId | privateRelativePath、format、byteLength、sha256、revision、manifest、installStatus |
| ai_embedding_index_generations | generationId | modelConfigId、modelFingerprint、dimension、normalization、chunkingVersion、sourceSnapshotHash、indexSchemaVersion、status、createdAt |
| ai_embedding_vectors | generationId + chunk identity | sourceId、sourceVersion、chunkId、contentHash、vector bytes、dimension |

ai_embedding_vectors 必须能按 generationId、sourceId、sourceVersion、chunkId 和 contentHash 检索/删除。外键与索引按 SQLite 实际约束验证。向量数据采用固定维度 Float32 little-endian BLOB 或经 Architecture 批准的等价表示；每条记录的 dimension 必须与该 generation 一致。不得把不同 modelFingerprint/dimension/normalization 的向量写进同一 active generation。

## 5. 云端 Provider 与 Model Gateway 实施

### 5.1 Provider Adapter 协议

不建设一个假定所有供应商都兼容的万能 API。协议实现必须按 task 类型显式注册：

- 文本生成：请求/响应 JSON schema、流式 SSE（供应商支持时）、终止标记、usage 字段、错误 envelope。
- 图片理解：图像载荷编码/尺寸限制、请求字段和响应协议。
- 音频理解：音频载荷格式、时长/字节限制、请求字段、响应协议。
- Embedding：批量文本输入和批量向量输出；响应必须保留输入顺序或提供明确 index 映射。
- Reranker：query、候选集合与 ordered candidate IDs 响应；如果供应商只返回 indices/scores，Adapter 负责把 indices 映射为本轮输入 candidate IDs，严格拒绝越界或重复项。

每个 Adapter 需要协议版本、请求 serializer、响应 parser、错误 mapper 和对应契约测试。不能用“OpenAI compatible”标签代替实际协议验证；兼容协议的端点和输出字段也必须按代码中的明确版本实现。首批先实现最小公共协议切片，确实不兼容时另加 Provider Adapter，不在 Gateway 中散落供应商 if/else。

不自动拉取供应商模型列表，不在网络请求后推断能力。modelIdentifier、apiProtocolId 和 taskKind 均由用户配置；实际调用失败即返回明确错误。

### 5.2 CloudProviderAdapter 接口

统一输入/输出语义，底层请求按任务分型。适配器最少提供：

- generate(request, modelConfig, credential)；
- understandImage(request, modelConfig, credential)；
- understandAudio(request, modelConfig, credential)；
- embed(textBatch, modelConfig, credential)；
- rerank(query, candidates, modelConfig, credential)。

Adapter 不能直接拿到业务执行器、数据库写入接口、License Token 或 Native Engine。Credential 以调用期参数注入，禁止保存在 Adapter 单例或调试状态中。任务不支持或请求字段不兼容时返回协议错误，不自动切换其他 Adapter。

### 5.3 HTTP 传输与失败策略

- 生产 Provider endpoint 必须为 HTTPS；拒绝 URL 中的 userinfo、非法 scheme 和不受控路径拼接。
- TLS 证书验证必须保持开启。跨 host 或降级到 HTTP 的重定向拒绝；任何重定向不得把 Authorization/API Key 转发到不同 Origin。
- 设置连接、首 Token、整请求和流空闲超时；超时值可由统一 transport policy 管理，但不能无限等待。
- 对响应体、图片/音频上传、Embedding batch 和 Rerank candidate payload 设定硬性字节/条数上限。
- 解析 SSE 必须正确处理跨网络 chunk 的半行、UTF-8 边界、注释行、结束标记、usage 末帧和中途断流；中途断流不得假装完整回复。
- HTTP 401/403、429、4xx schema error、5xx、DNS/TLS、timeout、parse failure 分别映射为稳定错误码并保留安全诊断信息。
- 默认不自动重试模型 POST。仅当协议明确提供幂等键且已验证不会重复计费/副作用时，才可单独设计受控重试。提交后失去响应、取消时无法确认服务端处理结果的请求标 UNKNOWN，不自动重放。
- 网络取消只表示客户端停止等待或关闭连接，不可声称供应商一定停止计算。
- UI 层的重复点击由 requestId/in-flight 状态抑制；同一业务请求不得因页面 rebuild、超时回调或状态恢复而重复发送。

### 5.4 Credential Vault

新增 AiCredentialVault 抽象：

- save(providerId, secret) 返回 credentialRef；
- read(credentialRef) 仅在一次真实请求期间提供明文；
- delete(credentialRef) 清理不再使用的凭证；
- exists(credentialRef) 只做本地引用存在性检查，不发网络请求。

Android 使用平台硬件/系统保护的 Keystore 体系封装安全存储；其他已支持平台使用系统安全凭证存储。具体插件/Native 实现先审计现有依赖，不重复创建 License TokenStore，也不复用 License 私钥存储来放 API Key。若平台没有安全存储实现，该平台云端凭证功能标 BLOCKED，不回退到明文 SharedPreferences、SQLite 或配置文件。

日志、崩溃报告、TRACE、异常 message、导出配置和数据库备份均不得包含 API Key、Authorization、原始音频/图片、整段用户问题或完整来源正文。导出 Provider 配置时只导出 credentialRef 的空占位，不导出秘密。

### 5.5 AiModelGateway 与唯一授权门禁

Gateway 在发送前必须再次计算：

ai_access 已验签有效
AND EntitlementService 状态为 active
AND 用户 AI 总开关为开启
AND 模型配置有效且 enabled
AND 凭证/本地资产可用
AND taskKey 与 ModelConfig.taskKind 一致。

其中任何状态为 checking、temporarilyUnavailable、invalid、unknown 或 missing，都拒绝新请求，返回稳定错误码。UI 禁用状态不是安全边界，Gateway 必须检查；Native LiteRT 仍由 AiModelAccessGate 最终 fail-closed。

总开关不得修改或伪造 EntitlementSnapshot，也不能把 ai_access 写入 user_settings。建议由 AiRuntimeAccessCoordinator 组合用户偏好与授权状态，并在偏好/授权变化时同步 Native gate 的有效状态。EntitlementService 与 Native gate 的现有生命周期必须先审计再改，避免“授权恢复把用户已关闭的总开关重新打开”。

关闭 AI：
- 阻止所有新模型请求，包括 Local E4B、Local/Cloud Embedding、Local/Cloud Reranker 和多模态；
- 正在执行请求按真实取消/UNKNOWN 状态处理，不自动重放；
- 不删除 Provider 配置、凭证、模型文件、向量索引、历史或 License Token；
- Native 模型资源按既有安全生命周期释放；不得在释放失败时报告已释放。

## 6. 本地模型配置与 Find N2 运行时

### 6.1 与 E4B 的边界

现有 Gemma 4 E4B + LiteRT-LM 是本地 text_reasoning 及其既有媒体输入路径。保持其固定模型文件长度、SHA-256、私有目录、导入恢复、Native 单线程执行、GPU/CPU 用户偏好和现有失败处理。

不得为追求统一配置而将 E4B 导入流程改成“任意模型文件加载器”，也不得因 E4B 使用 LiteRT-LM 就假设它能够输出 Embedding 向量或候选排序。E4B 的既有本地配置需注册成 ModelConfig 兼容项，但 Native Gate 和已验证的旧调用路径继续有效。

### 6.2 Local Embedding / Reranker 独立模型槽位

两项本地模型分别配置，禁止复用同一个 ModelConfig 的 taskKind：

- Local Embedding：独立模型文件、Tokenizer/预处理、runtimeAdapterId、模型指纹、输入长度、向量维度、归一化和批量上限。
- Local Reranker：独立模型文件、Tokenizer/预处理、runtimeAdapterId、模型指纹、候选编码/排序协议、最大候选数和输入预算。
- 二者可与 E4B 使用完全不同的文件格式和 runtime；不得要求都通过 LiteRT-LM。
- 用户选择具体本地模型后，必须显示模型资产是否完整、是否符合已编译的 runtime Adapter 和任务配置。静态配置校验不能宣称真实设备运行 PASS。
- 若 Local 审计确认当前 Find N2 没有可用 runtime/模型格式，先交付 MISSING/NOT AVAILABLE 状态和审计证据，不为了 UI 完整而塞入未经验证的运行库或模型文件。

### 6.3 本地模型安装/导入

模型文件不进入 APK，不自动联网下载。用户通过系统文件选择器导入本地模型包或模型文件及其 manifest：

1. 读取文件名和 manifest，不执行模型。
2. 校验 manifest schema、任务类型、runtimeAdapterId、modelFormat、Tokenizer 标识和必需字段。
3. 校验模型文件字节数、SHA-256、路径和大小上限；输入超限时拒绝，不覆盖旧资产。
4. 将文件流式复制到应用私有目录下的临时路径，复制时同步计算哈希。
5. 校验成功后原子替换目标版本并写 LocalAsset metadata；失败删除临时文件，保留旧模型和旧配置。
6. 模型首次加载再由 Runtime Adapter 检查格式/初始化结果；初始化失败回报真实 runtime 错误，不自动换 CPU/GPU 或其他模型。
7. 删除模型前检查 TaskModelSelection 和 active index generation 引用；被引用时要求先切换配置/完成索引重建，不做隐式级联删除。

manifest 的格式版本、大小上限、签名策略和许可检查由 Local 审计给出真实依据后冻结。不能因为 SHA-256 匹配就标记可信发布者或合法授权。

### 6.4 LocalTaskRuntimeAdapter

Local Adapter 至少实现：

- load(modelAsset, modelConfig)；
- embed(textBatch) 或 rerank(query, candidates)；
- release()；
- getRuntimeState()，返回真实的 notLoaded/loading/ready/failed/unknown；
- 返回真实 runtime id、model fingerprint、dimension 或其他任务必要元数据。

Native 方法必须有互斥/串行生命周期、参数边界和异常映射；不能把 Native crash 吞成空向量或空排序。并发调用不得造成重复加载、释放期间推理、半初始化 Engine 或资源句柄泄漏。

本地任务的 GPU/CPU 等后端只有在所选 runtime 实际支持且 Local 任务完成验证后才开放显式设置。不得自动探测并切换；用户选择的后端失败时给出错误和人工重试入口。没有硬件证据前，backend=UNKNOWN，不把偏好值当实际执行值。

### 6.5 Find N2 资源和生命周期要求

Find N2 本地资源方案必须基于真实测量。至少记录：
- App/ROM 版本、Find N2 型号和内存规格、APK commit SHA、模型 manifest revision 和 SHA-256；
- 冷启动/热启动加载耗时、单条和 batch Embedding 耗时、候选条数与 Reranker 耗时；
- Java/Kotlin/Native PSS 峰值、模型文件大小、存储占用；
- 前台/后台切换、屏幕内外折叠、连续执行、温度和电量变化；
- 加载、执行、释放、切换模型、导入失败、重启恢复和低存储空间场景。

默认不同时常驻 E4B、Embedding 和 Reranker 三套大型 Engine。实现按任务获取 runtime lease，任务完成后按设备实测策略释放或保留；在没有内存证据前以串行执行和显式释放为基线。索引构建、Reranker、E4B 推理不能互相争用导致 OOM/ANR、Activity 卡死或模型状态错乱。

真机验收不能用 Emulator、Android CI APK 或 Desktop runtime 代替。Find N2 升级安装继续遵守原签名覆盖升级要求，不卸载、不清库、不清除用户历史。

## 7. Embedding 向量索引与召回流程

### 7.1 单一向量空间

query 和 source chunk 必须使用同一 modelFingerprint、模型 revision、Tokenizer/预处理版本、embeddingDimension、normalization 和 embedding schema。下列任一项变化都视为新的向量空间，不能把新旧向量混合：

- 模型 ID / revision / 文件 SHA；
- runtime 或 provider 变化导致无法证明输出空间完全一致；
- Tokenizer、文本预处理、chunking 版本变化；
- 向量维度或归一化策略变化；
- 向量存储 schema 变化。

即使 Local 与 Cloud 配置填写相同 modelIdentifier，也不默认认为模型空间相同。只有有可复核的模型指纹和完全一致性证据才能共享 generation；默认按新的 modelConfigId/modelFingerprint 重建。

### 7.2 Chunk 生成和元数据

Embedding 只编码实际可回源的资料片段。复用项目当前资料解析与来源定位数据，不另建一套事实库。每个 Chunk 至少持有：

- sourceId、sourceVersion、materialKind；
- chunkId、assetId（如适用）、title、chapterPath、locator；
- contentHash、chunkingVersion、contentCompleteness；
- 原文/片段只在本地存储或按需回源；向量索引不能代替原始来源。
  
Chunking 必须确定性、可版本化：同一 source snapshot + 同一 chunkingVersion 生成相同 chunkId/contentHash；边界按完整段落/句子或已定义的结构边界切分，不能把来源或作者边界拼接在一起。不得把 MODEL_INFERRED、会话内容或用户聊天默认加入系统资料索引。

### 7.3 向量存储与检索

首期建立 VectorIndexStore 抽象并复用当前 nihaisha.db。默认实现先评估 SQLite Float32 BLOB + generation/source 元数据预过滤 + 分批精确 cosine scan；不一开始引入独立向量数据库或 HNSW 依赖。若全量扫描的时间/内存实测不满足设备和数据规模预算，再用独立 PR 提交 ANN 索引方案及对照证据，不能在第一批将未经验证的近似检索加入默认路径。

检索流程：

1. 读取 taskKey=embedding 的 TaskModelSelection。
2. 若未配置：只走既有关键词、实体、结构化资料查询。
3. 若已配置：先检查统一 AI Gate，再对 query 执行同一 Embedding 模型编码。
4. 校验向量数量、维度、有限数值、归一化状态和模型指纹。
5. 查询当前 active generation，仅扫描当前允许的资料来源和 sourceVersion；不跨 generation 取向量。
6. 使用明确的 cosine/dot-product 语义排序，取受限 topK；相似度只作本次相关性次序，不外推来源真实性。
7. 将命中映射为 CandidateEvidence，retrievalMethod 标记真实的 vector retrieval 路径，matchBasis 标记 embedding similarity；sourceId、sourceVersion、locator、verificationStatus 等全部由本地源记录回填。
8. 与现有关键词/结构化候选做去重合并，evidenceId 在本 request 内唯一；不因相似度覆盖来源身份或改变核验状态。
9. 交给统一证据排序层；来源和黄金查询行为仍必须通过原有测试。

首批不得硬编码未经黄金集对照确定的相似度阈值/融合权重。新增向量召回应通过黄金查询集逐项检查：应该召回的 sourceId 是否出现、原有必需候选是否丢失、不同版本/来源冲突是否保留、是否引入不相关来源。没有证据支持的 query 继续保留现有确定性召回。

### 7.4 Generation 构建和原子切换

状态建议：EMPTY → BUILDING → VALIDATING → ACTIVE；失败进入 FAILED，旧 active generation 继续服务。

重建流程：

1. 读取当前 source snapshot 与稳定 contentHash。
2. 创建新的 generationId，记录 modelConfigId、fingerprint、dimension、normalization、Tokenizer、chunkingVersion、schemaVersion。
3. 对变更 Chunk 做批量 Embedding，验证返回行数/映射顺序、维度、数值有限性和 normalization。
4. 写入新 generation 的向量记录；在 generation 完成前不得让检索读到 staging 记录。
5. 校验预期 Chunk 数、实际 Chunk 数、重复 chunkId、孤儿 sourceId、缺失向量、向量长度和 manifest checksum。
6. 一致性检查通过后，在一个 SQLite transaction 中将 active generation pointer 切换到新 generation；不得先删旧 generation。
7. 新 generation 激活后再异步清理可回收的 retired generation；删除失败不影响当前 active generation。
8. 构建中崩溃、断电、存储不足、模型失败或校验失败时，旧 active generation 保持可查询；启动恢复只修复 staging 状态，不假装它已激活。

source 内容变化采用增量更新：同一 active generation 的模型空间和 chunkingVersion 不变时，只更新受影响 source/chunk；涉及模型空间或 schema 的变化必须新建 generation 全量构建。用户切换 Local/Cloud Embedding 模型也必须按 fingerprint 重新构建，不直接把旧向量标记为新模型的输出。

## 8. Reranker 候选重排

### 8.1 调用范围

Reranker 只处理同一次请求已经产生的 CandidateEvidence，且先经过 App 的候选数量/来源限制与输入预算。它不能单独查询数据库、扩大候选集、访问会话历史、执行工具或生成新资料。

发给云端 Reranker 时，只发送完成排序所需的 query、候选临时 ID、标题/片段文本和必要的最小字段；sourceId、用户本地路径、文件 URI、来源核验状态、用户标识和会话持久化 ID 不传给供应商。临时候选 ID 只在本次请求内有效，响应解析后在 App 内映射回原 CandidateEvidence。

### 8.2 返回合同与校验

首期统一响应为 orderedCandidateIds。它必须是本次实际输入候选 ID 的完整、无重复排列：

- 空 ID、未知 ID、重复 ID、缺失 ID、越界 index、格式不合法均拒绝；
- 不接受模型返回新的来源、正文、sourceId、sourceVersion 或 verificationStatus；
- 不把任意 numeric score 映射成置信度；默认不向用户展示 score；
- 模型不能改变 App 的来源分组、来源核验和候选内容完整度；
- Reranker 不负责截断 token；候选预算由 App 在调用前确定，省略项必须记录原因和 ID。

App 将校验通过的 ID 顺序应用到原候选对象，产生新的 RankedEvidenceSet，记录 strategyId、strategyVersion、逐候选 KEEP/DROP、orderIndex 和 diagnostics。确定性来源限额和上下文预算仍由 App 执行，模型排序不能绕过。若需调整旧的 SourceAwareLegacyEvidenceRanker，先提取其确定性来源限额策略并用原黄金用例证明行为不变；不要直接修改旧排序循环导致默认路径顺序变化。

### 8.3 Reranker 失败

- taskKey 未配置：运行原有确定性排序。
- taskKey 已配置：必须真实请求指定 Reranker。
- 真实请求失败、超时、解析失败或 ID 校验失败：返回明确 RERANKING_FAILED / PARTIAL / UNKNOWN 诊断，不能静默改用另一个模型或把旧排序说成已完成的模型重排。
- 失败后可保留原候选数据以便 UI 重新执行，但不得把模型排序状态标为 RANKED。
- 用户显式切回 deterministic_unconfigured 后，才恢复原有确定性排序路径。

## 9. Token、输入和上下文预算

### 9.1 生成模型预算

每个生成模型分别保存 contextWindowTokens 和 maxOutputTokens。UI 提供常见预设和自定义整数；最大预设到 1M，但这不是容量保证。实际有效预算必须受用户配置、模型声明、Adapter/Tokenizer 能力、供应商接口上限或 Local Runtime/设备实测的最小值约束。

预算组成至少记录：

- system/developer prompt；
- 当前 user input；
- 历史完整轮次；
- SessionState 有界快照；
- RankedEvidence 正文；
- 工具真实执行结果；
- 为本次回复预留的 maxOutputTokens；
- Provider/Runtime 需要的额外协议开销（如有明确计算方式）。

准确 Token 计数：
- 云端优先使用该 modelIdentifier 对应的精确 Tokenizer 或 Provider 明确给出的预估接口；供应商响应 usage 作为事后真实统计。
- 本地使用当前 Runtime 可取得的真实 token count。
- 只知道字符数时，单位必须标 CHARACTERS；tokenCount 为 UNKNOWN，禁止字符比例换算伪造 Token。
- 如果不能在发出请求前证明输入满足预算，按明确的保守限制截断完整消息/证据块或拒绝请求，不把未知预算记为 PASS。
- 超出预算按完整对话轮次、完整证据块裁剪；保留 omittedEvidenceIds、truncatedEvidenceIds 和原因。不得截掉来源标签使正文失去来源语义。

Embedding 和 Reranker 不使用生成模型的 contextWindowTokens；各自使用 maxInputTokens、maxBatchItems、maxCandidates、maxCandidateTokens 独立预算。

### 9.2 1M 上下文的边界

1M 是 UI 可设置的配置上限选项，不是供应商或 E4B 实测容量的声明。保存 1M 不代表请求会实际使用 1M；只有精确 Tokenizer、Provider 真实接口合同或 Local Runtime/Find N2 证据满足时才能按该值发送。E4B ModelInfo.maxContextTokens 与 Conversation token count 当前仅是只读观测，未做设备级预算校准前 App 可用 Token budget 仍为 NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED。

## 10. 设置界面和用户操作

### 10.1 统一入口

在现有设置页增加“AI 模型与供应商”入口，不在每个助手或业务场景分别配置模型。保留已有 E4B GPU/CPU 设置，但把它明确归入本地 E4B 模型详情，不与云端 Provider 配置混淆。

页面按以下结构组织：

1. AI 总开关：一个统一开关。状态受有效 ai_access 约束；没有有效授权时显示不可用原因，不把开关状态伪装成已授权。
2. 供应商连接：新增/编辑/删除 Provider 名称、协议、HTTPS 地址和 API Key；API Key 保存至 Credential Vault。
3. 模型列表：新增/编辑/删除具体 ModelConfig，区分本地/云端，模型 ID 手工录入；本地项展示已导入资产和校验状态。
4. 任务分配：按五个 taskKey 指定 ModelConfig；图片/音频可选择继承默认推理；Embedding/Reranker 独立选择，不显示聊天模型作为继承选项。
5. 模型参数：生成模型设置 contextWindowTokens/maxOutputTokens；Embedding 设置输入长度、dimension/normalization；Reranker 设置候选条数和输入预算。
6. 运行状态：显示“未配置/配置无效/本地文件缺失/上次调用失败/当前状态未知”等事实，不把静态配置校验称为供应商在线或模型能力已确认。

### 10.2 用户交互规则

- 不展示每轮路由原因、能力探针详情或自动模型推荐。
- 不自动拉取或推断供应商模型清单；用户按其已获得的模型 ID 填写。
- 不提供自动切换或“失败后使用另一个模型”的暗箱开关。
- 配置页可展示一次性、常驻的明确说明：选择云端任务后，该任务需要的文本/图片/音频/候选片段会发送至所配置供应商；不增加每家 Provider、每种资料或每轮请求的额外确认弹窗。
- 用户保存配置后，只有真实任务发生时才调用模型；不在页面打开、保存、切换 Tab 时发能力探测请求。
- 切换 ModelConfig 对当前进行中的请求不做中途重路由；当前请求结束或标记 UNKNOWN 后，新请求才读取新配置。
- 删除 Provider 前检查关联 ModelConfig；删除模型前检查 TaskModelSelection 和索引 generation；所有清理动作必须可说明、可恢复。

### 10.3 状态文案

静态配置存在只表示 READY_BY_CONFIG，不表示远端服务可用。实际请求状态按真实结果记录：
- NOT_CONFIGURED；
- READY_BY_CONFIG；
- LOCAL_ASSET_MISSING / LOCAL_ASSET_INVALID；
- CREDENTIAL_MISSING；
- CONFIG_INVALID；
- REQUEST_IN_PROGRESS；
- COMPLETED；
- FAILED；
- UNKNOWN（响应不确定或状态无法确认）。

不得在没有网络请求时显示“连接成功”或“模型可用”。不得把本地 model file present 等同于 runtime ready。

## 11. 数据库迁移、升级与回滚

1. 实现前确认最新 master 的 DatabaseHelper schema version 和 onUpgrade 历史；本方案登记时为 8，后续必须重新核对。
2. 对新 Provider/Model/Selection/Asset/Index generation 表使用单独、顺序的 migration；不重写旧表，不清空 nihaisha.db，不改变既有用户知识、书签、会话和历史。
3. 新增简单 AI 总开关时保持现有已授权用户行为。迁移读取旧版本实际 AI 开关/模型启用行为，不得统一写 false；授权和用户偏好分开存储。
4. 把当前 E4B 安装路径、模型 SHA、GPU/CPU 偏好映射成兼容 ModelConfig，不复制或重新下载 3.66 GB 文件，不要求用户重新导入。
5. 图片/音频无专用配置时映射为 inherit_text_reasoning；Embedding/Reranker 迁移为 deterministic_unconfigured；不得把 E4B 自动映射为这两类任务。
6. migration 失败时数据库必须保持升级前可恢复状态；迁移脚本用旧版数据库 fixture 测试，覆盖新装、升级、重复启动、迁移中断和已有会话/书签保留。
7. Provider/Model 配置回滚不删除用户凭证、模型文件和旧 index generation；模型 Adapter 回滚可以切回用户显式保留的旧配置，但不自动跨模型 fallback。
8. 回滚数据结构时必须先确认已有用户数据可读；不能用删除表或清空缓存伪装回滚完成。

## 12. 错误状态、日志与可观测性

所有任务共享 requestId/traceId，但按任务记录独立阶段：

- CONFIG_RESOLVED；
- ACCESS_GATE_CHECKED；
- CREDENTIAL_RESOLVED（只记录 credentialRef 是否存在，不记录值）；
- RUNTIME_ACQUIRED；
- REQUEST_SENT（不记录敏感载荷）；
- FIRST_TOKEN / RESPONSE_RECEIVED；
- RESPONSE_PARSED；
- APP_VALIDATED；
- INDEX_GENERATION_STAGED / VALIDATED / ACTIVATED；
- RUNTIME_RELEASED。

TRACE 记录 modelConfigId、taskKey、runtimeKind、providerId（必要时脱敏）、modelIdentifier（按日志规则可脱敏）、adapter/protocol version、耗时、输入/输出 token 的实际或 UNKNOWN 状态、错误码、generationId 和实际 backend。默认不记录完整 userText、source excerpt、音视频文件、API Key 或原始模型输入。

错误分类至少覆盖：
- MODEL_NOT_CONFIGURED；
- AI_ACCESS_DENIED / AI_DISABLED / ENTITLEMENT_UNKNOWN；
- PROVIDER_CONFIG_INVALID / CREDENTIAL_MISSING / CREDENTIAL_UNAVAILABLE；
- NETWORK_TLS_FAILED / NETWORK_TIMEOUT / HTTP_UNAUTHORIZED / HTTP_RATE_LIMITED / HTTP_SERVER_ERROR；
- PROVIDER_PROTOCOL_UNSUPPORTED / RESPONSE_PARSE_FAILED / STREAM_INTERRUPTED；
- LOCAL_ASSET_MISSING / LOCAL_ASSET_HASH_MISMATCH / LOCAL_RUNTIME_UNAVAILABLE / LOCAL_RUNTIME_INIT_FAILED / LOCAL_RUNTIME_EXECUTION_FAILED；
- EMBEDDING_DIMENSION_MISMATCH / EMBEDDING_INDEX_BUILD_FAILED / EMBEDDING_INDEX_STALE；
- RERANK_CANDIDATE_ID_INVALID / RERANK_RESPONSE_INCOMPLETE；
- TOKEN_BUDGET_UNKNOWN / TOKEN_BUDGET_EXCEEDED；
- REQUEST_STATUS_UNKNOWN。

错误文字不得直接显示异常中的凭证、请求头、服务器原始 HTML 或绝对文件路径。失败不得被转换成空向量、空列表、默认排序或虚构的完整回复。

## 13. 自动化测试和验收合同

### 13.1 配置与迁移

- taskKey 与 ModelConfig.taskKind 不匹配必须拒绝保存。
- 每个 taskKey 只能有一条 active selection。
- image/audio 只允许继承 text_reasoning；embedding/reranking 继承必须被拒绝。
- 删除被引用 Provider/Model/Asset 时阻止或要求先解除引用。
- schema version 升级保留原有 E4B、用户设置、书签、会话和非 AI 数据。
- 旧用户 AI 行为不能被新开关默认值静默关闭。

### 13.2 授权与 Gateway

- ai_access=false、checking、invalid、temporarilyUnavailable、UNKNOWN、AI 总开关关闭时，Local/Cloud 五类任务均不得发起请求。
- Native 本地 Gate 继续独立 fail-closed。
- Provider Adapter 不能在测试中绕过 Gateway 被业务层直接访问。
- AI 开关变化与 entitlement 恢复竞态必须覆盖，证明不会错误重新打开 Native gate。
- 开关关闭不删除数据，不重置配置或索引；进行中请求的终态按证据记录。

### 13.3 Provider Adapter / HTTP

- SSE 跨 chunk、半行、UTF-8 边界、结束标记、usage、空流和中途断开测试。
- 401/403/429/5xx、TLS/DNS/timeout、错误 JSON、缺字段、超大 payload 和响应类型不匹配测试。
- 重定向跨域和 HTTP 降级不得转发 Authorization。
- 取消/超时后 UNKNOWN 不自动重放；UI 连续点击只发一个请求。
- 凭证不出现在日志、异常、数据库导出、测试快照和崩溃报告。

### 13.4 Embedding / Index

- query 与 chunk 模型 fingerprint、dimension、normalization 不一致必须拒绝查询或构建。
- 向量长度/有限值/归一化错误必须拒绝；不能写出 NaN/Infinity。
- 相同 source snapshot 与 chunkingVersion 输出稳定 chunkId/contentHash。
- 新 generation 构建中失败、应用崩溃、存储不足、模型改变、源数据变化时，旧 active generation 保持可查询。
- active pointer 只在新 generation 完整校验后事务切换。
- 查询永远不混合两个 generation；本地 sourceId/locator/verificationStatus 回链逐项正确。
- 与现有检索黄金集对比，保留原有必需 sourceId、冲突来源和版本；没有黄金证据的提升不得宣布通过。

### 13.5 Reranker

- 输入只来自本轮 CandidateEvidence，条数和 Token 预算可验证。
- 有效返回必须是输入候选 ID 的完整排列。
- 未知/重复/遗漏/越界 ID，坏 JSON，超时，模型输出正文或伪造来源字段，均必须被拒绝。
- App 最终输出仍使用原候选对象的 sourceId、locator、verificationStatus 与 excerpt。
- 确定性排序默认路径在没有配置 Reranker 时与现有 golden snapshot 完全一致。
- Reranker 配置后的失败不得静默转成 deterministic 排序成功。

### 13.6 本地设备验收

Find N2 必须使用真实安装包和固定模型 SHA。分别对 Local Embedding、Local Reranker、E4B 生成模型记录模型加载、冷/热执行、耗时分布、峰值内存、温度/电量、释放、前后台、折叠屏和重复调用。
PASS 必须有设备、系统、App commit SHA、模型 manifest/SHA、runtime/backend、场景、输入输出摘要和原始 TRACE 证据。无真实设备证据一律 MISSING/UNKNOWN/LOCAL ONLY，不以 CI 替代。

## 14. 分阶段实施顺序和任务 Owner

所有任务采用“master 最新基线 + 独立 worktree/分支 + 明确路径所有权 + 小批量 PR + 最终 HEAD 五项门禁 + 合并后 Push CI”的方式。任务开始前先登记 task card；不允许多人同时修改同一文件或共享文档。

| 阶段 | Task ID（建议） | Workstream / Owner | 文件范围（实施前以最新源码定位确认） | 依赖 | 交付与退出条件 |
|---|---|---|---|---|---|
| 0. Local 盘点 | LOCAL-MODEL-EMBED-RERANK-AUDIT-20261128（现 PR #626） | Local | 只读审计；必要时单独审计报告文件 | 无 | 确认 Find N2 可用模型格式、Tokenizer、runtime、内存/耗时和风险；不能证明则明确 MISSING/BLOCKED，不直接引入依赖 |
| 0. Remote 盘点 | REMOTE-MODEL-PROVIDER-AUDIT-20261128 | Remote | 只读检查现有 HTTP/依赖/设置/持久化/平台密钥接口 | 无 | 确认现有可复用代码和依赖；不得在此阶段抢改共享 DTO |
| 1. 配置与安全合同 | AI-MODEL-CONFIG-20261128 | Architecture 定义合同；Remote 实现；Integration 单写台账 | ModelConfig/ProviderConfig/TaskModelSelection、credentialRef、DB migration、Vault 抽象及测试 | 本方案冻结 | 配置字段、迁移、秘密存储和 taskKey 校验通过；只合一个公共配置 PR |
| 2. 统一门禁与 Gateway | AI-MODEL-GATEWAY-20261128 | Remote | AiRuntimeAccessCoordinator、AiModelGateway、HTTP transport、Entitlement/Settings 接线；不改 Native E4B 业务提示 | 阶段 1 | 五任务统一检查 ai_access + AI 开关；安全与 UNKNOWN 测试通过；Native AiModelAccessGate 保留 |
| 3. 云端文本推理 | AI-CLOUD-TEXT-REASONING-20261128 | Remote | Chat Provider Adapter、SSE parser、ReasoningRequest/Response Adapter、token budget | 阶段 2 | 一个明确协议的真实供应商端到端调用；Mock 合同测试齐全；密钥不入库/日志；没有自动路由 |
| 4. 云端多模态 | AI-CLOUD-MULTIMODAL-20261128 | Remote | Image/Audio Adapter 与对应配置；附件边界复用当前 App 约束 | 阶段 3 | 两任务独立配置与继承行为测试；实际供应商调用单独记录；不突破现有音视频输入校验 |
| 5. Local Embedding runtime | LOCAL-EMBED-RUNTIME-20261128 | Local | Local runtime adapter、manifest/importer、Tokenizer 和对应 Native 代码/测试；不改共享 docs | 阶段 0 审计、阶段 1 接口 | 有具体模型/运行库/设备证据；向量维度、预处理、导入哈希、释放和 Find N2 场景通过 |
| 5. Local Reranker runtime | LOCAL-RERANK-RUNTIME-20261128 | Local | 独立 Reranker adapter、manifest、候选协议和 Native 代码/测试；不与 Embedding 共享任务类型 | 阶段 0 审计、阶段 1 接口 | 候选 ID 合同和真实设备执行通过；无证据则保留 MISSING，不虚构本地模型配置可用 |
| 6. Cloud Embedding | AI-CLOUD-EMBEDDING-20261128 | Remote | Embedding Cloud Adapter、batch parser、模型 fingerprint 映射 | 阶段 1、2 | 真实供应商调用返回确定维度/向量顺序；Provider/Model/Token 限制可测 |
| 6. Cloud Reranker | AI-CLOUD-RERANKER-20261128 | Remote | Rerank Cloud Adapter、ID 映射、严格响应解析 | 阶段 1、2 | 真实供应商调用只重排输入候选；完整排列校验通过 |
| 7. 向量索引与 Core-2 接线 | AI-EMBEDDING-INDEX-20261128 | Core-2/Remote 单一 Owner | VectorIndexStore、IndexGeneration、Chunking、AssistantKnowledgeContext 接线；一次仅一条 PR 可改共享 Core-2 文件 | 阶段 5/6 中至少一条 Adapter 可用；阶段 1 | 新 generation/增量更新/原子切换/回滚和黄金召回测试通过；默认路径零回归 |
| 8. 模型设置 UI | AI-MODEL-SETTINGS-UI-20261128 | Remote/UI | SettingsScreen、Provider/Model 编辑页、任务选择页、模型导入 UI | 阶段 1、2；可与阶段 3/5 并行，但配置协议必须冻结 | 五任务配置可见；Embedding/Reranker 独立配置；无能力探针、无每助手模型、无明文凭证 |
| 9. 全链路集成 | AI-MODEL-E2E-20261128 | Integration 协调；各 Owner 分别修复 | 端到端调用、存储迁移、TRACE、回归；不允许 Integration 代替 Local 设备实测 | 阶段 2-8 | 云端真实请求、本地任务、索引与 Reranker 链路均有证据；所有 CI 和设备门禁分别通过 |

### 14.1 并行规则

- Local #626 审计与 Remote Provider/HTTP 源码盘点可并行，因为只读且文件不重叠。
- 阶段 1 的公共数据合同未冻结前，Local 与 Remote 不得分别定义相同 ModelConfig/ModelManifest DTO。
- Local Embedding 与 Local Reranker 可分开实施，但 Native 共用文件、Gradle 依赖、模型加载器必须声明单一 Owner；一段时间内只能一个分支写共享加载器。
- Cloud Embedding/Reranker 可与 Local runtime 实施并行，但不能并行修改 VectorIndexStore/schema 或 AssistantKnowledgeContext 的同一文件。
- Index generation 的 DB migration 由 AI-EMBEDDING-INDEX 的指定 Owner 提交；配置表 migration 由 AI-MODEL-CONFIG 的 Owner 提交，两个 migration 必须顺序基于最新 master，禁止同时把 DatabaseHelper 改成不同版本号。
- Settings UI 与 Provider Adapter 可在合同冻结后并行，但 ModelConfig DTO、字段和持久化 Repository 不允许另建副本。
- ai-layered-runtime-architecture.md 由 Architecture 单一写入；ai-modernization-execution-ledger.md 由 Integration 单一写入；local-real-device-acceptance-handoff.md 由 Local 单一写入。

### 14.2 建议目标代码边界

以下是目标职责位置，不要求为了目录整齐机械创建文件；开始实施时先全仓检索现有同类实现，复用优先：

- 公共模型：lib/models/ai_provider_config.dart、ai_model_config.dart、ai_task_model_selection.dart、ai_model_error.dart、ai_embedding_index_generation.dart。
- 配置与安全：lib/services/ai_model_config_repository.dart、ai_credential_vault.dart、ai_runtime_access_coordinator.dart。
- 统一调用：lib/services/ai_task_model_resolver.dart、ai_model_gateway.dart、ai_cloud_provider_adapter.dart。
- Embedding：lib/services/ai_embedding_adapter.dart、ai_embedding_index_service.dart、ai_vector_index_store.dart。
- Reranking：lib/services/ai_reranker_adapter.dart、ai_reranking_service.dart。
- UI：在现有 SettingsScreen 下建立统一模型/Provider 管理入口，保留现有 E4B 专项 Native 后端控件。
- Native：仅当 Local 审计证明需要时，新增单一任务 Native Adapter；不得把本地 E4B MainActivity 全部重构成通用模型平台。

若现有目录已经存在同职责代码，应扩展或收敛现有实现，不得平行建设第二套 gateway、provider registry、模型状态库或知识上下文 Builder。

## 15. 每个 PR 的提交和合并硬门槛

每个 Task PR 必须包含：

1. Task ID、最新 base SHA、Owner、允许路径、明确不改路径。
2. 修改前后的真实调用链与复用点；新增依赖的必要性和许可证。
3. Provider/Model/Task 的数据字段、错误码和 migration 证据（涉及配置时）。
4. 真实代码与测试，不允许只加 DTO/空 Adapter/占位按钮就标记完成。
5. 至少覆盖成功、失败、超时/UNKNOWN、未授权、开关关闭、配置损坏和回滚路径中的适用项。
6. 最终 PR HEAD 的 Branch validation、Flutter regression、Android arm64/JVM、PR required gate、Fork License 五项均为 SUCCESS；SKIPPED 不算 PASS。
7. 合并后重新核对 master SHA 和 Push CI。Fork License 必须独立记录。
8. Local 模型任务另附 Find N2 TRACE；云端 Mock、CI 和桌面运行结果不能代替设备证据。
9. 不删除失败测试、不放宽验收、不用跳过/重命名测试掩盖失败。
10. 一个 PR 只解决一个可验收边界；不要将 Provider、Index、Reranker、UI 和设备修复塞入一个无法回滚的大批次。

## 16. 回滚边界

- Provider/Model 配置回滚：保留用户数据和 credentialRef；移除代码调用入口前先把对应任务设为不可用，不能丢凭证。
- Credential Vault 回滚：先迁移或显式删除秘密，禁止明文转存。
- Cloud Adapter 回滚：只回退该 Adapter，不能改掉本地模型选择或授权 Token。
- Local Runtime 回滚：保留原有 E4B 和已安装模型文件；不删除用户索引和资料。
- Embedding 索引回滚：active generation 只切回上一个完整验证 generation；新旧 generation 不合并向量；失败构建不影响旧索引。
- Reranker 回滚：用户显式取消该任务模型选择后才回到确定性排序；不能把单次模型失败伪装为用户已经选择 deterministic。
- DB migration 回滚必须保证旧版 App 能读取其所拥有的数据；不可用清空数据库换取启动成功。
- 全局 AI 开关关闭不删除授权、模型、凭证、索引或历史。

## 17. 当前执行状态（初始基线，不可扩大解释）

| 能力 | 当前状态 | 证据/下一步 |
|---|---|---|
| 本地文本生成 | 已有代码路径 / 设备验收仍按设备交接单逐项判定 | Gemma 4 E4B + LiteRT-LM；不表示 Find N2 所有场景已 PASS |
| 本地图片/音频 | 已有 E4B 对应路径 / 设备证据单独记录 | docs/local-ai-e4b.md；不得推定云端接口已存在 |
| 本地 Embedding | MISSING / NEEDS LOCAL AUDIT | PR #626 Local 审计；审计完成前不准入模型文件和 Native 依赖 |
| 本地 Reranker | MISSING / NEEDS LOCAL AUDIT | PR #626 Local 审计；不得用 E4B Chat 补位 |
| 云端 Provider / Credential Vault | NOT_STARTED / MISSING | Remote 后续独立任务 |
| 云端 Gateway + AI 总开关 | NOT_STARTED / MISSING | Remote 后续独立任务；Native Gate 仍保留 |
| 云端文本推理/图片/音频 | NOT_STARTED / MISSING | 按阶段接入真实 Provider Adapter |
| 云端 Embedding / Reranker | NOT_STARTED / MISSING | 两个独立 taskKey 和 Adapter |
| 向量索引 generation | NOT_STARTED / MISSING | Core-2/Remote 单一 Owner；当前确定性召回与排序保持原样 |
| 模型配置 UI / 数据库 migration | NOT_STARTED / MISSING | SettingsScreen 现有本地后端控件只是 E4B 设置，不是通用模型管理 |
| 统一上下文 Token budget | NOT_STARTED / MISSING | 需精确 Tokenizer/Runtime 预算及测试；E4B 当前只是观测信息 |
| Find N2 Local Embedding/Reranker | LOCAL ONLY / UNKNOWN / MISSING | 必须真实设备测量；CI/模拟器/桌面不能替代 |

方案合入、任务卡建立、PR 通过 CI 只说明文档/代码范围完成了对应门槛，不自动提升本表任何运行时状态。

---

## 18. 最终完成定义

整个模型改造只有在以下条件全部具备时，才可整体标记完成：

- ProviderConfig、ModelConfig、TaskModelSelection、CredentialVault、模型资产和数据迁移均真实接线且可回滚。
- 一个统一 Gateway 覆盖五类 taskKey，授权与 AI 总开关在每个请求前生效，Native AiModelAccessGate 仍有效。
- 本地和云端文本推理、图片、音频有用户选择和可验证调用；未配置/失败状态如实呈现。
- 本地与云端 Embedding 各自有独立 Adapter；查询/文档同一向量空间；Index generation 可构建、验证、增量更新、原子切换和回滚。
- 本地与云端 Reranker 各自有独立 Adapter；严格只重排输入 CandidateEvidence ID；不修改来源字段。
- 现有关键词/实体/结构化召回、确定性排序、来源追溯和知识学习黄金行为保持回归通过。
- Token 预算对每个生成模型可解释；未知 Token 不冒充 Token；Local 预算有设备实测。
- 现有 E4B 安装、对话历史、用户资料、书签和旧数据库升级不丢失。
- 所有 PR 最终 HEAD 五项门禁通过，合并后主线 Push CI 复核完成。
- Find N2 的 Local Embedding、Local Reranker、E4B 与模型切换/释放/索引场景按唯一设备交接单有真实 TRACE 和结果。
- 没有残留的自动切换、自动上传、自动能力探测、隐式重试、来源状态提升或失败伪装。

达到这些条件前，整体状态只能是 PARTIAL，必须把每个 MISSING/UNKNOWN/BLOCKED 项留在执行台账，不能用“架构已定”代替“功能已实现”。
