# 历史策略记录：RedFlag Preflight

> **状态：SUPERSEDED / NOT IN SCOPE（2026-11-26）。** 本文件不再定义当前生产策略、调用门禁或发布条件。此前的临床 detector、医学审批和 fail-closed 放行策略不符合研纪的学习辅助产品定位，已正式废弃。

## 当前产品边界

研纪是中医学习辅助工具，不是临床诊断、分诊或医疗决策软件。当前不建设临床红旗检测器、医学风险阈值、风险评分、临床分流、动态处置规则或全模式临床安全门禁。

- 不要求医学专业人员审核词表、规则 ID、阈值、例外、急救/处置文案或 detector 版本。
- 不要求医生签字、责任审批、临床规则审核记录或以此作为版本发布条件。
- 不因 detector 缺失、无法评估、语义不确定或缺少医学审核而阻断学习助手、问诊学习流程、工具助手、玄学助手、附件理解或历史恢复。
- 问诊助手保留 docs/product-positioning-and-boundaries.md §4.3 的固定简明求助提示。它只是一般性提醒，不是由输入内容触发的临床判定、风险等级或治疗/急救操作指导。
- 普通软件校验仍然执行：输入长度与格式、附件读取、会话归属、工具参数/权限、用户确认、确定性业务结果及来源校验。

## 历史契约

本文件旧版中的 CLEAR / BLOCK_URGENT / CLARIFY / REVIEW_REQUIRED 组合、ruleSetReviewed、detectorCoverageComplete 和所有相关门禁测试，仅属于已经退役的临床化方案。不得将这些字段作为当前 App 的业务状态或重新接入生产模型调用路径。

当前范围以 docs/product-positioning-and-boundaries.md、docs/ai-capability-audit.md 和 docs/ai-modernization-execution-ledger.md 的最新有效章节为准。
