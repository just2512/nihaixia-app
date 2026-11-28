# AI 核心分层运行时架构约束

> **文件性质：AI 核心架构规范 / 高优先级执行约束。**
>
> **优先级：核心主线。** 本文件定义整个 AI 能力的职责划分、数据契约、跨层边界和实施顺序。用户 Markdown 书架、Embedding 模型和其他知识源扩展必须服从本文件，不得反过来牵引核心架构。
>
> **核心决策：** 知识召回、证据排序、会话记忆、语言推理、业务执行五项职责必须逻辑独立、输入输出可审计、状态所有权清楚。它们不是五个互相自治的 Agent，也不要求拆成五套服务、五个数据库或五个模型。
>
> 本文件与 docs/product-positioning-and-boundaries.md、docs/ai-capability-audit.md、docs/pro-edition-architecture-constraints.md 和 docs/ai-modernization-execution-ledger.md 配套使用。产品定位约束产品边界；本文件定义五层运行时职责；专业版架构约束 v1.4 定义本地/云端任务模型配置与唯一授权；AI 审计规范定义实现与证据门槛。2026-11-28 起，v1.4 模型运行时补充条款优先于本文早期仅有 E4B/尚未授权 Embedding、Reranker 或云端模型的历史表述。

## 1. 架构目标：五项职责独立，而不是一个模型包办

核心目标不是增加 Agent 数量，而是让每项能力都能独立解释、独立测试、独立失败和独立替换：

1. **知识召回（Knowledge Retrieval）**：确定“有哪些候选资料可能相关”。
2. **证据排序（Evidence Ranking）**：确定“哪些候选证据值得进入本轮上下文、先后顺序如何、为什么保留/排除”。
3. **会话记忆（Session Memory）**：确定“当前用户、当前会话和当前任务已经明确了什么，哪些状态可跨轮延续”。
4. **语言推理（Language Reasoning）**：由用户为 text_reasoning 选择的本地或云端生成模型理解问题、综合证据、解释、澄清和提出受约束的业务动作意图；当前端侧 E4B 是已实现的本地模型路径，不是唯一允许的推理运行时。
5. **业务执行（Business Execution）**：由 App 现有确定性代码校验参数、权限和状态，执行规则、计算或工具，并验证真实结果。

**不允许再把以下内容混成一个“AI 上下文/模型能力”：**

- 候选召回不等于证据判断；
- 相关性排序不等于来源真实性或医学正确性；
- 会话记忆不等于知识库，也不等于把所有历史文本重放给模型；
- 语言推理不等于业务执行；
- 模型提出工具意图不等于工具已执行；
- 模型生成引用 ID 不等于引用可定位；
- 引用可定位不等于作者、版本、底本或内容真实性已核验。

### 1.1 五层是逻辑边界，不是五套 Agent 平台

- 五层必须有独立责任、输入/输出契约、状态归属和测试边界。
- 可以先通过现有 Repository、Policy、Builder、Dispatcher 和轻量 Adapter 形成边界，不要求一开始新建五组服务或重写现有模块。
- 不新建通用 Agent 平台、DAG、自治多 Agent 协作或重复会话数据库。
- 不要求每层都有独立 LLM 或 Agent。模型按 v1.4 任务能力配置选择本地或云端；现有 Gemma 4 E4B 是已接入的本地推理路径。Embedding 与 Reranker 已获准作为知识召回/排序层的独立可配置任务模型，均须提供本地与云端接入路径；未配置时保持现有确定性检索/排序。该授权不等于运行时已经实现，也不授权自动能力探测或自动模型切换。
- 五层之间只交换定义明确的数据，不共享可任意修改的全局可变状态。

## 2. 五层职责与禁止越界

| 层 | 核心问题 | 唯一主要输出 | 明确禁止 |
|---|---|---|---|
| 知识召回 | 哪些本地资料候选可能匹配查询？ | CandidateEvidence 列表 | 直接认定权威性、医学正确性；把整本书塞给模型 |
| 证据排序 | 哪些候选应进入本轮证据集？ | RankedEvidenceSet | 伪造证据、篡改来源状态、把分数当真实性 |
| 会话记忆 | 当前会话和任务状态中，哪些有边界的信息可以跨轮延续？ | 有界 transcript + SessionStateSnapshot（结构事实、来源引用、任务状态） | RAG 正文、隐藏 Ledger 事件、跨会话事实、未确认推断被提升为用户事实；不得把字符上限称为 Token 预算 |
| 语言推理 | 如何理解、解释、比较和提出下一步？ | ReasoningResponse | 自行补造来源、规则结果、数值；直接执行工具 |
| 业务执行 | App 是否允许并确实完成指定操作？ | ExecutionResult | 由自由文本决定权限；把模型声称成功当成执行成功 |

### 2.1 知识召回：只负责候选发现

输入：

- 原始用户查询；
- 会话记忆提供的已解析实体、当前主题和必要指代；
- 用户明确指定的资料范围；
- 数据源过滤条件和检索策略版本。

输出每一条候选的稳定身份和可追溯信息，至少包含：

- sourceId、sourceType/origin、materialKind、verificationStatus；
- source version、asset/bookId、chunkId 或现有稳定条目 ID；
- title、chapterPath、locator、originalText/snippet；
- queryId、retrievalMethod、命中依据；
- 候选是否完整、是否被截断及可解释的失败状态。

约束：

- 保留原始 query；派生 query 必须另行记录，不能覆盖原始意图。
- 确定性实体、别名和既有索引优先；是否加入向量召回由黄金用例决定。
- 召回可以多路并行，但输出必须归一为候选契约。
- 检索未命中标记 MISSING；数据源不可访问或执行异常按实际情况标 FAILED/UNKNOWN。
- 不在本层直接把 top-K 候选拼成长 Prompt。候选必须先经过证据排序。

### 2.2 证据排序：与召回分离的证据选择层

证据排序不是“再搜索一次”，而是独立接收候选集，决定本轮证据集的选择、排序、去重和预算。

输入：

- CandidateEvidence 列表；
- 用户当前意图与限定范围；
- 明确的证据要求（例如必须有方剂组成、经典条文、规则结果或 App 计算结果）；
- 本轮上下文的 token/字符预算和来源多样性约束。

输出 RankedEvidenceSet，至少记录：

- 有序 evidence IDs；
- 每条候选的保留/排除结果和原因；
- 重复候选合并关系，但保留原始来源身份；
- 预算裁剪结果和遗漏来源；
- 排序策略/版本及可重复的输入快照。

约束：

- 排序可组合现有标题/精确匹配、关键词、已配置 Embedding 向量召回、RRF 和已配置 Reranker；每种策略必须单独可测。Embedding/Reranker 的本地与云端 Adapter 按用户配置选择，不由模型名推断。
- 评分只表示当前检索任务的相关性信号，不表示医学正确性、经典权威性、来源真实性或事实置信度。
- 来源身份和核验状态只能读取数据层提供的元数据，不能由排序模型自行提升。
- 不得静默融合版本冲突的方剂组成、剂量、条文和医案记载；冲突证据应分来源保留。
- 不以候选数量、向量相似度或 RRF 数值代替黄金查询集验收。
- Reranker 未配置时不发起模型调用，继续 SourceAwareLegacyEvidenceRanker 的确定性排序；配置后必须使用用户选定的本地或云端 Reranker，并验证返回的候选 ID 只能来自本轮输入集合。配置后的失败不得静默降级或自动换模型。

### 2.3 会话记忆：独立于知识库和临时证据

记忆层管理当前会话和任务状态，不负责搜索书籍，也不负责生成答案。

至少区分以下数据：

| 数据类别 | 生命周期 | 可保存内容 | 不应保存 |
|---|---|---|---|
| UI 会话记录 | 按现有消息数据库生命周期 | 用户消息、助手展示回复、消息元数据 | 把它当作完整模型 KV Cache |
| Native 模型历史 | 有界、可重建 | 最近少量干净用户原话、必要的紧凑状态/摘要 | RAG 正文、完整 modelInput、无界完整助手回复 |
| 结构化任务状态 | 按任务生命周期 | 已确认实体/字段、缺参、业务结果 ID、用户确认状态 | 未确认的模型猜测被提升为用户事实 |
| 证据引用状态 | 按会话/来源版本生命周期 | sourceId、版本 ID、chunk ID、可重新读取的引用标识 | 长期复制整段书籍正文作为记忆 |

记忆原则：

- Session ID 是硬隔离边界；无法确认所属会话时不得使用。
- 用户原话、模型推断、用户确认事实、App 规则结果和外部资料必须有不同来源标签。
- 模型摘要是派生状态，不得伪装成用户明确陈述；需可由原始消息或结构化字段追溯。
- 历轮 RAG 只保留 source IDs 与必要的证据状态；后续追问时重新读取/检索，不把旧正文无限叠加。
- conversationHistoryTurns 只接收干净、经过预算控制的会话内容；临时 RAG/context 不属于成功轮次的 userText。
- 完整助手回答可留在既有 UI 消息数据库，但不得无上限地重放到 Native Conversation。
- 历史重建必须在 Native 串行队列中完成；若无法安全恢复，显式停止并要求用户确认，不自动重放执行状态 UNKNOWN 的请求。
- Token 预算以运行时可取得的 token 数为准；字符数只能称字符数，截断只能按完整条目或明确定义的结构边界发生。

### 2.4 语言推理：用户选定的本地/云端模型负责理解和表达，不承担其他四层的权威职责

输入必须是已组装且带来源的 ReasoningRequest：

- 当前用户原话；
- 当前会话的有界 SessionStateSnapshot；
- 已排序的 RankedEvidenceSet；
- 如有则包含确定性 Business ExecutionResult；
- 当前模式、权限边界和响应 schema。

当前配置的生成模型可以：

- 理解自然语言、处理指代和歧义；
- 对候选证据进行归纳、比较和解释；
- 指出冲突、缺项和不确定项；
- 生成澄清问题；
- 提出一个已登记业务能力的结构化调用意图；
- 输出带引用 ID 的解释内容。

任何本地或云端生成模型均不可以：

- 根据预训练记忆补造本地库未命中的医学事实、古籍原文、条文号、书目版本或来源；
- 自行把 source 标成 SYSTEM/USER、AUTHORITATIVE/VERIFIED 或改变 verificationStatus；
- 声称自己已核验来源、已执行工具或已保存数据；
- 自行心算并替代 App 确定性计算；
- 直接调用任意 Native 方法、SQL、文件系统或未登记业务能力；
- 通过资料区、书籍内容或用户提示突破现有授权门禁和业务范围。

输出统一 ReasoningResponse：

- responseKind：ANSWER / CLARIFICATION / ACTION_PROPOSAL / REFUSAL / INSUFFICIENT_EVIDENCE；
- answer segments 与必要的结构化字段；
- referencedEvidenceIds；
- unknowns / conflicts / omittedEvidence；
- optional BusinessActionProposal（只能是已登记 capability ID + typed arguments）；
- model status 与解析状态。

模型不得输出“来源已核验”作为权威状态字段。代码对每个引用 ID 做存在性、版本和可访问性验证；UI 的原文卡片由本地数据回填。

### 2.5 业务执行：唯一真实动作入口

业务执行层只接收结构化、已登记的动作请求，负责：

1. capability 是否存在、当前模式是否允许；
2. 用户是否提供并确认所需参数；
3. typed argument schema、范围、单位和必填字段校验；
4. 统一 aiEnabledForRuntime（有效 ai_access 与用户 AI 总开关同时满足）；Native LiteRT 仍由 AiModelAccessGate 最终拦截，云端 HTTP 由受控 Model Gateway 在每次请求前检查；
5. 通过 App 已有确定性业务函数执行；
6. 返回真实 ExecutionResult，包括执行状态、解析后的参数、结果、来源和错误；
7. 在需要时提供可验证的幂等/重试语义。

约束：

- 用户自然语言和 RAG 正文不能直接执行工具。
- 当前配置的本地或云端模型只能提出 ACTION_PROPOSAL；由代码进行权限与参数判断后才可能执行。
- 未登记、未授权、缺参、类型不符、跨领域请求均由代码拒绝或要求澄清。
- 只有业务函数真实返回并通过结果校验，执行状态才可标 SUCCEEDED。
- 执行状态分为 NOT_STARTED / SUCCEEDED / FAILED / UNKNOWN；UNKNOWN 不得自动重放有副作用的请求。
- 排盘、历法、问诊规则、剂量换算及其他既有确定性计算继续由 App 既有函数执行，不能迁移给模型。
- 业务执行与模型授权分开治理。全部本地/云端 LLM、多模态、Embedding 和 Reranker 调用均受唯一 ai_access 与用户 AI 总开关共同约束；Native LiteRT 加载/推理继续经过 AiModelAccessGate，云端请求经过受控 Model Gateway。不得新增 cloud_ai_access 或其他独立收费权益。

### 2.6 核心 DTO 契约（v1，字段级冻结）

以下是五层之间的逻辑 DTO，不要求立即采用 JSON 序列化、增加数据库表或建立独立服务。第一批实现优先使用不可变 Dart/Kotlin 值对象；只有跨进程、跨语言或持久化确有需要时才定义 wire format。字段缺失、未命中和执行未知必须用状态表达，不能用空字符串统一吞并。

**通用约束**

- ID 均为不透明、非空标识；接收方不得通过解析 ID 推断来源类型、授权或真实性。
- 来源字段只能原样传递数据层提供的值。任何层均不得把 `UNKNOWN`、`UNVERIFIED` 或 `MISSING` 自动升级为 `VERIFIED`。
- 集合和快照创建后不可变；层间不得共享任意可修改的全局状态。
- v1 不定义相关性分数或事实置信度字段。后续若为排序实验引入数值，只能作为诊断信号，不能表达医学正确性、来源真实性或业务成功。
- 所有预算必须显式记录单位。字符数不能标成 token 数；无法取得 token 数时写 `UNKNOWN`。
- 原文正文不进入会话记忆；记忆保存稳定引用 ID，引用正文按需回源。

**A. 知识召回契约**

`CandidateEvidence`：

