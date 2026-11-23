# 研纪专业版永久授权协议规范（第一期）

版本：1.0  
商品：\`yanji_pro_lifetime\`  
应用 ID：\`com.nihaisha.nihaisha_app\`  
发行方式：线下私域销售、人工核单、本地签发、App 离线验签  
状态：批次 1 协议/签发工具规范；不是商业发行许可，也不代表可以立即对外销售 APK。

## 1. 商品范围

第一期仅定义一次性永久解锁商品，不包含订阅、自动续费、云端账户、虚拟币或远程设备管理。

| Feature ID | 专业版能力 |
|---|---|
| \`ai_advanced\` | 专业版 AI 助手能力 |
| \`contextual_assistant\` | 跨页面情境提问及上下文能力 |
| \`advanced_learning\` | 高级学习和资料整理能力 |
| \`advanced_export\` | 专业资料导出能力 |

永久授权的定义：凭证没有到期时间，不依赖客户端时钟判断有效性；授权仅覆盖签名凭证中列出的软件功能，不自动覆盖未来独立商品或未列入凭证的新增模块。云端服务、人工服务和外部 API 不属于永久离线承诺。用户个人笔记、会话和资料导出不应被免费版权限门槛锁死。

正式销售前，功能矩阵必须与代码执行入口和内容权利来源逐项核对。知识库正文、古籍、讲稿、医案、第三方模型权重、SDK、插件及外部 API 不因软件授权而自动成为可商业再授权内容。此前登记的权属证明和来源许可待办仍是发行前置门槛。

## 2. 密码学算法和密钥边界

### 2.1 发行者密钥

- 算法：Ed25519（RFC 8032）。
- 公钥：raw 32 字节，Base64URL 无填充编码，编译进 App 的受信任 Key Ring。
- 私钥：口令加密的 PKCS#8 PEM，只保存在运营方受控设备，绝不进入仓库、APK、日志或 CI。
- 签名：64 字节 Ed25519。
- Key ID：例如 \`issuer-2026-01\`，用于轮换和审计。
- 轮换：旧公钥必须保留，以验证旧的永久授权。密钥泄露时需要单独的换签/恢复计划，不能直接删掉旧公钥导致合法用户失效。

Ed25519 用于发行者离线签名，不要求 Android Keystore 支持 Ed25519。

### 2.2 设备密钥

- 算法：ECDSA P-256 / secp256r1。
- Android Keystore 生成密钥对，私钥不可导出；公钥导出为 X.509 SubjectPublicKeyInfo DER。
- 设备指纹：\`Base64URL_NoPadding(SHA-256(SPKI_DER))\`，解码固定 32 字节。
- 设备申请签名：\`SHA256withECDSA\`，签名编码 ASN.1 DER。
- 启动时原生端生成随机 nonce，用私钥签名并用公钥验证。该自检证明私钥当前可用，不证明它必定位于硬件中。

Android API 31+ 读取 \`KeyInfo.getSecurityLevel()\` 区分 SOFTWARE、TRUSTED_ENVIRONMENT 和 STRONGBOX；较低 API 使用可用的兼容属性并如实记录 UNKNOWN/软件级别。不得把软件密钥宣传成硬件保护。Find N2 真机记录必须保留实际安全级别。硬件级别不参与商品权益判断。

## 3. 紧凑令牌格式

\`\`\`text
YANJI1.<base64url(payload_utf8_json)>.<base64url(ed25519_signature)>
YANJIR1.<base64url(request_utf8_json)>.<base64url(ecdsa_p256_der_signature)>
\`\`\`

Base64URL 采用 RFC 4648 URL-safe 字符集且不带 \`=\` 填充。拒绝内部空格、换行、多余分隔段、非法字符及超长输入。用户界面可以对剪贴板输入去除首尾空白，但不能对令牌主体作 Unicode 规范化或重新序列化。

签名采用域分离：

- 授权：ASCII 字节 \`YANJI1.\` + 原始 payload Base64URL 段。
- 设备申请：ASCII 字节 \`YANJIR1.\` + 原始 request Base64URL 段。

签名覆盖协议前缀和完整 Base64URL 段。验签必须使用原始段，不能解析 JSON 后重新序列化再验签。JSON 生成端使用 UTF-8、无 BOM、紧凑分隔符和按键名排序；这是稳定输出约定，不是验签依据。

限制：授权令牌总长度 16 KiB，payload 12 KiB；设备申请 payload 8 KiB；Ed25519 签名必须恰好 64 字节。签发端拒绝重复 JSON 键。任一步骤失败均拒绝，不允许宽松恢复。

## 4. 设备授权申请（YANJIR1）

App 生成随机 32 字节 nonce 和 UUID request_id，构造 JSON：

| 字段 | 类型 | 规则 |
|---|---|---|
| \`schema_version\` | integer | 固定 1 |
| \`request_id\` | string | 唯一 UUID |
| \`nonce\` | string | 32 字节随机数的 Base64URL 无填充编码 |
| \`app_id\` | string | \`com.nihaisha.nihaisha_app\` |
| \`product_id\` | string | \`yanji_pro_lifetime\` |
| \`issued_at\` | string | ISO-8601 UTC，仅供审计 |
| \`device_public_key_spki\` | string | P-256 SPKI DER 的 Base64URL 无填充编码 |
| \`device_key_sha256\` | string | SPKI DER 的 SHA-256 Base64URL 指纹 |

App 使用设备私钥对 \`YANJIR1.<payload_segment>\` 签名。用户通过微信复制完整文本给运营方；二维码、相册识别和摄像头扫码只是后续 UI 输入方式，不是协议依赖。

签发器必须验证：令牌结构、schema、应用 ID、商品 ID、UUID、nonce 长度、UTC 时间字段、SPKI 格式、曲线确为 P-256、重新计算的指纹及 ECDSA 签名。签发前还必须人工核对付款状态。

nonce 是设备端随机生成，不是服务端在线挑战。它主要用于请求唯一性和审计；防止重复签发依赖订单数据库唯一约束。首次激活和后续 App 启动仍需本地执行 Keystore 私钥在位自检。

## 5. 永久授权 payload（YANJI1）

| 字段 | 类型 | 规则 |
|---|---|---|
| \`schema_version\` | integer | 固定 1 |
| \`license_id\` | string | 签发器生成的唯一授权编号 |
| \`order_id\` | string | 私域订单编号，不含买家身份信息 |
| \`product_id\` | string | \`yanji_pro_lifetime\` |
| \`product_revision\` | integer | 当前 1 |
| \`app_id\` | string | \`com.nihaisha.nihaisha_app\` |
| \`perpetual\` | boolean | 必须 true |
| \`features\` | array<string> | 签名覆盖的 Feature ID，不重复 |
| \`device_key_sha256\` | string | 设备 SPKI DER 的 SHA-256 Base64URL 指纹 |
| \`issued_at\` | string | ISO-8601 UTC，审计字段，不作到期判断 |
| \`issuer_key_id\` | string | App Key Ring 中的受信任公钥 ID |

签发端只签发本期固定 Feature allowlist。客户端只解锁自己明确实现的 Feature ID；未知 ID 不映射为其他权限。签名通过不等于客户端已实现全部商品权益，业务门禁仍需独立验收。

## 6. App 验证顺序

1. 对令牌总长度、段数、前缀和 Base64URL 字符集限长解析。
2. 只解析必要的 \`issuer_key_id\` 来选择公钥，此时 payload 仍是不可信数据。
3. 从 App 编译的 Key Ring 取 32 字节 Ed25519 公钥。
4. 对精确的 \`YANJI1.<payload_segment>\` 原始 ASCII 字节验签。
5. 验签成功后完整解析 schema、商品修订号、永久标记、字段长度和 Feature 列表。
6. 精确比较 \`app_id\` 和当前应用包名。
7. 原生 Keystore 导出 SPKI，重新计算指纹并执行私钥在位自检，与授权指纹比较。
8. 只有全部通过才构造内存态权益对象。数据库的 \`license_status\` 仅作诊断，不是授权依据。

任一步骤失败均 fail-closed，不授予专业权益。客户端应对用户显示简明错误，内部诊断不得记录设备私钥或个人对话。

## 7. 离线、备份和设备迁移

- 授权凭证保存在 SQLite v8 的 \`app_license\` 表，保留原始签名令牌。
- 每次启动都重新验签，绝不信任本地 bool、SharedPreferences、SQLite 状态字段或可编辑的功能列表。
- 正常覆盖升级应保留 SQLite 和 Keystore 密钥。
- 卸载或清除应用数据后，Keystore 密钥可能被系统删除；重装后必须检测密钥缺失/指纹变化并提示凭订单号申请免费重签。
- 不导出设备私钥，不将其放入备份或授权码。
- 恢复数据库但原 Keystore 密钥不存在时，不能沿用旧凭证。
- 完全离线的已签发凭证无法远程强制撤销；授权转移是运营方重新签发，不等于远程清除旧设备。

## 8. 运营方本地签发工具

目录：\`tool/license_issuer/\`；运行环境 Python 3.12+；依赖版本固定在 \`requirements.txt\`。

生成发行者密钥：

\`\`\`bash
python tool/license_issuer/issuer.py keygen --key-id issuer-2026-01
\`\`\`

默认写入仓库外 \`~/.yanji-license-issuer/keys/\`，私钥为口令加密的 PKCS#8 PEM。工具输出 raw 公钥 Base64URL，后续需人工纳入 App Key Ring。私钥必须离线加密备份，并与订单数据库分开保存；不得放入 GitHub、CI 或 APK。

人工核单并签发：

\`\`\`bash
python tool/license_issuer/issuer.py issue \\
  --request-file request.txt \\
  --order-id YJ-20261123-0001 \\
  --key-id issuer-2026-01 \\
  --private-key ~/.yanji-license-issuer/keys/issuer-2026-01.private.pem \\
  --payment-confirmed
\`\`\`

\`--payment-confirmed\` 是操作员确认收款的人工声明，不会向微信、支付宝或银行查询交易。签发器将技术订单记录保存在 \`~/.yanji-license-issuer/data/orders.sqlite3\`，不采集姓名、手机号、微信 ID 或付款截图。

同一 order_id + request_id + 设备指纹重复提交时返回原令牌；同一订单绑定另一设备或同一申请绑定另一订单均拒绝。订单数据库需设置操作系统权限并加密备份。

## 9. 安全边界和错误处理

格式错误、未知 Key ID、签名错误、schema 错误、包名/商品/设备不匹配、Keystore 私钥自检失败，全部拒绝授权。未知 Feature 不授予，不可映射成更高权限。

离线永久授权不能在线撤销；客户端权限门禁不能阻止有能力修改/重打包 APK 的攻击者绕过本地校验。签名证明凭证完整性及发行者密钥持有，不证明买家已付款；付款核验由运营方完成。

## 10. 批次 1 交付边界

本批次交付：授权数据模型、Ed25519 紧凑令牌验签器、Python 离线签发器、P-256 设备申请签名验证、SQLite 订单幂等记录、Dart/Python 协议测试。

本批次不实现：Android Keystore 桥接、安全级别探测、SQLite v8 授权表、EntitlementService、FeatureGate、启动接线、专业版 UI、剪贴板/相册/二维码交互及生产发行者公钥配置。它们由后续批次完成。正式发行前仍须完成商业授权、内容权属/来源审核、密钥备份及 Find N2 真机验收。
