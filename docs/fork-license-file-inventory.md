# Fork 修改文件全量清单

共同上游基线：c0f14e77a7fb721fc332576d21fef5f100392d0b；当前 master 已包含四种子午流注方法字段级情境 Ask AI 入口、本地 Android Release 签名保护、产品版本 2.0.0+8048、研纪 Launcher 资源，以及经典来源/锚点校验协议。本次将 Headless Executor 实现迁移到独立 ToolService 库，Executor 文件保留兼容类型别名；业务行为不变仍须由特征测试和 CI 证明。CI 对实际 PR HEAD 重新计算路径与 Git 状态。

本次范围纠偏同时从当前 Fork 文件清单移除 7 个未投入生产的临床红旗门禁实现/测试文件；其已从代码树删除，不再属于当前受管文件或许可证覆盖集合。

## 分类规则

- FORK_COMMERCIAL：Fork 新增业务实现、工程、品牌、文档或测试资源；仅在权利人拥有版权或取得充分再许可权时适用商业许可。
- APACHE_2_0_AND_FORK_COMMERCIAL：修改过的上游文件；上游原始部分仍为 Apache 2.0，Fork 原创修改部分按商业许可。
- KNOWLEDGE_BASE_EXCLUDED：知识库正文、索引、资料与资源；不转为商业授权，按来源许可/声明执行。
- THIRD_PARTY_EXCLUDED：第三方依赖元数据或第三方材料；继续按其自身条款执行。

授权文件本身（LICENSE、LICENSES、.reuse/dep5）不作为受许可对象重复列入清单。rights_status=OWNERSHIP_EVIDENCE_REQUIRED 的 Fork 文件需保存作者/贡献者版权或有效再许可权证据；不能仅凭 Git 作者字段或仓库管理员身份推定版权。

本次同时纳入 Core-1 完整轮次 Native 历史恢复边界：Flutter 侧仅保留完整 user/assistant turns，Native 双端校验 10,000 UTF-16 上限，拒绝任意消息中间裁剪；设备验收仍为 LOCAL ONLY / MISSING。另纳入 Android Keystore Plugin、AtomicFile TokenStore 与 JVM 策略测试；真机行为仍为 LOCAL ONLY / MISSING。Core-1 增加只读 SessionStateSnapshot 适配器；Core-2 增加医案、古籍 CandidateEvidence 召回适配器及统一多源批次/来源感知旧序排序基础，不改变医案或古籍正文及其来源核验结论；Core-3 增加严格 ReasoningResponse decoder 与不可变 ReasoningRequest/补充元数据 formatter，均未绕过 Native Gate 或授权执行边界。

## 全量新增与修改文件

