# 研纪专业版永久授权协议（v1.2）

> 状态：协议实现规范；**尚未达到商业发行条件**。本文件与 `docs/pro-edition-architecture-constraints.md` v1.2 配套。若细节与架构约束冲突，以架构约束为准。测试密钥与测试向量不得用于生产。

| 项目 | 值 |
|---|---|
| App ID | `com.nihaisha.nihaisha_app` |
| Product ID | `yanji_pro_lifetime` |
| Token 前缀 | `YANJI1` |
| 申请前缀 | `YANJIR1` |
| Protocol revision | `1` |
| 签发模型 | 人工核单、离线签发、客户端离线验签 |
| 设备密钥 | Android Keystore P-256 / ECDSA SHA-256 |
| 发行者签名 | Ed25519 |

## 1. 产品与 Feature 清单

协议已知 Feature（`knownFeatureIds`）固定为：

| Feature ID | 首期允许签发 | 首期实际授权 |
|---|---:|---:|
| `ai_advanced` | 是 | 是 |
| `contextual_assistant` | 是 | 是 |
| `advanced_learning` | 否 | 否 |
| `advanced_export` | 否 | 否 |

协议修订 1 允许签发集合（`protocolAllowedFeatureIds`）和发行端首期签发集合（`issuableFeaturesByRevision[1]`）均只有 `ai_advanced`、`contextual_assistant`。当前客户端门禁集合（`enforcedFeatureIds`）同样只有这两项。

客户端最终授予集合：

```text
GrantedFeatures =
  ClaimedFeatures
  ∩ KnownFeatureIds
  ∩ ProtocolAllowedFeatureIds[protocol_revision]
  ∩ EnforcedFeatureIds
```

未知 Feature 或已知但当前修订不允许的 Feature 不授予，并记录诊断；不得因此拒绝整份签名有效 Token。只有结构损坏、Feature 列表类型错误或重复 ID 等格式错误才拒绝 Token。发行端必须严格限制可签发集合，不得把保留 Feature 签入正式凭证。

## 2. 设备授权申请：YANJIR1

### 2.1 格式与签名

```text
YANJIR1.<base64url(canonical_request_payload)>.<base64url(ecdsa_p256_der_signature)>
```

- Request Payload 使用 UTF-8、无 BOM、RFC 8785 JCS 规范化 JSON。
- Base64URL 使用 URL-safe 字符集且无填充。
- 设备私钥为 Android Keystore P-256 / secp256r1，签名为 ECDSA + SHA-256，ASN.1 DER 编码。
- 申请签名输入为 ASCII `YANJIR1.` + 原始申请 Payload Base64URL 段；验签端使用原始段，不解析后另行序列化验签。
- Request nonce 是客户端生成的 32 字节 CSPRNG 随机值，不是服务器挑战，也不代表在线防重放。

### 2.2 Request Payload 字段

| 字段 | 规则 |
|---|---|
| `schema_version` | 整数 1 |
| `request_id` | UUID，单次申请唯一 |
| `request_nonce` | 32 字节 CSPRNG，Base64URL 无填充 |
| `app_id` | 精确等于 App ID |
| `product_id` | 精确等于 Product ID |
| `issued_at` | UTC ISO-8601，仅用于审计 |
| `device_public_key_spki` | 完整 P-256 SPKI DER，Base64URL 无填充 |
| `device_key_sha256` | SPKI DER 的 SHA-256 指纹 |
| `device_key_security_level` | SOFTWARE / TRUSTED_ENVIRONMENT / STRONGBOX / UNKNOWN 客户端报告值 |

发行端必须校验申请字段、SPKI 曲线/编码、指纹重算和设备签名。安全级别只是客户端报告元数据，不是 Android Key Attestation，也不是远程硬件证明。

### 2.3 发行端防重放与幂等

发行端数据库必须持久化 `request_id`、`request_nonce`、完整申请令牌 SHA-256（`request_sha256`）、订单 ID 和处理结果，并设置唯一约束：

1. 同一 `request_id` + 同一订单 + 同一 `request_sha256` 重复提交，幂等返回原签发结果或原处理状态。
2. 同一 `request_id` 对应不同订单或不同申请摘要，必须拒绝。
3. 同一订单更换设备必须显式走 reissue，保留旧签发记录及替代关系。
4. 订单可以关联多次签发历史；订单 1:N 不代表多设备同时有效。

