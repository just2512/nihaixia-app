# 用户 Markdown 书架与本地知识库架构约束

> **文件性质：已冻结的未来架构决策 / 后续实现约束。**
>
> **当前状态：DESIGN_FROZEN / NOT_IMPLEMENTED。** 本文冻结数据边界、来源治理、索引架构、资源调度、检索与验收规则；不代表书架功能已经实现，也不代表已有代码、CI 或 Find N2 真机验收通过。
>
> **优先级：未来可选扩展 / 当前非优先级。** 本文仅冻结用户 Markdown 书架作为一种 USER 知识源的未来约束。当前核心主线是先完成 docs/ai-layered-runtime-architecture.md 定义的五层职责解耦和现有多轮/证据边界；书架不得占用核心主线资源，不得要求核心层先为书架重构，也不得以书架的导入/Embedding 工程替代核心架构交付。
>
> **决策日期：2026-11-25。**
>
> 本文是书架范围内的专项约束，与 docs/ai-capability-audit.md、docs/ai-modernization-execution-ledger.md 配套使用。冲突时，产品定位和现有安全门禁优先；本文只约束未来用户书架及其接入方式，不授权扩大模型业务权限。

## 1. 目标与非目标

### 1.1 目标

允许用户导入自己拥有或有权使用的 Markdown 中医书籍、讲稿、医案整理和个人笔记，在设备本地完成：

1. 文件校验、Markdown 解析、文本规范化和质量报告；
2. 书籍、章节、片段及原文位置的结构化保存；
3. 关键词索引优先可用、向量索引异步补齐；
4. 按书架范围、指定书籍或系统知识源执行检索；
5. 把有限、可追溯的检索证据注入当前 E4B 轮次；
6. 从本地数据重新读取引用原文，不使用模型生成的引文作为原文展示；
7. 支持修改、增量重建、暂停续传、备份、删除和历史引用状态管理。

本能力是**本地数据处理、结构化索引和来源治理工程**。禁止把整本书直接放入 E4B Prompt，也不以微调或让生成模型“记住整本书”作为实现方式。

### 1.2 非目标

本阶段不建设：

- 云端书籍上传、云端 Embedding 或云端向量数据库；
- 通用 Agent、DAG、独立 RAG 平台或新的会话体系；
- 每本书一个 SQLite 数据库；
- 默认引入 ANN、外部向量数据库或重型 Reranker；
- 自动校勘古籍版本、作者身份、版权归属或医学真实性；
- 用户书籍触发工具调用、排盘、问诊、诊断、处方、剂量换算或其他业务执行；
- 以用户上传资料覆盖系统知识库或自动改变既有规则；
- 在当前多轮上下文治理尚未收口时，抢先实现完整书架 UI、后台索引和向量检索。

## 2. 顶层架构决策

### 2.1 两个物理数据库，统一检索契约

系统知识与用户书架物理隔离；两个数据源通过统一的检索接口供同一检索引擎使用。

> **现状说明：** system_knowledge.db 和 user_bookshelf.db 是本方案的目标存储文件名，不代表当前 master 已存在这两个数据库。当前系统知识资料和索引继续按现有资产/索引实现运行；将系统资料迁入 system_knowledge.db 属于后续独立迁移，必须保留现有黄金检索行为并通过对照验收，不能随本书架功能顺手迁移。

| 数据库 | 内容 | 访问属性 | 生命周期 |
|---|---|---|---|
| system_knowledge.db | SYSTEM 来源的古籍、讲稿、系统元数据及系统索引 | 运行时只读 | 随 App/知识包发布；版本化校验后原子切换 |
| user_bookshelf.db | 用户书籍、版本、章节、片段、向量、关键词索引、索引任务和用户偏好 | 读写 | App 升级不覆盖；支持独立备份、导出和删除 |

决策约束：

- 用户多本书共用 user_bookshelf.db 内的 books、book_versions、chapters、chunks、chunk_vectors、索引任务及关键词索引；按 bookId、source 范围过滤。
- 不为每本书创建独立数据库。跨书检索、书架筛选和整本删除通过 bookId 完成。
- user_bookshelf.db 仅保存用户书籍原文件/版本、章节/片段、索引、向量和索引任务等语料资产；不得迁入或取代现有 AI 会话、消息、问诊任务状态、Native transcript 或 TRACE 存储。现有会话/消息与 AI 数据清理边界保持不变。
- system_knowledge.db 与 user_bookshelf.db 不合并写入，也不将用户上传数据写入系统只读数据库。
- 统一的是 Dart 层的数据契约和检索/融合策略，不要求把两个数据库强行 ATTACH 成一个物理库。
- 系统知识库更新不得直接覆盖仍被打开的数据库文件。先写入临时文件，完成文件 SHA、schema/version 和 SQLite 完整性检查，再关闭旧连接并原子切换；失败时保留旧库。
- user_bookshelf.db 所有 SQLite 连接必须启用外键约束。普通表的 ON DELETE CASCADE 与 FTS/其他虚拟索引清理配合使用；虚拟表的删除必须有触发器或同一删除事务的显式步骤。
- 不把“SQLite 执行 DELETE”描述为磁盘介质级不可恢复擦除；WAL、空闲页、备份和文件级加密密钥销毁另按隐私策略处理。

