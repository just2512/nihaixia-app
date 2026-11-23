# Yanji Pro Offline License Issuer

本工具用于私域订单人工核验及离线签发，不处理支付。

## 环境

Python 3.12+，依赖版本见 \`requirements.txt\`。

\`\`\`bash
python -m pip install -r tool/license_issuer/requirements.txt
\`\`\`

## 生成发行者密钥

\`\`\`bash
python tool/license_issuer/issuer.py keygen --key-id issuer-2026-01
\`\`\`

工具要求输入两次口令（至少 12 个 UTF-8 字节），默认将加密 PKCS#8 私钥和公钥写到仓库外：

- \`~/.yanji-license-issuer/keys/issuer-2026-01.private.pem\`
- \`~/.yanji-license-issuer/keys/issuer-2026-01.public.pem\`

raw Ed25519 公钥（32 字节 Base64URL 无填充）会显示在终端，后续需加入 App 的受信任 Key Ring。**私钥不得进入仓库、APK、CI、工单、聊天记录或日志。** 离线加密备份必须与订单数据库分开保存。Windows 操作员还需通过系统 ACL 保护目录。

## 人工核单与签发

用户将完整的 \`YANJIR1\` 设备申请码通过微信文本复制给运营方。人工核对收款后执行：

\`\`\`bash
python tool/license_issuer/issuer.py issue \\
  --request-file request.txt \\
  --order-id YJ-20261123-0001 \\
  --key-id issuer-2026-01 \\
  --private-key ~/.yanji-license-issuer/keys/issuer-2026-01.private.pem \\
  --payment-confirmed
\`\`\`

工具验证 P-256 设备私钥持有证明和设备公钥指纹，再用 Ed25519 签发 \`YANJI1\` 永久授权。签发时会要求输入私钥口令。默认将授权文本输出到终端；可增加 \`--out /secure/path/license.txt\` 写入文件。

\`--payment-confirmed\` 是操作员人工收款确认，不会查询微信、支付宝、银行或支付服务商。

## 订单记录

默认 SQLite 数据库：\`~/.yanji-license-issuer/data/orders.sqlite3\`。

只记录订单号、request ID、商品、授权 ID、设备指纹、签发者 Key ID、签发时间和签名令牌；不记录买家姓名、手机号、微信 ID、聊天记录或付款截图。

- 同一订单号、同一 request ID、同一设备返回原授权令牌。
- 同一订单号用于另一设备请求会被拒绝。
- 同一 request ID 不能重复绑定另一个订单。

\`list --db PATH\` 可以列出技术授权记录。数据库本身也应设置操作系统访问权限并加密备份。

## 安全边界

- Ed25519 私钥只存在于运营方签发工具，App 仅内置公钥。
- 设备申请使用 Android Keystore P-256 和 SHA256withECDSA DER 签名。
- 签名证明内容完整性及签发者密钥持有，不证明付款事实。
- 离线永久授权不能被远程撤销，也不能阻止有能力重打包 APK 的攻击者绕过客户端校验。
