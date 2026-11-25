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
| 会话记忆 | Native history 由 `LocalAiConversationHistory` 管理，`LocalAiConversationSessionPolicy` 按 conversation ID 隔离；`SessionStateSnapshotBuilder.build` 投影有界结构事实和证据引用；候选 PR #519 将快照作为独立、只读、16,000 UTF-16 code units 上限的本轮 Native text prompt section，并保持 RAG 分离、恢复 transcript 只保留原始用户文本与成功助手回复。 | `LocalAiConversationHistoryPolicyTest`、`LocalAiConversationSessionPolicyTest`、`test/session_state_snapshot_builder_test.dart`、`test/session_state_snapshot_prompt_formatter_test.dart`、Native session owner 与 transcript isolation JVM 测试。 | PARTIAL：#519 尚待精确 HEAD CI 与合并；没有 ReasoningRequest 统一封装、跨进程 Native Conversation 恢复仍 UNKNOWN，16,000 是字符边界而非模型 token/input budget；KV Cache 当前 token 数与模型声明 maxContextTokens 均不是 App 可用输入预算；无自动压缩。 |
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

1. 当前知识检索与上下文构建有合并实现；需审计并明确 CandidateEvidence 与 RankedEvidenceSet 的边界，保留现有黄金行为。
2. Native Conversation 重建所用的成功轮次 transcript 与临时 RAG 输入需要严格隔离；不得把检索正文或完整 modelInput 写入用于恢复的历史列表。
3. 当前 UI transcript、Native Conversation history、结构化任务状态和检索证据是不同数据，不得彼此替代。
4. E4B 是语言推理层；ToolRouter/HeadlessToolDispatcher、ContextResolutionGateway 和 App 既有确定性业务函数承担不同的执行/来源校验职责，不能把它们合并为模型 Agent。
5. 现有授权、模型加载、Native 单线程队列、GPU/CPU fallback 和保守恢复语义必须保留；任何拆分须证明没有并发、重复执行、资源释放或数据恢复回归。
6. 每个候选新 Adapter/DTO 必须指向实际调用链缺口和可复现测试；不因为图上有五层就机械新增五个模块。

### 5.1 当前 master 源码映射与已确认断点

以下是本轮对 master 源码的静态映射快照。它说明当前职责分别落在哪里以及哪里仍然耦合；它不是设备运行证明。修改前必须再次以当时 master 核对行号和调用关系。

| 目标职责 | 当前主要代码位置 | 当前状态与断点 |
|---|---|---|
| 知识召回 | `ClassicEvidencePipeline.retrieveClassicIndexCandidates`、`MedicalCaseEvidencePipeline`（#507，已合并）、`GujiEvidencePipeline`（#512，已合并）分别输出本地候选；`MultiSourceEvidencePipeline.combine` 与 `SourceAwareLegacyEvidenceRanker.rank`（#516，已合并）已提供请求级批次隔离和来源感知 KEEP/DROP；生产 `AssistantKnowledgeContextBuilder.buildAsync` 接线位于候选 PR #518。 | PARTIAL：#516 已在 master；#518 将 classic → 显式指定 Guji → medical 的旧呈现序接入统一候选集，并保留 classic 4、每本 Guji 2、medical 2 的旧上限及 6,500 字符上下文截断；#518 精确 HEAD 的 Flutter 已通过，Android arm64/JVM 仍在执行，Fork License 已通过。 |
| 证据排序 | `LegacyOrderEvidenceRanker.rank` 保留旧单来源兼容策略；`SourceAwareLegacyEvidenceRanker.rank`（#516，已合并）按 retrievalMethod 和 Guji bookId 输出 KEEP/DROP 与原因；候选 PR #518 在 `AssistantKnowledgeContextBuilder.buildAsync` 中对 classic、Guji、medical 合并候选统一调用该策略。 | `test/legacy_order_evidence_ranker_test.dart`、`test/source_aware_legacy_evidence_ranker_test.dart`、`test/multi_source_evidence_pipeline_test.dart`、`test/assistant_knowledge_context_test.dart`、`test/ai_retrieval_golden_snapshot_test.dart`。 | PARTIAL：#516 契约已合并，#518 生产接线待 Android arm64/JVM 验收与合并；不使用相关性分数、不提升来源真实性、不引入 token/字符排序预算，6,500 字符是呈现层硬截断。 |
| 会话记忆 | `MainActivity`、`LocalAiConversationHistory`、`LocalAiConversationSessionPolicy`、`SessionStateSnapshotBuilder.build`；候选 PR #519 增加 formatter + MethodChannel 字段 + Native conversation owner 校验，将快照接入普通文本发送并显式排除恢复 transcript。 | PARTIAL：master 已有 read-only builder；#519 分支接入本轮输入，按 provenance 输出事实和来源身份指针，16,000 UTF-16 字符上限、PARTIAL/UNKNOWN 与跨会话 fail-closed；待 Flutter 全量、Android arm64/JVM 和 Fork License 精确 HEAD 验收。跨进程 Native 恢复仍 UNKNOWN，字符上限不代表 token budget。 |
| 语言推理 | android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt:905-921 | PARTIAL。E4B 通过 Conversation.sendMessage 执行自然语言推理，但输入仍是上游合并后的 modelInput；独立 ReasoningRequest/ReasoningResponse、证据 ID 和动作提案 schema 需要按失败证据逐步建立。 |
| 业务执行 | `lib/services/headless_tool_dispatcher.dart`、`lib/services/context_resolution_gateway.dart`；Core-4 UNKNOWN 行为修复已通过 PR #515 合并。 | PARTIAL：执行异常时保留先前 SUCCEEDED 步骤、当前步骤 UNKNOWN 并停止后续步骤；仍需逐项核对每个工具入口、typed args、授权、结果回填与模型提案协议。 |