### 2.2 统一检索输入/输出，来源数据不混库

系统源和用户源分别由 Repository 读取，经过同一检索编排器完成候选合并、去重、多样性控制和上下文预算。统一接口不得抹去来源身份、版本和信任状态。

建议的检索证据契约至少包含：

- sourceId、origin、materialKind、verificationStatus；
- bookId、bookVersionId、chunkId、chunkContentHash；
- title、author（未知时为空）、chapterPath、locator；
- originalText、canonicalTextVersion、startOffset、endOffset；
- retrievalMethod、queryId、rank/evidence metadata（可用时）；
- indexVersion、embeddingManifestId（向量索引可用时）。

当前系统源可逐步适配该契约，但必须保持现有黄金检索用例行为；接口适配不能顺手改变查询拆分、命中上限、排序、去重或来源展示。

## 3. 来源身份、资料类型与可信状态

### 3.1 三个独立维度

不得将“来源身份”“资料类型”和“真实性核验状态”合并成一个枚举。

| 维度 | 字段 | 允许值/示例 | 语义 |
|---|---|---|---|
| 来源身份 | origin | SYSTEM / USER | 由代码和存储归属决定，不由模型或文件内容决定 |
| 资料类型 | materialKind | CLASSIC_TEXT / LECTURE / BOOK / NOTE / CASE / OTHER | 内容分类；用户可提供建议值，但不得由其获得权威身份 |
| 核验状态 | verificationStatus | UNVERIFIED / METADATA_REVIEWED / TRANSCRIPTION_CHECKED / REFERENCE_CROSSCHECKED | 记录实际执行过的核验动作，不得按模型判断自动升级 |

约束：

- 系统资料可使用 SYSTEM_CLASSIC、SYSTEM_LECTURE 等展示类别，但必须由系统数据清单决定。
- 用户导入的文件一律 origin=USER，默认 verificationStatus=UNVERIFIED，展示为“用户提供 / 未核验”。
- 用户可将资料类型标记为 CLASSIC_TEXT（例如自认为是古籍），但其来源身份仍是 USER，界面不得显示成“系统核验经典原文”。
- 不因书名、文件夹名、Front Matter、用户填写作者或模型判断而自动升级核验状态。
- METADATA_REVIEWED 等状态必须对应可审计的人工/工具操作记录；不得将“文件成功解析”“chunkId 可回链”标为内容真实性核验。
- “引用可定位”只表示引用的 bookId/chunkId/version 可解析并能读取对应原文；不证明作者、版本、底本或文本内容真实。
- 若未来引入版权或来源权属核验，作为独立治理流程，不把技术导入成功等同于合法授权。

### 3.2 来源冲突

- 系统来源不因 origin=SYSTEM 就自动等同于所有版本、所有场景下的绝对正确答案。
- 系统已标明版本的原文与用户书籍出现剂量、药味、条文或释义差异时，默认分来源并列呈现，指出版本/整理口径可能不同。
- 不将不同版本的组成、剂量和原文静默融合成一个答案。
- 只有用户问题明确要求“按系统版本回答”或“按某本书回答”时，才按该范围优先选择来源；不得为了固定 SYSTEM 槽位牺牲明确的用户检索意图。
- 对混合检索设置来源多样性与单书命中上限，但具体 K 值和每书上限必须由黄金测试确定，不在架构阶段写死为 2、3 或其他数字。
- 同一原文出现在多本书时，可以减少送入模型的重复文本，但必须保留所有可用来源身份和定位，不能抹掉版本关系。

## 4. 用户书籍数据模型与身份稳定性

### 4.1 最小实体

用户数据库至少需要以下逻辑实体；物理 schema 和迁移版本在阶段 C 通过代码审计后再冻结：

| 实体 | 核心职责 | 关键字段 |
|---|---|---|
| books | 用户书架中的逻辑书籍 | bookId、title、author、origin、materialKind、verificationStatus、activeVersionId、createdAt |
| book_versions | 每次导入/修改的文件版本 | bookVersionId、bookId、rawFileHash、canonicalTextHash、parserVersion、normalizationVersion、importedAt |
| chapters | 章节层级与路径 | chapterId、bookVersionId、parentChapterId、heading、chapterPath、sequence |
| chunks | 可检索原文片段 | chunkId、bookId、bookVersionId、chapterId、chunkContentHash、embeddingInputHash、originalText、startOffset、endOffset、sequence |
| chunk_vectors | 片段向量及模型清单引用 | chunkId、embeddingManifestId、dimension、encoding、normalized、vectorBlob |
| book_index_jobs | 导入、关键词、向量、重建、删除任务 | jobId、bookId、bookVersionId、stage、status、cursor、processedCount、errorCode、updatedAt |
| keyword index | 中文关键词/字符索引 | source chunkId、token/gram、位置等；具体方案以黄金测试选择 |

实现可以增减物理表，但不得丢失上述职责和必要的引用关系。

### 4.2 三种身份不得混用

- chunkId：片段身份，用来在版本间延续引用关系。
- chunkContentHash：规范化原文内容哈希，用来判断原文是否变化。
- embeddingInputHash：实际 Embedding 输入（包含任务前缀、书名/章节上下文、预处理版本等）的哈希，用来判断向量是否需要重算。

