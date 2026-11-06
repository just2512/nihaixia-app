# Fork 独立维护与上游同步策略

更新日期：2026-11-06  
维护仓库：`just2512/nihaixia-app`  
上游仓库：`jangviktor-web/nihaixia-app`

## 当前分歧基线

- 共同祖先：`c0f14e77a7fb721fc332576d21fef5f100392d0b`
- 本 Fork 当前基线提交：`35e2b14f877de8fbc2a439908aca9341126bbf83`
- 本 Fork 相对共同祖先修改文件：196 个
- 上游相对共同祖先修改文件：1360 个
- 双方都修改过的路径：16 个

双方共同修改的路径（属于冲突候选，不等于 Git 已确认的文本冲突）：

`.github/workflows/gitee-sync.yml`、`.gitignore`、`README.md`、`lib/data/medical_case_data.dart`、`lib/engine/diagnostic_engine.dart`、`lib/screens/classic_library_screen.dart`、`lib/screens/formula_detail_screen.dart`、`lib/screens/herb_detail_screen.dart`、`lib/screens/knowledge_screen.dart`、`lib/screens/markdown_doc_screen.dart`、`lib/screens/medical_case_library_screen.dart`、`lib/screens/shanghan_jingui_screen.dart`、`lib/services/native_files_io.dart`、`pubspec.lock`、`pubspec.yaml`、`test/medical_case_filter_bar_test.dart`。

其中诊断引擎、医案数据、知识库界面、原生文件处理和依赖清单均存在双方同时修改，禁止直接合并上游分支。

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