**Core-1 当前状态与剩余目标：** #493 已将 Native completed-turn history 的 userText 改为干净用户原话；#496 限制为最多 12 个完整成功轮次/10,000 UTF-16 code units；#499 按 SQLite conversation ID 隔离 Native Conversation；#506 暴露当前 KV Cache token 实测值；#505 已合并只读 `SessionStateSnapshotBuilder`；#509 已合并 `ModelInfo.maxContextTokens()` 模型文件声明上限观测。候选 PR #519 将 builder 接入普通文本 Native 发送：将 USER_ORIGINAL/USER_CONFIRMED/MODEL_INFERRED/APP_RESULT/SOURCE_REFERENCE 以独立结构化段落传递，设置 16,000 UTF-16 code units 字符上限，Native 按当前 SQLite conversation ID fail-closed 校验；快照与 RAG 分离，且不写入 Native recovery transcript。#519 精确 HEAD CI 未全部完成，故此处保持 PARTIAL。KV Cache 实测值、模型声明 maxContextTokens 和 formatter 字符上限均不是 App token/input budget；没有自动压缩。跨进程 Native 恢复仍 UNKNOWN；ReasoningRequest typed envelope 尚未接入.

**Core-2 当前状态与剩余目标：** PR #516 已合并多源 CandidateEvidenceBatch 与来源感知 KEEP/DROP 旧序策略；候选 PR #518 将其接入 `AssistantKnowledgeContextBuilder.buildAsync`，固定 classic → 显式指定 Guji → medical 的候选顺序，保留 classic 4、每本 Guji 2、medical 2 的上限及原 6,500 字符呈现上限。#518 Flutter 全量回归已通过，Android arm64/JVM 与 Fork License 精确 HEAD 门禁仍需记录并完成后再合并。没有分数、向量 reranker 或 token/字符排序预算.

代码状态必须通过当前 master 的 CODE/TEST/CI/TRACE 审计分别填写 IMPLEMENTED / PARTIAL / MISSING / UNKNOWN。不能凭本设计文件给任何运行时能力标 IMPLEMENTED。

### 5.2 五层当前调用映射、测试与未闭环项（master 基线核验）

本节映射基线为 master `e960363b7e32da540ecfe9a52da1204c3013c9d6`（已包含 PR #515 Core-4 UNKNOWN 修复与 PR #516 Core-2 聚合/排序契约）。文件/函数定位优先于固定行号；候选 PR #518/#519/#517 与已合并代码分开记录。

