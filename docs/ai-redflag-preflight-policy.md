# RedFlag Preflight 策略契约（已退役历史档案）

> **状态：SUPERSEDED / NOT IN SCOPE（2026-11-26）。** 本文件曾描述面向临床分诊产品的红旗识别策略；它与研纪当前的中医学习辅助定位不符，不是当前架构规范、生产逻辑或发布条件。

## 当前结论

研纪不实现临床红旗 detector、疾病风险分类器、临床分诊、急救决策或个体化处置建议。因此：

- 不建设或维护临床红旗词表、风险阈值、例外规则和处置文案；
- 不要求医学背景人员审核这些词表/阈值/文案，不要求医生签字或临床审批版本；
- 不使用 CLEAR、BLOCK_URGENT、CLARIFY、REVIEW_REQUIRED 等临床评估状态决定模型调用或业务路由；
- 不把上述事项作为 automatic、consultation、learning、tools、metaphysics 任一模式的模型调用前置门禁或 RELEASE BLOCKED 条件。

## 仍然有效的边界

1. 用户个人信息、健康学习记录和生辰信息按各自数据域隔离；跨域读取需有明确用户授权。
2. App 对输入格式、长度、会话归属、工具参数和用户确认执行确定性校验。
3. 问诊/辨证和其他业务计算由 App 既有确定性规则执行；AI 只解释经校验的业务结果。
4. 固定、一般性的急重症求助提醒可以保留，但不构成检测、分级、分诊、处置或模型调用 gate。

## 退役代码

2026-11-26 清理的旧实现包括 RedFlagGate/RedFlagPreflight、NativeRedFlagExecutionBoundary、require_red_flag MethodChannel 参数和仅用于该门禁的测试夹具。若未来代码中再次出现这些接口，应先核对当前产品定位与规范，不应按历史策略直接恢复。

## 当前规范入口

- docs/product-positioning-and-boundaries.md
- docs/ai-capability-audit.md §17–18
- docs/ai-modernization-execution-ledger.md §119