客户端不持久化 pending request，也不做最终 Token 的 request nonce / request hash 匹配。Nonce 仅用于发行端去重和审计。

## 3. 永久授权凭证：YANJI1

### 3.1 外层格式和签名输入

```text
YANJI1.<base64url(canonical_payload)>.<base64url(ed25519_signature)>
```

Payload 使用 RFC 8785 JCS 规范化 JSON，UTF-8、无 BOM。签名输入固定为：

```text
UTF8("YANJI-PRO-LICENSE-V1\0") || canonicalPayloadBytes
```

Token 外层仍使用 `YANJI1`，但签名域前缀采用独立且固定的 `YANJI-PRO-LICENSE-V1\0`。验签端必须先按 JCS 重新计算 canonical bytes，并确认 Token 内 Payload 段就是该 canonical byte sequence；不得使用 `YANJI1.` + 原始段作为签名输入。

`features` 必须按字典序排序且无重复。字段类型固定，不使用不必要浮点数。Python Issuer 与 Dart Verifier 必须共享合法/非法向量。

### 3.2 Payload 字段

| 字段 | 规则 |
|---|---|
| `schema_version` | 整数 1 |
| `license_id` | 唯一授权 ID |
| `order_id` | 订单编号，不含客户姓名/手机号 |
| `product_id` | 固定 Product ID |
| `protocol_revision` | 整数；当前客户端只接受支持集合中的值 |
| `app_id` | 固定 App ID |
| `perpetual` | 必须为 true |
| `features` | 签名覆盖的 Feature ID 列表 |
| `device_public_key_sha256` | 当前设备公钥 SPKI DER 的 SHA-256 指纹 |
| `request_id` | 发行记录关联 ID |
| `issuer_key_id` | 发行者 Key Ring ID |
| `issued_at` | UTC 审计时间，不是过期时间 |

最终 Token **不得包含** `request_nonce`、`request_sha256`、设备报告安全级别或客户端 pending request 数据。它们属于申请和发行端记录，不是客户端授权匹配条件。

### 3.3 时间语义

- 首期没有 `expires_at`，永久授权不依赖客户端系统时钟。
- 不因 `issued_at` 晚于设备时间而拒绝。
- 不因设备时间回拨而拒绝。
- 不用 `issued_at` 推导过期或授权期限。

## 4. 协议修订兼容规则

客户端至少包含：

```text
minimumSupportedProtocolRevision = 1
supportedProtocolRevisions = {1}
```

验证必须同时满足：修订号不低于最低支持修订，且属于支持集合。禁止使用 `revision >= currentRevision` 自动放行未来修订。

常规 App 升级不得使仍受支持的旧 Token 失效。只有协议存在明确安全缺陷并经单独决策提高最低支持修订时，才淘汰旧格式。

## 5. Key Ring 与发行者轮换

Key Ring 由构造注入 `LicenseVerifier`，不得在 Verifier 中写测试专用分支。

| Key 状态 | 客户端验签 | 新签发 |
|---|---|---|
| active | 接受 | 允许 |
| standby | 接受 | 私钥启用后才允许 |
| retired | 接受历史凭证 | 禁止 |
| revoked / compromised | 拒绝该 Key 的全部凭证 | 禁止 |

测试公钥只能注入 Unit Test；Debug 如需测试激活，应装配独立 Debug Key Ring；Release 只装配生产公钥。Release 不得信任测试 issuer ID 或测试公钥。

Release Key Ring 通过编译期 Dart define `YANJI_RELEASE_LICENSE_KEY_RING_JSON` 注入，配置仅包含公钥，不包含发行私钥。协议配置结构固定为：

```json
{
  "schema_version": 1,
  "keys": [
    {
      "issuer_key_id": "issuer-YYYY-MM",
      "public_key_base64url": "<canonical 32-byte Ed25519 public key>",
      "status": "active"
    }
  ]
}
```

`issuer_key_id` 必须符合 `issuer-YYYY-MM`；每个公钥必须是无填充 Base64URL，解码后恰好 32 字节。允许状态为 active、standby、retired、revoked、compromised。Release 至少要有一个 active / standby / retired 信任锚；revoked / compromised 不计入有效信任锚。重复 ID、未知字段、未知状态、测试 issuer ID、空配置和格式错误一律拒绝。生产私钥只能由离线发行端保管。