| 字段 | 类型/含义 | 约束 |
|---|---|---|
| `evidenceId` | 候选证据实例 ID | 同一来源在不同查询/片段下可有不同实例 ID |
| `sourceId` | 本地来源稳定 ID | 必须能交给来源 Resolver 回查；不得由模型编造 |
| `sourceVersion` | 来源版本/内容版本 | 无版本信息时为 UNKNOWN，不用猜测值填充 |
| `origin` | SYSTEM / USER / APP_DATA / UNKNOWN | 由数据源提供；USER 内容始终是不可信输入 |
| `materialKind` | 资料类别 | 例如 classic_text、lecture、formula、medical_case；保留真实来源值 |
| `verificationStatus` | 来源核验状态 | 原样传递；不等于召回质量 |
| `assetId`、`chunkId` | 资产/片段稳定标识 | 可为空；不得把标题作为唯一身份 |
| `title`、`chapterPath`、`locator` | 可读标题和定位 | 缺失项显式 MISSING |
| `excerpt` | 候选原文片段或摘要 | 必须能由 sourceId + locator 回查；标明是否截断 |
| `queryId` | 命中的查询 ID | 原始 query 与派生 query 分别有 ID |
| `retrievalMethod`、`matchBasis` | 检索路径和命中依据 | 记录 deterministic/keyword/vector 等实际方式，不推断 |
| `completeness` | COMPLETE / TRUNCATED / UNKNOWN | 描述候选内容完整度，不描述来源可信度 |

`CandidateEvidenceBatch`：

- `requestId`、`originalQuery`、`derivedQueries[]`（每项含 queryId、query、reason）；
- `status`：RETRIEVED / MISSING / FAILED / UNKNOWN / PARTIAL；
- `candidates[]`：CandidateEvidence；
- `diagnostics[]`：数据源失败、跳过原因和截断记录。

召回层只发现候选；不能自行选出最终上下文，更不能把候选数或相似度当成成功。

**B. 证据排序契约**

`EvidenceRankingDecision`：

- `evidenceId`；
- `disposition`：KEEP / DROP；
- `reasonCode` 与可读 `reason`；
- KEEP 项必须有 `orderIndex`；DROP 项不得伪造排名。

`RankedEvidenceSet`：

- `requestId`、`strategyId`、`strategyVersion`；
- `decisions[]`：本轮收到的每个候选必须有 KEEP 或 DROP 记录；
- `orderedEvidenceIds[]`：与 KEEP 决策一一对应、顺序无歧义；
- `budget`：`unit`（CHARACTERS / TOKENS）、`limit`、`used`、`omittedEvidenceIds[]`、`truncatedEvidenceIds[]`；
- `status`：RANKED / NO_USABLE_EVIDENCE / BUDGET_TRUNCATED / FAILED。

排序层不负责召回，不改变来源核验状态，不通过静默合并消除不同来源/版本的冲突。v1 不要求打分字段。

**C. 会话记忆契约**

`SessionStateSnapshot`：

- `sessionId`、`revision`、`status`（RESTORED / PARTIAL / SESSION_MISMATCH / UNKNOWN）；
- `facts[]`：有限的结构化事实；
- `evidenceReferences[]`：sourceId、sourceVersion、evidenceId/chunkId 等可回查 ID；
- `activeTaskId`（可选）。

每个 `SessionStateFact` 必须包含 `factId`、`key`、`value`、`provenance` 和必要的 `sourceIds[]`。provenance 固定区分 USER_ORIGINAL、USER_CONFIRMED、MODEL_INFERRED、APP_RESULT、SOURCE_REFERENCE。MODEL_INFERRED 不得被提升为用户确认事实；APP_RESULT 必须能回查实际业务结果。任何 fact 的会话归属不明时不得装入快照。

Native 恢复 transcript 与 SessionStateSnapshot 是两个不同对象：前者只承载有界的干净对话轮次；后者承载可压缩、可校验的结构化任务状态。RAG 正文、完整 modelInput 和无界助手长回复均不属于 Native transcript。

**D. 语言推理契约**

`ReasoningRequest`：

- `requestId`、`sessionId`、`userText`（用户原话，不用改写后的提示替代）；
- `mode`、`sessionState`（有界快照）；
- `rankedEvidence`（可选；只能包含已排序且可回查的证据）；
- `executionResults[]`（可选；来自 App 实际执行结果）；
- `responseSchemaVersion`。

`ReasoningResponse`：

- `requestId`；
- `responseKind`：ANSWER / CLARIFICATION / ACTION_PROPOSAL / REFUSAL / INSUFFICIENT_EVIDENCE；
- `status`：COMPLETED / EMPTY / PARSE_FAILED / INSUFFICIENT_EVIDENCE / UNKNOWN；
- `segments[]`（可读文本片段；引用需以 evidence ID 单独标注）；
- `referencedEvidenceIds[]`、`unknowns[]`、`conflicts[]`、`omittedEvidenceIds[]`；
- `actionProposal`（仅 responseKind 为 ACTION_PROPOSAL 时可提供）。

模型生成的 evidence ID 和 action proposal 均为不可信输入，必须由 App 校验。解析失败、空回复和证据不足不能包装成 COMPLETED。

**E. 业务执行契约**

`BusinessActionProposal`：

- `proposalId`、`capabilityId`、`arguments`；
- v1 arguments 沿用现有工具计划的 key/value 字符串载荷，以便兼容当前执行器；它不是“已校验参数”，各能力必须用自己的确定性 schema 校验类型、单位、范围、必填项和用户确认。
- 不含模型可控制的 `authorized`、`userConfirmed`、`executed` 或 `success` 字段。提案本身永远不执行操作。

`ExecutionResult`：

- `invocationId`、`capabilityId`；
- `status`：NOT_STARTED / SUCCEEDED / FAILED / UNKNOWN；
- `actualArguments`：执行器实际采用并解析的参数；
- `resultValues`、`sourceIds[]`；
- `failureCode` / 安全错误说明（失败时）。

只有真实业务函数已执行、返回类型/来源/参数经过 App 校验后，才允许标 SUCCEEDED。执行调用后响应丢失且无法确认副作用时必须标 UNKNOWN；不得重放。

**兼容策略**

- 现有 `AssistantKnowledgeContextResult`、`ToolExecutionPlan`、`AssistantToolResult` 是 v1 的既有实现/适配源，不要求立即废弃或改名。
- 不创建第二套会话数据库，不迁移业务算法，不新增授权 Feature；v1.4 已有 ai_access 与 Native `AiModelAccessGate` 继续沿用，并由统一用户 AI 开关扩展到云端请求入口。
- 后续代码按“一个边界、一个可验证切片”逐步适配；未被调用路径消费的 DTO 只算契约资产，不算运行时能力已完成。

## 3. 五层之间的统一数据流

用户输入
  → 意图/实体初步解析 + 读取当前 SessionStateSnapshot
  → 知识召回，输出 CandidateEvidence
  → 证据排序，输出 RankedEvidenceSet
  → 会话记忆提供有界状态和来源引用
  → 组装 ReasoningRequest
  → 用户选定的本地/云端语言模型推理
  → ANSWER / CLARIFICATION，或输出 ACTION_PROPOSAL
  → 如有动作提案，经过业务执行 Gate
  → ExecutionResult 返回结果解释
  → 引用/结果确定性校验与最终展示
  → 按策略提交会话/任务状态

该流程表示职责与数据流，不要求每轮必须调用五个独立进程，也不表示所有请求都要检索或执行工具。

### 3.1 典型请求路径

| 请求类型 | 必须经过 | 可以省略 |
|---|---|---|
| 纯闲聊/简单解释 | 会话记忆读取 → 默认本地/云端推理模型 → 状态提交 | 知识召回、证据排序、业务执行 |
| 本地知识问答 | 会话记忆读取 → 知识召回（可按配置使用本地/云端 Embedding）→ 证据排序（可按配置使用本地/云端 Reranker）→ 默认本地/云端推理模型 → 引用校验 | 业务执行 |
| 跨轮追问 | 会话记忆/实体指代解析 → 必要时重新召回/排序 → 当前配置的本地/云端推理模型 | 无关历史资料重放 |
| App 确定性工具请求 | 会话记忆读取 → 当前配置的本地/云端模型意图/参数解析（必要时）→ 业务执行 Gate → 结果校验 → 当前配置模型解释 | 无关知识召回 |
| 复合任务 | 各子任务按显式顺序调用对应层，并分别保存状态 | 不要求每个子任务重复加载所有资料 |

## 4. 跨层失败状态与来源语义

各层必须保留自己的失败原因，禁止统一吞成“AI 回答失败”。

| 层 | 典型状态 | 处理要求 |
|---|---|---|
| 知识召回 | RETRIEVED / MISSING / FAILED / UNKNOWN / PARTIAL | 记录 query、数据源、候选 ID 和缺失原因 |
| 证据排序 | RANKED / NO_USABLE_EVIDENCE / BUDGET_TRUNCATED / FAILED | 记录保留与排除的候选、预算和策略版本 |
| 会话记忆 | RESTORED / PARTIAL / SESSION_MISMATCH / UNKNOWN | 不跨会话取值；状态不完整时显式降级 |
| 语言推理 | COMPLETED / EMPTY / PARSE_FAILED / INSUFFICIENT_EVIDENCE / UNKNOWN | 空回复不能假装成功；自由文本不能绕过 schema |
| 业务执行 | NOT_STARTED / SUCCEEDED / FAILED / UNKNOWN | UNKNOWN 不自动重放；结果必须回到验证层 |

所有层都遵守：

- 失败不自动提升其他层的权限；
- 证据不足不得用模型记忆补造；
- 排序分数不得作为核验结论；
- 模型自称“已完成”不构成测试证据；
- 数据和状态冲突时保留冲突并明确标记，不做静默覆盖。

## 5. 当前代码基线：先拆责任，不重写现有架构

本文件定义目标职责边界，不宣称当前代码已经完全分层。

当前已知的主要边界问题和审计方向：

1. Core-2 已完成当前约定的召回/聚合/排序责任边界：各来源输出 CandidateEvidence，MultiSourceEvidencePipeline 只做来源聚合，SourceAwareLegacyEvidenceRanker 独立产出 RankedEvidenceSet，AssistantKnowledgeContextResult 输出 metadata-only candidateSnapshot 与最终呈现引用。AssistantKnowledgeContextBuilder 仍编排查询生成和上下文物化；后续不得重复建设候选/排序审计对象或为追求分层而改变既有黄金行为。
2. Native Conversation 重建所用的成功轮次 transcript 与临时 RAG 输入需要严格隔离；不得把检索正文或完整 modelInput 写入用于恢复的历史列表。
3. 当前 UI transcript、Native Conversation history、结构化任务状态和检索证据是不同数据，不得彼此替代。
4. 配置的本地/云端生成模型承担语言推理；ToolRouter/HeadlessToolDispatcher、ContextResolutionGateway 和 App 既有确定性业务函数承担不同的执行/来源校验职责，不能把它们合并为模型 Agent。
5. 现有授权、模型加载、Native 单线程队列、GPU/CPU fallback 和保守恢复语义必须保留；任何拆分须证明没有并发、重复执行、资源释放或数据恢复回归。
6. 每个候选新 Adapter/DTO 必须指向实际调用链缺口和可复现测试；不因为图上有五层就机械新增五个模块。

### 5.1 当前 master 源码映射与已确认断点（2026-11-28）

**AI 运行时代码审计基线：** 五层运行时集成点仍为 PR #585 合并提交 `45144f6c3d140d259ac51f8cfbb886c19c10e0a3`（包含 PR #583 图片/音频结构化推理协议、PR #585 20 轮记忆隔离与工具执行回流 E2E）。Core-3 旧非结构化包装 API 已由 PR #594 退役（merge `11ac0c5918e5c25754b44e71f0ba48c82bea6669`），Native 不可达媒体 helper 已由 PR #598 清理（merge `04eb5bec9321b3d00eb85fdea7c0bd31b6fdc40f`）。后续 Core-1 用户输入恢复边界见 PR #610，ReasoningResponse 严格整数 schema 合同见 PR #611，并行工作流/PR 必备门禁见 PR #612，Native GPU→CPU fallback 原因观测见 PR #618，master CI 重复触发去重见 PR #619，确定性玄学入口路由优先级见 PR #615。**当前 AI 运行时代码基线为 `master@805f006ed502c5cbf10dba4ad30428ee9761eb42`（PR #622 squash merge），Core-1 新增 SessionState 专用 SQLite 有界投影；PR #617/#620 是此前的文档专用提交，不改变当时运行时代码。** PR #622 最终 HEAD `1bd334ba64d46488a7008a49647bf83860f652cb` 的 Branch validation `140903069854`、Flutter regression `140903070020`、Android arm64/JVM `140905099227`、PR required gate `140905913256` 与 Fork License job `140903069713` 均 SUCCESS；五项均绑定该最终 HEAD。此前文档主线快照为 `9a929398e8b15fef57d8a3f749d68cbc4a5113e4`，本次文档同步由 PR #623 单独承接。PR #619 将 Flutter Quality Gate 改为手动 `workflow_dispatch`，其诊断步骤保留。以下按已合并代码描述生产能力；其他 SHA 的 CI、SKIPPED 项和本地未执行的 TRACE 不计为当前通过证据。

