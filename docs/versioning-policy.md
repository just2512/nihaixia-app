# 研纪独立版本管理规范

> 状态：生效（版本源码候选已提交，正式 APK 未发布）
> 生效日期：2026-11-22
> 维护仓库：just2512/nihaixia-app

**当前项目版本**：`2.0.0+8048`  
**同 applicationId 已知最高 Android versionCode**：`8047`

本文件是研纪产品版本治理的权威规范。README、pubspec.yaml、App 更新日志与 CI guard 必须与本文件保持一致。

## 1. 版本体系

项目采用 SemVer 产品版本与独立 Android 构建号：

MAJOR.MINOR.PATCH+BUILD

- MAJOR.MINOR.PATCH 是研纪自己的产品版本，不跟随上游编号。
- BUILD 映射为 Android versionCode，必须严格单调递增。
- pubspec.yaml 是唯一可编辑版本来源；Gradle 只读取 Flutter 提供的 versionName/versionCode，不得另设第二套版本变量。
- 1.11.x 及更早编号保留为历史版本，不再继续该序列。

**2.0.0 是研纪首个独立主版本基线**，标志独立产品版本序列开始，不表示本版本 APK 已发布或设备升级已通过。

## 2. 产品版本递增规则

| 级别 | 递增条件 | 典型变更 |
|---|---|---|
| MAJOR | 产品定位、关键架构、核心数据契约或兼容边界发生重大变化 | 产品代际切换、关键流程重构、需明确迁移策略的不兼容变化 |
| MINOR | 在现有产品边界内增加向后兼容的重要能力 | 新学习模块、独立业务能力、主要工作流 |
| PATCH | 不改变既有产品契约的修复或小幅改进 | Bug 修复、稳定性、性能、兼容性、局部 UI 修订 |

版本级别由本项目实际交付决定，不由上游发布节奏、日期、提交数量或分支 ahead/behind 数量决定。普通提交不要求逐次 bump；形成新可交付版本时才按本规范更新。

## 3. Android 构建号与共享 applicationId

1. pubspec.yaml 中的 +BUILD 映射到 Android versionCode；MAJOR.MINOR.PATCH 映射到 versionName。
2. 本仓库当前应用版本为 1.11.30+8039。已核验上游 jangviktor-web/nihaixia-app 的 pubspec.yaml 在提交 92ef759 为 1.11.34+8047。
3. 本仓库和上游使用相同 Android applicationId：com.nihaisha.nihaisha_app。因此本次独立版本使用 2.0.0+8048，构建号严格高于目前已核验的共享 package 版本源最高值 8047。
4. 该上限是已核验代码版本源的保守基线，不等同于对所有历史分发包或目标设备当前安装包的完整盘点。**Find N2 当前安装包的实际 versionCode 必须在本地读取**；若设备值不低于 8048，不得安装本版本，须先重新评估构建号。
5. versionCode 更高只是安装升级的必要条件之一；覆盖安装还要求签名证书兼容。不得更换原签名密钥、applicationId、数据目录或数据库身份来绕过系统校验。
6. 本版本不改变 applicationId、既有签名配置、数据库 schema、持久化目录或用户数据。

上游版本源证据：[jangviktor-web/nihaixia-app pubspec.yaml @ 92ef759](https://github.com/jangviktor-web/nihaixia-app/blob/92ef759bd217a9433308a9c47d3c56a59ef2f2e7/pubspec.yaml)。

## 4. 唯一来源与自动校验

- pubspec.yaml 是唯一可编辑版本来源。
- README 的“当前源码版本”和“当前仓库版本”、本规范中的当前项目版本必须逐字匹配 pubspec。
- tool/check_version_source.sh 检查上述三处版本一致，并阻止 Android build number 不高于本规范登记的共享 applicationId 已知上限。
- Flutter CI 的版本源步骤必须执行该脚本；测试需覆盖正常一致、README 漂移、规范漂移和版本码不高于上限等条件。
- 不得只改 README、应用内 changelog 或 Gradle 单独制造版本号。

## 5. 本地发布与上游隔离

- 正式 APK 只能由维护者在本地使用设备当前安装包对应的原签名密钥构建、签名和验收后本地或私下交付。
- 不推送发行 Tag，不创建 GitHub Release，不上传正式签名 APK 或 keystore；GitHub Actions 只运行源码回归、Android Debug ABI / Manifest / Native 单测及 Release 签名缺失负向门禁。
- 上游版本、Tag、Release、APK 和 changelog 不构成本项目版本或发行依据。上游代码仅在明确提出需求时手动评估和小批量引入。
- 不恢复 App 启动时查询上游 Release、提示安装上游 APK 或下载上游更新的逻辑。

## 6. 历史与发布状态

- 旧 1.11.x 及更早记录保留，不改写历史记录，不再用于当前版本递增。
- assets/data/changelog.json 按产品版本倒序；新版本须排在历史版本之前。
- 2.0.0+8048 当前状态为 PREPARATION / NOT RELEASED。版本源、CI 或版本码门禁通过都不表示已生成正式 APK。
- 正式交付前仍须本地验证原签名证书、目标设备实际 versionCode、applicationId、APK SHA-256、adb install -r 和用户数据保留；证据不足时保持 UNKNOWN / LOCAL ONLY。

## 7. 变更控制

重置 Android 构建号、变更 applicationId、替换签名身份或数据目录、恢复在线 APK 发布、改用其他版本源，均属于独立高风险变更，须单独评估兼容与数据迁移，不得混入普通版本 bump。
