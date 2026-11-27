# Release 构建的授权信任锚配置

本文是 `docs/pro-edition-architecture-constraints.md` v1.3 §11.1–§11.4 的工程操作说明，不替代协议规范；协议字段与兼容规则以 v1.3 配套协议文档为准。

## 配置格式

Release 构建必须通过 `--dart-define=YANJI_LICENSE_KEY_RING=...` 注入发行方**公钥** JSON：

```json
{
  "keys": [
    {
      "key_id": "issuer-2026-01",
      "public_key_base64url": "<32-byte Ed25519 public key, unpadded Base64URL>",
      "status": "active"
    },
    {
      "key_id": "issuer-2026-00",
      "public_key_base64url": "<previous trusted public key>",
      "status": "retired"
    }
  ]
}
```

仅允许 `key_id`、`public_key_base64url`、`status` 三个字段；外层只允许 `keys`。公钥须解码为恰好 32 字节。支持状态为 `active`、`standby`、`retired`、`revoked`、`compromised`。同一 Key Ring 至少需要一个 `active` 或 `standby` 条目。

公钥不是签发秘密，可以随客户端发布；发行私钥不得进入仓库、Dart define、Gradle 属性、APK/AAB 或 CI 日志。私钥应由发行端离线保管，签发工作继续使用 `tool/license_issuer` 的发行流程。

## Release 构建命令

PowerShell 示例（先在本地安全构造只含公钥的 JSON 字符串）：

```powershell
$env:YANJI_LICENSE_KEY_RING = '{"keys":[{"key_id":"issuer-2026-01","public_key_base64url":"<public-key>","status":"active"}]}'
flutter build appbundle --release "--dart-define=YANJI_LICENSE_KEY_RING=$env:YANJI_LICENSE_KEY_RING"
```

Gradle 会检查实际传给 Flutter 的 `dart-defines`，而不是只检查一个未参与编译的环境变量。Release tag / 手动工作流还会读取 GitHub Actions Secret `YANJI_LICENSE_KEY_RING`，用同一 JSON 构建 arm64 APK，并扫描生产源码与最终 APK。缺少、重复、格式错误、无有效 active/standby 条目或含测试发行者/测试向量公钥时，Release 构建必须失败。现有 Android Release signing identity 检查仍独立保留，两项必须同时满足。

## 当前仓库状态

- Dart `LicenseKeyRingFactory` 从同一编译期 define 创建只含公钥的 Key Ring；缺少或无效配置产生空 Ring，不阻止免费功能启动。
- 应用主入口注入 `EntitlementService` 和 `LicenseVerifier`。空 Ring 无法验证任何 issuer，付费授权仍 fail-closed。
- Android Release 构建还要求真实 Key Ring 非空、至少存在 active/standby issuer，并拒绝协议测试向量中的 issuer ID、公钥 Base64URL 和原始公钥字节（Hex）。
- 仓库当前没有经确认的正式发行方公钥。因此不得用测试向量或临时生成的公钥替代；在正式公钥由发行方交付并通过发行流程核验前，正式 Release 仍保持阻断。
- Release readiness scanner 与测试必须和 Dart/Gradle 使用完全相同的 `YANJI_LICENSE_KEY_RING`、`keys` 根对象和 `key_id` 字段，不允许沿用旧的 `YANJI_RELEASE_LICENSE_KEY_RING_JSON` / `issuer_key_id` schema。
- Release workflow 使用临时 CI-only APK 签名身份进行产物扫描，不上传或分发该 APK，也不替代产品正式 Android 签名身份。
- PR #455 已将客户端激活/Token 导入 UI 集成到设置页：用户显式生成 YANJIR1 设备申请，并可粘贴经发行方返回的完整 YANJI1 Token；Token 验证、设备绑定、权益降低确认与原子替换由既有 EntitlementService 完成。该 UI 不包含发行服务器、发行私钥或自动签发服务，不能替代离线发行端流程。
- 正式发行公钥及其来源仍未获核验，因此正式 Release 仍 BLOCKED。生产私钥离线保管/恢复演练、真实客户签发、密钥轮换操作和 Find N2 设备验收均未因此自动完成；详见 `docs/ai-modernization-execution-ledger.md` §93.4–§93.6，以及 `docs/local-real-device-acceptance-handoff.md` §6.5。