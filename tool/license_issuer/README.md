# Yanji Pro Offline License Issuer

本工具用于私域订单人工核验及离线签发，不处理支付。当前签发规范以 `docs/pro-edition-license-protocol.md` 和 v1.3 单一 `ai_access` 约束为准。Python 签发器与 Dart 验证器共用 `test/fixtures/pro-license-test-vectors.json` 中的跨语言测试向量；其中的密钥、订单和 Token 全部是测试数据，绝不能用于生产。

> **当前生产状态：BLOCKED。** 仓库尚无经来源核验的正式发行者公钥；正式私钥备份/恢复演练、真实签发运营、源码权属及来源许可材料和正式 Android 签名身份也未齐备。下列命令说明工具流程，不代表已获准开始生产签发。不要为了“先跑通”而把测试密钥或临时生成密钥加入生产 Key Ring。

## 环境

Python 3.12+，依赖版本见 `requirements.txt`。

```bash
python -m pip install -r tool/license_issuer/requirements.txt
```

## 发行者密钥与密钥环

准备正式密钥前，先确定发行主体、密钥管理责任人、备份地点、访问控制和恢复流程。不要在本仓库或 CI 中生成/保存生产私钥。

```bash
python tool/license_issuer/issuer.py keygen --key-id issuer-2026-01
```

工具要求输入两次口令（至少 12 个 UTF-8 字节），默认写入仓库外：

- `~/.yanji-license-issuer/keys/issuer-2026-01.private.pem`
- `~/.yanji-license-issuer/keys/issuer-2026-01.public.pem`
- `~/.yanji-license-issuer/keys/issuer-keyring.json`

私钥为口令加密的 PKCS#8 PEM。运营端 `issuer-keyring.json` 使用签发器自己的 schema：`schema_version` 和 `keys` 对象；每个 Key ID 对应 `status` 与 `public_key_raw_base64url`。它与 App Release 的 `YANJI_LICENSE_KEY_RING` JSON 不是同一份配置文件，不能直接混用。签发时工具会检查指定私钥与该 Key ID 的公钥是否匹配；错误私钥、错误 Key ID 或非 `active` Key 均不能签发。

Ed25519 raw 公钥长度必须为 32 字节，以无填充 Base64URL 表示。keygen 输出的公钥可经来源核验后纳入 App Release 的 `YANJI_LICENSE_KEY_RING`；私钥绝不能随公钥进入客户端。App Release Key Ring 的字段、状态和注入方式以 `docs/release-license-keyring-configuration.md` 为准；生产 App 可以预置多个发行者公钥。历史 Key 设为 `retired` 后只用于验证历史凭证，不再签发；`revoked` / `compromised` 必须在客户端信任策略更新后拒绝相应 Token。离线客户端不会实时接收撤销消息。

**密钥恢复要求：** 正式销售前至少保留两份口令加密的离线备份，位于不同介质/地点；备份口令独立保管。必须实际演练一次恢复，核对恢复公钥与 Key ID 的对应关系，并使用共享测试向量执行签名/验签。私钥与订单数据库分开备份。不要将私钥、口令放入仓库、APK、CI、工单、聊天记录或日志。

Windows 操作员还需通过系统 ACL 保护 key 目录；POSIX 权限设置只是附加保护，不能替代离线备份和访问控制。

## 当前签发协议与首次签发

**新 Token 只能按协议修订 2 签发，且只包含唯一运行时权益 `ai_access`。** 修订 1 的 `ai_advanced` / `contextual_assistant` 仅为历史 Token 兼容读取保留，禁止新签发器再签发这两个旧 ID，也不代表两种独立付费权益。

用户将完整 YANJIR1 设备申请码通过约定的安全渠道交给运营方。人工核对订单及收款后执行：

```bash
python tool/license_issuer/issuer.py issue \
  --request-file request.txt \
  --order-id YJ-20261125-0001 \
  --key-id issuer-2026-01 \
  --private-key ~/.yanji-license-issuer/keys/issuer-2026-01.private.pem \
  --payment-confirmed
```

签发器验证申请内完整的 P-256 SPKI 公钥、指纹、请求 nonce、request_id 和 ECDSA 私钥持有证明；随后计算完整申请令牌的 SHA-256，并将 request_id、nonce、hash、设备指纹保存在运营方订单数据库用于唯一约束、幂等和审计。最终客户端 Token 包含 request_id 与设备公钥指纹，不含 nonce/hash/设备安全级别，不要求客户端持久化或匹配 pending request。

