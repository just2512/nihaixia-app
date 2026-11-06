# 并行开发与 CI 约定

## 分支职责

- `master`：稳定主线，只接收已完成集成验收的改动。
- `integration`：跨模块集成分支；在这里运行完整 Flutter 回归、Android 单元测试和 arm64 Debug APK 构建。
- `work/ziwei-fold-layout`：Find N2 内外屏布局与交互。
- `work/ai-unified-assistant`：统一会话、意图识别、调度和对话体验。
- `work/tcm-knowledge-tools`：知识检索、来源元数据、确定性工具执行。
- `work/classic-case-provenance`：经典条文与医案来源账本、核验状态。
- `work/app-capability-audit`：全 App 能力盘点、迁移边界与跨模块验收清单。

## 并行规则

1. 每条工作流使用独立分支和独立 worktree；禁止多个代理共用同一工作目录。
2. 不同工作流不得同时修改同一文件。共享接口必须先在集成分支定义，再由依赖工作流同步。
3. AI 调度层不得自行计算或编造工具结果；知识检索必须返回来源、版本和核验状态。
4. 生产代码改动必须伴随回归测试。工作分支 CI 执行静态分析和本分支变更测试；纯文档/工作流变更不强制执行 Dart 测试。
5. 集成分支和 master 执行完整 Flutter 回归、Android 单元测试及 arm64 Debug APK 构建。工作分支快速 CI 不能替代集成全量回归。
6. 失败测试必须修复真实问题，不得删除断言、跳过测试或降低验收条件来取得绿色结果。
7. 未经明确授权，不自动创建 PR、不合并 master、不进行 force push。

## 集成顺序

1. 先确定 AssistantMessage、AssistantIntent、ToolRequest、ToolResult、KnowledgeContext 的字段和错误语义。
2. 知识与工具能力先提供稳定调用契约，AI 调度层再消费该契约。
3. UI 层只负责会话展示和用户交互，不复制业务规则或工具计算。
4. 功能分支完成定向验证后，按接口依赖顺序进入 integration；全部集成验收通过后再进入 master。

## CI 分层

- L0：依赖锁定、静态分析。
- L1：工作分支变更测试。
- L2：integration 完整 Flutter 测试、Android 单元测试、arm64 Debug APK。
- L3：OPPO Find N2 真机折叠/展开、键盘、旋转/恢复和关键会话流程验收。
- `flutter-quality.yml` 保留为手动扩展质量检查，避免与主 CI 重复触发。

## 当前边界

GitHub Actions 负责远程 CI；多代理进程和多个 worktree 应在开发机本地运行。GitHub 分支本身不会自动启动多个 Claude Code/Opencode 代理。
