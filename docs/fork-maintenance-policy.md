# Fork 独立维护与上游同步策略

更新日期：2026-11-06  
维护仓库：`just2512/nihaixia-app`  
上游仓库：`jangviktor-web/nihaixia-app`

## 当前分歧基线

- 共同祖先：`c0f14e77a7fb721fc332576d21fef5f100392d0b`
- 本 Fork 当前 HEAD：`e72101d7ca25e76d2d62c08a03d810503f6091af`
- 上游当前 HEAD：`e29610fd9be0494d51ffb27e61d3ea0b32b24002`
- 当前分支关系：Fork ahead 790 / behind 29（本轮 GitHub compare，2026-11-06）
- 本 Fork 相对共同祖先修改文件：201 个（compare 返回完整 201 项）
- 上游落后于 Fork 的 29 个提交已逐个读取提交元数据；部分大提交的 GitHub commit 文件清单返回 300 项上限，不能宣称上游所有变更路径已穷举
- 已确认的同路径改动至少包括：`.github/workflows/gitee-sync.yml`、`.gitignore`、`README.md`、`pubspec.yaml`、`pubspec.lock`、`lib/engine/diagnostic_engine.dart`、`lib/screens/shanghan_jingui_screen.dart`、`lib/screens/formula_detail_screen.dart`、`lib/screens/herb_detail_screen.dart`、`lib/screens/markdown_doc_screen.dart`、`lib/screens/settings_screen.dart`、`lib/screens/classic_library_screen.dart`、`lib/services/native_files_io.dart`
- 上述路径是**同路径两侧均有改动**的确认清单，不等于每一项都已发生 Git 文本冲突；尤其 `diagnostic_engine.dart`、知识/经典页面、依赖配置需逐项三方审查
- 上游 29 个提交涉及本草讲稿库、金匮讲稿与撤回、方剂经典索引、伤寒条文内容/编号/排版、繁简转换、Release/README、Gitee 工作流等。它们不是可以整批合入的单纯修复提交

**冲突结论：** 当前已确认 Fork 与上游分歧；仅凭 compare 文件列表不能证明所有潜在冲突路径已经穷举，也不能把同路径修改等同于 Git 已确认的文本冲突。`diagnostic_engine.dart`、`medical_case_data.dart`、`pubspec.yaml` 等核心文件仍须在任何候选移植前做逐文件三方差异检查。当前没有执行合并模拟，也没有合并上游。

## 强制维护规则

1. `master` 是本 Fork 唯一产品维护分支；禁止使用 GitHub 的 Sync fork / Update branch 直接合并上游。
2. 禁止 App 启动时查询上游 Release、提示安装上游 APK、从上游下载 APK 或通过上游 Gitee 镜像更新。
3. Fork 的正式发行版只能由本仓库的 tag 与 GitHub Actions 生成；当前尚无独立 Fork Release 时，不提供上游 APK 作为替代下载。
4. 上游新增内容只有在明确提出引入需求后才逐项评估。优先考虑独立数据文件；诊断引擎、医案数据、依赖和 UI 重叠路径必须先做三方差异审查。
5. 每次候选移植必须记录：来源提交、涉及文件、Fork 本地改动、数据结构兼容性、测试影响、回滚方式。禁止合并整个上游分支来“补齐落后提交”。
6. CI 以 Fork 当前提交 SHA 为验收对象。取消、排队和旧 SHA 的绿色结果都不能替代当前提交的通过结果。

## 本次清理

- 删除 App 内上游 Release 检测、更新提示、APK 下载与安装入口。
- 删除原项目 Release 下载和 Gitee 同步工作流、脚本及手动同步工具。
- 删除 Android 专用 APK 安装 MethodChannel 与 `REQUEST_INSTALL_PACKAGES` 权限。
- 删除 APK 下载和校验专用原生文件代码；保留临时缓存清理。
- 删除启动时的版本更新公告弹窗；保留关于页本地更新日志。
- 保留本地 E4B 模型导入、加载、SHA-256 校验和本地会话恢复能力。