| 目标职责 | 当前主要代码位置 | 当前状态与断点 |
|---|---|---|
| 知识召回 | ClassicEvidencePipeline、GujiEvidencePipeline、MedicalCaseEvidencePipeline；Formula、Herb、Acupuncture formula、Acupoint、Neijing 结构化资料适配为 CandidateEvidence；AssistantKnowledgeContextBuilder.buildAsync/buildWithEvidenceAsync | **当前约定范围已落地：** #568 将五类本地结构化资料纳入请求级候选，并与经典/医案/古籍候选进入 MultiSourceEvidencePipeline；候选快照保留 query/retrieval provenance 和来源身份，后续由独立 ranker 处理。AssistantKnowledgeContextBuilder 仍编排现有 query/matching 与上下文物化，保留 legacy 命中语义；不代表覆盖全部数据源、独立查询生成器或内容正确性审定。 |
| 证据排序 | MultiSourceEvidencePipeline.combine、SourceAwareLegacyEvidenceRanker.rank、AssistantKnowledgeContextBuilder.buildWithEvidenceAsync | **当前约定范围已落地：** MultiSourceEvidencePipeline 仅合并并命名空间隔离各来源 CandidateEvidence，不自行排序；SourceAwareLegacyEvidenceRanker 独立接收候选并输出不可变 RankedEvidenceSet（requestId、strategyId/version、逐候选 KEEP/DROP 原因、稳定顺序、状态和诊断）。AssistantKnowledgeContextResult 同时提供排序前的 metadata-only AssistantKnowledgeCandidateSnapshot、完整排序决策，以及仅包含完整呈现且已解析来源的 rankedEvidence；最终 6,500 UTF-16 code units 呈现预算记录 omitted/truncated evidence IDs。**边界：** 当前策略是有意保留的确定性 legacy 来源顺序/每来源上限，不是语义相关性排序；6,500 字符是呈现预算，不是模型 Token/input budget。检索查询和上下文物化仍由 AssistantKnowledgeContextBuilder 编排，但召回/聚合/排序输入输出边界已独立可测。 |
| 会话记忆 | SessionStateSnapshotBuilder、AssistantConversationStore.getAssistantMessagesForSessionState / DatabaseHelper、LocalAiConversationHistory / LocalAiConversationSessionPolicy、Native LocalAiConversationHistoryPolicy / LocalAiSessionStateInputPolicy、AssistantReasoningTurnLedger、AssistantToolInvocationLedger | **云端确定性边界已落地，设备级证据仍缺失：** SessionStateSnapshot 具有 provenance 与 conversation owner 校验；隐藏 role=tool 的推理/执行 Ledger 不进入普通会话记忆。PR #565 追踪 RAG/SessionState/reasoning metadata/媒体输入污染活动 KV，并在下一请求前仅对 dirty cache 从有界成功 transcript 重建；PR #575 持久化 PENDING/FINALIZED/REJECTED/UNKNOWN/SUPERSEDED，未完成请求恢复为 UNKNOWN 且不自动重放；PR #610 在 MethodChannel 前限制用户自述投影并由 Native 二次校验。**PR #622（merge `805f006ed502c5cbf10dba4ad30428ee9761eb42`）新增 SessionState 专用 SQLite 读取：最多读取最近 129 条 user/assistant 行，按消息 ID 正序返回，assistant 正文不投影；Builder 最多处理最近 128 条，检测到更早前缀后标记 PARTIAL；用户正文与 metadata 在 SQL 层做有界投影，超限 metadata 在 JSON 解码前拒绝；证据引用最多 64 条并显式报告截断。** 原始完整历史 API 保持不变，继续供 UI 与 Reasoning Ledger 使用。Native `Conversation.getTokenCount()` 与 `ModelInfo.maxContextTokens()` 仍只是只读观测；`conversationKvCacheBudgetStatus=NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`，App 可用输入 Token 预算、动态预算、安全裁剪和自动压缩仍未配置。LiteRT KV Cache 本身不持久化；真实设备数值、GPU/CPU 多轮与进程恢复为 DEVICE UNKNOWN。
| 语言推理 | ReasoningRequest / ReasoningResponse v1、ReasoningRequestPromptFormatter、ReasoningResponseCodec、ReasoningKnowledgeAnswerAdapter、LocalAiService；Native sendLocalReasoningMessage / sendLocalReasoningAttachmentMessage、finalizeReasoningTurn / rejectReasoningTurn | **结构化主路径与媒体附件协议已接线；旧自由文本入口退役：** #573 覆盖 automatic、consultation、learning、tools、metaphysics 五种主文本模式，#583 覆盖 image/audio 附件与 Native 双阶段提交；#594 删除 LocalAiService 旧 sendMessage*/sendImage*/sendAudio* 包装 API；#598 删除 MainActivity 中无调用点的 sendLocalImage()/sendLocalAudio() 旧自由文本媒体 helper。Native 旧 sendMessage/sendImage/sendAudio MethodChannel 仅保留 fail-closed 拒绝，不调用模型。静态审计核对 8 个真实 Native 模型调用入口均设置 requiresAiAccess=true，统一 runAiTask 执行唯一 AiModelAccessGate。图片结果为结构化观察，音频转写在用户确认前仍是待确认草稿；intent、Bazi slot、symptom、单题问项继续使用独立窄任务 DTO。 |
| 业务执行 | ReasoningActionProposalGate / Adapter、AssistantToolExecutionCoordinator、AssistantToolInvocationLedger、HeadlessToolDispatcher.executePlan、ReasoningExecutionResultAdapter | **四项受限动作提案闭环及能力级审计已完成当前云端范围：** #561/#566 接通请求级 allowlist、App 显式确认、持久化 one-shot claim、Dispatcher、终态安全读回和只读结果解释。当前仅允许 `dosage`、`solar_terms`、`yuxiaji_omen`、`sanshan_lingqian` 四项；能力输入、来源、副作用、幂等/时间依赖及补偿适用性已逐项记录（见 `docs/assistant-tool-capability-audit.md` §14 与执行台账 §126）。四项均为纯计算或本地只读，没有外部业务写入；执行中通用协作取消与 deadline 未实现，不把关闭 UI 或 `Future.timeout` 说成底层执行已取消。其他 Router 注册项不因此自动成为模型可调用能力。UNKNOWN 不重放。 |

### 5.2 当前源码、测试锚点与未闭环项

| 层 | 主要回归锚点 | 仍需解决的明确缺口 |
|---|---|---|
| Core-0 契约与源码映射 | 本文件 §2 DTO、§3 数据流、§5.1 当前映射；各层现有契约测试 | 本轮只冻结当前代码真实入口、数据所有权和状态，不新增服务、Agent、数据库、模型或权限门禁。 |
| Core-1 会话记忆 | `test/session_state_snapshot_builder_test.dart`、`test/session_state_snapshot_prompt_formatter_test.dart`、`test/assistant_conversation_storage_test.dart`、`test/assistant_history_resume_test.dart`、`test/assistant_tool_result_handoff_test.dart`、`test/local_ai_interview_screen_test.dart`、reasoning turn ledger 相关测试、Native LocalAiConversationHistoryPolicyTest / LocalAiSessionStateInputPolicyTest、`test/local_ai_service_test.dart` | **云端确定性边界已落地：** PR #622 增加 DAO 有界读取、SQLite 行数/正文/metadata 投影、128 条快照上限与 PARTIAL 诊断、64 条 evidence 引用上限，并保留完整历史读取合同；上述测试覆盖存储、Builder、调用端与恢复/回流路径。仍未配置 App 可用输入 Token 预算、输出预留、动态预算策略/自动压缩；`conversationKvCacheBudgetStatus=NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`。Find N2 GPU/CPU 多轮、state:7、Activity/process restart 和真实上下文观测仍为 DEVICE UNKNOWN。
| Core-2 知识召回/排序 | test/assistant_knowledge_context_test.dart（Formula/Herb/Acupuncture/Acupoint/Neijing/MedicalCase）、test/multi_source_evidence_pipeline_test.dart、test/source_aware_legacy_evidence_ranker_test.dart、test/ai_retrieval_golden_snapshot_test.dart | **已落地：** 五类结构化本地资料与 Classic/Guji/MedicalCase 均进入 CandidateEvidence；候选元数据快照、query/retrieval provenance、完整 KEEP/DROP reason、strategy/version、顺序、状态、诊断和最终字符预算均有结构化输出与回归。**限制：** 仍保留 legacy 查询生成、匹配和来源限额；不提供 Token 预算或语义相关性分数。KEEP/DROP 不是来源真实性、经典权威性或医学正确性判断。 |
| Core-3 语言推理 | test/reasoning_request_prompt_formatter_test.dart、test/reasoning_response_codec_test.dart、test/reasoning_knowledge_answer_adapter_test.dart、test/local_ai_service_legacy_entrypoint_audit_test.dart、test/reasoning_attachment_architecture_test.dart、test/local_ai_interview_screen_test.dart | #594 退役 LocalAiService 旧包装 API；#598 删除无调用点的 Native 旧媒体 helper。`sendMessage` / `sendImage` / `sendAudio` MethodChannel 仅 fail-closed；静态回归扫描全仓旧 Dart 调用、旧 Native 路由不触发模型、旧 helper 不复活，并逐项核对 8 个真实模型调用入口均设置 `requiresAiAccess=true`，共享 `runAiTask` 强制执行唯一 Native Gate。主文本/附件继续走结构化协议；音频 transcriptDraft 在用户确认前不得提升为 USER_ORIGINAL 记忆事实。辅助窄任务入口继续独立。 |
| Core-4 业务执行 | test/reasoning_action_proposal_gate_test.dart、test/reasoning_action_proposal_adapter_test.dart、test/assistant_tool_execution_coordinator_test.dart、test/assistant_tool_invocation_ledger_test.dart、test/assistant_tool_invocation_ledger_storage_test.dart、test/reasoning_execution_result_adapter_test.dart、四项 executor 测试及 `test/local_ai_interview_screen_test.dart` | 四项 plan-eligible capability 的能力级输入、数据来源、副作用、幂等/时间依赖及补偿适用性已逐项复核；显式确认、claim-before-dispatch、终态读回、来源校验和 UNKNOWN 不重放有针对性测试。执行中通用取消/deadline 尚未实现，但当前四项没有外部业务写入，不为此引入虚假的通用取消框架；不扩展其余工具的模型提案权限。 |
| Core-5 端到端验收 | test/local_ai_interview_screen_test.dart：Core-5 20 轮知识追问与一次工具执行回归；Flutter 全量回归、Android arm64/JVM、Fork License | 云端 widget/fake-executor 闭环已验证；不等于真实 E4B Native 推理或 Find N2 GPU/CPU、媒体、Activity/process restart TRACE。设备证据留到所有云端改造收尾后本地执行。 |

**文件责任与集成约束：** Core-1 改动集中在 Native 会话历史/请求 Ledger、SessionStateSnapshot 及对应 Kotlin/Flutter 测试；Core-2 改动集中在 CandidateEvidence 适配、多源 Pipeline、Ranker 与黄金 fixture；Core-3 改动集中在 Reasoning DTO/formatter/codec、LocalAiService、MainActivity 和助手发送 UI；Core-4 改动集中在 Gate/Coordinator/InvocationLedger/Dispatcher 连接及确认 UI；Core-5 负责跨层测试和 TRACE 对照。每个切片从当时 master 创建独立分支，按小批量 PR 集成；设备验收不阻塞云端代码、测试或文档工作。

### 5.15 2026-11-28 入口模式路由与 Native fallback 状态观测映射

本节记录两项横跨现有层次/平台的实现映射，不增加 AI 层、Agent、业务能力或授权范围。

#### 确定性入口模式路由

- **源码：** `lib/services/assistant_conversation_orchestrator.dart` 的 `AssistantConversationOrchestrator.resolve`。
- **责任：** 在现有 Assistant dispatch 中确定本轮模式与澄清状态；它是进入结构化推理请求之前的确定性路由，不替代知识召回/证据排序，也不执行任何工具。
- **优先级约束：** 显式术数动作词、匹配到的工具动作、知识解释 cue 和 pending tool selection 必须阻止“纯术数短词”捷径误吞工具或学习意图；小六壬宫名 `大安/留连/速喜/赤口/小吉/空亡` 只有在非 `yunqi-only` 领域才作为独立玄学模式 cue。五运六气同句含宫名时仍服从 Yunqi 领域判断。
- **回归：** `test/assistant_conversation_orchestrator_test.dart` 的“**五运六气领域优先于同句的小六壬宫名，独立宫名仍进入玄学**”覆盖：`五运六气空亡`（无通用知识 cue）不被宫名捷径改判为 metaphysics；`五运六气空亡的含义是什么` 进入 learning；独立 `空亡` 进入 metaphysics。其他既有动作、工具澄清、knowledge cue 与 pending-selection 回归保持。
- **边界：** 不把模式路由变更解释为工具授权；工具仍须走既有 ACTION_PROPOSAL、App schema 校验和显式用户确认。Core-4 四项 capability allowlist 不变。

#### Native GPU fallback 原因的状态可观测性

- **源码：** `android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt` 内的 `backendFallbackReason`；通过 `LocalAiModelStatus.backendFallbackReason`（`lib/services/local_ai_service.dart`）投影到 `lib/widgets/local_ai_backend_settings_tile.dart`。
- **语义：** 仅当优选 GPU 初始化失败、CPU fallback 成功后记录 GPU 失败原因；设置页显示当前运行时的原因，并允许按既有路径重试 preferred backend。
- **清理：** 显式选择 CPU、GPU 初始化成功、`releaseRuntimePreservingConversationState()` 或 `releaseLocalModel()` 释放 Native runtime/model 时清空原因。该字段描述当前活动 fallback runtime，不作为持久化设备诊断历史。
- **回归：** `test/local_ai_service_test.dart` 的“Native GPU fallback reason is preserved in model status”和 `test/local_ai_backend_settings_tile_test.dart` 的“shows the Native GPU-to-CPU fallback reason”覆盖 status 解析与 UI 展示；PR Android arm64/JVM CI 覆盖 Native 单元测试。
- **边界：** 这是错误状态观测，不改变 GPU/CPU fallback 策略，不证明实际 Find N2 GPU 初始化失败、CPU fallback 成功率或真实设备稳定性。GPU/CPU 真机 retest 仍为 DEVICE MISSING / UNKNOWN。

### 5.16 2026-11-28 SessionState SQLite 有界读取与证据提取（PR #622）