不得直接以内容哈希作为唯一 chunkId。一本书或同一章节可能出现重复段落；前面插入内容也不应导致后续所有引用 ID 漂移。

稳定身份规则：

1. 新片段首次创建时分配持久化 chunkId。
2. 重新导入时，按 bookId、章节结构、内容哈希及前后邻接信息做差异匹配；重复段落按出现位置/上下文消歧。
3. 能匹配到原片段且内容未变时复用原 chunkId 和向量。
4. 仅偏移量变化时，只更新版本和定位信息，不重新生成向量。
5. 原文变化、章节语义上下文变化、Embedding 前缀/预处理版本变化或模型 manifest 变化时，按对应范围重算向量。
6. 新增片段分配新 ID；不存在的旧片段标记为旧版本失效或移除，不得把旧 ID 指向新文本。
7. 历史消息引用保存 bookId、bookVersionId、chunkId 和引用状态。书籍被修改或删除后，引用标记为 SOURCE_CHANGED / SOURCE_DELETED，不得静默指向当前版本中的另一段内容。

### 4.3 原文、换行与偏移

- 用户上传的原始文件保留为只读导入源，不因索引而覆盖或改写。
- 解析管线生成独立规范化文本副本：统一 CRLF/CR 为 LF；记录 normalizationVersion。
- rawFileHash 对原始字节计算；canonicalTextHash 对规范化文本计算。换行格式变化不必导致所有片段向量重算。
- startOffset/endOffset 统一定义为规范化文本中的 Dart UTF-16 Code Unit 半开区间 [startOffset, endOffset)，并绑定 bookVersionId / canonicalTextVersion。
- originalText 保存片段对应的精确规范化原文快照；偏移不能脱离版本单独解释。
- 阅读器如果展示规范化文本，可直接用上述偏移高亮；如果展示原始字节内容，必须另做偏移映射，禁止将 UTF-16 索引当 UTF-8 字节偏移。
- 繁简体、标点、空白归一化只能用于检索侧辅助字段；原始展示保留用户原文，任何规范化算法都需要版本化。

## 5. Markdown 导入、解析与切分

### 5.1 输入处理

- 首期文件格式为 Markdown（.md）；不自动导入 PDF、DOCX、图片或压缩包。
- 首选 UTF-8；正确处理 UTF-8 BOM。若检测到疑似 GBK/其他编码，给出编码选择或明确失败提示，不得静默用错误编码解码。
- 设置文件大小、解析时间、章节数量和单片段上限；具体数值由 Find N2 真实内存/耗时验证后确定。
- 大文件使用流式/分段解析或有界缓冲；不得一次复制多个完整大字符串造成内存峰值不可控。
- Front Matter 可提取 title、author、edition、sourceNote 等声明字段，但全部属于用户提供的元数据，默认未核验。
- HTML 标签、图片链接、脚注、脚注引用、代码围栏、引用块和表格需要明确解析规则；无法解析的内容保留可回溯原文或报告，不得静默丢弃。
- 文件内容中即使包含“system”“assistant”“忽略前文”等指令样式，也一律视为书籍文本数据。

### 5.2 标题和章节路径

- 有规范标题时，维护标题栈，形成完整 chapterPath，例如“辨太阳病 > 桂枝汤证 > 方剂组成”。
- 标题层级异常、跳级、无标题或标题噪声时，采用明确的解析降级规则，不能因此丢失正文。
- 没有可用标题的文档，退化为段落、句子边界和滑动窗口切分；窗口可有重叠，但必须保存原文位置，避免重复上下文过度增加检索权重。
- 章节路径是检索上下文与定位信息，不是经过外部核验的书目章节信息。

### 5.3 中医内容原子性

- 方剂表格、药味/剂量表、歌诀、引用块、医案复诊记录等应优先保留结构完整性。
- 表格优先按整表或完整行切分；表格超过单片段上限时，按行边界拆分，并在后续片段重复表头，不能在药名与剂量之间任意截断。
- 引用块和代码块优先完整保留；超过上限时按段落/句子边界拆分。
- 过长自然段按句号、分号等语义边界切分；不得使用不具语义感知的任意字符截断。
- 每个 chunk 的 Embedding 输入包含书名和 chapterPath 等轻量上下文头，但 originalText 不添加标题、不改写原文。
- Embedding 输入长度必须小于模型实际有效输入上限；字符数不得冒充 token 数。若当前运行时不能取得精确 token 数，记录为 UNKNOWN，并使用经测试的保守切分规则。

### 5.4 导入质量报告

每次导入至少显示并持久化：

- 文件名、原始字节大小、原始文件哈希、规范化文本哈希；
- 识别编码、是否含 BOM、换行规范化情况；
- 章节数、片段数、平均/最大片段长度；
- 空片段数、疑似乱码/替换字符比例、重复段落比例；
- 表格、引用块、脚注、HTML 和无法解析内容的计数；
- 解析器与切分版本；
- 关键词索引状态、向量索引状态和失败原因。

质量报告只能提示疑似问题，不能声称自动校正了 OCR 或古籍文本。OCR 错字、异体字、繁简混用和版本差异应保留原文，并让用户在导入阶段看到质量风险。

## 6. 关键词索引与向量索引

### 6.1 两阶段可用

