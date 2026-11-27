# AI 核心分层运行时架构约束

> **文件性质：AI 核心架构规范 / 高优先级执行约束。**
>
> **优先级：核心主线。** 本文件定义整个 AI 能力的职责划分、数据契约、跨层边界和实施顺序。用户 Markdown 书架、Embedding 模型和其他知识源扩展必须服从本文件，不得反过来牵引核心架构。
>
> **核心决策：** 知识召回、证据排序、会话记忆、语言推理、业务执行五项职责必须逻辑独立、输入输出可审计、状态所有权清楚。它们不是五个互相自治的 Agent，也不要求拆成五套服务、五个数据库或五个模型。
>
> 本文件与 docs/product-positioning-and-boundaries.md、docs/ai-capability-audit.md 和 docs/ai-modernization-execution-ledger.md 配套使用。产品定位约束产品边界；本文件定义核心运行时职责；AI 审计规范定义实现与证据门槛。若有冲突，不得扩大模型权限或破坏确定性业务边界。

## 1. 架构目标：五项职责独立，而不是一个模型包办

核心目标不是增加 Agent 数量，而是让每项能力都能独立解释、独立测试、独立失败和独立替换：

1. **知识召回（Knowledge Retrieval）**：确定“有哪些候选资料可能相关”。
2. **证据排序（Evidence Ranking）**：确定“哪些候选证据值得进入本轮上下文、先后顺序如何、为什么保留/排除”。
3. **会话记忆（Session Memory）**：确定“当前用户、当前会话和当前任务已经明确了什么，哪些状态可跨轮延续”。
4. **语言推理（Language Reasoning）**：由端侧 E4B 理解问题、综合证据、解释、澄清和提出受约束的业务动作意图。
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
- 不要求每层都有独立 LLM。当前 Gemma 4 E4B IT 仍承担语言推理；检索可先用现有确定性检索；Embedding/Reranker 仅在单独阶段有证据后引入。
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

- 排序可组合现有标题/精确匹配、关键词、向量、RRF 或后续 Reranker；但每种策略必须单独可测。
- 评分只表示当前检索任务的相关性信号，不表示医学正确性、经典权威性、来源真实性或事实置信度。
- 来源身份和核验状态只能读取数据层提供的元数据，不能由排序模型自行提升。
- 不得静默融合版本冲突的方剂组成、剂量、条文和医案记载；冲突证据应分来源保留。
- 不以候选数量、向量相似度或 RRF 数值代替黄金查询集验收。
- Reranker 不是必选组件。只有出现可复现错排且对照实验有净收益时，才单独评估。

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

### 2.4 语言推理：E4B 负责理解和表达，不承担其他四层的权威职责

输入必须是已组装且带来源的 ReasoningRequest：

- 当前用户原话；
- 当前会话的有界 SessionStateSnapshot；
- 已排序的 RankedEvidenceSet；
- 如有则包含确定性 Business ExecutionResult；
- 当前模式、权限边界和响应 schema。

E4B 可以：

- 理解自然语言、处理指代和歧义；
- 对候选证据进行归纳、比较和解释；
- 指出冲突、缺项和不确定项；
- 生成澄清问题；
- 提出一个已登记业务能力的结构化调用意图；
- 输出带引用 ID 的解释内容。

E4B 不可以：

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
4. 现有 ai_access / Native AiModelAccessGate 等访问门禁；
5. 通过 App 已有确定性业务函数执行；
6. 返回真实 ExecutionResult，包括执行状态、解析后的参数、结果、来源和错误；
7. 在需要时提供可验证的幂等/重试语义。

约束：

- 用户自然语言和 RAG 正文不能直接执行工具。
- E4B 只能提出 ACTION_PROPOSAL；由代码进行权限与参数判断后才可能执行。
- 未登记、未授权、缺参、类型不符、跨领域请求均由代码拒绝或要求澄清。
- 只有业务函数真实返回并通过结果校验，执行状态才可标 SUCCEEDED。
- 执行状态分为 NOT_STARTED / SUCCEEDED / FAILED / UNKNOWN；UNKNOWN 不得自动重放有副作用的请求。
- 排盘、历法、问诊规则、剂量换算及其他既有确定性计算继续由 App 既有函数执行，不能迁移给模型。
- 业务执行与模型授权分开治理；任何 LiteRT/LiteRT-LM 模型加载/推理均遵守项目既有唯一 ai_access 和 Native AiModelAccessGate，不新增第二套门禁或收费权益。

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
- 不创建第二套会话数据库，不迁移业务算法，不新增 ai_access 或 Native `AiModelAccessGate`。
- 后续代码按“一个边界、一个可验证切片”逐步适配；未被调用路径消费的 DTO 只算契约资产，不算运行时能力已完成。