Debug 的应用组合根继续使用 fail-closed `UnconfiguredFeatureAuthorizer`。Release 的组合根从上述 Key Ring 创建唯一 `EntitlementService`；没有生产 Key Ring 时，Release 启动装配失败，不会回退到允许授权的默认值。

备用 Key 只有在真实备用公钥已经预置于客户端时才有效。吊销某发行者 Key 会影响该 Key 签署的全部 Token；离线客户端只有更新 App 才能执行新 Key Ring 策略，无法实时远程撤销。吊销后必须按订单证据为真实客户重新签发。

## 6. 客户端 Token 存储与激活

### 6.1 存储

第一版只持久化一份已签名 Token 文件：

```text
context.noBackupFilesDir/yanji_license/active_license.token
```

- 路径由 Android Context 动态取得。
- 不使用独立 SQLite 授权库。
- 主数据库 `nihaisha.db` 维持 version 7，不新增授权表或迁移。
- 不保存 `is_pro` 或独立可授予权益的 Feature 列表。
- 进程启动时必须重新验签，内存快照只用于当前进程。

### 6.2 原子替换

导入新 Token 时先验证签名、Key Ring 状态、协议修订、Feature 结构、App ID 和设备公钥指纹；验证完成后通过 Android AtomicFile 或等价同目录 fsync + 原子替换写入。验证失败或写入失败必须保留旧 Token。禁止先删除旧 Token 再写入新 Token。

新 Token 是完整授权替换，不做 Feature 并集；若新 Token 权益少于旧 Token，必须展示将失去的 Feature 并由用户明确确认。

### 6.3 设备密钥接口

必须区分：

- `getDeviceKey()`：get-only，不存在时返回 keyMissing。
- `createDeviceKeyForActivation()`：仅用户主动生成激活申请时调用。
- `signActivationRequest()`：只用既有密钥，不自动生成替代密钥。
- `checkPrivateKeyUsability()`：本地挑战签名检查，不创建或替换密钥。

启动、验签、Token 导入和后台检查全部 get-only。Keystore alias 丢失或失效时不能自动创建替代密钥并沿用旧 Token。

## 7. Key/Token 验证结果

Verifier 至少区分：

- invalidFormat / invalidPayload / unsupportedSchema
- unknownIssuer / issuerCompromised / invalidIssuerKey / invalidSignature
- unsupportedRevision / wrongProduct / wrongApplication / wrongDevice
- revoked
- valid / validWithUnsupportedFeatures / validWithoutGrantedFeatures

未知或协议尚未允许的 Feature 只记录诊断、不授予，但不应拒绝其余合法 Feature。未知发行者、错误签名、错误设备指纹和不支持协议修订必须拒绝。

## 8. 尚未完成的发布条件

本规范及测试向量通过不等于允许生产发行。生产发行至少需要真实发行者 Key Ring、发行私钥离线备份/恢复演练、Release fail-closed 行为测试、权属证据、隐私/用户协议和发行渠道审查。

仓库中的 `.github/workflows/release-trust-anchor.yml` 是发行前置门禁，监听 `v*` 标签和手动触发。正式发布前必须在 GitHub Actions Secret 配置 `YANJI_RELEASE_LICENSE_KEY_RING_JSON`，其值与编译 Release 时传入的 Dart define 完全一致。门禁运行 `tool/license_issuer/check_release_readiness.py`，校验生产 issuer ID、公钥长度和规范编码、可信状态数量，并扫描 `lib/` 与 Android 主源码中的测试公钥原始字节、Base64URL、Base64、Hex 及测试 issuer ID；随后执行 Release 组合根行为测试和协议回归测试。该门禁失败时不得上传或发布任何 Release 产物。

目前仓库不含正式发行者公钥或私钥；因此新门禁在真实生产公钥生成并完成离线保管、配置 GitHub Secret 前应保持失败。不得用测试向量、公用示例或临时生成的密钥替代生产信任锚。所有尚无源码、CI 或设备证据的项目继续保持 MISSING / UNKNOWN。