| 路径 | Git 状态 | 分类 | SPDX 表达式 | 权属/来源状态 |
|---|---|---|---|---|
| .github/workflows/flutter-quality.yml | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| .github/workflows/flutter-tests.yml | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| .github/workflows/fork-license-compliance.yml | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| .github/workflows/release-trust-anchor.yml | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| .gitignore | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| analysis_options.yaml | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/build.gradle.kts | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/proguard-rules.pro | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/AndroidManifest.xml | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/AiModelAccessGate.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/ConversationResetPolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/ConversationResourceReleasePolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/FirstTurnGpuFallbackPolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LicenseKeystore.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LicenseKeystorePolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LicensePlugin.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LicenseTokenStore.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LicenseTokenStorePolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiActivityTaskLifecycle.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiAttachmentPolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiBackendSelectionPolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiConversationHistoryPolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiImagePolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiModelImportRecovery.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiModelIntegrityPolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiRuntimeCacheClearPolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiSessionStateInputPolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiTraceIdPolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiTranscriptRestorePolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/LocalAiWavPolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/kotlin/com/nihaisha/nihaisha_app/UserReportedInputPolicy.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/res/drawable/ic_launcher_foreground.xml | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/res/mipmap-anydpi/ic_launcher_round.xml | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/res/mipmap-anydpi/ic_launcher.xml | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/res/mipmap-hdpi/ic_launcher.png | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/res/mipmap-mdpi/ic_launcher.png | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/res/mipmap-xhdpi/ic_launcher.png | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/res/values/ic_launcher_background.xml | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/res/xml/backup_rules.xml | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/main/res/xml/data_extraction_rules.xml | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/AiModelAccessGateTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/ConversationResetPolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/ConversationResourceReleasePolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/FirstTurnGpuFallbackPolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LicenseKeystorePolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LicenseTokenStorePolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LicenseTokenStoreRecoveryTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiActivityTaskLifecycleTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiAttachmentPolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiBackendSelectionPolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiConversationHistoryPolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiImagePolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiModelImportRecoveryTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiModelIntegrityPolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiRuntimeCacheClearPolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiSessionStateInputPolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiTraceIdPolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiTranscriptRestorePolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/LocalAiWavPolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/app/src/test/kotlin/com/nihaisha/nihaisha_app/UserReportedInputPolicyTest.kt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| android/key.properties.template | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| APP_DEVELOPMENT_DETAIL.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| assets/bencao_lecture/000_总论自序.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/001_总论前言.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/002_总论药性总义.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/003_上经丹砂.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/004_上经云母.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/005_上经玉泉.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/006_上经石钟乳.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/007_上经涅石矾石.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/008_上经消石.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/009_上经朴消.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/010_上经滑石.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/011_上经石胆又名胆矾.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/012_上经空青.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/013_上经曾青.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/014_上经禹余粮.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/015_上经太一余粮.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/016_上经白石英.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/017_上经紫石英.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/018_上经青石赤石黄石白石黑石脂等.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/019_上经白青.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/020_上经扁青.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/021_上经昌蒲.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/022_上经鞠华.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/023_上经人参.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/024_上经天门冬.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/025_上经甘草.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/026_上经干地黄.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/027_上经白术.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/028_上经菟丝子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/029_上经牛膝.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/030_上经充蔚子益母草.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/031_上经女萎玉竹.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/032_上经防葵.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/033_上经茈胡.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/034_上经麦门冬.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/035_上经独活.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/036_上经车前子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/037_上经木香.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/038_上经署豫.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/039_上经薏苡仁.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/040_上经泽泻.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/041_上经远志.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/042_上经龙胆.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/043_上经细辛.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/044_上经石斛.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/045_上经巴戟天.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/046_上经白英.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/047_上经白蒿.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/048_上经赤箭.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/049_上经奄闾子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/050_上经析蓂子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/051_上经蓍实.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/052_上经卷柏.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/053_上经蓝实青黛.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/054_上经芎穷.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/055_上经蘼芜.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/056_上经黄连.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/057_上经络石.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/058_上经蒺藜子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/059_上经黄耆.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/060_上经肉松容.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/061_上经防风.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/062_上经蒲黄.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/063_上经香蒲.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/064_上经续断.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/065_上经漏芦.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/066_上经营实.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/067_上经天名精.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/068_上经决明子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/069_上经丹参.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/070_上经茜根.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/071_上经飞廉.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/072_上经五味子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/073_上经旋华.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/074_上经兰草.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/075_上经蛇床子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/076_上经地肤子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/077_上经景天.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/078_上经茵陈.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/079_上经杜若.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/080_上经沙参.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/081_上经白兔藿.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/082_上经徐长卿.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/083_上经石龙刍.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/084_上经薇衔.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/085_上经云实.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/086_上经王不留行.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/087_上经升麻.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/088_上经青蘘.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/089_上经姑活.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/090_上经别羁.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/091_上经屈草.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/092_上经淮木.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/093_上经牡桂.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/094_上经菌桂.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/095_上经松脂.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/096_上经槐实.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/097_上经枸杞.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/098_上经柏实.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/099_上经茯苓.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/100_上经榆皮.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/101_上经橘柚.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/102_上经发髲.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/103_上经龙骨.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/104_上经麝香.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/105_上经牛黄.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/106_上经熊脂.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/107_上经白胶.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/108_上经阿胶.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/109_上经丹雄鸡.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/110_上经石蜜.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/111_上经蜂子蜂蜜蜂蜡.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/112_上经蜜蜡.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/113_上经牡蛎.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/114_上经龟甲.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/115_上经桑蜱蛸.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/116_上经海蛤.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/117_上经文蛤.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/118_上经蠡鱼.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/119_上经藕实茎.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/120_上经大枣.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/121_上经蒲萄.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/122_上经蓬蘽.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/123_上经鸡头实.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/124_上经胡麻.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/125_上经麻蕡麻子仁.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/126_上经冬葵子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/127_上经苋实.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/128_上经白瓜子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/129_上经苦菜.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/130_中经雄黄.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/131_中经石硫黄.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/132_中经雌黄.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/133_中经水银.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/134_中经石膏.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/135_中经慈石.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/136_中经凝水石.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/137_中经孔公孽.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/138_中经殷孽.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/139_中经铁精.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/140_中经理石.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/141_中经长石.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/142_中经肤青.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/143_中经干姜.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/144_中经枲耳实.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/145_中经葛根.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/146_中经苦参.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/147_中经当归.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/148_中经麻黄.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/149_中经通草.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/150_中经芍药.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/151_中经蠡实.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/152_中经瞿麦.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/153_中经玄参.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/154_中经秦艽.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/155_中经知母.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/156_中经贝母.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/157_中经白芷.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/158_中经淫羊藿.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/159_中经黄芩.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/160_中经狗脊.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/161_中经石龙芮.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/162_中经茅根.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/163_中经紫苑.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/164_中经败酱.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/165_中经白鲜皮.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/166_中经酸浆.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/167_中经紫参.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/168_中经槀本.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/169_中经石苇.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/170_中经萆薢.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/171_中经白薇.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/172_中经水萍.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/173_中经地榆.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/174_中经海藻.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/175_中经泽兰.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/176_中经防己.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/177_中经款冬花.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/178_中经牡丹.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/179_中经马先蒿.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/180_中经积雪草.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/181_中经女菀.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/182_中经厚朴.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/183_中经秦皮.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/184_中经秦椒.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/185_中经山茱萸.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/186_中经紫葳.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/187_中经猪苓.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/188_中经白棘.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/189_中经龙眼.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/190_中经松萝.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/191_中经合欢.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/192_中经白马茎.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/193_中经鹿茸.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/194_中经牛角鳃.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/195_中经羖羊角.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/196_中经牡狗阴茎.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/197_中经羚羊角.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/198_中经犀角.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/199_中经燕屎.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/200_中经猬皮.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/201_中经露蜂房.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/202_中经鳖甲.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/203_中经蟹.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/204_中经蚱蝉.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/205_中经蛴螬.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/206_中经乌贼鱼骨.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/207_中经白僵蚕.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/208_中经鮀鱼甲.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/209_中经蛞蝓.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/210_中经石龙子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/211_中经木虻.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/212_中经蜚虻.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/213_中经蜚蠊.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/214_中经蟅虫.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/215_中经伏翼.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/216_中经梅实.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/217_中经大豆黄卷.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/218_中经黍米.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/219_中经蓼实.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/220_中经葱实.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/221_中经水苏.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/222_下经石灰.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/223_下经礜石.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/224_下经铅丹.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/225_下经粉钖.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/226_下经代赭.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/227_下经白垩.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/228_下经冬灰.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/229_下经青琅玕.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/230_下经附子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/231_下经乌头.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/232_下经天雄.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/233_下经半夏.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/234_下经虎掌.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/235_下经鸢尾.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/236_下经葶苈.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/237_下经桔梗.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/238_下经莨菪子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/239_下经草蒿青蒿.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/240_下经旋复花旋覆花.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/241_下经藜芦.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/242_下经钩吻.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/243_下经射干.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/244_下经蛇含.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/245_下经蜀漆.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/246_下经甘遂.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/247_下经白敛.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/248_下经青葙子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/249_下经雚菌.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/250_下经白及白芨.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/251_下经大戟.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/252_下经泽漆.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/253_下经茵芋.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/254_下经荛花.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/255_下经牙子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/256_下经羊踯躅.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/257_下经商陆.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/258_下经羊蹄.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/259_下经萹蓄.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/260_下经狼毒.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/261_下经白头翁.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/262_下经鬼臼.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/263_下经夏枯草.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/264_下经芫花.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/265_下经巴豆.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/266_下经蜀椒.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/267_下经皂荚.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/268_下经柳花.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/269_下经楝实.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/270_下经郁李仁.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/271_下经莽草.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/272_下经桐叶.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/273_下经梓白皮.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/274_下经古南.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/275_下经黄环.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/276_下经溲疏.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/277_下经鼠李.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/278_下经药实根.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/279_下经栾花.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/280_下经蔓椒.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/281_下经麋脂.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/282_下经鼯鼠.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/283_下经六畜毛蹄甲.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/284_下经虾蟆.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/285_下经马刀.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/286_下经蛇蜕.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/287_下经白颈蚯蚓.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/288_下经翳螉.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/289_下经蜈蚣.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/290_下经斑蟊猫.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/291_下经贝子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/292_下经石蚕.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/293_下经雀瓮.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/294_下经蜣螂.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/295_下经蝼蛄.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/296_下经马陆.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/297_下经地胆.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/298_下经鼠妇.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/299_下经衣鱼.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/300_下经桃核仁.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/301_下经杏核仁杏仁.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/302_下经腐婢.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/303_下经苦瓠.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/304_下经水斳芹菜.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/305_下经彼子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/306_增补青盐.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/307_增补诃黎勒诃子.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/308_增补红花.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/309_增补蜘蛛.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/310_增补赤小豆.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/311_增补艾叶.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/312_增补紫苏.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/313_增补饴糖.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/314_增补柏叶.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/315_增补豆豉.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/316_增补鸡矢白.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/317_增补蒴翟细叶.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/318_增补没药.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/319_增补乳香.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/320_增补白芷.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/321_增补粳米.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/322_增补甘李根白皮.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/323_增补三七.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/324_增补鸡子黄.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/325_增补猪胆猪肤.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/326_增补郁金玉金.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/327_增补木通.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/328_增补新绛.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/329_增补薤白.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/330_增补白前.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/331_增补神曲.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/332_增补小麦.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/333_增补灶心土.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/334_总论药性理论与五行.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/bencao_lecture/herb_index.json | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/data/changelog.json | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| assets/guji/upstream_increment_index.json.gz | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/jingui/clause_453.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/jingui/clause_454.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/medical_cases/cases_table.md | 修改 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/176_board.jpg | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/appendix_001_六经辨证总结.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/appendix_002_六经传变规律.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/appendix_003_六经病欲解时.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/appendix_004_六经辨证临床要点.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/clause_176_upstream.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/clause_380.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/clause_381.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/clause_382.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/clause_383.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/clause_384.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/clause_385.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/clause_386.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/clause_387.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/clause_388.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/clause_389.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/shanghan/clause_390.md | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| assets/zhenjiu_lecture/acupoint_index.json | 修改 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| build-apk.sh | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| CHANGELOG.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| CONTRIBUTING.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/2026-11-04-unified-assistant-acceptance-audit.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/2026-11-06-execution-audit.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/ai-capability-audit-report.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/ai-capability-audit.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/ai-capability-inventory.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/ai-commercial-license.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/ai-data-clear-scope-audit.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/ai-layered-runtime-architecture.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/ai-modernization-execution-ledger.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/ai-p0-transcript-rehydration.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/ai-parallel-execution-protocol.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/ai-redflag-entrypoint-audit.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/ai-redflag-preflight-policy.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/ai-trace-contract.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/ai-trace-implementation.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/ai-trace-local-writer.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/app_capability_ai_integration_audit.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/app_capability_inventory.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/assistant-tool-capability-audit.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/brand-identity.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/classic-retrieval-golden-review.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/classic-rule-source-manifest.json | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/combined-pattern-reachability-matrix.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/contextual-ask-ai-spec.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/cross_platform_solution.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/diagnostic_engine_optimization_report.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/find-n2-acceptance-2026-11-02.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/find-n2-adaptive-layout.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/find-n2-ai-trace-acceptance-plan.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/find-n2-audit-round2-2026-11-09.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/find-n2-fold-aware-layout.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/find-n2-local-ai-acceptance-checklist.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/find-n2-real-device-acceptance.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/find-n2-real-device-brand-acceptance.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/find-n2-test-results-ak-round4.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/find-n2-test-results-final.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/find-n2-test-results-round3.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/find-n2-text-scaling-fix.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/fork-license-boundary.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/fork-license-file-inventory.json | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/fork-license-file-inventory.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/fork-maintenance-policy.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-round3/AI_keyboard_off.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-round3/AI_keyboard_on.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-round3/D_ziwei_result.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-round3/E_font200.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-round3/F_keyboard_text.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-round3/F_keyboard.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-round3/v_展开态两列全屏.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-round3/v_折叠态全屏.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-test-round2/01_tab_ai.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-test-round2/02_tab_tools.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-test-round2/03_tab_knowledge.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-test-round2/04_tab_bookmarks.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-test-round2/05_tab_settings.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-test/01_outer_screen_folded.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-test/02_inner_screen_ai_reply.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-test/03_photo_inference_reply.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-test/04_half_fold.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/find-n2-test/05_after_release_reload.png | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/logo.svg | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/readme_banner.svg | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/images/readme_features.svg | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/index.html | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/local-ai-e4b.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/local-ai-multiturn-audit.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/local-android-release-checklist.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/local-real-device-acceptance-handoff.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/privacy.html | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/pro-edition-architecture-constraints.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/pro-edition-license-protocol.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/product-positioning-and-boundaries.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/release-license-keyring-configuration.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/tcm-diagnosis-code-diff-audit.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/tcm-diagnosis-system-integration-audit.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/tcm-diagnosis-upstream-data-diff.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/tcm-diagnosis-zangfu-source-audit.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/tcm-hebing-reachability-matrix.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/testing.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/unified-conversation-orchestration-architecture.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/upstream_sync_audit_2026-11-06.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/upstream-sync-ledger.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/user-bookshelf-local-knowledge-architecture.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/versioning-policy.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/yanji-editorial-frontend-design-plan.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| docs/yanji-visual-design-system.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/data/acupoint_repository.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/data/assistant_conversation_store.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/data/bencao_lecture_data.dart | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| lib/data/bencao_lecture_index.dart | 新增 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| lib/data/classic_lecture_data.dart | 修改 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| lib/data/database_helper.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/data/guji_data.dart | 修改 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| lib/data/herb_repository.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/data/medical_case_data.dart | 修改 | KNOWLEDGE_BASE_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| lib/engine/diagnostic_engine.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/engine/diagnostic_rules.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/engine/zangfu_evidence_builder.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/licensing/ai_model_access_platform.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/licensing/license_key_ring_factory.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/licensing/license_model.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/licensing/license_platform.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/licensing/license_verifier.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/main.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/models/ai_context_ref.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/models/ai_evidence.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/models/assistant_message_metadata.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/models/assistant_tool_result.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/models/diagnosis_result_codec.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/models/diagnosis.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/models/evidence_ranking_decision.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/models/session_state_snapshot.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/models/tcm_interview_message.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/models/tcm_interview_task_state.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/models/tool_execution_plan.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/models/zangfu_evidence.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/acupoint_detail_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/acupuncture_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/app_dialogs.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/assistant_history_screen.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/assistant_tool_router.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/bazi_paipan_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/bencao_library_screen.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/bookmarks_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/chat_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/chenggu_bone_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/classic_library_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/critical_illness_list_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/daily_almanac_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/diagnosis_history_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/dosage_converter_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/dream_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/festival_lookup_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/formula_detail_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/guansha_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/guji_library_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/herb_detail_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/herb_related_screens.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/home_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/huangdi_siji_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/knowledge_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/local_ai_interview_screen.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/markdown_doc_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/medical_case_detail_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/medical_case_insights_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/medical_case_library_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/meihua_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/meridian_detail_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/minggua_calculator_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/minggua_library_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/neijing_entries_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/neijing_knowledge_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/neijing_library_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/neijing_search_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/sanshan_lingqian_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/saved_charts_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/search_tab.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/settings_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/shanghan_jingui_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/shousheng_debt_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/solar_term_section_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/tools_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/xiaoliuren_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/yijing_detail_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/yijing_result_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/yijing_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/yunqi_charts.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/yunqi_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/yuxiaji_omen_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/zhenjiu_library_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/ziwei_cases_list_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/ziwei_chart_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/ziwei_doc_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/ziwei_reference_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/screens/ziwuliuzhu_screen.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/ai_context_prompt_builder.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/ai_context_resolver.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/ai_tool_result_snapshot.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/ai_trace_runtime.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/ai_trace_store.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/ai_trace.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/almanac_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/almanac_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/assistant_chart_result_formatter.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/assistant_conversation_orchestrator.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/assistant_knowledge_context.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/assistant_reasoning_turn_ledger.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/assistant_tool_execution_plan_builder.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/bazi_context_snapshot.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/bazi_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/bazi_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/chenggu_result_context_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/chenggu_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/chenggu_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/classic_evidence_pipeline.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/classic_search_service.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/context_resolution_gateway.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/dosage_conversion_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/dosage_result_context_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/dosage_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/dosage_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/dream_result_context_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/dream_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/dream_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/entitlement_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/guansha_result_context_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/guansha_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/guansha_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/guji_evidence_pipeline.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/guji_source_anchor_resolver.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/headless_tool_dispatcher.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/headless_tool_plan_result_handler.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/headless_tool_result_handler.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/huangdi_siji_result_context_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/huangdi_siji_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/huangdi_siji_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/legacy_order_evidence_ranker.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/license_activation_request_builder.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/local_ai_attachment_store.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/local_ai_data_clear_coordinator.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/local_ai_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/medical_case_evidence_pipeline.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/meihua_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/meihua_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/multi_source_evidence_pipeline.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/native_files_io.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/native_files_stub.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/sanshan_lingqian_result_context_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/sanshan_lingqian_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/sanshan_lingqian_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/saved_chart_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/session_state_snapshot_builder.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/session_state_snapshot_prompt_formatter.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/shousheng_debt_result_context_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/shousheng_debt_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/shousheng_debt_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/solar_term_result_context_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/solar_term_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/solar_term_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/source_aware_legacy_evidence_ranker.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/tcm_interview_adapter.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/tcm_interview_conversation_controller.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/tool_argument_support.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/xiaoliuren_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/xiaoliuren_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/yijing_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/yijing_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/yunqi_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/yunqi_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/yuxiaji_omen_result_context_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/yuxiaji_omen_time.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/yuxiaji_omen_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/yuxiaji_omen_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/ziwei_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/ziwuliuzhu_calculation_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/ziwuliuzhu_tool_executor.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/ziwuliuzhu_tool_service.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/theme/app_colors.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/theme/app_preference_text_scaler.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/theme/app_tokens.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/theme/yanji_palette.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/theme/yanji_status_semantics.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/utils/chart_export.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/utils/fold_aware_routes.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/utils/ziwei_plate_layout.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/adaptive_content_width.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/adaptive_home_navigation.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/adaptive_master_detail.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/bazi_location_picker.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/bazi_paipan_widgets.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/contextual_ai_sheet.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/license_activation_settings_section.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/license_status_presentation.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/local_ai_backend_settings_tile.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/local_ai_data_clear_tile.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/local_ai_trace_debug_tile.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/meridian_map.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/solar_term_card.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/text_scale_slider.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/window_metrics_diagnostics.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/yanji_status_badge.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/widgets/zone_section.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| PROMO_COPY.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| pubspec.lock | 修改 | THIRD_PARTY_EXCLUDED | NOASSERTION | SOURCE_LICENSE_REVIEW |
| pubspec.yaml | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| README.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| RELEASE_NOTES_1.11.1-1.11.7.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| RELEASE_NOTES.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.10.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.11.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.12.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.13.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.14.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.15.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.16.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.17.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.18.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.19.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.22.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.23.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.24.body.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.24.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.25.body.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.25.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.26.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.27.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.28.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v1.11.29.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release_notes/v2.0.0.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release/download-page/index.html | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release/研纪_历史版本_v1.10.0+7_发布说明.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| release/研纪_历史版本_v1.10.1_发布说明.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/acupoint_contextual_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/acupoint_detail_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/acupoint_index_cross_meridian_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/acupoint_sparse_detail_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/acupuncture_editorial_typography_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/acupuncture_half_fold_root_navigation_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/adaptive_home_navigation_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/adaptive_master_detail_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ai_context_prompt_builder_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ai_data_clear_database_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ai_model_access_platform_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ai_retrieval_golden_snapshot_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ai_tool_result_snapshot_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ai_trace_store_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ai_trace_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/almanac_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/almanac_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/android_ai_backup_rules_contract_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/android_release_signing_gate_contract_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/app_brand_identity_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/app_capability_registry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/app_preference_text_scaler_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/app_theme_color_scheme_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_acupuncture_source_navigation_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_chart_result_formatter_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_conversation_orchestrator_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_conversation_storage_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_history_persistence_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_history_resume_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_history_screen_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_knowledge_context_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_message_metadata_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_provenance_integration_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_reasoning_turn_ledger_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_tool_execution_plan_builder_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_tool_registry_build_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_tool_result_handoff_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_tool_result_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/assistant_tool_router_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/bazi_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/bazi_foldable_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/bazi_service_location_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/bazi_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/bencao_lecture_index_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/bencao_lecture_navigation_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/bookmarks_editorial_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/chaoshan_omen_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/chat_screen_initial_context_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/chat_screen_retirement_audit_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/chat_screen_task_resume_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/chenggu_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/chenggu_smoke_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/chenggu_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/city_search_dialog_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/classic_evidence_pipeline_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/classic_lecture_assets_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/classic_library_contextual_ask_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/classic_paragraph_contextual_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/classic_rule_source_manifest_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/classic_search_backlink_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/classic_search_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/context_resolution_gateway_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/contextual_ai_panel_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/critical_illness_list_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/diagnosis_history_editorial_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/dosage_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/dosage_conversion_service_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/dosage_converter_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/dosage_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/dream_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/dream_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/editorial_semantic_contrast_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/engine/combined_pattern_followup_score_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/engine/combined_pattern_negative_reachability_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/engine/combined_pattern_question_flow_reachability_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/engine/combined_pattern_reachability_matrix_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/engine/combined_pattern_regression_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/engine/diagnostic_engine_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/engine/pulse_tongue_cross_validation_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/engine/three_yang_clause268_gate_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/engine/zangfu_evidence_builder_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/entitlement_service_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/festival_lookup_editorial_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/fixtures/ai_retrieval_golden_metadata.json | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/fixtures/pro-license-test-vectors.json | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/fold_aware_navigation_contract_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/fold_aware_routes_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/folk_tools_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/fork_update_isolation_policy_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/formula_contextual_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/guansha_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/guansha_editorial_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/guansha_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/guji_contextual_paragraph_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/guji_data_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/guji_evidence_pipeline_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/guji_library_editorial_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/headless_tool_dispatcher_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/headless_tool_plan_result_handler_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/headless_tool_result_handler_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/herb_alias_search_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/herb_backlinks_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/herb_contextual_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/home_screen_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/huangdi_siji_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/huangdi_siji_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/knowledge_adaptive_master_detail_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/knowledge_editorial_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/knowledge_foldable_reading_matrix_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/legacy_order_evidence_ranker_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/license_activation_request_builder_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/license_activation_settings_section_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/license_key_ring_factory_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/license_platform_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/license_status_presentation_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/license_verifier_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/local_ai_adaptive_content_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/local_ai_atomic_turn_persistence_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/local_ai_attachment_store_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/local_ai_backend_settings_tile_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/local_ai_data_clear_coordinator_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/local_ai_data_clear_database_boundary_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/local_ai_data_clear_tile_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/local_ai_interview_screen_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/local_ai_service_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/local_ai_trace_debug_tile_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/markdown_doc_contextual_selection_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/medical_case_contextual_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/medical_case_data_integrity_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/medical_case_detail_editorial_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/medical_case_evidence_pipeline_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/medical_case_filter_bar_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/medical_case_formula_alias_extract_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/medical_case_list_light.png | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/meihua_contextual_field_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/meihua_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/meihua_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/meridian_contextual_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/meridian_detail_editorial_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/minggua_screen_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/models/tcm_interview_task_state_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/multi_source_evidence_pipeline_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/native_ai_access_gate_architecture_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/native_files_io_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/neijing_contextual_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/neijing_entries_screen_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/phase2_core_detail_editorial_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/phase2_remaining_half_fold_routes_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/quality_score_bc.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/readme_version_consistency_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/release_license_key_ring_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/repository_version_consistency_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/sanshan_lingqian_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/sanshan_lingqian_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/saved_chart_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/saved_charts_editorial_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/search_tab_classic_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/services/tcm_interview_conversation_controller_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/session_state_snapshot_builder_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/session_state_snapshot_prompt_formatter_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/settings_screen_editorial_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/shanghan_jingui_paragraph_context_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/shanghan_upstream_board_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/shousheng_debt_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/shousheng_debt_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/solar_term_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/solar_term_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/source_aware_legacy_evidence_ranker_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/support/fake_ai_model_access_platform.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/support/in_memory_assistant_conversation_store.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/tcm_interview_adapter_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/tcm_interview_message_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/tcm_interview_task_state_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/theme/yanji_contrast_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/theme/yanji_lingqian_status_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/theme/yanji_status_badge_widget_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/theme/yanji_status_semantics_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/theme/yanji_theme_wiring_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/tool_execution_plan_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/tool_foldable_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/tools_screen_editorial_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/version_source_policy_contract_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/window_metrics_diagnostics_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/xiaoliuren_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/xiaoliuren_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yanji_android_icon_resource_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yijing_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yijing_detail_screen_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yijing_editorial_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yijing_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yunqi_chart_text_scale_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yunqi_charts_contrast_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yunqi_contextual_chart_field_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yunqi_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yunqi_engine_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yunqi_screen_editorial_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yunqi_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yunqi_wuxing_badge_geometry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yuxiaji_omen_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/yuxiaji_omen_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/zhenjiu_lecture_paragraph_context_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/zhenjiu_lecture_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwei_bench_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwei_cases_list_screen_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwei_chart_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwei_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwei_doc_screen_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwei_engine_crosscheck_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwei_plate_layout_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwei_reference_screen_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwei_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwuliuzhu_assistant_handoff_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwuliuzhu_calculation_service_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwuliuzhu_contextual_method_field_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwuliuzhu_contextual_result_entry_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwuliuzhu_nazi_benxue_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwuliuzhu_tool_executor_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/ziwuliuzhu_wumen_test.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/zone_section_responsive_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/audit_color_tokens.py | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/audit_product_brand.py | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/bazi_dump.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/bazi_stage_dump.dart | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/build_classic_search_index.py | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/capture_find_n2_metrics.ps1 | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/check_design_tokens.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/check_fork_license_inventory.py | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/check_version_source.sh | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/color_token_audit_allowlist.json | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/fix_launcher_png.py | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/import_graph_audit/analysis_options.yaml | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/import_graph_audit/bin/audit.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/import_graph_audit/pubspec.yaml | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/import_renji_zhenjiu.py | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/license_issuer/check_release_readiness.py | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/license_issuer/issuer.py | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/license_issuer/README.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/license_issuer/requirements.txt | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/license_issuer/test_issuer.py | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/license_issuer/test_release_readiness.py | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| tool/reindex_zhenjiu_index.py | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| web/index.html | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| web/manifest.json | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| zhenjiu_audit_report.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| zweiwei_doushu_integration_assessment.md | 修改 | APACHE_2_0_AND_FORK_COMMERCIAL | Apache-2.0 AND LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| 企划书_研纪_v2.0.md | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/models/reasoning_request.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/models/reasoning_response.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/reasoning_request_prompt_formatter.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| lib/services/reasoning_response_codec.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/reasoning_request_prompt_formatter_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/reasoning_response_codec_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |

