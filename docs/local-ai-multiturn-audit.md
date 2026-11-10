# 本地 AI 多轮稳定性专项审计

- 审计类型：只读静态代码审计
- 审计基线：`master` @ `60011c4d237cd8d80659038beb6a3a7257228e01`
- 审计范围：Native Engine/Conversation 生命周期、GPU/CPU fallback、Dart 调用与历史恢复、测试覆盖
- 设备实测：未执行；所有硬件/模型运行时根因保持 `UNKNOWN`
- 注意：本报告记录源码可证事实，不等同于修复完成或真机验收。

## 1. 状态模型与状态迁移

### 1.1 当前状态字段

`MainActivity.kt` 当前核心状态为：

- `aiEngine: Engine?`（第 37 行）
- `aiConversation: Conversation?`（第 38 行）
- `activeBackend`（第 38 行）
- `conversationHasSuccessfulTurn`（第 39 行）

`modelStatus()` 的 `ready` 仅由 Engine 和 Conversation 均非 null 推导（第 319-323 行）。它没有独立表达：
- Engine 是否初始化完成、是否已进入关闭流程；
- Conversation 是否可用、是否正在执行推理；
- 历史是否已经完整回放；
- 当前请求是否已执行但响应丢失。

因此 `ready=true` 只能表示两个引用非 null，不能证明 Conversation 内部状态健康，也不能证明历史与 SQLite/UI 一致。

### 1.2 主要迁移

```text
NOT_LOADED
  └─ loadLocalModel
       ├─ GPU Engine.initialize 成功 -> GPU_ENGINE_READY
       ├─ GPU 初始化失败 -> CPU Engine.initialize
       │    ├─ 成功 -> CPU_ENGINE_READY
       │    └─ 失败 -> NOT_LOADED + error
       └─ createConversation
            ├─ 成功 -> READY
            └─ 失败 -> releaseLocalModel -> NOT_LOADED

READY
  ├─ send 成功 -> READY + successfulTurn=true
  ├─ 首轮已知 OpenCL 缺失 -> detach old refs -> close old Conversation/Engine
  │    -> CPU initialize -> create Conversation -> CPU_READY
  ├─ 其他推理异常（包括注释所称多轮 state:7）
  │    -> detach old refs -> CPU initialize -> create Conversation
  │    -> CPU 重试本轮（不回放历史）
  └─ 空回复 -> 尝试 CPU 重建；失败则尝试原 Engine 重建
       -> 再次发送本轮；最终空串交给 Dart 检查

任意运行态
  ├─ reset -> 清空 Conversation 引用 -> 关闭/重建 Conversation
  ├─ release -> 先清空引用，再按 Conversation -> Engine 顺序释放
  └─ Activity.onDestroy -> 向单线程 Executor 排入 release，再 shutdown Executor
```

### 1.3 null / 半初始化 / 失效引用点

| 位置 | 可证行为 | 风险/结论 |
|---|---|---|
| `loadLocalModel` 约 335-397 | Engine initialize 成功后先赋给 `aiEngine`，再创建 Conversation；创建失败调用 release | 创建过程存在短暂 Engine 非 null、Conversation 为 null 的半初始化态；Executor 串行化降低并发观察风险 |
| `recreateCpuEngineAfterFirstTurnOpenClFailure` 493-569 | 先将两个引用置 null，再关闭旧对象，之后新建 CPU Engine/Conversation | 释放失败或初始化失败后会处于 not_loaded；旧 GPU runtime 已不可复用 |
| `recreateConversationOnly` 479-490 | 关闭旧 Conversation 后在原 Engine 创建新对象 | 创建失败时字段仍为 null；上层是否回退取决于调用路径 |
| `resetLocalConversation` 724-752 | 先置空 Conversation；策略失败时同时清空 Engine/Conversation 并标记 not_loaded | 不保留只有 Engine 的“ready”状态 |
| `releaseLocalModel` 758-775 | 先置空引用，再按 Conversation/Engine 顺序关闭 | 资源引用清理顺序明确 |

## 2. 重试与恢复路径

### 2.1 首轮 OpenCL fallback

- 触发：backend 为 GPU、`conversationHasSuccessfulTurn=false`，且异常 cause 链含已知文本 `Can not find OpenCL library on this device`。
- 策略定义：`FirstTurnGpuFallbackPolicy.kt`。
- 调用位置：`MainActivity.kt` 428-455。
- 资源顺序：先清空旧引用，再关闭 Conversation，最后关闭 Engine；关闭失败时不启动 CPU 重试（493-529）。
- CPU 成功后创建新 Conversation，只带 systemInstruction（551-569）。
- 历史：没有把之前 transcript 回放到新 Conversation；首轮策略限定 successfulTurn=false，按策略应没有成功轮次，但“请求曾执行但响应丢失”的状态未被独立建模。

### 2.2 多轮异常 fallback（包括注释提及的 state:7）