- 阶段 C：文件解析完成后，先建立关键词索引；关键词索引可用即允许书籍参与基本检索。
- 阶段 D：Embedding 向量索引通过后台任务补齐。索引未全部完成时，只对已有向量的片段做语义召回，同时保留关键词召回。
- UI 明确显示 PARSED / KEYWORD_READY / VECTOR_BUILDING / READY / PARTIAL / FAILED / REBUILD_REQUIRED 等状态和可核验进度。
- 向量模型未安装、初始化失败或设备资源不允许时，关键词检索仍可用；不得把部分向量索引展示为完整索引。

### 6.2 中文关键词策略

- 不假定 SQLite FTS5 默认 tokenizer 对中文方名、药名、条文编号和古汉语分词足够准确。
- 对字 n-gram、自定义词典/分词、现有内存索引及 FTS5 做小规模对照；针对方名、药名、异名、条文编号、繁简体和连续原文建立黄金查询集。
- 只有实测表明当前方案存在可复现缺陷，且对照实验有收益时，才选择 FTS5 或新增分词依赖。
- 系统资料已有别名词典可以复用，但不得假设它覆盖用户任意书籍中的所有称谓。用户书籍召回要保留原始查询和规范化查询，显示实际命中的词项。
- 繁简归一化只用于检索候选；引用和原文展示始终使用原始文本。

### 6.3 EmbeddingGemma 2 候选方案

当前首选 PoC 为 Google EmbeddingGemma 2 的 text/code 270M 配置，而不是加载 740M 多模态完整模型。模型名、权重 revision、文件 SHA 和实际 LiteRT-LM 模型包必须在 PoC 时锁定。

已核对的候选事实和实现边界：

- EmbeddingGemma 2 提供 270M text/code 配置，原始向量空间为 768 维，文本输入上下文为 8192 tokens，并支持 MRL 维度截断。
- 候选维度为 768 / 512 / 256 / 128；查询和文档必须采用相同维度。先用中医书籍黄金集对 256 与 512（必要时加入 768）做召回对照，不在设计阶段拍板最终维度。
- MRL 截断后必须重新做 L2 normalization；manifest 必须记录输出维度、归一化方式和量化编码。
- 文档向量和查询向量使用模型官方对应的不同 retrieval task prefix。当前 LiteRT-LM Embedding Models API 中，实施时应逐字核对 document/query 模板；禁止沿用旧版 EmbeddingGemma v1 的提示格式。当前候选格式为 document: “task: search result | text: ...”，query: “task: search query | text: ...”。
- 文档 Embedding 输入在正文前加入书名、章节路径等上下文头；上下文头版本纳入 embeddingInputHash。
- LiteRT-LM 官方 Embedding Models API 已提供 Kotlin `EmbeddingEngine` / `computeEmbedding` 示例，并明确文档索引前缀 `task: search result | text:`、查询前缀 `task: search query | text:`；实际实施时仍须逐字核对所锁定 SDK/API 的模板，不能仅凭文档说明推定项目调用链已兼容。
- LiteRT-LM v0.18.0 的官方发布说明已包含 EmbeddingGemma 2（文本、视觉、音频 Embedding）支持；v0.18.1 发布说明另注明修复“从源码构建 LiteRT-LM”时运行 EmbeddingGemma 2 的 ABI 不兼容。当前 master 的 Android Gradle 依赖实际锁定为 `com.google.ai.edge.litertlm:litertlm-android:0.18.0`（PoC 执行时重新核验）。源码构建修复不能直接推定为该 Maven AAR 的缺陷，也不能反向证明该 AAR 在 Find N2 可用。
- 因此 C 阶段必须针对项目实际 Maven AAR、目标模型包、Android arm64、CPU/GPU backend 和 Native Gate/串行资源协调做独立 PoC；不得只凭上游 release/API 文档宣布兼容，不得为本功能未经兼容与回归测试直接升级 LiteRT-LM。若拟升级，先提交版本变更说明、兼容性/风险/回滚方案。
- 不下载、不提交或自动替换模型权重，直到模型许可、文件来源、哈希、安装/升级路径和设备占用完成核验。

官方参考：
- EmbeddingGemma 2 概览与参数：https://ai.google.dev/gemma/docs/embeddinggemma
- Google Developer Guide（2026-10-06）：https://developers.googleblog.com/en/embeddinggemma-2-the-developer-guide/
- LiteRT-LM Embedding Models API：https://ai.google.dev/edge/litert-lm/embedding_models
- LiteRT-LM v0.18.0 release：https://github.com/google-ai-edge/LiteRT-LM/releases/tag/v0.18.0
- LiteRT-LM releases（含 v0.18.1 源码构建 ABI 修复说明）：https://github.com/google-ai-edge/LiteRT-LM/releases

### 6.4 向量存储和检索规模

- 初期向量存储使用 user_bookshelf.db 内的 SQLite BLOB/受控编码表，不引入独立向量数据库。
- 多本用户书籍共用 chunk_vectors，按 bookId、bookVersionId、embeddingManifestId 过滤。
- 先实现可验证的精确相似度扫描基线；不得仅凭“20 本书约 4 万片段、256/768 维”推断所有 Find N2 场景都无需 ANN。
- 在 1k、10k、约 40k chunks 等代表性规模测试索引体积、查询延迟、CPU、内存峰值和温升；只有精确扫描不能满足明确延迟/规模门槛并有设备数据时，才评估 ANN。
- 不使用来源分数/任意排名分值替代证据；检索排序须由黄金查询集验证。