## 3. 五层之间的统一数据流

用户输入
  → 意图/实体初步解析 + 读取当前 SessionStateSnapshot
  → 知识召回，输出 CandidateEvidence
  → 证据排序，输出 RankedEvidenceSet
  → 会话记忆提供有界状态和来源引用
  → 组装 ReasoningRequest
  → E4B 语言推理
  → ANSWER / CLARIFICATION，或输出 ACTION_PROPOSAL
  → 如有动作提案，经过业务执行 Gate
  → ExecutionResult 返回结果解释
  → 引用/结果确定性校验与最终展示
  → 按策略提交会话/任务状态

该流程表示职责与数据流，不要求每轮必须调用五个独立进程，也不表示所有请求都要检索或执行工具。

### 3.1 典型请求路径

| 请求类型 | 必须经过 | 可以省略 |
|---|---|---|
| 纯闲聊/简单解释 | 会话记忆读取 → E4B → 状态提交 | 知识召回、证据排序、业务执行 |
| 本地知识问答 | 会话记忆读取 → 知识召回 → 证据排序 → E4B → 引用校验 | 业务执行 |
| 跨轮追问 | 会话记忆/实体指代解析 → 必要时重新召回 → 证据排序 → E4B | 无关历史资料重放 |
| App 确定性工具请求 | 会话记忆读取 → E4B 意图/参数解析（必要时）→ 业务执行 Gate → 结果校验 → E4B 解释 | 无关知识召回 |
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
4. E4B 是语言推理层；ToolRouter/HeadlessToolDispatcher、ContextResolutionGateway 和 App 既有确定性业务函数承担不同的执行/来源校验职责，不能把它们合并为模型 Agent。
5. 现有授权、模型加载、Native 单线程队列、GPU/CPU fallback 和保守恢复语义必须保留；任何拆分须证明没有并发、重复执行、资源释放或数据恢复回归。
6. 每个候选新 Adapter/DTO 必须指向实际调用链缺口和可复现测试；不因为图上有五层就机械新增五个模块。

### 5.1 当前 master 源码映射与已确认断点（2026-11-27）

**AI 运行时代码审计基线：** PR #585 合并点 `45144f6c3d140d259ac51f8cfbb886c19c10e0a3`，已包含 PR #583 的 Core-3 图片/音频结构化推理接线，以及 PR #585 的 Core-5 20 轮记忆隔离与工具执行回流 E2E。当前仓库 `master` 已推进至 `d024d2e277e80bb960b8986dc01d860eb7f7670f`（该提交仅同步五层架构/执行台账/Native 多轮审计/设备交接文档，没有改变五层 AI 运行时代码；其父基线 `922285573e263ecd08a1eed535d4adec771a5979` 的 Flutter tests、Flutter Quality Gate 与 Fork License 均有 SUCCESS 记录，但本轮未取得 d024d2e 的独立 post-merge CI 终态）；本节五层审计以 45144f6c 的 AI 运行时集成点为锚，并以当前 master 检查文档/兼容性。以下按已合并代码描述生产能力；开放 PR、旧 SHA 的 CI 和本地未执行的 TRACE 不计为当前通过证据。