| lib/services/local_ai_transcript_restore_policy.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/local_ai_service_legacy_entrypoint_audit_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/local_ai_transcript_restore_architecture_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |
| test/local_ai_transcript_restore_policy_test.dart | 新增 | FORK_COMMERCIAL | LicenseRef-Nihaixia-Fork-Commercial | OWNERSHIP_EVIDENCE_REQUIRED |

## 删除路径

- .github/scripts/gitee_release.py
- .github/workflows/build-apk.yml
- .github/workflows/gitee-sync.yml
- .github/workflows/release.yml
- docs/images/logo.jpg
- docs/images/logo.webp
- lib/services/update_service.dart
- lib/services/whats_new_service.dart
- lib/widgets/update_dialog.dart
- release/汉唐中医_v1.10.0+7_发布说明.md
- release/汉唐中医_v1.10.1_发布说明.md
- test/services/update_service_test.dart
- test/update_download_sources_test.dart
- tool/sync_gitee.sh
- 企划书_汉唐中医_v2.0.md

## 计数与验收说明

- 新增/修改路径共 1014 个（新增 850，修改 164）；删除路径 15 个。
- 分类统计：Apache 2.0 + Fork 双层许可 158；Fork 商业授权候选 492；知识库排除 363；第三方排除 1。
- .reuse/dep5 对每个非许可元数据的变更路径逐项精确登记；知识库与第三方排除项使用 NOASSERTION，不产生新的授权。
- 自动检查以共同上游基线为比较点，在实际 PR HEAD 上重算新增、修改、重命名和删除；许可元数据本身从待授权文件集合排除。未来新增、修改或删除文件若未同步更新清单和 DEP5，CI 失败。
- 清单和 SPDX 映射证明工程分类完整性，不代替贡献者权属/再许可权证明，也不构成法律意见。