- **基线与合并：** PR #622 最终 HEAD 为 `1bd334ba64d46488a7008a49647bf83860f652cb`，squash merge commit 为 `805f006ed502c5cbf10dba4ad30428ee9761eb42`。
- **读取边界：** 新增 `AssistantConversationStore.getAssistantMessagesForSessionState` 和 SQLite 实现；只查询当前 conversation 的 user/assistant 行，SQL LIMIT 硬上限为 129，按 ID 倒序取最新窗口后转为时间正序。隐藏 tool/system 行不进入快照投影，assistant body 被投影为空；原 `getAssistantMessages` 完整历史合同未改变。
- **负载边界：** SnapshotBuilder 最多处理最近 128 条；当 129 条读取证明更早历史存在时，快照状态为 PARTIAL 并携带 `SESSION_STATE_OLDER_MESSAGES_OMITTED`。SQL 层将用户正文限制为最多 1,201 Unicode code points，metadata 投影限制为最多 16,001 code points；Dart Builder 在 replayability JSON 解码前按 UTF-16 长度拒绝超过 16,000 的 metadata。超限数据不会被静默当作完整记忆。
- **证据边界：** source/evidence/chunk 引用继续去重并最多保留 64 条；达到上限后停止累计 overflow keys，设置 PARTIAL 与 `SESSION_EVIDENCE_REFERENCES_TRUNCATED`。超限 metadata 设置 `SESSION_EVIDENCE_METADATA_OMITTED_OVERSIZED`。
- **回归与兼容：** DAO、Builder、screen caller 与 in-memory adapters 有针对性测试；覆盖隐藏角色排除、时间顺序、正文/metadata 投影、行数上限、PARTIAL 诊断和完整历史 API 不被截断。没有删除或降低既有断言，没有修改 Native runtime、Token budget、自动摘要或工作流 I。
- **最终 HEAD 自动验收：** Branch validation job `140903069854`、Flutter regression job `140903070020`、Android arm64/JVM job `140905099227`、PR required gate job `140905913256`、Fork License job `140903069713` 均 SUCCESS，全部绑定最终 PR HEAD `1bd334ba64d46488a7008a49647bf83860f652cb`。
- **设备边界：** 该 PR 只证明 Dart/SQLite SessionState 投影边界。Find N2 E4B、GPU/CPU 多轮、state:7、媒体、Activity/process restart、真实 KV Cache/context 数值仍为 MISSING / UNKNOWN / LOCAL ONLY；不得把 CI 或 Flutter 测试写成设备 PASS。

## 6. 当前执行状态与后续放行顺序（代码基线 master@805f006e；文档同步由 PR #623 承接）

本节取代早期“各 Core 尚待接线”的排期快照。当前 AI 运行时代码主线为 `master@805f006ed502c5cbf10dba4ad30428ee9761eb42`（PR #622 merge）；此前已同步的文档快照为 `master@9a929398e8b15fef57d8a3f749d68cbc4a5113e4`。本次 PR #623 只更新架构、执行台账和唯一设备交接文档，不修改运行时代码。

| 顺序 | 层 | 当前主线状态 | 现有证据 | 尚未闭合 / 放行边界 |
|---|---|---|---|---|
| 1 | Core-0 契约与源码映射 | **DOC/CODE MAP 已完成** | §5.1–§5.5 已映射五层 DTO、数据所有权、Native 入口、失败语义和测试锚点 | 后续随主线变更维护映射；不再为已存在的类重复建第二套抽象 |
| 2 | Core-1 会话记忆与 Native 多轮 | **云端确定性记忆隔离及 SessionState 有界读取已落地；设备观测仍 UNKNOWN；Token 预算未配置** | #565 dirty-KV flush；#575 持久化推理请求终态；#117/#119 原子 transcript 与 TRACE 分离；#120 Activity 资源串行释放；PR #610 限制跨 MethodChannel 的用户自述投影；PR #622 为 SessionState 建立独立 SQLite 查询，最多读取 129 条可见记录、处理最近 128 条、限制正文/metadata 投影、证据引用≤64 并将遗漏明确标为 PARTIAL。PR #622 final HEAD `1bd334ba64d46488a7008a49647bf83860f652cb` 的五项 PR 门禁全部 SUCCESS，合并为 `805f006ed502c5cbf10dba4ad30428ee9761eb42` | LiteRT KV Cache 不跨进程持久化；`conversationKvCacheBudgetStatus=NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`，尚无 App 可用输入 Token 预算或自动压缩；Find N2 GPU/CPU、多轮数值、state:7、Activity/process restart 与三方历史一致性留给最终设备 TRACE |
| 3 | Core-2 知识召回与证据排序 | **当前约定范围已完成** | #527 RankedEvidenceSet；#568 五类结构化资料 CandidateEvidence；metadata-only candidateSnapshot、query/retrieval provenance、KEEP/DROP reason、strategy/version 和 6,500 UTF-16 呈现预算 | 保留 legacy query/matching/order/per-source caps 与 golden 行为；不将字符预算说成 Token，不扩展语义评分/Embedding/Reranker 作为虚假收尾条件 |
| 4 | Core-3 语言推理 | **主对话与媒体结构化协议已落地；旧自由文本入口退役** | #573 five modes；#583 image/audio structured Request/Response 与 Native finalize/reject；#594 删除旧 LocalAiService 包装 API，Native sendMessage/sendImage/sendAudio 均 fail-closed；全仓静态审计覆盖旧 Dart 调用，当前批次进一步删除两个无调用点的 Native 私有自由文本媒体 helper；PR #611 严格要求 ReasoningResponse v1 `schemaVersion` 为整数并拒绝浮点 `1.0`；入口模式确定性路由映射见 §5.15，不增加模型或工具权限 | resolveAssistantIntent、extractBaziSlots、extractSymptoms、understandTcmInterviewAnswer 继续使用各自窄 DTO；保留的旧 MethodChannel 名称只作拒绝兼容，不得触发模型；真实 E4B/Find N2 行为留给设备 TRACE |
| 5 | Core-4 业务执行 | **四项受限能力闭环与能力级审计已完成当前云端范围** | #561/#566 闭环；#126 已逐项记录四项 capability 的输入 schema、数据来源、副作用、幂等/时间依赖与补偿适用性；显式确认、持久 one-shot claim、终态安全读回和 UNKNOWN 不重放均有回归 | 只开放 dosage、solar_terms、yuxiaji_omen、sanshan_lingqian；执行中通用取消/deadline 未实现，但四项当前为纯计算或本地只读、没有外部业务写入，不作为本轮收尾阻塞；不扩权 |
| 6 | Core-5 端到端验收 | **云端 20 轮 + 单次工具闭环 PASS；设备部分 UNKNOWN** | #585 widget E2E 覆盖 20 轮、owner/requestId、记忆隔离、一次确认动作与只读结果回流；PR #585 应用层 20 轮与单次工具闭环 E2E 已合并；本轮 PR #597 文档同步的精确 HEAD `6e69c907c7117bb859f37b4979394b07b388a571` Flutter 完整回归、Android arm64 验证 APK/JVM 与 Fork License 均 SUCCESS | fake executor 不证明 E4B Native/GPU/CPU 或真机进程恢复；设备实测统一放到所有云端改造/CI/文档收尾之后 |

执行与集成要求：

- 当前不因设备未连接而暂停 Core-1 至 Core-5 的云端代码、回归和文档审计；只有需要物理硬件的 TRACE 才记为 DEVICE UNKNOWN。
- 对已通过的 Core-2，不重新实现候选快照或排序审计；除非发现具体旧黄金用例回归或输入/输出契约缺陷，否则保持现有策略。
- Core-3 的旧兼容入口与辅助窄任务单独审计，不以“统一”名义把不同约束的任务塞进主聊天 DTO。
- Core-4 不扩大四项白名单，不允许模型跳过 App 显式确认，不允许 UNKNOWN 自动重放。
- 小批量集成继续从最新 master 建独立分支；最终 HEAD 要有适用的 Flutter、Android arm64/JVM、Fork License 和静态分析证据。SKIPPED 不计 PASS，旧 SHA CI 不替代最新 HEAD。
- 全部云端事项收尾后，本地按唯一 docs/local-real-device-acceptance-handoff.md 执行 Find N2 TRACE；MISSING/UNKNOWN 保持原状态，不预填 PASS。

**2026-11-28 AI 运行时代码集成闭环（`master@f4b2aaab42e498bdca48ed55f45d39b8f18319cd`；当前仓库文档主线 `9a929398e8b15fef57d8a3f749d68cbc4a5113e4`）：**

- PR #610（Native 用户自述恢复投影跨进程前限界）最终 HEAD `39e841917139bb2b9036d615cb7bacb30031b75f`，merge commit `bcfa2e36440689d7d5cd12abfd80cf191c6d66dc`；Flutter regression、Android arm64/JVM、Fork License 均 SUCCESS。Branch validation 为 SKIPPED，不计 PASS。
- PR #611（ReasoningResponse schemaVersion 严格整数）最终 HEAD `46ceb7490f0afb43c357dc59d0a15939a2f33803`，merge commit `178bf925a667e93a26539d2967a34519fc4ca5ff`；Flutter regression、Android arm64/JVM、Fork License 均 SUCCESS。Branch validation 为 SKIPPED，不计 PASS。
- PR #612（本地—远程并行治理与 PR 汇总门禁）最终 HEAD `0a98a8a374ee5bb037a25a468c550d60296af5db`，merge commit `8c444c66d368ce27f0a3d839edbd2edd0c040c66`；Branch validation、Flutter regression、Android arm64/JVM、PR required gate、Fork License 五项均 SUCCESS。
- PR #619（master Flutter Quality Gate 自动触发去重）最终 HEAD `33163d91f736959454d386c657340f920a98ec5f`，merge commit `6ec027592dd6915aafd0353818214ed87675a86e`；只修改 `.github/workflows/flutter-quality.yml` 的触发配置，保留所有静态分析、Dart 测试、Android Native/JVM 和 arm64 诊断步骤，手动 `workflow_dispatch` 仍可运行。最终 HEAD 的 Branch validation job `140838053127`、Flutter regression job `140838053340`、Android arm64/JVM job `140839506843`、PR required gate job `140840474683`、Fork License run `46099363860` 均 SUCCESS。
- PR #618（Native GPU→CPU fallback 原因状态可观测）最终 HEAD `0b2aff6963e6fe79dabe788b05a529a273840567`，merge commit `73a79b9ac36879b22db60c8be9c1cd25ef31037a`；最终 HEAD 的 Branch validation job `140844538153`、Flutter regression job `140844538488`、Android arm64/JVM job `140846198464`、PR required gate job `140847230585`、Fork License run `46101434294` 均 SUCCESS。
- PR #615（五运六气/小六壬宫名确定性模式路由优先级）最终 HEAD `4a916dd8847404406364a59a43865b21149a8310`，merge commit `f4b2aaab42e498bdca48ed55f45d39b8f18319cd`；最终 HEAD 的 Branch validation job `140847951174`、Flutter regression job `140847950958`、Android arm64/JVM job `140849888468`、PR required gate job `140850831785`、Fork License run `46102527332` 均 SUCCESS。
- PR #618 合并后的 `master@73a79b9a` Push CI：Flutter regression run `46102435178` / job `140847654952` SUCCESS；Android arm64/JVM job `140849750121` SUCCESS；Fork License run `46102435181` SUCCESS。Push 事件的 Branch validation / PR required gate 为 SKIPPED，不计 PASS。
- PR #615 合并后的当前主线 `master@f4b2aaab42e498bdca48ed55f45d39b8f18319cd` Push CI：Flutter regression run `46103578217` / job `140851236286` SUCCESS；Android arm64/JVM job `140852758501` SUCCESS（22/22）；Fork License run `46103578205` SUCCESS。Push 事件的 Branch validation job `140851237663` 与 PR required gate job `140853757013` 为 SKIPPED，不计 PASS。
- **PR #617 文档收尾：** 仅修改本文件与 `docs/ai-modernization-execution-ledger.md`；最终 HEAD `9f87ad7d8f339988700161c74ca6b0f24394d033`，merge commit / 当前仓库 master `b188aadbe10b91a2dd639e2c51e901039801e447`。该合并不改变 AI 运行时代码。
- **PR #617 精确 HEAD 验收：** Branch validation job `140854181797`、Flutter regression job `140854181627`、Android arm64/JVM job `140855769369`、PR required gate job `140856635902` 与 Fork License run `46104525606` 均 SUCCESS。
- **PR #617 合并后主线验收：** Push run `46105373769` 的 Flutter regression job `140856830001` 与 Android arm64/JVM job `140858889845` 均 SUCCESS；Fork License run `46105373752` SUCCESS。Push 事件的 Branch validation / PR required gate 为 SKIPPED，不计 PASS。
- **PR #620 文档收尾：** 仅修改本文件与 `docs/ai-modernization-execution-ledger.md`；最终 HEAD `331763a5544f5ac4bf499fdd2d549a8dfee8ede8`，merge commit / 当前仓库文档 master `9a929398e8b15fef57d8a3f749d68cbc4a5113e4`。没有修改运行时代码、Workflow、许可证实现或设备交接文件。
- **PR #620 精确 HEAD 验收：** Branch validation job `140862104727`、Flutter regression job `140862104447`、Android arm64/JVM job `140864111270`、PR required gate job `140865099452`、Fork License run `46107061082` 均 SUCCESS，全部对应 PR 最终 HEAD `331763a5544f5ac4bf499fdd2d549a8dfee8ede8`。
- **PR #620 合并后主线 CI：** `master@9a929398` 的 Flutter regression job `140869245983`、Android arm64/JVM job `140871145617`、Fork License run `46109373085` 均 SUCCESS。Push 事件的 Branch validation job `140869247091` 与 PR required gate job `140872191422` 为 SKIPPED，不计 PASS。
- **master 分支保护（2026-11-28 复核）：** 公开 branch 响应在 PR #620 合并后仍确认 `master.protected=true`、`protection.enabled=true`、状态检查 enforcement 为 `everyone`，required checks 精确包含 `PR required gate` 与 `Fork license inventory and boundary`（GitHub Actions App）。仓库管理员报告已将所需审批人数设为 0；PR #620 在无 review 记录的情况下通过受保护合并操作，证明此前的审批阻塞已解除。当前连接无权读取完整 `/branches/master/protection` 详情，因此 `required_approving_review_count`、`strict`、`enforce_admins`、force-push/deletion 等配置值仍未获得该 API 的独立读取证据；不得将用户报告或合并成功扩大表述为这些字段均已逐项 API 验证。后续 PR 仍须以 required checks 实际通过和保护规则生效为准。
- **设备与延期边界：** Find N2 GPU/CPU 真机、E4B 多轮、state:7、进程恢复、媒体、升级及 TRACE 仍按唯一 `docs/local-real-device-acceptance-handoff.md` 记录为 MISSING / UNKNOWN / LOCAL ONLY；工作流 I（用户 Markdown 书架）仍 DEFERRED / NOT AUTHORIZED。


## 7. 书架和其他知识源的优先级