最终 Token 的预期为：`protocol_revision = 2`、`features = ["ai_access"]`。签发器当前常量 `PROTOCOL_REVISION = 2` 与 `ISSUABLE_FEATURES_BY_REVISION = {2: ("ai_access",)}` 是代码依据；不要按旧手册手工改成 revision 1 或加入旧 Feature ID。

`--payment-confirmed` 是操作员人工确认，不会查询微信、支付宝、银行或支付服务商。签发器不采集客户姓名、手机号、微信 ID 或付款截图。签名只证明凭证由发行者密钥签发且内容未被篡改，不证明买家已经付款。

## 换机 / 重签

同一订单更换设备时，必须产生一份新的设备申请，并显式使用：

```bash
python tool/license_issuer/issuer.py issue \
  --request-file new-device-request.txt \
  --order-id YJ-20261125-0001 \
  --key-id issuer-2026-01 \
  --private-key ~/.yanji-license-issuer/keys/issuer-2026-01.private.pem \
  --payment-confirmed \
  --reissue \
  --reason "Customer reinstalled after clearing application data"
```

工具在一个 SQLite 事务中将旧签发记录标记为 `superseded`，追加新 `license_id`，并记录替代关系和审计事件。旧令牌不会因为发行端数据库状态变化就在已离线运行的旧 App 上自动失效；只有后续客户端版本内置更新的 Key Ring / denylist 策略才会产生对应影响。

同一 `order_id + request_id + request_sha256` 重复提交时幂等返回原活动令牌；同一 `request_id` 不能用于其他订单。request_nonce 和 request_sha256 只在发行端订单数据库留存，用于唯一约束和审计，不写入最终 Token。存在旧签发记录时，新的请求必须显式 `--reissue` 并提供 `--reason`。

免费重签次数/收费规则没有被签发器硬编码，必须由产品条款另行确定。正式销售前未完成该产品决策，不得收费销售。

## 订单与审计数据库

默认位置：`~/.yanji-license-issuer/data/orders.sqlite3`。

数据库采用订单 1:N 授权记录结构：

- `orders`：订单编号、商品、创建时间、核款状态、重签次数。
- `issued_licenses`：每次授权的 `license_id`、`request_id`、`request_sha256`、设备指纹、Key ID、签发时间、令牌、当前状态和替代关系。
- `issuer_audit_events`：issue/reissue/迁移事件及脱敏细节。

不记录姓名、手机号、微信 ID、付款截图或聊天内容。审计明细不写入私钥、口令或完整 Token。授权 Token 本身需要保存在订单库用于幂等补发，因此数据库同样必须设置严格操作系统权限并加密备份。

列出订单和历史签发：

```bash
python tool/license_issuer/issuer.py list
```

## 安全与商业许可边界

- App 侧授权 Token 存储在 `noBackupFilesDir/yanji_license/active_license.token` 单 Token 原子文件中；不创建 Android 授权 SQLite 表，主数据库 schema 保持 v7。发行端 `orders.sqlite3` 是独立运营/审计数据库。
- Ed25519 私钥只存在于受控发行端，App 仅内置公钥。
- 设备申请使用 Android Keystore P-256 和 SHA256withECDSA DER 签名；最终授权 Token 使用 Ed25519 对 JCS canonical payload 按 `YANJI-PRO-LICENSE-V1\0` 域分隔签名。
- 设备安全级别由客户端报告，不是 Android Key Attestation 远程硬件证明。
- App 永久 `ai_access` Token 只授予 App 内 Native Gate 管理的 LiteRT 模型访问，不授予 Fork 源代码商业集成、OEM、白标或对外再分发权；源代码商业使用必须依据独立书面许可。
- 离线永久授权不能远程即时撤销；本地状态 superseded 只影响运营记录，不能关闭未更新、长期离线的旧版本。
- 有能力修改/重打包 APK 的攻击者仍可能绕过客户端门禁。
- 正式发行前还必须完成生产 Key Ring 与来源核验、私钥离线备份/恢复演练、源码权属和第三方许可复核、正式 Android 签名与 Find N2 本地验收。不得把这些事项写成自动测试已通过。