| 目标职责 | 当前主要代码位置 | 当前状态与断点 |
|---|---|---|
| 知识召回 | ClassicEvidencePipeline、GujiEvidencePipeline、MedicalCaseEvidencePipeline；Formula、Herb、Acupuncture formula、Acupoint、Neijing 结构化资料适配为 CandidateEvidence；AssistantKnowledgeContextBuilder.buildAsync/buildWithEvidenceAsync | **当前约定范围已落地：** #568 将五类本地结构化资料纳入请求级候选，并与经典/医案/古籍候选进入 MultiSourceEvidencePipeline；候选快照保留 query/retrieval provenance 和来源身份，后续由独立 ranker 处理。AssistantKnowledgeContextBuilder 仍编排现有 query/matching 与上下文物化，保留 legacy 命中语义；不代表覆盖全部数据源、独立查询生成器或内容正确性审定。 |
| 证据排序 | MultiSourceEvidencePipeline.combine、SourceAwareLegacyEvidenceRanker.rank、AssistantKnowledgeContextBuilder.buildWithEvidenceAsync | **当前约定范围已落地：** MultiSourceEvidencePipeline 仅合并并命名空间隔离各来源 CandidateEvidence，不自行排序；SourceAwareLegacyEvidenceRanker 独立接收候选并输出不可变 RankedEvidenceSet（requestId、strategyId/version、逐候选 KEEP/DROP 原因、稳定顺序、状态和诊断）。AssistantKnowledgeContextResult 同时提供排序前的 metadata-only AssistantKnowledgeCandidateSnapshot、完整排序决策，以及仅包含完整呈现且已解析来源的 rankedEvidence；最终 6,500 UTF-16 code units 呈现预算记录 omitted/truncated evidence IDs。**边界：** 当前策略是有意保留的确定性 legacy 来源顺序/每来源上限，不是语义相关性排序；6,500 字符是呈现预算，不是模型 Token/input budget。检索查询和上下文物化仍由 AssistantKnowledgeContextBuilder 编排，但召回/聚合/排序输入输出边界已独立可测。 |
| 会话记忆 | SessionStateSnapshotBuilder、LocalAiConversationHistory / LocalAiConversationSessionPolicy、Native LocalAiSessionStateInputPolicy、AssistantReasoningTurnLedger、AssistantToolInvocationLedger | **云端代码/测试已落地，仍有设备级缺口：** SessionStateSnapshot 具有 provenance 与 conversation owner 校验；隐藏 role=tool 的推理/执行 Ledger 不进入普通会话记忆。#565 追踪 RAG/SessionState/reasoning metadata/媒体输入是否污染活动 KV，并在下一请求前仅对 dirty cache 从有界成功 transcript 重建；#575 持久化推理 PENDING/FINALIZED/REJECTED/UNKNOWN/SUPERSEDED 状态，未完成请求恢复为 UNKNOWN 且不自动重放。LiteRT KV Cache 本身不持久化；12 轮/10,000 transcript、16,000 SessionState 字符限制不是模型 Token 预算；自动压缩仍未实现，真实进程恢复为 DEVICE UNKNOWN。 |
| 语言推理 | ReasoningRequest / ReasoningResponse v1、ReasoningRequestPromptFormatter、ReasoningResponseCodec、ReasoningKnowledgeAnswerAdapter、LocalAiService；Native sendLocalReasoningMessage / sendLocalReasoningAttachmentMessage、finalizeReasoningTurn / rejectReasoningTurn | **主路径已接线，边界仍需持续审计：** #573 将 automatic、consultation、learning、tools、metaphysics 五种主文本模式接入结构化协议；#583 将 image/audio 附件接入同一请求/响应契约与 Native 双阶段提交。图片结果是结构化观察，音频转写是待用户确认草稿。intent、Bazi slot、symptom、单题问项仍是独立窄任务 DTO；旧 sendMessage 兼容入口仍存在。 |
| 业务执行 | ReasoningActionProposalGate / Adapter、AssistantToolExecutionCoordinator、AssistantToolInvocationLedger、HeadlessToolDispatcher.executePlan、ReasoningExecutionResultAdapter | **受限生产闭环已接线：** #561/#566 将工具模式动作提案、请求级能力 allowlist、App 显式确认、持久化 one-shot claim、Dispatcher、终态安全读回和只读结果解释回合接通。当前仅开放四个既有 plan-eligible capability；allowlist 不等于授权，模型输出不直接执行，UNKNOWN 不重放。其他 Router 注册项不因此自动成为模型可调用能力。 |

### 5.2 当前源码、测试锚点与未闭环项