### 6.5 索引 manifest

每个向量索引必须关联不可歧义的 manifest，至少包括：

- embeddingModelId、modelRevision、modelFileSha256；
- LiteRT-LM runtime version、backend、相关模型配置；
- embeddingInputTemplateVersion、queryTemplateVersion、preprocessingVersion；
- chunkingVersion、normalizationVersion、corpus/schema version；
- dimension、MRL truncate dimension、normalization method；
- quantization/encoding、向量序列化格式和 manifest/indexVersion。

任一影响向量空间或输入文本的字段变化，都必须标记 REBUILD_REQUIRED，不能把旧向量与新模型/新模板的查询向量混用。纯 UI 或定位字段变更不应无故触发全量 Embedding。

## 7. 后台索引任务与模型资源协调

### 7.1 可暂停、可续传、可恢复

- 索引任务及每个 chunk 的处理状态以 SQLite 持久化；内存队列只负责当前批次执行，不是唯一进度来源。
- 以小批次处理并在事务中提交结果和游标。批次大小由 Find N2 实测确定，不将“每批 10～20 个”写成固定性能事实。
- 进程被杀或 App 崩溃后，只从最后成功提交的 chunk 继续；已经成功的 embedding 不重复生成。
- 单 chunk 失败可重试并记录原因；达到重试策略后标记 PARTIAL/FAILED，不能阻断整本书的关键词检索。
- 任务必须支持 PAUSE、RESUME、CANCEL、RETRY 和 REBUILD_REQUIRED，并能解释暂停/失败原因。
- 不承诺 Android 在 App 被系统终止后仍持续计算；默认允许任务在 App 运行期间推进，进程结束后下次启动续传。是否采用 WorkManager/前台服务等平台能力，另按产品体验、电量、权限和实测决定，不在首期预先引入。

### 7.2 E4B 优先与共享资源门禁

- Embedding Engine 可与 E4B Engine/Conversation 使用独立模型实例和生命周期，但不能拥有绕开现有模型访问门禁、Native 串行队列或资源协调的独立通道。
- **唯一授权门禁：** 只要 Embedding 模型在 Native 侧使用 LiteRT / LiteRT-LM 加载或推理，就必须与 E4B 一样受 v1.3 唯一 `ai_access` 授权权益及同一个 Native AiModelAccessGate 控制；不得为书架、Embedding 或其他业务场景新增独立收费权益、旁路或第二套授权判定。资源调度队列负责串行与让出，不替代授权 Gate。
- `HeadlessToolDispatcher` 与 `ContextResolutionGateway` 继续只承担各自的确定性执行安全、引用/来源校验职责，不承担书架或 Embedding 的独立收费门禁。
- App 永久授权 Token 的 `ai_access` 权益不代表 Fork 源代码商业许可，也不扩大第三方模型/书籍内容的授权范围。
- 同一时刻不得并发执行 E4B 推理与 Embedding 向量构建。新建索引任务进入统一 Native 资源协调队列。
- 用户进入 AI 对话并发起推理时，Embedding 任务暂停或在当前安全批次结束后让出资源；E4B 结束后按任务状态恢复。
- Embedding 模型不应长期与 E4B 同时常驻而未经内存实测；需要时按批次加载、释放或延迟初始化。
- 充电状态、电量、系统温度/热状态和用户的“仅充电时索引”等偏好可以影响任务调度；默认策略与阈值须经设备实测和用户可见设置确定。
- 暂停/恢复不得重放未确认完成的 E4B 请求；不得改变现有“执行状态 UNKNOWN 不自动重放”的语义。

## 8. 检索编排、来源冲突和上下文预算

### 8.1 检索范围由用户意图决定

至少支持：

- SYSTEM_ONLY；
- USER_BOOKSHELF；
- SELECTED_BOOKS；
- SYSTEM_AND_USER；
- 指定 bookId 的限定检索。

指定一本书时不得为了 SYSTEM 预留槽位挤掉用户明确指定的资料。混合检索使用来源多样性、单书候选上限、重复段落处理和相关性排序；具体规则必须由黄金测试证明，不预设固定配额。

### 8.2 混合召回

- 关键词检索与向量检索各自返回候选及来源定位。
- 在黄金测试证明有收益后，采用 RRF 或等价的可解释融合方法；保留原始 query、派生 query、检索来源、候选 ID、排序变化和被裁剪原因。
- Query Rewrite 先使用已有实体/别名/确定性映射；模型改写仅在明确歧义场景评估，原始 query 必须保留并参与检索。
- 不根据命中数量直接增加候选，不将相似度或 RRF 数值解释为医学正确性或来源可信等级。
- Reranker 仅在黄金集中存在可复现错排且对照实验显示净收益时再立项。

### 8.3 Context 与多轮历史隔离

