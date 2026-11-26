# RedFlag Preflight 策略（历史档案，已退役）

> **状态：** SUPERSEDED / NOT IN SCOPE（2026-11-26）。
>
> 本文件中的 RedFlagAssessment、ruleSetReviewed、detectorCoverageComplete、REVIEW_REQUIRED、临床阈值、医学审核和全入口 fail-closed 接入要求属于早期临床产品化设想。它们不再是研纪当前生产代码、测试、验收或发布要求。

研纪是中医学习辅助工具，不是医疗诊断、临床分诊或医学风险评估软件。当前不建设临床红旗 detector，不要求医生或医学背景人员审批词表、阈值、例外规则和急救文案，也不因 detector 缺失/未知而阻断正常学习或问诊学习。

当前仍有效的工程安全边界是：

- Native 模型访问必须通过 App 自身的 AiModelAccessGate。
- 工具调用必须经过注册能力、权限、用户确认和 typed 参数校验。
- 辨病辨证和数值结果由 App 确定性代码执行，模型不能直接覆盖或伪造。
- 结果的来源 ID、参数、执行状态和失败状态必须由 App 校验。
- 用户自述、模型解释、知识资料和确定性业务结果必须区分。
- 简明急重症求助提醒只提示寻求现实帮助，不做风险分级，不作为调用门禁。

历史 RedFlag TRACE 枚举值如需读取旧记录，仅用于兼容历史数据，不表示当前仍执行 detector 或 safety preflight。