| 层 | 主要回归锚点 | 仍需解决的明确缺口 |
|---|---|---|
| Core-0 契约与源码映射 | 本文件 §2 DTO、§3 数据流、§5.1 当前映射；各层现有契约测试 | 本轮只冻结当前代码真实入口、数据所有权和状态，不新增服务、Agent、数据库、模型或权限门禁。 |
| Core-1 会话记忆 | test/session_state_snapshot_builder_test.dart、test/session_state_snapshot_prompt_formatter_test.dart、reasoning turn ledger 相关测试、Native LocalAiConversationHistoryPolicyTest / LocalAiSessionStateInputPolicyTest | 不持久化 LiteRT KV Cache；Native context 通过 transcript 重建，不等于 KV 状态恢复。模型实际可用 Token/input budget、自动压缩、Find N2 进程恢复 TRACE 仍为 UNKNOWN / NOT IMPLEMENTED。 |
| Core-2 知识召回/排序 | test/assistant_knowledge_context_test.dart（Formula/Herb/Acupuncture/Acupoint/Neijing/MedicalCase）、test/multi_source_evidence_pipeline_test.dart、test/source_aware_legacy_evidence_ranker_test.dart、test/ai_retrieval_golden_snapshot_test.dart | **已落地：** 五类结构化本地资料与 Classic/Guji/MedicalCase 均进入 CandidateEvidence；候选元数据快照、query/retrieval provenance、完整 KEEP/DROP reason、strategy/version、顺序、状态、诊断和最终字符预算均有结构化输出与回归。**限制：** 仍保留 legacy 查询生成、匹配和来源限额；不提供 Token 预算或语义相关性分数。KEEP/DROP 不是来源真实性、经典权威性或医学正确性判断。 |
| Core-3 语言推理 | test/reasoning_request_prompt_formatter_test.dart、test/reasoning_response_codec_test.dart、test/reasoning_knowledge_answer_adapter_test.dart、test/local_ai_service_test.dart、test/reasoning_attachment_architecture_test.dart、test/local_ai_interview_screen_test.dart | 主对话与媒体附件结构化协议已接线；仍需审计旧兼容接口的全仓调用者和各辅助窄任务边界。音频 transcriptDraft 在用户确认前不得提升为 USER_ORIGINAL 记忆事实。 |
| Core-4 业务执行 | test/reasoning_action_proposal_adapter_test.dart、test/assistant_tool_invocation_ledger_test.dart、test/headless_tool_dispatcher_test.dart、test/reasoning_execution_result_adapter_test.dart、test/local_ai_interview_screen_test.dart | 四个 plan-eligible capability 闭环已接入；其他工具不自动扩权。能力级 schema/副作用/幂等/取消等治理按既有 capability audit 继续补齐；UNKNOWN 不重放。 |
| Core-5 端到端验收 | test/local_ai_interview_screen_test.dart：Core-5 20 轮知识追问与一次工具执行回归；Flutter 全量回归、Android arm64/JVM、Fork License | 云端 widget/fake-executor 闭环已验证；不等于真实 E4B Native 推理或 Find N2 GPU/CPU、媒体、Activity/process restart TRACE。设备证据留到所有云端改造收尾后本地执行。 |

**文件责任与集成约束：** Core-1 改动集中在 Native 会话历史/请求 Ledger、SessionStateSnapshot 及对应 Kotlin/Flutter 测试；Core-2 改动集中在 CandidateEvidence 适配、多源 Pipeline、Ranker 与黄金 fixture；Core-3 改动集中在 Reasoning DTO/formatter/codec、LocalAiService、MainActivity 和助手发送 UI；Core-4 改动集中在 Gate/Coordinator/InvocationLedger/Dispatcher 连接及确认 UI；Core-5 负责跨层测试和 TRACE 对照。每个切片从当时 master 创建独立分支，按小批量 PR 集成；设备验收不阻塞云端代码、测试或文档工作。

## 6. 当前执行状态与后续放行顺序

本节取代早期“各 Core 尚待接线”的排期快照。当前状态以 2026-11-27 主线和精确 PR HEAD 证据为准；历史分支描述保留作演进记录，不作为当前待办。