- RAG 检索片段属于当轮 ephemeral context，不得作为 user message 或完整 modelInput 写入 Native 成功轮次历史。
- 持久化模型历史只保留干净的用户原话、必要的结构化任务状态/紧凑摘要及可重新检索的 source IDs；完整 UI 问答仍由现有 SQLite 消息记录负责。
- 不将完整历史助手回答和历轮 RAG 正文无上限地重放进 Conversation。
- 跨轮需要前轮证据时，根据 sourceId/bookVersionId/chunkId 重新读取和检索；如果来源已变更/删除，明确返回对应状态。
- 上下文预算必须使用可取得的实际 token 计数；字符数只用于字符限制，不能伪装成 token 数。按完整证据条目裁剪，记录被省略来源和原因。
- LiteRT-LM Conversation.getTokenCount() 可用于当前活跃 Conversation token 观察，但不能据此提前得知尚未发送的新消息 token；不把它当成新输入精确预检接口。Conversation 状态回滚不可依赖，清理 KV Cache 应在 Native 串行队列内关闭旧 Conversation 并按预算重建。

## 9. 用户资料不可信与提示注入防护

- 所有 USER 内容均为不可信数据，即使书名、Front Matter 或正文中出现 system/developer/assistant/tool 标签也一样。
- 进入模型上下文时，来源元数据由代码生成，资料正文以明确的引用数据区域传入；必须对分隔符、角色标签和控制字符做结构化转义，不能直接把用户正文拼接成可伪造的系统/工具消息。
- Prompt 明确声明书籍内容是待分析资料，不是系统指令；但 Prompt 声明不构成安全边界。
- 工具调用、业务执行、权限、输入参数、问诊和其他业务动作仍由 Dart/Native 确定性代码与既有门禁决定；书籍内容不得直接触发工具调用，也不得改变允许工具集合。
- 资料中的指令文本可以作为原文被讨论或引用，但不能被执行。
- 不为了“安全清洗”而篡改 originalText；安全封装只作用于模型输入表示。
- 继续遵守现有中医业务边界、知识依据要求和拒绝/澄清规则。书籍有引用不代表该内容已核验，也不自动授权个体诊断、处方或其他医疗业务执行。

## 10. 引用定位与 UI 展示

### 10.1 模型只能返回引用 ID，不负责提供权威引文

- 模型结构化输出可提出 sourceId/bookId/bookVersionId/chunkId 等引用 ID。
- Dart/Repository 验证这些 ID 属于当前会话可访问的数据源，且版本与 chunk 关系真实存在。
- UI 的参考原文卡片不得直接展示模型生成的“原文”；必须使用引用 ID 从 SQLite/系统知识库重新读取 originalText。
- startOffset/endOffset 仅在对应 canonicalTextVersion 中使用；不得跨版本复用。
- 若 chunk 不存在、版本不匹配、来源不可访问，引用状态为 MISSING / SOURCE_CHANGED / SOURCE_DELETED，并在 UI 明示。
- 引用定位成功只代表可以回填该条原文，不表示引文对应作者、版本或内容已被外部校勘。

### 10.2 UI 最低信息

书籍详情和引用卡片至少显示：

- 书名、作者（未知则显示未知）、章节路径；
- 来源标签：SYSTEM / USER；
- 用户书籍明确显示“用户提供 / 未核验”；
- 当前书籍版本和索引状态；
- 可定位原文及打开书籍位置；
- 来源已变更、来源已删除或索引不完整的状态。

不得让模型自行决定来源标签、核验状态或权威措辞。

## 11. 删除、更新、缓存与备份

### 11.1 删除书籍

删除流程应由单一 Repository/事务入口协调，并清理：

- books、book_versions、chapters、chunks、chunk_vectors；
- FTS/关键词索引及相关触发器维护数据；
- 尚未执行的索引任务、批次游标和临时文件；
- 检索缓存、内存缓存和待展示结果缓存；
- 关联的临时 embedding 输入/输出文件。

外键 ON DELETE CASCADE 是基础保护，不替代 FTS 虚拟表、文件和内存缓存清理。清理中途失败必须可重试，书籍不能假显示为已删除而仍参与检索。

### 11.2 历史引用

- 历史消息保留引用身份和删除/变更 tombstone，不保留可继续检索的已删除书籍正文。
- 来源删除后历史 UI 显示“来源已删除”，不静默展示新书中的相同 chunkId 或相同内容。
- 若以后支持用户显式保留历史版本，必须单独设计并告知占用；首期不默认保留已删除正文副本。

### 11.3 备份和恢复

- user_bookshelf.db 与用户原始 Markdown 文件作为同一逻辑书架数据集备份/导出，记录 manifest 和文件哈希。
- 恢复后检查书籍文件、数据库版本、chunk/vector manifest 和文件哈希；向量缺失或模型不兼容时标记 REBUILD_REQUIRED，关键词索引可先恢复。
- App 升级不得覆盖或清空用户数据库和原始 Markdown 文件。
- 备份不上传任何用户书籍到项目服务器；若用户主动导出，由用户决定存放位置。

## 12. 性能、内存与 Find N2 验收

所有性能指标必须由真实设备和真实模型实测。以下是必须测量的项目，不是预设通过值：

- 导入不同字数/文件大小的规范标题书和无标题书；
- 解析吞吐、首个关键词可用时间、每片段 Embedding 耗时分布、全书完成耗时；
- 1k、10k、约 40k chunks 的关键词/向量查询延迟；
- 索引数据库体积、向量体积、导入期间峰值内存、E4B 共存/切换内存；
- CPU 占用、电量变化、设备温度、热降频和 AI 首 token 延迟；
- E4B 对话开始/结束时索引队列暂停与恢复；
- 进程终止、强制停止、重启后的索引续传；
- 运行中取消、单 chunk 失败、Embedding 模型不可用、SQLite 写入失败及磁盘空间不足。