| 层 | 当前生产代码/真实调用路径 | 已有测试证据 | 仍缺少的边界 |
|---|---|---|---|
| 知识召回 | `ClassicEvidencePipeline.retrieveClassicIndexCandidates`、`MedicalCaseEvidencePipeline`（#507，已合并）、`GujiEvidencePipeline`（#512，已合并）分别输出本地候选；`MultiSourceEvidencePipeline.combine` 与 `SourceAwareLegacyEvidenceRanker.rank`（#516，已合并）已提供请求级批次隔离和来源感知 KEEP/DROP；生产 `AssistantKnowledgeContextBuilder.buildAsync` 接线位于候选 PR #518。 | PARTIAL：#516 已在 master；#518 将 classic → 显式指定 Guji → medical 的旧呈现序接入统一候选集，并保留 classic 4、每本 Guji 2、medical 2 的旧上限及 6,500 字符上下文截断；#518 精确 HEAD 的 Flutter 已通过，Android arm64/JVM 仍在执行，Fork License 已通过。 |
| 证据排序 | `LegacyOrderEvidenceRanker.rank` 保留旧单来源兼容策略；`SourceAwareLegacyEvidenceRanker.rank`（#516，已合并）按 retrievalMethod 和 Guji bookId 输出 KEEP/DROP 与原因；候选 PR #518 在 `AssistantKnowledgeContextBuilder.buildAsync` 中对 classic、Guji、medical 合并候选统一调用该策略。 | `test/legacy_order_evidence_ranker_test.dart`、`test/source_aware_legacy_evidence_ranker_test.dart`、`test/multi_source_evidence_pipeline_test.dart`、`test/assistant_knowledge_context_test.dart`、`test/ai_retrieval_golden_snapshot_test.dart`。 | PARTIAL：#516 契约已合并，#518 生产接线待 Android arm64/JVM 验收与合并；不使用相关性分数、不提升来源真实性、不引入 token/字符排序预算，6,500 字符是呈现层硬截断。 |
| 会话记忆 | `LocalAiConversationHistory` / `LocalAiConversationSessionPolicy` 管理 Native transcript/session ID；`SessionStateSnapshotBuilder.build` 投影结构事实/来源 ID；候选 PR #519 将快照 formatter 独立接入普通 Native text turn，Dart MethodChannel 分离传递，Native 校验 active conversation ID。 | `LocalAiConversationHistoryPolicyTest`、`LocalAiConversationSessionPolicyTest`、`test/session_state_snapshot_builder_test.dart`、`test/session_state_snapshot_prompt_formatter_test.dart`、`LocalAiSessionStateInputPolicyTest` 与 transcript isolation 测试。 | PARTIAL：#519 精确 HEAD 的 Flutter 与 changed-tests 正在执行；未合并前 master 生产路径未改变。Snapshot 只作为临时 prompt section，不写入 recovery transcript；无 ReasoningRequest 封装、无跨进程恢复、无模型输入 token 预算。 |
| 语言推理 | Native 路径位于 `MainActivity.sendLocalMessage` / `sendWithFirstTurnGpuFallback`：`Conversation.sendMessage(modelInput)` 返回自由文本，再由 `stripSimpleMarkdown` 清理；Dart 侧按当前模式/上下文组织输入。 | `test/assistant_conversation_orchestrator_test.dart`、`test/assistant_history_resume_test.dart` 覆盖相关编排/恢复行为；尚无五层 ReasoningRequest/ReasoningResponse 独立 schema 回归。 | 当前 Native 主对话路径尚无统一 ReasoningRequest/ReasoningResponse schema；引用 ID、缺证据、冲突和 ACTION_PROPOSAL 尚未成为统一模型输出协议。不能把 Prompt 文本或结构化 JSON 样例当作代码级 schema 校验。 |
| 业务执行 | `ToolExecutionPlan/ToolExecutionStep` 与 `HeadlessToolDispatcher.executePlan` 对已登记计划预校验并顺序执行；PR #515 已合并 UNKNOWN 语义修复。 | `test/headless_tool_dispatcher_test.dart`、`test/headless_tool_result_handler_test.dart`、`test/headless_tool_plan_result_handler_test.dart`、`test/assistant_tool_execution_plan_builder_test.dart`、`test/context_resolution_gateway_test.dart`。 | PARTIAL：UNKNOWN 执行结果已保留且停止重放；模型输出 ACTION_PROPOSAL 的协议接线、能力级 typed args、显式授权与跨层结果回填仍未形成完整闭环。 |

**边界澄清**

- `ContextResolutionGateway` 是来源引用锚点校验和 Resolver 回链保护，不是业务工具执行器，也不是授权/收费门禁。
- `HeadlessToolDispatcher` 是已登记 Headless executor 的实际调度边界；`AssistantToolResult` 是现有结果载体，但它们并不证明所有 Router 注册能力都可执行。
- `AssistantKnowledgeContextResult.text` 是已组装上下文，不是候选集；`sources` 是解析后的来源引用，不等同于逐候选召回/排序审计记录。
- UI 会话记录、Native Conversation transcript、SessionStateSnapshot 和证据引用必须继续作为不同的数据所有权处理。

