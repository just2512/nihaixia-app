# 全模式 RedFlag 入口审计（已退役历史档案）

> **状态：SUPERSEDED / NOT IN SCOPE（2026-11-26）。** 本文早期规划的临床 RedFlag detector、医学审核、五种模式全入口拦截和 RELEASE BLOCKED 要求已被当前产品定位取代。本文只保留作历史追溯，不是当前实施方案、验收清单或发布门槛。

## 当前有效结论

研纪是中医学习辅助工具，不是医疗诊断软件、急救决策系统或临床分诊系统。当前不建设：

- 临床红旗识别 detector、风险分级或临床分诊流程；
- 医学词表、临床阈值、例外规则或个体化处置文案审批；
- 要求医学背景人员审核上述规则、要求医生签字或留存临床审批版本；
- 对 automatic、consultation、learning、tools、metaphysics 五种模式实施统一的临床模型调用拦截。

因此，缺少上述 detector 或医学审核记录不是功能缺陷，也不得导致普通学习、模拟问诊、工具、玄学或知识解释入口 RELEASE BLOCKED。

## 仍然有效的软件边界

- App 自己的输入格式、长度、会话身份和数据访问权限校验继续执行。
- 工具参数白名单、明确用户确认、确定性业务规则执行、结果结构和来源完整性校验继续执行。
- App 的确定性规则/计算产生业务结果；AI 只解释已产生并通过校验的结果，不自行计算、伪造或覆盖。
- 可展示固定、一般性的急重症求助提醒；它不识别或判断风险，不分级、不分诊、不提供个体急救操作指导，也不决定是否允许模型调用。

## 代码状态

2026-11-26 的代码清理移除旧 RedFlagGate/RedFlagPreflight 生产接线、require_red_flag MethodChannel 参数、Android NativeRedFlagExecutionBoundary 以及仅用于该门禁的测试夹具。模型访问仍受唯一 Native AiModelAccessGate 控制，普通数据/参数/工具权限校验不变。

## 当前规范入口

- docs/product-positioning-and-boundaries.md
- docs/ai-capability-audit.md §17–18
- docs/ai-modernization-execution-ledger.md §119

本文历史调用图和历史状态只说明当时的设计，不得继续转成当前待办或代码门禁。
