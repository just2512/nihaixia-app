# Fork 独立维护与统一助手计划执行审计

审计日期：2026-11-06  
维护分支：`just2512/nihaixia-app:master`

## 一、Fork 与原项目分歧

本次审计读取 GitHub compare，而不是仅沿用页面旧数字：

- Fork 审计基线：`da8d4b00e3102f14544d2320fbe0a081d9644b38`
- 原项目 master：`e29610fd9be0494d51ffb27e61d3ea0b32b24002`
- 共同祖先：`c0f14e77a7fb721fc332576d21fef5f100392d0b`
- 基线分支关系：Fork ahead 792 / behind 29，状态 `diverged`
- compare 返回 Fork 相对共同祖先的 201 个变更文件。它不是“201 个 Git 文本冲突”；同路径改动需要三方审查，不能直接合并。

确认原项目更新机制的风险路径包括诊断引擎、医案数据、依赖、古籍/方剂页面、设置页和原生文件服务。原项目 29 个提交不应整批合入。禁止 Sync fork / Update branch；只允许在提出明确需求后逐文件移植，并记录来源提交、三方差异、数据兼容性、测试与回滚办法。

## 二、Fork App 自动更新隔离

状态：**源码清理已完成；本次增加回归防线，CI 待本次提交确认。**

compare 显示以下上游更新功能文件已从 Fork 删除：

- `lib/services/update_service.dart`
- `lib/services/whats_new_service.dart`
- `lib/widgets/update_dialog.dart`
- `test/services/update_service_test.dart`
- `test/update_download_sources_test.dart`
- `.github/workflows/gitee-sync.yml`
- `.github/scripts/gitee_release.py`

同时，`tools/sync_gitee.sh` 已从 Fork 删除。当前 `lib/main.dart` 启动链没有上游版本检查/公告调用；AndroidManifest 不含 `REQUEST_INSTALL_PACKAGES`；原生主通道保留本地模型导入、推理和会话恢复，不提供 APK 下载/安装方法。

**保留项：** `ChangelogRepository` 只读取打包在 APK 内的 `assets/data/changelog.json`，在“关于”页展示本 Fork 自己的本地更新日志。它不是联网检查、上游更新提示或自动安装功能。

新增 `test/fork_update_isolation_policy_test.dart`，防止后续提交重新引入上游更新服务、更新后弹窗、Gitee 同步和 APK 安装权限。该测试必须随当前提交通过后，才将回归防线标为 PASS。

Fork 自身仍可通过本仓库 tag / GitHub Actions 构建 Release；这与 App 启动时自动更新原项目完全分离。

## 三、用户计划状态矩阵

状态定义：`PASS` = 源码和对应自动化检查均有证据；`PARTIAL` = 主路径存在但仍有明确缺口；`MISSING` = 尚无可核验实现/验收证据；`UNKNOWN` = 当前证据不足。

| 事项 | 当前状态 | 已核验的实现 | 未关闭项 |
|---|---|---|---|
| 1. 经典条文与医案关联 | PARTIAL | `classic-rule-source-manifest.json`；来源审计区分仲景原文、版本校勘、倪师讲授、后世注家；知识检索能附本地古籍/医案片段 | 逐条底本、版次、卷页、异文和影印页尚未齐备；医案稳定来源 ID、原始定位缺失；1256/1257 表格记录与 1337 来源统计差额未核清；不得自动确立医案—条文关联 |
| 2. Find N2 内外屏适配 | PARTIAL | 窗口断点、双面板导航、折痕/铰链安全区、窄屏换行；八字表单已有 402dp/840dp 布局回归 | 其他排盘和知识页面仍需逐页检查；OPPO Find N2 外屏、内屏、半折叠、键盘、相机、文件选择器、模型导入实机验收缺失 |
| 3. 统一问诊 | PARTIAL（主消息流已实现） | `LocalAiInterviewScreen` 内联启动 `TcmInterviewConversationController`；题目、选项、回答和结果写入统一消息流；`DiagnosticEngine` 负责确定性辨证；任务快照可恢复待答状态 | 清理旧 `ChatScreen` builder 兼容入口；核验跨重启消息/任务快照一致性、完成态回看及附件原件生命周期 |
| 4. 本地 AI 连接知识库与工具 | PARTIAL | `AssistantKnowledgeContextBuilder` 将本地方剂、本草、穴位、古籍和医案检索片段注入模型上下文；工具注册表可路由到现有工具页面，部分结果可回传 | 知识条目来源字段/定位协议仍不完整；工具缺少统一 typed args/result schema、参数抽取、缺参追问、取消/失败协议和原生对话内执行结果卡 |
| 5. 全 App 功能盘点与 AI 融合 | PARTIAL | 已有 AI 能力矩阵、工具注册表、主入口/知识/工具/历史/设置入口 | 尚未逐页盘点所有功能、数据源、重复入口、持久化、权限、错误状态和可调用性；不能宣称全应用重构完成 |
| 11. 单一主入口与统一调度 | PARTIAL | 首页默认统一 AI 对话；`AssistantConversationOrchestrator` 区分问诊/学习/工具/玄学；`AssistantToolRouter` 覆盖现有工具目的地；意图不清时能澄清 | 当前主要是规则/关键词路由，不是模型结构化意图协议；工具参数 schema、跨轮任务状态、多工具计划和统一结果渲染尚未完成 |

## 四、统一调度必须遵守的职责边界

统一的是用户入口、会话上下文、历史记录、知识检索和工具调度，不是把所有业务逻辑交给模型。

1. 问诊：本地模型负责倾听、澄清、整理用户自述；结构化辨证由确定性 `DiagnosticEngine` 逐题收集已确认输入并计算。模型不得伪造诊断证据、处方或剂量。
2. 学习：检索本地知识库，返回条目、来源类型、版本状态和内部定位；未命中或出处不全时明确标记 `MISSING`。
3. 工具：模型识别用户意图并补齐参数；确定性工具服务执行五运六气、紫微、八字等计算；结果必须由服务返回，模型不能猜算。
4. 玄学：仅作为传统术数/民俗文化参考，不包装成科学预测，也不介入医疗、法律和投资决策。
5. 同一轮出现多个工具、缺少必要参数或用户表达含糊时，先澄清，不按关键词命中顺序擅自执行。

## 五、CI 基线

- 2026-11-06，Fork 基线提交 `da8d4b0` 的 Flutter regression tests 与 arm64 Debug APK 构建均为 SUCCESS（run `42186504264`）。
- 该 run 覆盖 Dart/Flutter 静态分析、Local AI contract、录音/照片生命周期、历史续聊、问诊任务快照、合病回归、统一助手 dispatch、完整 Flutter 测试、Android debug APK、ABI/SHA-256 校验及 Android native unit tests。
- 新增更新隔离回归测试后，必须以新提交 SHA 的 CI 结果重新确认；旧 SHA 绿色结果不能替代新提交验收。
- 自动化测试不替代 Find N2 真机验收，也不替代古籍纸本版本和医案逐案来源校勘。

## 六、执行原则

- 不合并原项目分支，不执行 Sync fork / Update branch。
- 允许在同一轮并行推进来源审计、折叠屏布局、统一助手/知识检索、工具协议和 CI。
- 只把有源码、测试或实机证据的事项标为完成；文档完成不等于功能完成。
- 对来源不明的经典和医案数据保持 `MISSING` / `REVIEW_REQUIRED`，不补造书页、版本或案例出处。