**文件所有权（Core-0 后续实现排程）**

| 工作流 | 主改文件 | 当前约束 |
|---|---|---|
| Core-0 契约/源码映射 | 本架构文档、AI 执行台账 | 不改生产调用顺序；不新增数据库/服务 |
| Core-1 Memory | `MainActivity.kt`、`LocalAiConversationHistoryPolicy.kt`、`SessionStateSnapshot`/`SessionStateSnapshotBuilder` 及 Kotlin/Flutter 测试 | #493/#496/#499 已完成 Native RAG/历史预算/session ID 边界；本轮只读快照 builder 不新增 schema，也尚未接入推理 prompt |
| Core-2 Retrieval/Ranking | `assistant_knowledge_context.dart`、`classic_search_service.dart`、黄金测试/fixture | 一个分支独占 Builder/Search 文件；先保留当前黄金输出，再分离 CandidateEvidence 与 ranking |
| Core-3 Reasoning | Native 输入/输出 Adapter 与纯协议测试 | 等 Core-0 合同冻结；不得直接让模型触发工具 |
| Core-4 Execution | 工具计划构建、Dispatcher、结果校验和每个 executor | 逐能力核查，不改变 ai_access/AiModelAccessGate |
| Core-5 E2E | 跨层测试与 TRACE 规范接线 | 依赖前四层可独立观测；设备 TRACE 由本地最后完成 |

## 6. 当前最高优先级执行顺序

本节为整个 AI 核心架构优先级，优先于任何书架或新增知识源项目。与 docs/ai-capability-audit.md 的全局 P0～P5 配套，不替换其状态定义。

| 顺序 | 工作流 | 工作范围 | 放行门槛 |
|---|---|---|---|
| Core-0 | 五层契约与源码映射 | 冻结 DTO、数据所有权、现有类/函数映射、调用方和证据缺口 | 每层有实际代码入口、输出契约、失败状态、测试与文件所有权；不做大规模迁移 |
| Core-1 | 会话记忆与 Native 多轮边界 | 解决 RAG 污染历史、历史预算、恢复一致性和 UNKNOWN 请求不重放 | Native/Flutter/SQLite 三种表示一致；Kotlin/Flutter 回归通过；Find N2 证据按既有设备清单单独记录 |
| Core-2 | 知识召回与证据排序解耦 | 先冻结召回候选快照，再单独评估排序；记录每次保留/排除和上下文预算 | 现有黄金用例行为可重现；任何算法变更有旧/新对照，不以候选数量增加为成功 |
| Core-3 | 语言推理输入/输出契约 | E4B 只消费有边界的 Memory + Ranked Evidence + ExecutionResult；输出结构化回答/澄清/动作提案/引用 ID | schema 解析、引用回填、缺证据和模型空回复有回归 |
| Core-4 | 确定性业务执行边界 | 审计并完善已登记工具的 typed args、权限、缺参、执行终态和结果校验 | 未授权动作被阻断；UNKNOWN 不重放；规则/计算结果真实可追溯 |
| Core-5 | 端到端闭环验收 | 覆盖五层组合、跨轮恢复、来源冲突、工具提案与结果解释 | CODE + TEST + 指定 PR HEAD CI + Find N2 实际场景 TRACE；未测保持 UNKNOWN |

执行要求：

- Core-0 可与当前 Native 多轮稳定性修复并行，但必须明确文件所有权；Core-1 直接承接当前多轮治理。
- Core-2 先建立召回与排序可观察接口，不先换向量模型、不先加 FTS5、不先上 Reranker。
- Core-3/4 可以做独立契约审计和负向测试，不允许绕过 Native 生命周期与授权门禁。
- 不要求 Core-0 到 Core-5 全部串行开发；可在不共享冲突文件的前提下并行，但集成顺序必须满足依赖。
- 小批量 PR；每批从当时 master 建独立分支，定向测试优先，之后按仓库适用的 Flutter、Android arm64/JVM、Fork license 和 Analyze 检查。
- SKIPPED 不计 PASS；旧 SHA 的 CI 不能替代最新 PR HEAD；Find N2 实机测试不能被 CI 替代。

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