- 用户 Markdown 书架是未来可选的 USER 知识源，不是五层架构的中心，也不是当前核心主线。
- 书架只能通过知识召回层提供 CandidateEvidence；不得绕过证据排序、会话记忆边界、语言推理协议或业务执行 Gate。
- 系统知识库、用户书架、用户笔记、医案、未来其他本地资料都属于知识源输入，不能为每种来源复制一套推理/记忆/工具执行架构。
- 只有 Core-0 的数据契约冻结，Core-1 的 RAG/Memory 隔离具备可集成条件，Core-2 的召回/排序边界与黄金行为明确后，才评估书架 C 阶段。
- 书架导入、Embedding、后台任务、数据库拆分等不能阻塞核心五层架构，也不能要求先重写核心层来服务书架。
- Embedding/Reranker 是召回或排序层的任务模型组件，不是独立产品主线；由用户选择本地或云端模型。当前代码尚未确认其独立运行时，必须按 v1.4 任务拆分实施，并用黄金查询集及适用设备证据验收。

## 8. 核心验收矩阵

| ID | 核心层 | 场景 | 验收要点 |
|---|---|---|---|
| CORE-01 | 召回 | 原始 query 无命中、派生 query 有命中 | 原始 query 保留；候选身份/来源/截断状态可回查 |
| CORE-02 | 召回 | 两个相近实体/复合查询 | 每个子目标的候选集合独立记录，不能互相覆盖 |
| CORE-03 | 排序 | 同一候选集使用不同排序策略 | 召回结果不变，排序结果及保留/排除原因可单测 |
| CORE-04 | 排序 | SYSTEM/USER 两种来源冲突 | 不混为一条；来源元数据由代码提供；分数不提升真实性 |
| CORE-05 | 记忆 | 第二轮不再注入上轮 RAG 正文 | Native history 只有干净轮次和结构状态；证据按 ID 重取 |
| CORE-06 | 记忆 | 多会话切换、重启恢复 | session scope 严格隔离；状态缺失明确标记 |
| CORE-07 | 记忆 | 历史超出预算 | 按完整轮次/结构条目裁剪并显示省略，不能任意截断误导 |
| CORE-08 | 推理 | 知识未命中时要求古籍原文 | 返回证据不足，不补造原文、条号和出处 |
| CORE-09 | 推理 | 模型输出不存在/伪造 sourceId | 引用校验阻断；UI 不显示为真实原文 |
| CORE-10 | 推理 | 模型输出工具调用意图 | 只形成 ACTION_PROPOSAL，未过代码校验前不执行 |
| CORE-11 | 执行 | 缺参或未授权能力 | 代码拒绝/澄清，不接受模型补默认值 |
| CORE-12 | 执行 | 工具执行后响应丢失 | 执行状态 UNKNOWN，禁止盲目重放 |
| CORE-13 | 执行 | 业务成功但解释错误 | ExecutionResult 保留真实值；模型解释不覆盖原始结果 |
| CORE-14 | 跨层 | 连续 20 轮知识追问和一次工具动作 | 记忆、证据、推理、执行均有独立 trace；无上下文污染/重复动作 |
| CORE-15 | 资源 | E4B 推理期间触发其他端侧模型任务 | 按统一 Gate/串行资源协调处理，不破坏 E4B 推理状态 |

### 8.1 证据要求

- CODE：实际类/方法和调用路径。
- TEST：隔离每层输入/输出及跨层契约测试。
- CI：对 PR 精确 HEAD 执行的适用工作流；SKIPPED 不通过。
- TRACE：Find N2 设备、Android 版本、App SHA、E4B 模型哈希、实际 backend、trace_id 和场景日志。
- 任一层证据不完整则保持 PARTIAL/UNKNOWN；不能把“接口文档完成”当成运行时实现完成。

## 9. 变更控制

以下变更必须有单独设计、对照测试和回滚说明：

- 把两层职责重新合并到无法独立测试的单一 Builder/Agent；
- 把证据排序信号提升为来源真实性/医学正确性判断；
- 把知识库内容或 RAG 正文写入长期 Native 会话历史；
- 将模型动作提案绕过业务执行门禁；
- 引入新的 Agent/DAG、第二套会话表、第二套授权门禁或第二套重复状态存储；
- 未经数据规模/性能证据引入独立向量数据库、FTS5、ANN 或第二套知识库；Embedding/Reranker 与云端模型本身已由 v1.4 授权，但必须遵循用户显式任务配置、来源边界和失败语义；
- 改变现有黄金检索行为、GPU/CPU fallback、Native 串行队列或 UNKNOWN 请求恢复语义。

所有变更都必须先回答：现有哪一层无法履行职责、用什么 CODE/TEST/TRACE 证明、最小替代方案是什么、失败如何回滚。

---

**最终约束：** 研纪 AI 的核心不是“一个大模型负责一切”，而是五项职责独立协作：知识召回发现候选、证据排序选择本轮依据、会话记忆保存有界状态、用户选定的本地/云端模型负责语言推理、App 确定性代码负责业务执行。五层共享统一契约但不共享不受控状态。模型的本地/云端运行时、任务键、用户开关、唯一 ai_access 和上下文配置遵循本文件 §10 及专业版架构 v1.4；Embedding/Reranker 已被纳入配置范围，但不因此视为已经实现。


### 5.3 历史快照（2026-11-26，后续状态以 §5.5 为准）：Core-3 / Core-4 早期切片

> **历史状态说明：** 本节记录 #540/#561/#566 合入前后的分支阶段，不再代表当前生产接线状态。当前五种文本模式及图片/音频附件见 §5.5；当前受限工具提案闭环见 §5.5 与 docs/assistant-tool-capability-audit.md 第 13 节。

- Core-3 已落地部分：PR #540 在 master e2cdc1c1541eea369a5135d91c1bf9eb0891669a 合并。显式 learning 和 automatic entity-hit learning 使用 Request/Response v1；其他模式未迁移。
- Native 双阶段提交：sendReasoningMessage 生成原始 JSON，但不将它作为完成轮次写入 LocalAiConversationHistory；返回 Dart 前 Native 从此前成功 transcript 重建 Conversation，清除模型 KV 中的原始 JSON。Dart strict decoder 与 evidence/source 映射通过后调用 finalizeReasoningTurn，失败调用 rejectReasoningTurn。终态确认未知时不重放模型推理。
- 证据边界：ranked evidence IDs 是本轮唯一可引用的证据集合；sourceId / evidenceId / 本地存储定位只作为 App 内部元数据，不进入普通回答文本。学习路径允许 capability 集合为空，动作提案一律 fail-closed。
- Core-4 执行结果投影：`ReasoningExecutionResultAdapter` 将经验证的 `AssistantToolResult` 映射为下一轮可消费的结构化执行结果。SUCCEEDED 需要真实参数、结构化值和来源；FAILED/NO_RESULT/CANCELLED 保留各自终态；UNKNOWN 保持 UNKNOWN，不得重放。
- Core-4 ACTION_PROPOSAL Gate：独立工作分支 `work/core4-action-proposal-gate-contract-20261126` 增加 App-owned `ReasoningActionProposalGate`。它绑定当前 requestId、请求级 capability allowlist、四个既有 plan-eligible Headless capability 以及参数 schema；准备阶段只生成不可变确认预览，显式用户确认后才可创建单步 `ToolExecutionPlan`。Gate 不调用 Dispatcher，也不构成第二套访问授权门禁。
- Core-4 Request/Adapter：独立分支 `work/core4-tool-proposal-runtime-contract-20261126` 将不可变 `allowedCapabilityIds` 加入 `ReasoningRequest`，仅 `mode=tools` 可以非空；prompt 输出本轮 `actionCapabilityAllowlist`，空集合明确禁止 ACTION_PROPOSAL。`ReasoningActionProposalAdapter` 只接受 Gate 已登记能力，Response codec 使用同一 request allowlist，拒绝携带证据引用的动作提案，不向确认 UI 暴露模型 action narrative，只返回 App-owned preview，并在确认后按原 requestId/allowlist 再校验。
- Core-4 One-shot：后续独立切片在现有 `assistant_messages` 加 nullable `invocation_key` 和部分唯一索引，以隐藏 `role=tool` 事件记录 CLAIMED/TERMINAL；进程恢复时未完成 claim 转为 UNKNOWN，不自动重放。不得新增第二套会话表。该代码切片仍待重基线与精确 HEAD CI。
- **Core-4 当前仍为 PARTIAL：** Gate、Request、Adapter 与 Invocation Ledger 仍是独立契约/持久化切片，尚未接入 Native 工具模式生产 Request/Response、App 确认 UI、HeadlessToolDispatcher 或下一轮真实 ExecutionResult 回流。模型参数不能越过 App schema、原始用户文本解析和用户确认直接送入执行器。
- 后续硬门槛：工具模式接入结构化 Request/Response；App 确认 UI 独立展示并绑定原 requestId/allowlist；持久化 claim 成功后才调用现有 Dispatcher；真实 `AssistantToolResult` 经适配加入下一轮 Request 供模型解释，同时 App 保留原始执行结果/来源。Page-only、未登记能力、缺参、非法参数、拒绝、取消和 UNKNOWN 均不得伪装成功；UNKNOWN 不自动重放。


### 5.4 历史快照（PR #575 合并前，状态已由 §5.5 与 Native 多轮审计第 10 节更新）：Core-1 持久化请求生命周期

> **历史状态说明：** 下列条目记录 PR #575 合并前的设计与验收门槛。PR #575 已合并；当前生命周期、精确 HEAD CI 和 UNKNOWN/non-replayable 语义见 §5.5、docs/local-ai-multiturn-audit.md 第 10 节及执行台账第 122 节。

- **请求身份与所有权：** `AssistantReasoningTurnLedger` 以 conversationId + 32 位 requestId 绑定一次 Native 结构化推理。每次 Native 推理调用前写入隐藏 `role=tool` PENDING 事件，使用既有 `invocation_key` + 部分唯一索引；不新增会话表或数据库迁移。
- **终态：** Native finalize 确认后记录 FINALIZED 与经过 Dart 协议/证据校验的答案；Native reject 确认后记录 REJECTED；完成确认不明确或进程中断时记录/恢复为 UNKNOWN；工具动作提案在 App 执行成功后被有意丢弃的第一轮记录为 SUPERSEDED，不伪装为拒绝或成功答案。
- **进程恢复：** 打开历史会话时执行 `recoverAndReconcile`。未决 PENDING 转为 UNKNOWN，绝不自动重放模型推理或工具；Native 已确认 FINALIZED、但 SQLite transcript 原子写入前进程退出时，从 Ledger 中的已校验答案重建 user/assistant 消息对；UNKNOWN/REJECTED 恢复为可见状态消息，SUPERSEDED 不额外生成重复对话。
- **记忆隔离：** `reasoningRequestId` 写入 transcript 元数据用于去重和恢复。UNKNOWN/REJECTED 的原始 user 消息标记 `replayable=false`；Native transcript restore 不回放这些请求，`SessionStateSnapshotBuilder` 也不将其提升为用户会话记忆事实。隐藏 role=tool 的请求/终态记录仍不进入 Memory/RAG。
- **边界：** 此实现恢复的是 SQLite transcript 与请求终态，不持久化 LiteRT KV Cache，也不意味着 Native Conversation 在进程重启后自动恢复；用户重新打开历史会话时才按 transcript 重建 Native context。16,000/24,000 UTF-16 字符限制均不是模型 token/input budget；自动压缩仍未实现。
- **状态：** PR #575 依赖 PR #573 的 Core-3 结构化多模式调用分支；两者均未合并前不得计为主线完成。Flutter regression、静态分析、Android arm64/JVM 与 Fork License 必须以最终 PR HEAD 重新验收；Find N2 E4B 实机测量和 TRACE 留在全部云端工作结束后本地完成。


---

### Core-0：历史契约映射快照（2026-11-26；当前状态以 §5.5 为准）

> **历史状态说明：** 本节保留 2026-11-26 当时的 Core-0 源码映射和未闭合项。后续 #573/#583/#561/#566/#575/#585 已改变 Core-3/4/1/5 的实际状态，不能继续以本节“待合并”描述作为当前结论。当前实现映射以 §5.1–§5.2 和 §5.5 为准。

**历史审计基线：** `master@5889383b13742ea68ca4156fce5f7e657b3dde62`（当时已包含 #558 Request/Adapter 与 #559 One-shot Ledger）。本节是当时的代码映射和数据所有权冻结，不代表当前主线工作状态。

#### 1. 五层契约、真实入口和输出