验收必须在项目目标设备 OPPO Find N2（PGU110，Android 16）执行。不得用其他 Pixel/模拟器或公开 benchmark 推断 Find N2 通过。

不得在设计阶段写死“一本 30 万字医书只需 15～30 秒”“20 本书必然只需 30 MB”或“暴力扫描一定足够”等结论。容量可按公式估算，但延迟、内存、温升和交互体验必须用设备 TRACE 证明。

## 13. 分阶段执行顺序与放行门槛

本节 A～E 仅是书架功能内部的未来阶段，不是当前 AI 核心架构路线。核心五层职责和其当前实施顺序以 docs/ai-layered-runtime-architecture.md 为准。

| 书架阶段 | 工作范围 | 前置条件 | 放行条件 |
|---|---|---|---|
| A（延后） | 将核心五层的统一 CandidateEvidence / RankedEvidenceSet / 引用状态契约适配到书架数据源 | Core-0 契约和 Core-1 会话/证据隔离完成；用户明确启动书架项目 | 不改变现有检索语义；独立接口审查通过 |
| B | Markdown 导入、解析、质量报告、章节/片段模型、关键词索引、书架 CRUD | A 完成；有独立工作分支与文件所有权 | 有标题/无标题书均可解析；关键词检索可用；原文定位、质量报告、失败状态通过测试 |
| C | EmbeddingGemma 2 Android PoC、manifest、向量索引、后台任务/续传和资源协调 | B 完成；必须先完成模型 API / 文件 / LiteRT 兼容核验 | Find N2 证明可运行；Golden 检索较关键词阶段有可复现收益；性能/内存/温升满足实测门槛 |
| D | 关键词+向量混合检索、来源多样性、冲突并列、引用回填 | C 完成；系统黄金行为不得退化 | 原始与派生 query、候选排序、来源、原文回填和冲突场景均通过 |
| E | 增量更新、稳定 ID、删除清理、缓存失效、进程恢复、备份恢复 | B、C 完成；可按文件所有权分小批量 | 章节局部修改只重算受影响向量；删除后无可检索残留；历史引用状态准确；中断可续传 |
| 可选 | Reranker / ANN | 只有 D 阶段出现可复现错排/性能瓶颈时评估 | 有对照数据和 Find N2 证据证明净收益后单独决策 |

### 13.1 当前获准范围

- 本文只批准将书架作为未来可选 USER 知识源的设计约束，不代表启动书架实现。
- **当前书架优先级为 DEFERRED / NOT_AUTHORIZED。** 不并行启动书架 DTO、Repository、Schema、导入、索引或 Embedding 实现；先完成核心五层架构的 Core-0～Core-2 及当前多轮治理。
- 不因本文存在而增加书架页面、SQLite schema、模型权重、Embedding 依赖、FTS5、向量数据库、后台服务，或修改现有系统知识检索排序。
- 只有核心层契约、Memory/RAG 隔离、Recall/Ranking 边界及黄金行为稳定后，用户明确恢复书架事项，才从当时 master 新建书架独立分支。
- EmbeddingGemma 2 仍只是未来 PoC 候选；不是当前主线，也不能预先锁定生产模型或维度。
- 当前 Native 多轮治理属于核心会话记忆层，不属于书架项目的阶段 A；继续按 AI 总体台账推进。

### 13.2 主线和分支集成纪律

1. 每个实现切片开始前核验 master 当前 HEAD、相关文档和打开的 PR。
2. 每个独立工作流从当时 master 基线创建自己的工作分支；不得从过时功能分支堆叠整串历史提交。
3. 使用明确文件所有权拆分并行工作，避免多个分支同时改动同一 Native 生命周期、知识检索或数据库文件。
4. 每个 PR 只包含一个可验收的薄切片；先跑定向测试，再跑 Flutter regression、Android arm64/JVM 和适用的 Fork/许可边界检查。
5. CI 必须针对 PR 精确 HEAD；SKIPPED 不计 PASS，旧 commit 的 CI 不替代新 HEAD。
6. 小批量集成前核对 diff、测试、CI、文档台账和回滚路径；通过后再合并到 master。
7. 不删除失败测试、不降低验收标准、不把 UNKNOWN/PARTIAL 改成 PASS、不以代码存在替代设备 TRACE。
8. 历史分支不整体批量合并；只挑选已审计、可独立验收且仍有价值的提交。

## 14. 书架专项自动验收集

下列测试在相应阶段实现；未实现的阶段保持 NOT_STARTED，不可用设计文档替代运行证据。