- 触发：`sendWithFirstTurnGpuFallback` 中首轮专用 fallback 不命中后，进入通用异常恢复分支（456-477）。
- 当前代码会尝试重建 CPU Engine 和 Conversation。
- CPU Conversation 仅包含 systemInstruction（551-569），没有历史 transcript。
- 随后只重试本轮 `modelInput`（466-470），因此模型上下文与 Flutter/SQLite 历史可能分叉。
- 若 CPU 重建失败，会尝试同 Engine 重建 Conversation（459-464）；若重建也失败则抛出原始异常。
- CPU 重试再次失败时，代码抛出原始 `error`，没有把 `retryError` 作为 suppressed exception（472-475）；二次失败原因可能丢失。

**结论：** 多轮推理异常后的自动恢复路径存在确定的历史丢失风险。这是源码可证的恢复契约缺口，不等于已证实 state:7 的根因。

### 2.3 空回复重试

- `sendLocalMessage` 首次返回空白时，先尝试 CPU Engine 重建（415-417）。
- 若 CPU 重建失败，则尝试同 Engine 重建 Conversation。
- 再发送相同的本轮 `modelInput`（419-421）。
- 若第二次仍为空，Native 仍将空字符串放在 `reply` 字段返回；Dart `sendMessage` / `sendMessageWithContext` 会在回复非 String 或空白时抛出 `EMPTY_REPLY`（`local_ai_service.dart` 约 42-80 行）。

**风险：** 若第一次模型调用实际已执行，只是回复为空/响应不可读，重试可能形成重复推理；当前没有请求 ID 或执行状态去区分“未执行”“执行结果未知”“已成功但响应丢失”。

### 2.4 手动历史恢复

- Dart `restoreConversation` 调用 Native `restoreConversation`，校验 `restored == true`（`local_ai_service.dart` 141-159 行）。
- Native 重建 Conversation 后把 transcript 拼成一条恢复 prompt，最多 10000 字符，再发送一次（`MainActivity.kt` 701-722）。
- 这条路径是显式恢复入口，不会自动参与 CPU fallback 或空回复恢复。
- 历史恢复本身以“模型确认已载入”为标记；没有独立核验模型内部是否完整保留了被截断前的全部 transcript。

## 3. state:7 与“模型没有返回有效文本”

- Native 源码注释在 `MainActivity.kt` 457-458 行将 state:7 描述为多轮 GPU 不稳定的可能表现，并将其归入通用异常恢复。
- Native 不解析/分类 LiteRT-LM state:7 的结构化错误码；仅捕获 Exception 并执行 fallback。
- Dart `EMPTY_REPLY` 是对 Native 返回的空白 reply 的二次校验，不是 state:7 本身。
- state:7 的底层来源、LiteRT-LM 0.18.0 对应状态定义、GPU driver/OpenCL/资源耗尽等具体根因：`UNKNOWN`。
- 没有 Find N2 设备日志、native stack trace、模型 runtime trace，不得将其归因于某个具体 GPU/驱动问题。

## 4. 并发、重入、取消与 Activity 生命周期

### 4.1 已有串行化

- Native 使用单线程 `aiExecutor`（`MainActivity.kt` 第 25 行）。
- 所有模型加载、推理、重置、释放都通过 `runAiTask` 投递到该 Executor（第 83-124、130-165 行）。
- Flutter 页面在发送入口检查 `_sending`、录音和附件状态（`local_ai_interview_screen.dart` 约 2110 行起），正常 UI 路径会阻止第二次点击发送。

这降低了同一个 Activity 内多个 Native 任务并发操作 Engine/Conversation 的风险，但不等于 Native 具备请求幂等或可取消能力。

### 4.2 取消/超时

- MethodChannel 暴露的方法中未发现 cancel 请求。
- Dart 的模型请求没有业务级取消 token 或请求 ID。
- Dart Future 超时/页面离开不等于 Native 推理停止；Native 任务继续占用单线程 Executor 的行为没有被取消。
- Activity 销毁时将释放任务排入 Executor 后调用 shutdown（第 815-825 行）；shutdown 不会中断已经运行的任务，也没有 awaitTermination/完成屏障。
- Activity teardown 时正在执行的推理、待返回的 MethodChannel.Result 与释放任务的最终交互：没有设备生命周期测试，标记 `UNKNOWN`。

### 4.3 并发/重入判断

- 同一 Activity 的 Native 任务通过单线程 Executor 排队，属于串行执行。
- UI `_sending` 只约束页面发送按钮，不是跨页面、跨 Activity、Native 通道层的幂等锁。
- Native 缺少显式 in-flight request state；如果 Dart 侧出现重复调用，Native 会排队而不是拒绝重复请求。

## 5. SQLite transcript、Flutter UI 与 Native 上下文一致性