| 层 | 真实代码入口 / 主要所有者 | 输出契约 | 失败状态与硬边界 | 当前证据 |
|---|---|---|---|---|
| Core-1 会话记忆 | `SessionStateSnapshotBuilder.build`；`LocalAiConversationHistory`；`AssistantConversationStore`；Native `LocalAiSessionStateInputPolicy.validate` | `SessionStateSnapshot(sessionId, revision, status, facts, evidenceReferences, activeTaskId, omittedUserMessageCount)`；事实带 `SessionFactProvenance` | RESTORED / PARTIAL / SESSION_MISMATCH / UNKNOWN；owner 不匹配全量拒绝；只读快照不替代 transcript；RAG 正文不能进入记忆；隐藏 `role=tool` Ledger 事件不得进入记忆；没有 token budget 或自动压缩时不能声称已完成预算治理 | `test/session_state_snapshot_builder_test.dart`、`test/session_state_snapshot_prompt_formatter_test.dart`、Native `LocalAiSessionStateInputPolicyTest` 与 transcript isolation tests |
| Core-2 知识召回 | `AssistantKnowledgeContextBuilder.buildAsync/buildWithEvidenceAsync`；`ClassicEvidencePipeline`、`MedicalCaseEvidencePipeline`、`GujiEvidencePipeline` | 候选集合、`knownEvidenceIds`、sourceId 映射和实际组装的证据正文；`AssistantKnowledgeContextResult` | NO_RESULTS / RETRIEVED / PARTIAL / FAILED；候选 ID 与正文是否实际送入模型是两件事；未解析来源不能伪装成可导航来源 | `test/assistant_knowledge_context_test.dart`、各 Evidence Pipeline 测试、`test/ai_retrieval_golden_snapshot_test.dart` |
| Core-2 证据排序 | `MultiSourceEvidencePipeline.combine`；`SourceAwareLegacyEvidenceRanker.rank` | `RankedEvidenceSet`：候选身份、KEEP/DROP 决策、策略元数据与上下文预算；Request 只接收完整提供给模型的 `rankedEvidence`，`knownEvidenceIds` 可保留被丢弃候选身份 | 排序不是来源真实性、经典出处或医学正确性判断；known-but-dropped ID 不可作为模型引用；呈现字符上限不等于 token budget | `test/multi_source_evidence_pipeline_test.dart`、`test/source_aware_legacy_evidence_ranker_test.dart`、`test/ai_retrieval_golden_snapshot_test.dart` |
| Core-3 语言推理 | `ReasoningRequest`；`ReasoningRequestPromptFormatter.formatSupplementalContext`；`LocalAiService.sendReasoningMessage`；Native `MainActivity.sendLocalReasoningMessage`；`ReasoningResponseCodec.decode`；`ReasoningKnowledgeAnswerAdapter.decodeAndResolve` | App 构造的 Request 与严格 v1 Response；ANSWER/CLARIFICATION/REFUSAL/INSUFFICIENT_EVIDENCE；证据引用回填为 App-owned sourceIds | EMPTY / PARSE_FAILED / UNKNOWN / requestId mismatch / unranked reference 均不作为成功回答；模型输出是非可信载荷；模型不能声明来源真实或动作已执行 | `test/reasoning_request_prompt_formatter_test.dart`、`test/reasoning_response_codec_test.dart`、`test/reasoning_knowledge_answer_adapter_test.dart`、`test/local_ai_service_test.dart` |
| Core-4 业务执行 | `ReasoningActionProposalGate`、`ReasoningActionProposalAdapter`、`ToolExecutionPlan`、`HeadlessToolDispatcher.executePlan`、`AssistantToolInvocationLedger`、`ReasoningExecutionResultAdapter` | Gate 只产生 App-owned 预览/已确认计划；Dispatcher 输出 `AssistantToolResult`；Ledger 终态安全读回后才能投影为 `ReasoningExecutionResult` | allowlist 不等于用户授权；必须显式确认；CLAIMED 必须先于 Dispatcher；FAILED/UNKNOWN 不带成功值或来源；UNKNOWN、进程中断、终态读回失败不自动重放 | `test/reasoning_action_proposal_adapter_test.dart`、`test/headless_tool_dispatcher_test.dart`、`test/assistant_tool_invocation_ledger_test.dart`、`test/reasoning_execution_result_adapter_test.dart` |
| Core-5 端到端 | Flutter widget/integration tests、Kotlin Native policy tests、Android arm64 build、真实设备 TRACE | 按同一 requestId/conversationId 关联 Memory、Evidence、Reasoning、Execution 和最终答复 | CI SKIPPED 不是 PASS；旧 SHA 的结果不替代当前 PR HEAD；云端 CI 不能替代 E4B/GPU/CPU/进程恢复设备 TRACE | `test/local_ai_interview_screen_test.dart`、Native `LocalAiConversationHistoryPolicyTest`、Android arm64 workflow；完整五层 E2E 和设备 TRACE 仍待补齐 |

#### 2. Native 调用字段与数据所有权

`LocalAiService._sendReasoningMessage` 将不同所有权的数据分字段传递，Native `MainActivity` 逐项读取并校验，不应把它们合并成一个无来源区分的 prompt 字符串：

| MethodChannel 字段 | 来源 / 所有者 | 用途 | 不允许的混用 |
|---|---|---|---|
| `text` | 用户原始输入，Dart UI | 当前轮用户意图；不得被检索 query 改写替代 | 不得用归一化 query 取代原始用户文本 |
| `context` | Core-2 App 检索组装 | 实际检索到且通过上下文预算的证据正文 | 不进入 Native 持久化 transcript 或 SessionStateSnapshot |
| `reasoning_context` | `ReasoningRequestPromptFormatter` | requestId、session 元信息、ranked/known evidence ID、能力 allowlist、允许暴露的 executionResults | 不承担 source 正文；不能被模型当成用户确认或执行授权 |
| `session_state_context` | `SessionStateSnapshotPromptFormatter` | 当前会话有界事实和来源引用 | 不是检索上下文；必须与 `session_state_conversation_id` 一并校验 |
| `session_state_conversation_id` | App 当前会话 ID | Native owner binding | 不匹配即拒绝，不做跨会话回退 |
| `trace_id` | App Trace 生命周期 | 关联各阶段诊断 | Trace 成功不代表模型答案或业务执行成功 |

Native 推理是双阶段提交：`sendReasoningMessage` 返回待校验回复，不等于成功轮次；Dart 完成 Response schema、requestId、证据引用和来源映射校验后，才调用 `finalizeReasoningTurn`；拒绝或校验失败调用 `rejectReasoningTurn`。终态 ACK 只允许重试 ACK 操作，不重放模型推理。普通知识正文、模型原始 JSON、隐藏 Ledger 消息和 SessionStateSnapshot 必须保持不同的持久化边界。

#### 3. DTO 字段约束与信任边界

- `ReasoningRequest`：App 生成 requestId、sessionId、原始 userText、mode 和 schemaVersion；`rankedEvidence` 是本轮实际提供的引用集合；`knownEvidenceIds` 只用于识别已知但可能被 DROP 的候选；`executionResults` 只能来自 App 验证；`allowedCapabilityIds` 仅定义当前请求允许模型提出的能力范围，不能替代确认。
- `SessionStateSnapshot`：只携带有界事实和证据指针；事实记录 USER_ORIGINAL、USER_CONFIRMED、MODEL_INFERRED、APP_RESULT、SOURCE_REFERENCE 来源类别。UNKNOWN / SESSION_MISMATCH 状态不能携带可暴露事实。
- `ReasoningResponse`：v1 必须包含固定字段；未知字段、缺字段、重复 ID、requestId 不匹配、kind/status 不一致、未排名引用或未允许能力全部 fail-closed。模型声明的 status 不能覆盖 App 解码结果。
- `ReasoningExecutionResult`：SUCCEEDED 必须同时有实际参数、结构化结果和值来源；FAILED/UNKNOWN 必须有 failureCode，且不得带成功 values/sourceIds；NOT_STARTED 不得携带执行数据。
- `AssistantToolInvocationLedger`：只存储执行 claim 和 terminal，不作为聊天记忆或 RAG 证据。SessionStateSnapshotBuilder 只从 user/assistant 消息提取来源引用，明确跳过隐藏 tool-role 事件。

#### 4. 当前调用方覆盖与未闭合项

- master 已完成结构化 Request/Response 的 learning 路径；普通知识问答仍由 `ReasoningKnowledgeAnswerAdapter` 做严格解析和来源回填。
- 截至本审计基线，tools mode 生产调用方仍不能按“全部 Core-4 已接线”描述。Gate、Request/Adapter、Ledger 是契约/持久化基础；待合并的协调器、显式确认 UI、真实 Dispatcher 调用和 executionResults 下一轮回流，必须分别以当前 PR HEAD CI 验收后再计入生产状态。
- `ReasoningRequestPromptFormatter.maxSupplementalContextCharacters` 是 UTF-16 字符上限，不是 tokenizer token budget；现有历史字符裁剪也不等同于模型输入 token 预算。
- SessionStateSnapshot 是结构化记忆投影，不替代 transcript，不承载 RAG 正文，也未解决所有跨进程恢复语义；没有确定证据的状态保持 UNKNOWN。
- Core-2 当前保留排序审计对象，但任何未来算法变更仍需冻结候选快照、比较旧/新 KEEP-DROP、保持既有 golden 行为；不能用召回候选数增长证明改进。
- Core-5 尚缺把跨层 CI、真实 Native 多轮、工具执行、应用重启恢复和设备 TRACE 串为一个可复核验收包。

#### 5. Core-0 放行结论

**Core-0 文档映射：完成本轮冻结。** 五层主要代码入口、DTO、字段传输、数据所有权、失败语义、测试锚点和文件责任已形成明确映射。此结论只关闭“契约/源码映射”文档工作，不把 Core-1 至 Core-5 标记为完成；后续生产接线必须按本节对应的真实入口和边界实施。

### 5.5 当前主线运行态复核与 Native 辅助推理入口映射（2026-11-27）

**AI 运行时复核基线：** 五层运行时集成锚点为 `45144f6c3d140d259ac51f8cfbb886c19c10e0a3`；最新 Native/AI 运行时代码基线为 `master@04eb5bec9321b3d00eb85fdea7c0bd31b6fdc40f`（PR #598 merge）；最新 master 文档 HEAD 为 `f34b12573e16a790032a1450afb245d67891d680`（PR #599，仅文档同步）。PR #598 删除无调用点的 Native 旧媒体 helper；PR #599 不修改运行时代码。最新 master 文档 SHA 对应 Flutter tests `46003046571`、Flutter Quality Gate `46003046432`、Fork License `46003046794` 均 SUCCESS，Android arm64/JVM job `140522734914` SUCCESS；Branch validation `140519281368` 为 SKIPPED，不计 PASS。历史章节保留当时决策和实现轨迹；当前运行态以本节及 §5.8 为准。当前产品范围仍是中医学习辅助工具，不建设临床 detector、不安排医学审核、不恢复已撤销的临床门禁。

#### 当前五层状态

| 层 | 当前主线已落地 | 当前仍未闭合 / 不得夸大 |
|---|---|---|
| Core-0 契约与源码映射 | 五层 DTO、Native 字段所有权、主要生产入口、失败状态、测试锚点和当前文件责任已形成映射 | 本文档只关闭契约/源码映射工作，不把各层运行时实现统一标记为完成 |
| Core-1 会话记忆 | #565 dirty-KV flush；#575 持久化请求终态与非 replayable 恢复；SessionState owner 与隐藏 Ledger 隔离；Native transcript 从 SQLite 重建且按 12 轮/10,000 UTF-16 有界；`Conversation.getTokenCount()` / `ModelInfo.maxContextTokens()` 提供只读观测 | 不持久化 LiteRT KV Cache；观测不等于 App 可用输入预算（当前为 `NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`）；自动预算治理/压缩、真实设备进程恢复与 GPU/CPU TRACE 未完成 |
| Core-2 知识召回与排序 | #527 建立 RankedEvidenceSet（逐候选 KEEP/DROP 原因、策略版本、有序 ID、预算诊断）；#568 将 Formula、Herb、Acupuncture formula、Acupoint、Neijing 五类结构化资料接入 CandidateEvidence；候选快照与排序结果均由 AssistantKnowledgeContextResult 输出 | **当前既定范围已完成。** 保留 legacy query/matching/order/per-source caps；6,500 UTF-16 code units 为最终呈现字符预算，不是 Token budget。没有语义评分、Embedding 或 Reranker；这些不是当前交付门槛。若以后调整策略，必须冻结同输入候选快照并进行旧/新黄金对照。 |
| Core-3 语言推理 | #573 五种主文本模式结构化；#583 图片/音频附件使用 sendReasoningAttachmentMessage 和 ReasoningResponse v1，执行 Native 两阶段提交；#594 已退役 LocalAiService 旧自由文本/媒体包装 API，Native 旧 sendMessage fail-closed，且有全仓静态防回归测试 | 辅助 intent/Bazi/symptom/问项任务仍为独立窄 DTO；旧 Native 路由仅保留拒绝兼容，不执行模型；真实 E4B/Find N2 行为仍需设备 TRACE |
| Core-4 业务执行 | #561/#566 已接通 Gate、Request allowlist、显式确认、one-shot claim、现有 Headless Dispatcher、Ledger 安全读回及只读 ExecutionResult 下一轮解释 | 只允许四个既有 plan-eligible capability；不代表其余 Router 能力已开放；UNKNOWN 不重放 |
| Core-5 端到端验收 | #585 已合入 20 轮知识追问 + 一次工具提案/确认/执行/结果解释的 Flutter widget E2E；同一会话、请求 ID 唯一、Memory 隔离、Ledger 终态与结果回流均有断言 | 使用测试 fake executor，不是 E4B 真模型推理；GPU/CPU、多媒体、应用进程恢复和真实 TRACE 仍为 LOCAL ONLY / NOT RUN |

#### Native 模型调用入口完整性清单

MainActivity 的 MethodChannel 入口与当前 UI 调用关系如下。所有推理任务仍由 Native 串行任务队列和唯一 App AI access gate 管理；辅助窄任务继续使用独立输入/输出校验。