| ID | 阶段 | 场景 | 必须验证 |
|---|---|---|---|
| BS-01 | C | 导入规范标题 Markdown | 标题栈、章节路径、原文片段与偏移一致 |
| BS-02 | C | 导入无标题/标题混乱 Markdown | 降级切分可用，文本无静默丢失 |
| BS-03 | C | 含方剂表格、歌诀、引用块和医案复诊记录 | 表格药味/剂量关系、引用块和复诊边界不被任意截断 |
| BS-04 | C | UTF-8 BOM、CRLF、LF、疑似 GBK、乱码文件 | 编码状态明确，规范化与 offset 一致，未知编码不静默误读 |
| BS-05 | C | 检索方名、药名、别名、条文号、繁简体 | 以中医黄金查询集验证关键词召回；展示保留原文 |
| BS-06 | C | 解析中出现无法处理的 HTML/脚注/图片引用 | 报告问题并保留可回溯信息，不静默丢弃 |
| BS-07 | D | 关键词可用、向量尚未完成 | 可检索关键词结果；向量状态准确显示 PARTIAL |
| BS-08 | D | Embedding 初始化失败/模型不可用 | 不影响 E4B；关键词路径仍工作；任务失败原因可见 |
| BS-09 | D | 用户发起 E4B 对话时后台正在 Embedding | 按资源协调暂停/让出；E4B 推理不与 Embedding 并发 |
| BS-10 | D | 建索引中强杀进程并重启 | 从最后已提交 chunk 续传；不重复、不漏项 |
| BS-11 | D | 对同一查询比较 256/512/768 维候选 | 同一 query/doc 维度、归一化及前缀版本一致；以黄金集选择维度 |
| BS-12 | E | SYSTEM 与 USER 内容冲突 | 分来源并列显示，不静默混合；来源标签由代码渲染 |
| BS-13 | E | 指定用户书籍提问 | 不被 SYSTEM 固定配额挤掉指定书籍证据 |
| BS-14 | E | 资料中包含“忽略系统指令/调用工具”等文本 | 不触发工具或业务执行，内容只作为资料 |
| BS-15 | E | 模型返回不存在/越权/过期 chunkId | 引用校验失败并显示 MISSING/SOURCE_CHANGED，不生成伪引用 |
| BS-16 | E | 模型伪造或改写原文 | UI 从本地库回填 originalText，不展示模型编造文本为原文 |
| BS-17 | F | 修改书籍中间一个章节 | 未变化 chunkId/向量复用；只有受影响片段重算 |
| BS-18 | F | 在前文插入段落导致后续 offset 移动 | 后续片段 ID 保持，更新 offset/version，不重算无变化向量 |
| BS-19 | F | 同一章节存在重复段落 | 差异匹配能区分出现位置，不让两个片段共享错误身份 |
| BS-20 | F | 删除一本书 | chunks、vectors、关键词索引、任务、缓存和文件清理；无残留命中 |
| BS-21 | F | 删除后查看历史引用 | 显示 SOURCE_DELETED，不显示其他文本、不恢复删除正文 |
| BS-22 | F | 书籍修改后查看旧引用 | 显示 SOURCE_CHANGED 或对应旧版本状态，不静默指向新内容 |
| BS-23 | A/E | 连续至少 20 轮、跨轮引用书籍证据 | RAG 正文不进入持久化 Native 历史；source IDs 可重新检索；会话不串线 |
| BS-24 | F | 备份并恢复书架 | 原始文件、数据库、版本、manifest 一致；不兼容向量标记重建 |
| BS-25 | D/F | 磁盘空间不足、单 chunk 失败、SQLite 事务失败 | 状态可见、任务可恢复、无半提交向量或伪完成状态 |

### 14.1 证据等级

- CODE 证明实现路径；
- TEST 证明自动化条件下的行为；
- CI 证明指定 commit 的自动化运行；
- TRACE 证明 Find N2 指定设备、Android 版本、App SHA、模型 revision/backend 和真实场景。
- IMPLEMENTED 必须按现有 docs/ai-capability-audit.md 的证据定义判定；设计文件、页面入口、索引状态标签或 CI 单独通过都不足以证明设备能力完成。
- Find N2 未执行的项目保持 UNKNOWN / LOCAL ONLY；本地验收交接必须记录设备、App SHA、模型哈希、backend、trace_id 和结果。

## 15. 变更控制

以下任何变更都必须单独记录理由、证据、迁移路径、回滚和测试，不得通过实现细节悄悄改变本规范：

- 合并系统与用户数据库、改变来源身份/可信状态；
- 将用户资料提升为系统经典或自动标记已核验；
- 改变 chunkId 稳定性或 offset 语义；
- 更换 Embedding 模型、revision、前缀、维度、量化或 chunking 规则；
- 引入 FTS5、自定义分词依赖、ANN、向量数据库或 Reranker；
- 允许 E4B 与 Embedding 并发；
- 改变跨轮历史持久化范围或把 RAG 正文写回 Native 历史；
- 改变用户书籍删除、备份和历史引用语义；
- 以系统固定配额覆盖用户指定的检索范围；
- 将“引用可定位”改写为“内容真实/版本已核验”。

任何阶段如需修改既有黄金检索行为，必须保留旧基线、补充对照结果和解释有意行为变化；不得只因新检索算法的命中数量更多就替换旧实现。

---

**最终约束：** 用户 Markdown 书架只是未来可选的 USER 知识源，优先级低于核心五层职责解耦。核心知识召回、证据排序、会话记忆、E4B 语言推理和确定性业务执行统一遵守 docs/ai-layered-runtime-architecture.md；书架只有在核心契约和现有 RAG/Memory 边界稳定、用户明确恢复该项目后，才按本文件 B→C→D→E 分批实现。