| 顺序 | 层 | 当前主线状态 | 现有证据 | 尚未闭合 / 放行边界 |
|---|---|---|---|---|
| 1 | Core-0 契约与源码映射 | **DOC/CODE MAP 已完成** | §5.1–§5.5 已映射五层 DTO、数据所有权、Native 入口、失败语义和测试锚点 | 后续随主线变更维护映射；不再为已存在的类重复建第二套抽象 |
| 2 | Core-1 会话记忆与 Native 多轮 | **云端代码/测试已落地；DEVICE UNKNOWN** | #565 dirty-KV flush；#575 持久化推理请求终态；#117/#119 原子 transcript 与 TRACE 分离；#120 Activity 资源串行释放；Native 12 轮/10,000 UTF-16 边界与恢复测试 | LiteRT KV Cache 不跨进程持久化；模型实际 Token/input budget、自动压缩、Find N2 GPU/CPU 连续推理、state:7、Activity/process restart 与三方历史一致性留给最终设备 TRACE |
| 3 | Core-2 知识召回与证据排序 | **当前约定范围已完成** | #527 RankedEvidenceSet；#568 五类结构化资料 CandidateEvidence；metadata-only candidateSnapshot、query/retrieval provenance、KEEP/DROP reason、strategy/version 和 6,500 UTF-16 呈现预算 | 保留 legacy query/matching/order/per-source caps 与 golden 行为；不将字符预算说成 Token，不扩展语义评分/Embedding/Reranker 作为虚假收尾条件 |
| 4 | Core-3 语言推理 | **五种主文本模式与媒体附件已接入结构化协议** | #573 five modes；#583 image/audio structured Request/Response 与 Native finalize/reject；旧 sendImage/sendAudio fail-closed | 辅助 intent/Bazi/symptom/问项保留窄 DTO；旧 sendMessage 兼容入口需按全仓真实调用者审计后决定退役，不能无证据删除 |
| 5 | Core-4 业务执行 | **四项能力的受限生产闭环已接通** | #561/#566：ACTION_PROPOSAL → App 显式确认 → durable one-shot claim → Dispatcher → terminal read-back → 新 requestId/空 allowlist 只读解释 | 仅四项 plan-eligible capability；不等于 18 个 Headless executor 全部可被模型调用。逐项版本化 schema、副作用、幂等、取消/超时和补偿策略仍需按能力审计 |
| 6 | Core-5 端到端验收 | **云端 20 轮 + 单次工具闭环 PASS；设备部分 UNKNOWN** | #585 widget E2E 覆盖 20 轮、owner/requestId、记忆隔离、一次确认动作与只读结果回流；精确 PR HEAD Flutter/Android arm64/JVM/Fork License PASS | fake executor 不证明 E4B Native/GPU/CPU 或真机进程恢复；设备实测统一放到所有云端改造/CI/文档收尾之后 |

执行与集成要求：

- 当前不因设备未连接而暂停 Core-1 至 Core-5 的云端代码、回归和文档审计；只有需要物理硬件的 TRACE 才记为 DEVICE UNKNOWN。
- 对已通过的 Core-2，不重新实现候选快照或排序审计；除非发现具体旧黄金用例回归或输入/输出契约缺陷，否则保持现有策略。
- Core-3 的旧兼容入口与辅助窄任务单独审计，不以“统一”名义把不同约束的任务塞进主聊天 DTO。
- Core-4 不扩大四项白名单，不允许模型跳过 App 显式确认，不允许 UNKNOWN 自动重放。
- 小批量集成继续从最新 master 建独立分支；最终 HEAD 要有适用的 Flutter、Android arm64/JVM、Fork License 和静态分析证据。SKIPPED 不计 PASS，旧 SHA CI 不替代最新 HEAD。
- 全部云端事项收尾后，本地按唯一 docs/local-real-device-acceptance-handoff.md 执行 Find N2 TRACE；MISSING/UNKNOWN 保持原状态，不预填 PASS。

## 7. 书架和其他知识源的优先级

- 用户 Markdown 书架是未来可选的 USER 知识源，不是五层架构的中心，也不是当前核心主线。
- 书架只能通过知识召回层提供 CandidateEvidence；不得绕过证据排序、会话记忆边界、语言推理协议或业务执行 Gate。
- 系统知识库、用户书架、用户笔记、医案、未来其他本地资料都属于知识源输入，不能为每种来源复制一套推理/记忆/工具执行架构。
- 只有 Core-0 的数据契约冻结，Core-1 的 RAG/Memory 隔离具备可集成条件，Core-2 的召回/排序边界与黄金行为明确后，才评估书架 C 阶段。
- 书架导入、Embedding、后台任务、数据库拆分等不能阻塞核心五层架构，也不能要求先重写核心层来服务书架。
- Embedding/Reranker 是召回或排序层的可选技术组件，不是独立产品主线；必须由中医黄金查询集和 Find N2 实测证明收益。

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
- 引入 Embedding、FTS5、ANN、Reranker、独立向量数据库或云端推理；
- 改变现有黄金检索行为、GPU/CPU fallback、Native 串行队列或 UNKNOWN 请求恢复语义。

所有变更都必须先回答：现有哪一层无法履行职责、用什么 CODE/TEST/TRACE 证明、最小替代方案是什么、失败如何回滚。

---