| Native 入口 | 当前调用方 / 生产用途 | 输入边界与输出验证 | 分层归属与状态 |
|---|---|---|---|
| `sendReasoningMessage` | LocalAiInterviewScreen 五种主文本模式；工具执行结果的下一轮解释也走这里 | App 生成 requestId、原始用户文本、检索上下文、SessionState 和 reasoning_context；Dart 校验 Response v1、requestId、ranked evidence/sourceIds 后 finalize，否则 reject | Core-3 主对话生产路径，已接线 |
| `sendReasoningAttachmentMessage` | LocalAiInterviewScreen 图片/音频附件发送主路径 | 传入 attachmentType、path、requestId、原始用户文本、context、SessionState、reasoning_context；Native 按附件类型校验文件后经唯一 access gate 和串行队列推理；保留 raw output 直至 Dart 按模态校验结构化 attachmentResult 并 finalize/reject | Core-3 媒体主路径，#583 已接线 |
| `resolveAssistantIntent` | 工具/玄学模式的候选意图选择 | 只提供 App 候选集（2–6 项）；模型仅返回 select/plan/clarify/none；Dart 再校验 ID 必须属于候选集，模型不得提供参数或执行结果 | Core-3 辅助路由窄任务；不是业务授权或执行 |
| `extractBaziSlots` | 工具参数缺失时的八字出生资料抽取 | 只允许 App 声明的缺失字段；模型必须提供原文 evidence；Dart Draft parser、字段白名单和工具参数 schema 再校验；缺失/不确定不得推断补齐 | Core-3 辅助槽位抽取；结果仅为候选输入 |
| `extractSymptoms` | 问诊初始描述与“整理症状”入口 | 使用 App 当前问诊题目 schema；候选 answer 必须命中原选项并有用户原文证据；UI 提供核对/接受步骤 | Core-3 辅助症状草稿；不是诊断或规则结果 |
| `understandTcmInterviewAnswer` | 结构化问诊逐题自然语言补充 | 当前 questionId、题目、合法选项及用户原文上下文是固定输入；Dart 校验 answer 必须逐字匹配选项且 evidence 存在于用户文字，歧义转澄清 | Core-3 辅助单题理解；不决定下一题、不诊断、不代替用户确认 |
| `sendImage` / `sendAudio` | 旧 MethodChannel 名称的 fail-closed 拒绝路由 | 分别固定返回 `STRUCTURED_ATTACHMENT_PROTOCOL_REQUIRED`；不进入 `runAiTask`，不调用模型；原私有自由文本媒体 helper 已删除 | 只保留拒绝兼容，不是推理入口；生产附件必须使用结构化协议 |
| `restoreConversation` | 历史会话恢复与模型上下文重建 | Flutter 按 UTF-16 10,000 字符及最近 12 个完整轮次裁剪；以 typed completed turns（user_text / assistant_text）和被省略的已完成轮次元数据传入 Native。Native 校验字段、surrogate、轮次数及字符边界，恢复 `LocalAiConversationHistorySnapshot` 后以 `ConversationConfig.initialMessages` 构建 USER/MODEL 角色消息；不触发模型推理、不生成合成恢复轮次。未完成 user-only 输入不计入 Native 成功轮次，但仍通过 `userMessages` 独立保留供症状整理 | Core-1 transcript 到 Native context 的确定性重建入口；不是 KV Cache 持久化 |
| `sendMessage` | 已无生产 Dart 调用方；Native `MainActivity` 仅保留旧 MethodChannel 名称作拒绝兼容 | 固定返回 `STRUCTURED_REASONING_PROTOCOL_REQUIRED`；不调用 `runAiTask`、不触发模型、不写入成功 transcript；旧 Service 包装 API 已删除，静态审计测试防止旧调用回归 | 已 fail-closed；不是可执行推理入口，不得恢复为自由文本旁路 |
| `finalizeReasoningTurn` / `rejectReasoningTurn` | 所有结构化主对话回合，包括媒体附件 | 按 conversationId + requestId 确认 pending turn；finalize 才提交成功答案，reject 清除未验证原始 JSON | Core-1/Core-3 双阶段提交边界，不是独立推理入口 |

补充判断：

- #576 已从生产 Flutter/Android 调用链删除临床 RedFlag Gate/Preflight、Native boundary 及医学审核专用测试；这类临床治理不属于当前产品范围或发布条件。
- `initialPrompt` 在 LocalAiInterviewScreen 初始化时只写入输入框；用户发送后仍进入正常路由，不是绕过 ReasoningRequest 的 Native 入口。
- 工具结果回流使用新的 reasoning requestId 和结构化 `executionResults`；执行结果回合的 capability allowlist 为空，不会把解释回合变成二次授权。
- 图片/音频附件不再是自由文本旁路：#583 将两种附件纳入结构化 ReasoningRequest/Response，未验证 raw output 不写入成功历史；音频 transcriptDraft 在用户核对前不得提升为用户事实。
- #585 的 20 轮 E2E 使用 Flutter widget、内存会话仓库和测试 fake executor；它证明应用层跨层合同，不证明真实 E4B Native 输出质量、GPU/CPU 行为或物理设备恢复。
- `resolveAssistantIntent`、`extractBaziSlots`、`extractSymptoms`、`understandTcmInterviewAnswer` 是有明确输入范围和 App 侧 parser 的辅助任务；维持独立 DTO、字段白名单、原文 evidence 和失败语义，不强行伪装成主聊天协议。
- 历史恢复只从 SQLite transcript 重建 Native Conversation，不持久化 Live LiteRT KV Cache。Transcript 恢复、模型运行态缓存和用户侧会话记录是不同状态层。

#### 当前依赖顺序与放行结论

1. Core-0：当前五层契约/源码映射与测试锚点已冻结；AI 运行时代码集成锚点为 45144f6c，当前 master 文档复核基线为 1d79bc2；代码入口和数据所有权保持可追溯。
2. Core-1：推理请求账本、UNKNOWN/non-replayable 和 transcript 对账已合入；Native `Conversation.getTokenCount()` 与 `ModelInfo.maxContextTokens()` 已提供 KV Cache token 数/模型声明最大上下文长度只读观测；LiteRT KV Cache 不持久化，App 可用输入 Token 预算仍为 `NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`，自动预算治理/压缩保持 UNKNOWN 或 NOT IMPLEMENTED。
3. Core-2：当前约定范围已落地：五类结构化资料进入 CandidateEvidence，MultiSourceEvidencePipeline、SourceAwareLegacyEvidenceRanker、候选元数据快照与 RankedEvidenceSet 分层输出；后续维持黄金行为，不新增语义评分/Embedding/Reranker，也不把字符预算写成 Token budget。
4. Core-3：五种主文本模式与图片/音频附件均通过结构化协议；旧辅助任务与兼容入口按各自边界治理。
5. Core-4：工具模式既有四项白名单能力完成提案—确认—claim—执行—安全读回—结果解释链；扩展能力前先补足各能力 schema/副作用治理。
6. Core-5：云端 20 轮 + 单次工具动作回流 E2E 已合并并通过精确 HEAD CI；真实 Find N2 E4B/GPU/CPU/多媒体/进程恢复与 Token TRACE 留到所有云端工作收尾后，由本地执行。

**工作流 I（用户 Markdown 书架）继续 DEFERRED / NOT AUTHORIZED。** 本轮没有引入新的检索源、Embedding、向量数据库、Reranker 或第二套会话/授权存储。

### 5.6 Core-3 旧 LocalAiService 入口调用点审计（2026-11-27）

- 当前基线：`master@62f18244220c073bcd5f7bf802ca48d7714f7aeb`。
- 直接检查 `LocalAiInterviewScreen`：生产主文本与附件发送均调用 `sendReasoningMessage` / `sendReasoningAttachmentMessage`；未见旧 `sendMessage*`、`sendImage*`、`sendAudio*` 调用。
- 旧 Dart 包装方法仍保留在 `LocalAiService`；Native `MainActivity` 仍有活动的 `sendMessage` handler。媒体 Native handler 已 fail-closed，返回 `STRUCTURED_ATTACHMENT_PROTOCOL_REQUIRED`。
- 新增 `test/local_ai_service_legacy_entrypoint_audit_test.dart`：递归扫描全部 `lib/**/*.dart`，在明确引用 LocalAiService 的文件中检查旧包装方法调用，并检查原始 local AI MethodChannel 是否被其他生产文件直接创建。
- 该测试只用于补全静态调用点证据，不负责删除接口，也不把测试合同误判为生产调用。必须以该测试和最新 HEAD CI 终态为准；在此之前不移除任何兼容 API。Native 辅助 intent、八字槽位、症状整理、单题理解继续使用各自窄任务协议。
- 本节不改变 ReasoningRequest/Response、Native 会话历史、访问门禁或模型行为。


### 5.7 Core-3 旧非结构化入口退役后的当前状态（2026-11-27）

> 本节以 PR #594 合并后的主线为准，覆盖 §5.5 Native 入口清单和 §5.6 旧兼容入口审计中的过期状态；前述章节保留为审计历史。

- **当前 master：** `11ac0c5918e5c25754b44e71f0ba48c82bea6669`（PR #594 merge commit）；PR #594 精确 HEAD：`85e77de947d144fd52902690094ba84de4d248c8`。
- **旧 Dart 包装接口已退役：** `LocalAiService` 不再公开 `sendMessage`、`sendMessageWithTrace`、`sendMessageWithContext`、`sendMessageWithContextAndTrace`、`sendImage`、`sendImageWithTrace`、`sendAudio`、`sendAudioWithTrace`，以及只服务这些包装层的私有自由文本/媒体转发实现。
- **Native 兼容路由 fail-closed：** `MainActivity` 的旧 `sendMessage` MethodChannel 名称仍保留为兼容拒绝入口，固定返回 `STRUCTURED_REASONING_PROTOCOL_REQUIRED`，不调用模型、不进入推理业务处理；`sendImage` / `sendAudio` 继续返回 `STRUCTURED_ATTACHMENT_PROTOCOL_REQUIRED`。这些旧路由不是生产模型调用入口。
- **生产主路径保持不变：** 五种助手模式的主文本仍走 `sendReasoningMessage`，图片/音频仍走 `sendReasoningAttachmentMessage` 和 ReasoningRequest/Response v1 双阶段提交；response 校验失败仍 reject，不将未验证输出记为成功轮次。
- **辅助窄任务保持独立：** `resolveAssistantIntent`、`extractBaziSlots`、`extractSymptoms`、`understandTcmInterviewAnswer` 继续使用各自窄 DTO、候选约束和 App 侧校验，不并入主聊天协议。
- **全仓静态防回归：** PR #591 新增的 `test/local_ai_service_legacy_entrypoint_audit_test.dart` 已扩展为扫描 `lib/` 与 `test/` Dart 源码，检查旧包装调用点；同时断言 Service 不再暴露旧方法，并检查 Native 旧文本路由 fail-closed。直接创建原始 local-AI MethodChannel 的生产 Dart 文件仍受扫描约束。该测试是仓库静态合同，不是对仓库外部二进制消费者的兼容承诺。
- **精确 HEAD CI：** PR #594 Flutter regression run `45968674159` SUCCESS；Android arm64 APK/JVM job `140406700872` SUCCESS（22/22 steps）；Fork License run `45968674271` SUCCESS。PR 事件 Branch validation 为 SKIPPED，不计 PASS。合并后 master push 的 Flutter tests run `45970274621` 与 Flutter Quality Gate run `45970274579` 在本节编写时仍为 IN_PROGRESS；其终态须按各自 SHA 记录，不能提前继承 PR 结果。
- **分层判定：** Core-3 旧自由文本包装入口退役已完成；结构化文本/媒体推理保持原协议。Core-1 请求账本、会话归属、隐藏 Ledger 隔离与 UNKNOWN 不重放没有因本次退役改变。Core-4 白名单仍只有既有四项能力；Core-5 20 轮/单次工具闭环仍是应用层测试，不等于真实 E4B/设备测试。
- **边界：** 不新增第二套会话存储、Native access Gate、Agent/DAG、Embedding、向量数据库或 Reranker；工作流 I 用户 Markdown 书架继续 DEFERRED / NOT AUTHORIZED。



### 5.8 2026-11-27 PR #598 合并后 Native 旧媒体入口清理与当前主线基线

- **运行时代码基线：** `master@04eb5bec9321b3d00eb85fdea7c0bd31b6fdc40f`（PR #598 merge）；最新 master 文档 HEAD 为 `f34b12573e16a790032a1450afb245d67891d680`（PR #599，仅文档同步）。五层运行时集成锚点仍为 `45144f6c3d140d259ac51f8cfbb886c19c10e0a3`。
- **精确 CI：** 最新 master 文档 SHA 上 Flutter tests run `46003046571`、Flutter Quality Gate run `46003046432`、Fork License run `46003046794` 均 SUCCESS；Android arm64/JVM job `140522734914` SUCCESS；Branch validation job `140519281368` 为 SKIPPED，不计 PASS。PR #598 运行时代码 SHA 上的 Flutter tests、Flutter Quality Gate、Fork License 与 Android arm64/JVM job 也均 SUCCESS（run/job 见本台账 §131）。
- **Native 模型入口审计：** `MainActivity` 的 8 个真实模型调用 MethodChannel 入口——`loadModel`、`understandTcmInterviewAnswer`、`extractSymptoms`、`resolveAssistantIntent`、`extractBaziSlots`、`sendReasoningMessage`、`sendReasoningAttachmentMessage`、`restoreConversation`——均通过 `runAiTask(result, requiresAiAccess = true)`；共享 `runAiTask` 在任务执行前检查唯一 `AiModelAccessGate`。旧 `sendMessage`、`sendImage`、`sendAudio` 路由分别固定 fail-closed，不进入模型执行；`sendLocalImage()` / `sendLocalAudio()` 无调用点且已删除。
- **Core-0～Core-5：** Core-0 契约与源码映射冻结；Core-1 云端 transcript/SessionState/provenance、临时上下文隔离和 request ledger 已有代码/自动化证据；Core-2 当前 CandidateEvidence、多源聚合、独立 RankedEvidenceSet 与黄金回归已完成；Core-3 主文本/附件结构化协议和旧入口退役已完成当前云端范围；Core-4 仅开放四项已审计 capability，UNKNOWN 不重放；Core-5 20 轮知识追问与一次工具闭环为应用层 fake Native/executor E2E，不代表真机模型表现。
- **Core-1 Token 与设备边界：** `Conversation.getTokenCount()` / `ModelInfo.maxContextTokens()` 仅提供只读观测；`conversationKvCacheBudgetStatus=NOT_CONFIGURED_DEVICE_CALIBRATION_REQUIRED`。不把模型声明上限或当前 KV Cache token 数解释为 App 可用输入预算，不添加推测的阈值、输出预留、自动裁剪/压缩或 KV Cache 持久化。
- **设备验收：** Find N2 GPU/CPU 长会话、state:7、真实 E4B 生成质量、图片/音频、多轮/Activity/process restart、SQLite/UI/Native transcript 一致性、覆盖升级、数据清理及 TRACE 均为 LOCAL ONLY / MISSING / UNKNOWN，必须在设备实测；云端 CI 不替代。
- **优先级边界：** 工作流 H 的既定云端范围完成当前批次；工作流 I 用户 Markdown 书架继续 DEFERRED / NOT AUTHORIZED；不新增 Agent、服务、数据库、AI Gate、Embedding、向量数据库或 Reranker，不扩张四项 capability allowlist。


### 5.10 2026-11-27 Core-1 Native 跨进程 transcript 恢复改为确定性角色重建

