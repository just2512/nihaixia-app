# AI Credential Vault Android 实施任务卡

> **Task ID:** \`AI-CREDENTIAL-VAULT-ANDROID-20261128\`
>
> **Parent Task:** \`AI-MODEL-CONFIG-20261128\`（完整模型开发方案 §5.4 / §14）
>
> **Workstream:** Remote
>
> **Owner:** Remote 唯一 Owner；Integration 负责台账与 PR 集成；Architecture 负责安全合同审核。
>
> **Source baseline:** \`master@9017388415e3744485c212340957c5f01c410d43\`
>
> **Implementation branch:** \`remote/ai-credential-vault-android-20261128\`
>
> **Current branch HEAD at task-card creation:** \`c1a2f752aa356aa00130d17135bbfd32aee8ba31\`
>
> **Status:** Implementation draft; not merged; pending R1A configuration schema integration and exact-HEAD automated acceptance.

## 1. Objective

为云端 Provider API 凭证提供独立的 Android 安全存储抽象，不把任何 Secret 写入 SQLite、\`user_settings\`、SharedPreferences、日志、配置导出或备份可见文件。

R1A 配置 Repository 只保存不透明 \`credentialRef\`；本任务提供其底层 Vault。

## 2. Scope

- Dart \`AiCredentialVault\` interface：\`save(providerId, secret)\`、\`read(credentialRef)\`、\`delete(credentialRef)\`、\`exists(credentialRef)\`。
- Android 独立 Flutter Plugin / MethodChannel：\`com.nihaisha.app/ai_credential_vault\`。
- 独立 AndroidKeyStore AES-256/GCM key alias；不得复用 License ECDSA KeyRing、License Keystore 或 LicenseTokenStore。
- 加密文件存储于 \`Context.noBackupFilesDir/ai_credentials\`，通过 \`AtomicFile\` 写入；保存 Envelope 版本、IV、密文。
- AAD 绑定 credentialRef 和 Envelope 版本，阻止密文被替换到其他 credentialRef。
- 密文 payload 同时保存 providerId；读取返回 providerId 与 secret，未来 ModelGateway 必须比对 ProviderConfig.providerId 后才能使用。
- 缺失/失效 Keystore key、认证失败、损坏密文必须 fail-closed；不得在已有密文仍存在时静默重新生成密钥。
- Web/当前未实现的其他平台统一返回 \`CREDENTIAL_VAULT_UNAVAILABLE\`；不实现明文或浏览器本地存储 fallback。
- Kotlin JVM policy tests 与 Flutter MethodChannel tests。

## 3. Allowed paths

- \`android/app/src/main/kotlin/com/nihaisha/nihaisha_app/AiCredentialVaultPolicy.kt\`
- \`android/app/src/main/kotlin/com/nihaisha/nihaisha_app/AiCredentialVaultStore.kt\`
- \`android/app/src/main/kotlin/com/nihaisha/nihaisha_app/AiCredentialVaultPlugin.kt\`
- \`android/app/src/main/kotlin/com/nihaisha/nihaisha_app/MainActivity.kt\`（只增加 Plugin 注册）
- \`android/app/src/test/kotlin/com/nihaisha/nihaisha_app/AiCredentialVaultPolicyTest.kt\`
- \`lib/licensing/ai_credential_vault.dart\`
- \`test/ai_credential_vault_test.dart\`
- 本任务 PR 中的 Fork inventory / SPDX 同步。
- 本任务自己的任务卡文件。

## 4. Explicitly forbidden

- 不改 \`DatabaseHelper\`、R1A Provider/Model/Task DTO/Repository 或 R1A migration。
- 不改共享架构规范、AI 审计规范、执行台账或唯一 Find N2 设备交接文件。
- 不调用任何 Provider，不实现 HTTP/SSE/Model Gateway。
- 不新增 AI 总开关，不改 E4B Native 推理路径。
- 不把 License private key 或 License TokenStore 用于 Provider Secret。
- 不写明文 SharedPreferences / SQLite / 文件 / Web localStorage / 日志。
- 不把模拟器/CI/JVM 测试宣称为真实 Find N2 Keystore PASS。

## 5. Security contract

- AES-GCM 256-bit；12-byte IV；128-bit authentication tag。
- CredentialRef 使用随机 UUID；Envelope 中固定版本。
- AAD 包含 credentialRef 与版本。
- Secret 上限由策略统一限制；不在异常文字或日志输出 Secret。
- Provider ID 在加密 payload 内；读取回传后由未来 Gateway 与所选 Provider 记录进行等值校验。
- \`exists\` 只查本地文件和 Keystore alias，不做网络请求。
- \`read\` 只允许在真实模型请求的执行窗口调用；不要在设置页打开时解密/探测凭证。
- Secret 删除后不保留明文副本；加密文件写入与删除保持原子恢复边界。

## 6. Dependencies and integration sequence

1. R1A Provider/Model/Task schema v9 merge.
2. 本 R1B Credential Vault 独立 PR merge。
3. R2 AiRuntimeAccessCoordinator / AiModelGateway / HTTPS transport。
4. R3 Cloud text reasoning Adapter。
5. R4 image/audio Adapter。
6. R5 Cloud Embedding / Reranker Adapter。
7. R6 vector index generation。
8. R7 Settings UI and cloud E2E。

本任务不阻塞云端其他不依赖凭证的文档/审计工作，但 R2+ 的可用云端请求必须等 Vault 合入。

## 7. Acceptance

- Dart static analysis / MethodChannel tests pass.
- Android arm64/JVM compilation and Native policy unit tests pass.
- Verify Vault file path is under \`noBackupFilesDir\`; no plaintext secret in files/DB/log/export.
- Verify corrupt envelope, wrong AAD/reference, missing key and invalidated key fail closed.
- Verify \`credentialRef\` from Provider A cannot be accepted as Provider B secret by the next Gateway.
- Exact final HEAD: Branch validation, Flutter regression, Android arm64/JVM, PR required gate and Fork License all SUCCESS; SKIPPED is not PASS.
- After merge, verify master SHA and Push CI.

**Hardware note:** The current JVM tests validate serialization and AES-GCM/AAD contract with a software test key, not AndroidKeyStore/AtomicFile behavior on Find N2. Those device results remain \`LOCAL ONLY / UNKNOWN\` until the single final device-acceptance phase.