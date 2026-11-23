# Yanji Pro Offline License Issuer

本工具用于私域订单人工核验及离线签发，不处理支付。协议固定在 docs/pro-edition-license-protocol.md；Python 签发器与 Dart 验证器共用 test/fixtures/pro-license-test-vectors.json 中的跨语言测试向量。该向量中的密钥和订单均为测试数据，绝不能用于生产。

## 环境

Python 3.12+，依赖版本见 requirements.txt。

    python -m pip install -r tool/license_issuer/requirements.txt

## 生成发行者密钥

    python tool/license_issuer/issuer.py keygen --key-id issuer-2026-01

工具要求输入两次口令（至少 12 个 UTF-8 字节），默认写入仓库外：

- ~/.yanji-license-issuer/keys/issuer-2026-01.private.pem
- ~/.yanji-license-issuer/keys/issuer-2026-01.public.pem
- ~/.yanji-license-issuer/keys/issuer-keyring.json

私钥为口令加密的 PKCS#8 PEM。keyring.json 记录 Key ID、raw Ed25519 公钥和状态，里面没有私钥。签发时工具会检查指定私钥与该 Key ID 对应的公钥是否匹配；错误私钥、错误 Key ID 或 retired/compromised Key 都不能签发。

raw Ed25519 公钥（32 字节 Base64URL 无填充）会在终端显示，后续由受控代码变更加入 App 内置 Key Ring。生产 App 可包含多个 Key ID；retired Key 只验证旧凭证，不可签发；compromised Key 必须在后续 App 版本中拒绝。

**密钥恢复要求：** 正式销售前至少保留两份口令加密离线备份，位于不同介质/地点；备份口令独立保管。必须实际演练一次恢复，核对恢复公钥与 Key ID 的对应关系，并用共享测试向量执行签名/验签。私钥和订单数据库必须分开备份。不要将私钥、口令放入仓库、APK、CI、工单、聊天记录或日志。

Windows 操作员还需通过系统 ACL 保护 key 目录；POSIX 权限设置只是附加保护，不替代离线备份和访问控制。

## 首次签发

用户将完整 YANJIR1 设备申请码通过微信文本复制给运营方。人工核对收款后执行：

    python tool/license_issuer/issuer.py issue \
      --request-file request.txt \
      --order-id YJ-20261123-0001 \
      --key-id issuer-2026-01 \
      --private-key ~/.yanji-license-issuer/keys/issuer-2026-01.private.pem \
      --payment-confirmed

签发器验证申请内的完整 P-256 SPKI 公钥、指纹、请求 nonce、request_id 和 ECDSA 私钥持有证明；随后计算完整申请令牌的 SHA-256，并将 request_id、nonce、hash、设备指纹保存在运营方订单数据库用于唯一约束、幂等和审计。最终客户端 Token 仅含 request_id 与设备公钥指纹，不含 nonce/hash/设备安全级别，不要求客户端持久化或匹配 pending request。Token 按协议修订 1 签发，Feature 固定为 `ai_advanced` 与 `contextual_assistant`。

--payment-confirmed 是操作员人工收款确认，不会查询微信、支付宝、银行或支付服务商。签发器不采集客户姓名、手机号、微信 ID 或付款截图。

## 换机 / 重签

同一订单更换设备时，必须产生一份新的设备申请，并显式使用：

    python tool/license_issuer/issuer.py issue \
      --request-file new-device-request.txt \
      --order-id YJ-20261123-0001 \
      --key-id issuer-2026-01 \
      --private-key ~/.yanji-license-issuer/keys/issuer-2026-01.private.pem \
      --payment-confirmed \
      --reissue \
      --reason "Customer reinstalled after clearing application data"

工具在一个 SQLite 事务中将旧签发记录标记为 superseded，追加新 license_id，并记录替代关系和审计事件。旧令牌不会因本地数据库状态变化就从已离线运行的旧 App 自动失效；只有更新版本内置的 license_id denylist 才能在更新后的 App 上拒绝它。

同一 order_id + request_id + request_sha256 重复提交时幂等返回原活动令牌；同一 request_id 不能用于其他订单。request_nonce 和 request_sha256 只在发行端订单数据库留存，用于唯一约束和审计，不写入最终 Token。存在旧签发记录时，新的请求必须显式 --reissue 并提供 --reason。

免费重签次数/收费规则没有被签发器硬编码，必须由产品条款另行确定。正式销售前未完成这项产品决策，不得收费销售。

## 订单与审计数据库

默认位置：~/.yanji-license-issuer/data/orders.sqlite3。

数据库采用订单 1:N 授权记录结构：

- orders：订单编号、商品、创建时间、核款状态、重签次数。
- issued_licenses：每次授权的 license_id、request_id、request_sha256、设备指纹、Key ID、签发时间、令牌、当前状态和替代关系。
- issuer_audit_events：issue/reissue/迁移事件及脱敏细节。

不记录姓名、手机号、微信 ID、付款截图或聊天内容。审计明细不写入私钥、口令或完整 token。授权 token 本身需要保存在订单库用于幂等补发，故数据库同样必须设置操作系统权限并加密备份。

列出订单和历史签发：

    python tool/license_issuer/issuer.py list

## 安全边界

- Ed25519 私钥只存在于运营方签发工具，App 仅内置公钥。
- 设备申请使用 Android Keystore P-256 和 SHA256withECDSA DER 签名；最终授权 Token 用 Ed25519 对 JCS canonical payload 按 `YANJI-PRO-LICENSE-V1\\0` 域分隔签名。
- 设备安全级别由客户端报告，不是 Android Key Attestation 远程硬件证明。
- 签名证明凭证完整性及发行者密钥持有，不证明买家已付款。
- 离线永久授权不能远程即时撤销；本地状态 superseded 只影响运营记录。
- 本地 denylist 只能随 App 版本更新生效，不能关闭未更新、长期离线的旧版本。
- 有能力修改/重打包 APK 的攻击者仍可能绕过客户端门禁。

- 授权 Payload 使用 `protocol_revision`，不是 `product_revision`；revision 1 仅能签发 `ai_advanced` 和 `contextual_assistant`。
- 客户端用 Token 中的 `device_public_key_sha256` 与当前 Keystore SPKI 指纹匹配；不校验本地 pending request，也不将发行端 nonce/hash 当作授权条件。
- App 端授权存储为 `noBackupFilesDir/yanji_license/active_license.token` 单 Token 原子文件；不创建 Android 授权 SQLite 库，主数据库保持 schema v7。Issuer 主机端订单 SQLite 是另一套仅供签发运营和审计的数据库。