- **缺陷：** 旧 `restoreLocalConversation` 将历史文本包成一条新的用户 prompt，再调用模型生成“上下文已载入”确认。这会额外运行一次推理，并把旧 user/assistant 角色边界压扁成一个合成 Native 成功轮次；Native 12 轮上限也可能被绕开。
- **修复：** Flutter 按最近 12 个完整轮次和 10,000 UTF-16 code units 裁剪，并输出结构化 `completedTurns`、已完成轮次省略数及字符数。Native 校验字段、surrogate、轮次数与字符数，恢复 `LocalAiConversationHistorySnapshot` 后直接通过 `ConversationConfig.initialMessages` 重建角色序列。
- **记忆边界：** 完整轮次保留原 user/assistant 角色；同一 user turn 下连续 assistant 消息合并到该轮 assistant 文本。assistant-only 欢迎/前导消息不伪装成用户轮次。未完成 user-only 消息不进入 Native 成功 transcript，也不计入已完成/已省略成功轮次数；原始用户文字仍通过独立 `userMessages` 保留，供症状整理使用。
- **SessionState 元数据准入：** 通用 `AssistantMessageMetadata.decode` 保持历史展示兼容；记忆事实准入单独使用 schema-aware `isReplayableForSessionMemory`。仅接受 schema v1 与已识别的历史分号格式；显式非 replayable、未知 schema、损坏或无法识别的 metadata 不得晋升为 `USER_ORIGINAL`，计入省略数并将快照标记为 `PARTIAL`。缺失 metadata 的旧消息继续兼容。
- **执行语义：** 恢复过程不调用 E4B、不触发 GPU/CPU fallback、不生成 synthetic assistant reply；Live KV Cache 仍不跨进程持久化。模型生成与工具执行的请求状态语义不变，UNKNOWN 仍不自动重放。
- **云端回归：** Dart 覆盖最近 12 轮、UTF-16 边界、完整轮次与未完成 user-only 分离；Kotlin 覆盖 typed role 恢复、代理字符与 Native 字符/轮次边界；静态架构回归确认 `restoreLocalConversation` 不调用模型或 GPU/CPU fallback。
- **单次 Native 会话创建：** 历史恢复把已校验快照传入 `resetLocalConversation`；旧 Conversation 关闭后先恢复成功历史，再通过 `createConversationWithHistory` 一次性创建目标 Conversation，不创建空会话中间态。若关闭/创建失败，Engine 按既有 fail-closed 规则释放，并保留已校验快照供后续模型重载恢复；普通 reset 仍创建空会话。 reset 必须关闭 Engine 时，若 `Engine.close()` 本身失败（包括 `Throwable`/Native `Error`），通过 `LocalAiProcessExecutor.health` 将当前进程标记为不可用；共享 `LocalAiActivityTaskLifecycle` 随后拒绝该进程中的新任务，必须强制停止并重启 App 才能重新初始化。只有 Engine 释放成功，普通 close/create 失败才允许后续重新加载。
- **设备边界：** 真实 E4B 生成、GPU/CPU 多轮、state:7、Activity/process restart 和 SQLite/UI/Native transcript 一致性仍需 Find N2 TRACE；CI 不替代设备 PASS。


### 5.11 Core-1 Native 历史恢复载荷采用必需字段校验

- `restoreConversation` 的 MethodChannel envelope 必须同时包含 `completed_turns`、`omitted_completed_turn_count`、`omitted_completed_character_count` 和 `userMessages`；缺失字段、非整数计数、负数/越界计数或非字符串用户输入均在会话重置之前以 `INVALID_RESTORE_PAYLOAD` 拒绝。
- 不再用空列表或 0 替代缺失字段，避免协议错配被误当成有效空历史而清空当前 Native 会话。合法空 `completed_turns` 仍允许用于没有完整成功轮次、仅有未完成输入的历史；独立用户输入投影仍按既有 60 条入口和 `UserReportedInputPolicy` 字符/条目边界治理。
- 不改变历史裁剪、12 轮/10,000 UTF-16 上限、Token 预算状态、会话所有权、模型推理和业务逻辑。


### 5.12 Core-1 SessionState metadata schemaVersion 使用严格整数合同

- SessionState 记忆准入只接受 JSON metadata 中类型为整数且值为 `1` 的 `schemaVersion`；`1.0` 等数值相等但类型不符的版本值视为未知/不兼容格式，fail-closed，不得提升为 `USER_ORIGINAL`。
- 该约束只作用于 `isReplayableForSessionMemory`；通用 `AssistantMessageMetadata.decode` 的历史/UI 兼容 fallback 不改变。
- 回归覆盖 metadata 准入函数与 `SessionStateSnapshotBuilder` 的最终事实投影，确保该类原始消息只计入 omitted 数，快照保持 PARTIAL。


### 5.13 Core-1 Native 历史恢复的用户输入投影在跨进程前限界

- `userMessages` 是单独用于症状整理的用户自述投影，不属于 Native 成功 transcript，也不等同于 SessionState 事实。Flutter 在 MethodChannel 发送前增量保留最近 60 条非空用户输入；遍历历史时即淘汰较早条目，不先创建无界的完整用户消息副本。
- 边界按 Native 最终保存格式计算，包含每条固定来源标签 `用户文字自述：`：格式化后每条最多 2,000 UTF-16 code units，合计最多 16,000 UTF-16 code units。超长单条只按完整 UTF-16 代理对边界裁剪，数量/单条/总量发生裁剪时统一将 `user_messages_truncated=true` 随载荷传给 Native。
- Native `parsePayload` 必须收到显式 Boolean 截断状态，并再次验证最多 60 条、每条及总量（均包含来源标签）；缺失、类型错误或超界在当前 Conversation reset 之前以 `INVALID_RESTORE_PAYLOAD` 拒绝。成功恢复后，`userReportedInputsTruncated` 由显式状态初始化，继续进入既有症状来源完整性提示；不再接收无界列表后静默丢弃旧条目。
- 本边界不改变成功 transcript 最近 12 个完整轮次 / 10,000 UTF-16 上限、SessionState memory admission、UNKNOWN/non-replayable 规则、RAG 隔离、LiteRT KV Cache 或 App Token budget。上述均为 UTF-16 字符数/条目数，不是 Token 预算。


### 5.14 2026-11-28 Core-3 ReasoningResponse v1 schemaVersion 严格整数校验

- **基线：** 从 PR #610 合并后的 `master@bcfa2e36440689d7d5cd12abfd80cf191c6d66dc` 重基 Core-3 独立协议修复；原始独立切片提交为 `dfb0d7aae3555f8ba47bbfa09118e16b13e29b82`，只涉及 ReasoningResponse decoder 与对应负向测试。
- **问题：** JSON 数值 `1.0` 在 Dart 中是 `double`，但仅比较数值时可能与整数 `1` 相等。v1 解码器若只比较数值，会把类型不符合版本合同的载荷作为受支持 schema 接受。
- **修复：** `ReasoningResponseCodec.decode` 先要求 `payload['schemaVersion'] is int`，再要求值严格等于 `schemaVersion == 1`。未知字段、缺失字段、版本不支持以及类型不符均保持 `PARSE_FAILED` / fail-closed；不改变通用 JSON 读取或其他 DTO 的兼容规则。
- **回归：** `test/reasoning_response_codec_test.dart` 覆盖整数 v1 正常路径、缺失/未知字段、不支持版本 `2`，以及浮点版本 `1.0` 必须拒绝。
- **边界：** 不改变 ReasoningRequest、requestId/evidence ID 校验、响应 kind/status、ACTION_PROPOSAL 确认/执行门禁、Native 调用链、业务白名单或记忆层；本修复不是 Core-3 所有设备行为的证明。Find N2 真实 E4B/媒体/多轮结果仍留在最终设备验收，未知状态继续 MISSING / UNKNOWN。
- **验收：** 以该独立 PR 最终 HEAD 的 Flutter 静态分析/全量回归、Android arm64/JVM 和 Fork License 为准；SKIPPED 不计 PASS。
## 10. 2026-11-28 v1.4 本地/云端统一模型运行时补充（当前规范）

> 本节与 docs/pro-edition-architecture-constraints.md §18 同步，优先于本文早期只描述 E4B、未授权云端模型或将 Embedding/Reranker 延后的历史表述。历史任务记录保留作为时间轨迹，不再自动构成当前禁止项。

### 6.1 任务模型配置

首期任务键固定为：

| taskKey | 模型职责 | 选择与继承规则 | 未配置时行为 |
|---|---|---|---|
| text_reasoning | 默认语言推理 | 必须由用户选定一个本地或云端生成模型 | 明确提示默认模型未配置，不自动选取 |
| image_understanding | 图片理解 | 可选专用本地/云端模型；未配置时跟随默认推理模型 | 若用户选定的模型不支持，显示真实错误 |
| audio_understanding | 音频理解 | 可选专用本地/云端模型；未配置时跟随默认推理模型 | 若用户选定的模型不支持，显示真实错误 |
| embedding | 向量嵌入 | 必须独立选择本地或云端 Embedding 模型 | 保留现有确定性关键词/实体/结构化召回，不发起模型调用 |
| reranking | 候选重排 | 必须独立选择本地或云端 Reranker 模型 | 保留 SourceAwareLegacyEvidenceRanker 确定性排序，不发起模型调用 |

- 各任务选择的是具体 ModelConfig，不是助手场景或模式；不按问诊/学习/工具/玄学单独绑定模型。
- 不建设能力探测、模型探针、能力目录或基于模型名/供应商模型列表的能力推断。
- 不展示每轮路由原因/能力探针细节；任务不支持时以实际调用错误提示。
- 禁止本地与云端、供应商之间或模型之间自动切换；禁止本地失败后自动上传云端或云端失败后自动回退本地。

### 6.2 统一授权和 AI 总开关

模型请求的统一可用条件为：有效专业版 ai_access AND 用户保存的 AI 总开关开启 AND entitlement 当前状态可用。

- ai_access 是唯一签名授权权益；不新增 cloud_ai_access、embedding_access、reranker_access 或其他按任务收费 Feature。
- 用户开关是普通用户偏好，不是授权事实；非专业版、授权校验中或授权无效时不得开启/调用模型。新增开关的默认值/升级迁移必须兼容既有用户行为，不能静默关闭既有专业版用户正在使用的 AI。
- 所有本地/云端生成模型、多模态、Embedding 和 Reranker 请求均须在统一调用入口检查此条件。
- Android Native LiteRT 继续由 AiModelAccessGate 在模型访问边界最终 fail-closed；云端 HTTP 通过受控 Model Gateway 在请求前检查同一状态。Provider Adapter 不得成为绕过统一 Gate 的可直接调用入口。
- 关闭 AI 或授权失效不删除模型文件、API Key、供应商配置、索引或历史；停止新请求并按既有生命周期释放本地运行时。已发出的云请求若无法确认是否处理，标 UNKNOWN，不自动重放。

### 6.3 Embedding 与 Reranker 的层间合同

- Embedding 只负责把 query/chunk 转换为向量候选；候选必须映射回 App 已存在的 sourceId、chunkId、版本和 locator，模型不得生成或提升来源元数据。
- 每个向量索引记录 runtime/provider、modelConfigId、模型 ID/指纹、模型版本、向量维度、归一化策略、索引 schema/generation 与源内容 hash；不兼容模型空间不得混用。
- Embedding 模型变化时建立新 generation 并重建；全部构建并通过一致性检查后原子切换，失败保留旧索引。
- Reranker 只处理本轮已召回且有界的 CandidateEvidence；输出仅接受输入集合中的候选 ID 合法排序，由 App 校验无未知/重复 ID。
- Reranker 不得创建/改写候选正文、sourceId、verificationStatus 或来源版本；其相关性分数不是资料真实性、经典权威性、医学正确性或事实置信度。
- 显式配置后，所选 Embedding/Reranker 失败必须报告失败；不回退到其他模型，也不把失败伪装成确定性召回/排序成功。

### 6.4 上下文窗口与历史预算

- 每个生成模型配置独立的用户声明 contextWindowTokens 与 maxOutputTokens，可用常见预设及自定义整数（包括 1M）；预设不是模型能力保证。
- 云端请求按对应模型 Tokenizer/接口统计计算系统提示、当前输入、完整会话历史、证据和工具结果预算，并为输出预留 Token。不能取得准确 Token 数时标 UNKNOWN，不以字符比例冒充 Token。
- 本地模型值不得超过模型声明、Native Runtime 和 Find N2 实测可用上限；E4B 当前 ModelInfo/KV Cache 只是只读观测，真实设备校准前不配置 App 可用 Token budget。
- Embedding/Reranker 使用各自输入长度/候选条数合同，不使用生成模型 contextWindowTokens。
- 长上下文不放宽 Session ID 隔离、transcript、SessionState provenance、用户确认和 UNKNOWN 不重放。

### 6.5 Local / Remote / Architecture / Integration 责任

| Workstream | 主要交付 | 不得声称 |
|---|---|---|
| Local | 本地 Embedding/Reranker 格式、运行库、Tokenizer、文件导入完整性、Find N2 内存/耗时/稳定性和真实 TRACE；现有 E4B GPU/CPU/媒体/生命周期实机验收 | 不得以云端 Mock、CI 或代码存在声称本地模型/设备 PASS |
| Remote | Provider Adapter、Credential Vault、统一 Gateway、设置/模型配置、云端各任务 Adapter、SQLite 配置/索引方案与自动化测试 | 不得声称 Find N2 设备运行已通过 |
| Architecture | 公共 taskKey、配置 DTO、授权状态、失败语义、Adapter 接口与五层边界冻结 | 不把规范文本当作实现完成 |
| Integration | 当前 master 基线、文件 Owner、PR、CI、合并后主线同步和执行台账 | 不让多个分支同时写相同共享文件 |

### 6.6 当前实现状态边界

- 当前已确认本地生成模型为 Gemma 4 E4B + LiteRT-LM；本地 Embedding/Reranker 独立 runtime 尚未确认，标记 MISSING / NEEDS LOCAL AUDIT。
- 云端 Provider、Credential Vault、Model Gateway、云端 LLM/图片/音频、云端 Embedding/Reranker、统一 AI 总开关、TaskModelSelection 与上下文 Token budget 端到端接线均为 NOT_STARTED / MISSING。
- 当前 CandidateEvidence、MultiSourceEvidencePipeline 与 SourceAwareLegacyEvidenceRanker 是可复用 Core-2 基础，不等于向量索引或 Reranker 已接通。
- v1.4 只冻结边界；全部功能仍需独立 Task ID、文件范围、源码/测试/CI/设备证据和可回滚小批量 PR。