- SQLite `assistant_messages` 负责持久化会话消息（`database_helper.dart` 中 `saveAssistantMessage` 使用事务写入消息并更新会话预览）。
- Native `sendLocalMessage` 只接收当前 `text` 与当前轮 `context`，拼装后发送（`MainActivity.kt` 398-426）；没有在每轮请求中读取 SQLite transcript。
- 正常连续对话依赖同一个 LiteRT-LM Conversation 内部状态。
- UI 切换历史时会显式调用 `restoreConversation`；但 GPU/CPU fallback 与空回复恢复不调用该恢复接口。
- 因此 fallback 后，SQLite/UI 可能仍有完整历史，Native 新 Conversation 却只有 systemInstruction + 本轮消息。

### 持久化时序

- UI 在发送前先把用户消息加入内存列表（`local_ai_interview_screen.dart` 约 2190 行附近）。
- 成功收到回复后才调用 `_persistSuccessfulTurn` 保存 user/assistant 消息（约 2230 行后）。
- Native 异常时 UI 会移除最后一条临时 user 消息并保留输入编辑内容（约 2270-2340 行）。
- 需继续检查 `_persistSuccessfulTurn` 的事务边界及应用进程被杀时的落库时序；“只有 user 消息落库”的完整中断场景目前没有在本次审计中实测，标记 `UNKNOWN`。

## 6. 测试覆盖与缺口

### 已存在的自动化覆盖

- Kotlin `FirstTurnGpuFallbackPolicyTest`：首轮 OpenCL 匹配、成功轮次后不 fallback、CPU backend 不 fallback、无关异常不 fallback、cause 链匹配。
- Kotlin `ConversationResourceReleasePolicyTest`：Conversation 先于 Engine 关闭；关闭异常时继续释放 Engine；保留 suppressed error。
- Kotlin `ConversationResetPolicyTest`：关闭旧 Conversation 后再创建；关闭或创建失败时释放 Engine。
- Flutter `local_ai_interview_screen_test.dart`：覆盖发送状态、模型状态读取失败、模型释放后状态处理、部分重试/输入保留。
- Flutter CI 有独立本地 AI contract tests 和相关 widget regressions。

### 未覆盖或证据不足

- 未发现针对真实 LiteRT-LM Engine/Conversation 的状态迁移集成测试。
- 未发现多轮 state:7 后 transcript 自动回放的测试。
- 未发现空回复后重试的请求幂等/执行状态测试。
- 未发现 Native cancel/timeout/Activity destroy 的可控生命周期测试。
- 未发现 GPU/CPU fallback 后 SQLite、UI、Native 三方历史一致性测试。
- Find N2 GPU/CPU 连续 20 轮、图片/语音、进程中断恢复：`UNKNOWN`。

## 7. 最小修复建议与埋点

按风险和依赖排序：

1. **先补 Native 请求状态契约**：requestId、inFlight、started/completed/failed/unknown；禁止对执行状态未知的请求自动重放。
2. **将 Engine 与 Conversation 状态拆开**：分别表达 initializing/ready/closing/closed/failed；另设 `historyRehydrated`。不能用单一 `ready` 代替。
3. **统一恢复入口**：CPU fallback、Conversation 重建、空回复重试都必须调用同一 transcript rehydration 流程；回放成功后才允许重试本轮。
4. **保留二次异常**：retryError 作为 suppressed/cause 保存，并同时保留原始异常；不得吞掉恢复失败。
5. **明确取消语义**：至少区分 UI abandon、Dart timeout、Native cancellation requested、Native stopped、result unknown；若 LiteRT-LM 不支持安全中断，UI 应显示“请求仍在执行/状态未知”，不得假装已取消。
6. **补齐持久化轮次状态**：为 pending user turn 与 assistant result 建立可恢复的状态或幂等键，处理中断后可识别未完成轮次，避免盲目重发。
7. **增加 trace**：requestId、conversationId、engineGeneration、conversationGeneration、backend、turnIndex、start/end 时间、输入类型、恢复原因、释放顺序、异常类/cause/suppressed、historyRehydrated、Native 执行状态。日志不得记录健康正文、附件原文或身份信息。

## 8. 当前结论

| 审计项 | 结论 |
|---|---|
| Native 任务串行化 | `IMPLEMENTED`（单 Activity 单线程 Executor） |
| UI 防重复点击 | `IMPLEMENTED`（页面级 _sending 等状态） |
| 首轮 OpenCL CPU fallback | `IMPLEMENTED`（策略受限） |
| 多轮异常 CPU fallback | `PARTIAL`（有 fallback，但不回放历史） |
| 空回复重试 | `PARTIAL`（有重试，但无请求幂等/执行状态） |
| 手动历史恢复 | `PARTIAL`（显式路径存在；未证明 fallback 复用） |
| Engine/Conversation 独立状态 | `MISSING` |
| 取消/超时状态契约 | `MISSING` |
| Native 请求幂等与结果未知状态 | `MISSING` |
| state:7 设备根因 | `UNKNOWN` |
| Find N2 GPU/CPU 实测 | `UNKNOWN` |

本报告是静态审计产物，不代表已修复。所有涉及 LiteRT-LM 运行时行为的结论仍须通过目标设备日志与实机测试验证。