**最终约束：** 研纪 AI 的核心不是“一个大模型负责一切”，而是五项职责独立协作：知识召回发现候选、证据排序选择本轮依据、会话记忆保存有界状态、E4B 负责语言推理、App 确定性代码负责业务执行。五层共享统一契约但不共享不受控状态；书架只是未来可选知识源。先完成核心分层和多轮/证据边界，再决定是否扩展书架、Embedding 或 Reranker。


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

**AI 运行时复核基线：** PR #585 合并点 `45144f6c3d140d259ac51f8cfbb886c19c10e0a3`；当前仓库主线 HEAD 为 `d024d2e277e80bb960b8986dc01d860eb7f7670f`（仅文档对齐提交；运行时代码仍以 `922285573e263ecd08a1eed535d4adec771a5979` 及更早的 AI 集成点为准）。本节是当前主线 AI 运行态快照；§5.1–§5.2 描述的 AI 生产入口以 45144f6c 为实现集成锚点，文档与全仓现状以当前 master 为准。历史章节保留当时决策和实现轨迹，不覆盖本节当前状态。当前产品范围仍是中医学习辅助工具，不建设临床 detector、不安排医学审核、不恢复已撤销的临床门禁。

#### 当前五层状态

| 层 | 当前主线已落地 | 当前仍未闭合 / 不得夸大 |
|---|---|---|
| Core-0 契约与源码映射 | 五层 DTO、Native 字段所有权、主要生产入口、失败状态、测试锚点和当前文件责任已形成映射 | 本文档只关闭契约/源码映射工作，不把各层运行时实现统一标记为完成 |
| Core-1 会话记忆 | #565 dirty-KV flush；#575 持久化请求终态与非 replayable 恢复；SessionState owner 与隐藏 Ledger 隔离；Native transcript 从 SQLite 重建且按 12 轮/10,000 UTF-16 有界 | 不持久化 LiteRT KV Cache；字符上限不等于 Token budget；自动压缩、真实设备进程恢复与 GPU/CPU TRACE 未完成 |
| Core-2 知识召回与排序 | #527 建立 RankedEvidenceSet（逐候选 KEEP/DROP 原因、策略版本、有序 ID、预算诊断）；#568 将 Formula、Herb、Acupuncture formula、Acupoint、Neijing 五类结构化资料接入 CandidateEvidence；候选快照与排序结果均由 AssistantKnowledgeContextResult 输出 | **当前既定范围已完成。** 保留 legacy query/matching/order/per-source caps；6,500 UTF-16 code units 为最终呈现字符预算，不是 Token budget。没有语义评分、Embedding 或 Reranker；这些不是当前交付门槛。若以后调整策略，必须冻结同输入候选快照并进行旧/新黄金对照。 |
| Core-3 语言推理 | #573 五种主文本模式结构化；#583 图片/音频附件使用 sendReasoningAttachmentMessage 和 ReasoningResponse v1，执行 Native 两阶段提交；旧 sendImage/sendAudio fail-closed | 辅助 intent/Bazi/symptom/问项任务仍为独立窄 DTO；旧 sendMessage Native 兼容入口仍存在，需按实际调用者决定后续退役 |
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
| `sendImage` / `sendAudio` | 旧 Native 自由文本附件兼容入口 | 统一返回 STRUCTURED_ATTACHMENT_PROTOCOL_REQUIRED，不启动模型推理；生产助手发送路径不再调用这两个旧入口 | 已 fail-closed；保留旧入口仅为兼容，不可用于新代码 |
| `restoreConversation` | 历史会话恢复与模型上下文重建 | Native 接收按完整轮次裁剪后的 transcript，reset 后重建 Conversation；提示将历史视为记录而非新指令；只确认 restored，不作为一轮成功答案写入 | Core-1 transcript 到 Native context 的重建入口；不是 KV Cache 持久化 |
| `sendMessage` | LocalAiService 保留的旧 Native 自由文本兼容接口 | 直接返回文本，不经过 ReasoningRequest/Response v1；当前助手主文本/附件路径使用结构化入口，但兼容接口仍存在 | 兼容入口需按全仓真实调用者审计后再决定移除或封禁；不得作为新主路径 |
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

1. Core-0：当前五层契约/源码映射与测试锚点已刷新；AI 运行时实现锚点为 45144f6c，仓库文档/主线 HEAD 已推进到 92228557；代码入口和数据所有权保持可追溯。
2. Core-1：推理请求账本、UNKNOWN/non-replayable 和 transcript 对账已合入；Token budget/KV Cache/自动压缩保持 UNKNOWN 或 NOT IMPLEMENTED。
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

