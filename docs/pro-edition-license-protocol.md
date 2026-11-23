# 研纪专业版永久授权技术规范

版本：1.1（评审稿）  
商品 ID：yanji_pro_lifetime  
Dart package：nihaisha_app  
Android applicationId：com.nihaisha.nihaisha_app  
发行模型：人工核单、离线签发、客户端离线验签  
状态：**协议评审稿；不得据此开展商业发行或收款**

## 1. 已核实的仓库基线与设计约束

截至本规范编写时，仓库实际配置如下：

| 项目 | 已核实值 |
|---|---|
| Android applicationId / namespace | com.nihaisha.nihaisha_app |
| Dart package name | nihaisha_app |
| Flutter 版本标记 | 2.0.0+8048 |
| 当前主数据 SQLite | nihaisha.db |
| 当前主数据 SQLite schema version | **7** |
| Android 备份配置 | 同时配置 fullBackupContent 与 dataExtractionRules |
| 当前备份排除项 | ai_models/、TRACE 文件；尚未有授权库 |

主数据库含书签、用户设置、命盘、助手对话/消息、问诊任务等个人数据。Android Auto Backup 规则按文件系统 domain/path 包含或排除，不提供 SQLite 单表/单行过滤。因此，**不能把授权记录混入 nihaisha.db，再声称仅排除授权表**。

### 第一项架构决策：授权库独立且不参与备份

Android 授权记录使用独立数据库文件，存放在原生 Context.noBackupFilesDir 下，例如 yanji_license.db。该目录由 Android 自动排除备份；设备私钥由 Android Keystore 管理，不进入数据库或备份。

- 原有 nihaisha.db 保持 v7，不做本期 v7→v8 迁移，不触碰用户数据表。
- 授权库有独立 schema version（初版为 1），失败时只影响专业版，不能阻止免费版启动。
- 不要用主数据库的 license_status、SharedPreferences 或可编辑 Feature 列表决定授权。
- 清除应用数据、卸载、系统搬家或克隆后，只要原 Keystore 私钥不可用，就重新申请设备授权。不能假设 Keystore 私钥可被系统备份/迁移。

该设计避免“授权凭证被备份恢复，但设备私钥没有恢复”的半激活状态，同时保留原主库的系统备份和用户数据恢复能力。

## 2. 算法与信任边界

### 2.1 发行者签名

- 算法固定为 **Ed25519**，私钥只存在运营方签发环境。
- 公钥为 raw 32 字节，App 内置多个 issuer_key_id → public_key 项，支持轮换。
- 签名长度固定 64 字节。
- Key 状态区分 active（可签发、可验证）、retired（不可签发、仍可验证）、compromised（新版本拒绝该 Key 的全部凭证）。
- 不能因为“旧公钥要保留”就保留已泄露密钥的信任。密钥泄露后，更新版本必须拒绝该 Key，并按订单证据为真实客户换发新 Key 凭证；旧版本和长期离线设备无法被即时远程撤销。

Dart 使用 cryptography 2.9.0 的 Ed25519。该库包含跨平台实现，平台没有原生实现时会回退纯 Dart；官方 cryptography_flutter 的 Ed25519 原生加速目前列为 Apple 平台能力，不应把它当作 Android Ed25519 的前置依赖。Android 首发仍须通过当前 Flutter/Android CI 与 Find N2 真机耗时验证。客户端验签只处理很短的授权载荷，不需要把发行者私钥带进 App。

### 2.2 设备密钥

- 算法固定为 Android Keystore **ECDSA P-256 / secp256r1 + SHA-256**。
- 私钥不可导出；公钥以完整 X.509 SubjectPublicKeyInfo DER 传给运营方，不能只发指纹。
- 设备指纹：Base64URL_NoPadding(SHA-256(SPKI_DER))。
- ECDSA 签名采用 ASN.1 DER 编码。
- KeyInfo 可报告 SOFTWARE、TRUSTED_ENVIRONMENT、STRONGBOX 或 UNKNOWN。该值只作为签发记录里的**客户端报告元数据**，不是硬件远程证明，不能仅凭令牌字段证明密钥确实位于 TEE/StrongBox。
- 无 TEE/StrongBox 的设备不因硬件等级被拒绝；若平台能建立软件 Keystore 密钥，则允许继续激活，同时明确标记保护级别较低。完全无法创建/使用密钥时，专业版保持未激活，免费功能继续运行。
- 第一版设备绑定只面向 Android；其他平台必须提供各自安全存储实现，不能静默退化为可复制的随机设备 ID。

## 3. 设备授权申请：YANJIR1

申请码是**完整文本令牌**，微信私聊以复制/粘贴为主，二维码/相册识别为辅助。摄像头扫码不能成为唯一激活方式。

令牌格式：

    YANJIR1.<base64url(request_utf8_json)>.<base64url(ecdsa_p256_der_signature)>

Base64URL 使用 URL-safe 字符集且不带填充。签名输入为 ASCII 字节 YANJIR1. + 原始 payload 段。验签端必须使用原始段，不得解析后重序列化 JSON 再验签。

申请 JSON 字段：

| 字段 | 规则 |
|---|---|
| schema_version | 固定整数 1 |
| request_id | UUID，单次申请唯一 |
| request_nonce | 32 字节 CSPRNG 随机数，Base64URL 无填充 |
| app_id | 精确等于 com.nihaisha.nihaisha_app |
| product_id | yanji_pro_lifetime |
| issued_at | UTC ISO-8601，仅用于审计，不能作为授权期限 |
| device_public_key_spki | 完整 P-256 SPKI DER，Base64URL 无填充 |
| device_key_sha256 | SPKI DER 的 SHA-256 指纹 |
| device_key_security_level | SOFTWARE / TRUSTED_ENVIRONMENT / STRONGBOX / UNKNOWN 的报告值 |

App 使用该 Keystore 私钥对原始申请 payload 签名。运营方校验 schema、包名、商品 ID、nonce 长度、UUID、SPKI 曲线、指纹重算及 ECDSA 持有证明。请求中包含完整公钥；仅提供 SHA-256 指纹不足以让签发端验证申请签名。

申请 nonce 由设备端生成，不是服务器在线挑战；它用于唯一申请、凭证关联和审计，不声称具备在线防重放能力。重复签发由运营方订单数据库的唯一约束负责阻止。

## 4. 永久授权凭证：YANJI1

    YANJI1.<base64url(payload_utf8_json)>.<base64url(ed25519_signature)>

保留三段文本格式，避免增加二次封装；复制、粘贴、文件导入和二维码均传输完全相同的令牌。签名输入为 ASCII 字节 YANJI1. + 原始 payload Base64URL 段。验签必须对原始段验签，之后才解析 JSON。JSON 生成端固定 UTF-8、无 BOM、紧凑分隔符、键名排序；这些是签发输出规范，不是验签时的重序列化步骤。

授权 payload 至少包含：

| 字段 | 规则 |
|---|---|
| schema_version | 固定 1 |
| license_id | 唯一授权 ID |
| order_id | 运营方订单编号，不包含客户姓名/手机号 |
| product_id / product_revision | 商品 ID 和客户端明确支持的修订号 |
| app_id | 固定 Android applicationId |
| perpetual | 必须为 true；不依赖客户端时间判断到期 |
| features | 签名覆盖的功能 ID |
| device_key_sha256 | 绑定设备公钥指纹 |
| request_id | 对应设备申请 ID |
| request_nonce | 回显对应申请随机数 |
| request_sha256 | 对完整 YANJIR1 紧凑令牌字节计算的 SHA-256 |
| issuer_key_id | App 内置 Key Ring 可识别的签发 Key ID |
| issued_at | UTC 审计时间，不是到期时间 |

加入 request_id、request_nonce、request_sha256 后，一份签发凭证只对应一份确切申请；客户端必须与本机保存的 pending request 比较。重装后本地 pending request 和 Keystore 密钥均不可用，旧凭证不能在新设备密钥上激活。

### Feature 前向兼容

- 格式错误、重复 Feature ID、类型错误必须拒绝。
- **未知但格式合法的 Feature ID 忽略，不因此拒绝整份凭证。**
- 只授予当前 App 明确识别的 Feature ID；未知 ID 永远不映射成现有权限。
- 若凭证只有未知 Feature，状态为 unknown_feature_only，不授予专业权益；若已知/未知混合，授予已知项并记录 valid_with_unknown_features。
- 客户端只接受明确支持的 product_revision；不能因版本号更高就自动放行。

## 5. 激活、启动校验与状态

### 首次激活

1. 读取本地 pending request，验证申请格式和当前 Keystore 公钥指纹。
2. 对授权令牌限长解析，选择 Key ID，验证 Ed25519 签名。
3. 签名通过后校验 schema、app_id、product_id、product_revision、license_id 黑名单、device fingerprint。
4. 比较 request_id、request_nonce、request_sha256 与本地 pending request。
5. 原生端生成新的本地随机 challenge，以 Keystore 私钥签名，并用当前完整公钥验证；验证失败即拒绝激活。
6. 在独立 no-backup 授权库保存原始 signed token、pending request 关联、签发元数据和诊断状态；不能仅保存一个 valid=true。

### 后续启动

- 不需要每次都重新生成并走完整用户激活流程。
- 每次启动重新验证发行者签名、商品/应用/Feature 和本机授权记录；从 Keystore 取得当前公钥，重算指纹并与凭证匹配，同时检查私钥 alias 可用。若 Keystore 报 key missing / permanently invalidated，状态降级为免费版。
- 不信任数据库中的 status 字段。它只能帮助售后排查，不能单独授予权益。
- 启动初始化不得抛出异常阻塞 App；任何授权库损坏、验签异常或 Keystore 错误均进入免费版状态。
- EntitlementService 使用可监听状态对象；激活成功立即通知页面，不要求重启。

建议统一状态枚举：

| 状态 | 含义/处理 |
|---|---|
| unlicensed | 无授权，免费版 |
| loading | 正在检查；不得短暂错误显示已解锁 |
| valid | 全部当前支持权益通过 |
| valid_with_unknown_features | 已知权益通过，未知项忽略 |
| unknown_feature_only | 签名有效但没有当前 App 支持的 Feature |
| key_missing | Keystore alias 缺失，提示重新申请 |
| key_invalidated | 私钥永久失效，提示重新申请 |
| signature_invalid | 签名错误，拒绝 |
| app_mismatch | 包名不匹配，拒绝 |
| product_mismatch | 商品或修订号不受支持 |
| issuer_unknown / issuer_compromised | Key ID 未知/已泄露禁用 |
| device_mismatch | 当前设备指纹不匹配 |
| request_mismatch | 申请 ID/nonce/hash 不匹配 |
| revoked_in_updated_app | 新版本本地黑名单命中 |
| store_corrupt | 授权库损坏，免费版并提示恢复/重签 |

## 6. 重签、订单记录与离线撤销边界

运营方数据库必须采用 **订单 1:N 授权签发记录**，不能用 order_id 主键把一单永久限制为一张凭证。

- orders 保存订单主记录与人工核款状态。
- issued_licenses 保存每次签发的 license_id、request_id、request_sha256、设备指纹、Key ID、签发时间、原令牌、状态和替代关系。
- issuer_audit_events 记录 issue、reissue、refund/status-change 等审计事件；不得记录私钥、口令、姓名、手机号、微信号或付款截图。
- 相同 order_id + request_id + request hash 重复操作，幂等返回原令牌。
- 同一订单换设备必须显式使用 reissue 操作并记录原因；旧签发记录标记 superseded，新签发生成新的 license_id。订单可关联多次签发历史。
- 免费重签次数/收费规则目前**未形成产品决策**。签发器不得擅自硬编码次数或收费；正式销售前必须将免费次数、人工核验要求和退款规则写入用户协议。

**重要限制：** 标记旧授权为 superseded 不会立即关闭已离线设备上的旧版本。可在后续 App 版本中内置经过签名的 license_id denylist，对更新到该版本的设备生效；这属于“随版本更新的本地黑名单”，不是远程撤销。第一期签发数据库预留 license status，不能对外宣称可实时撤销。

## 7. 私钥管理、隐私和商业合规

### 私钥流程

- 私钥使用口令加密 PKCS#8，存仓库外、受控运营电脑；不得进入 Git、CI、APK、客服聊天或日志。
- 至少两份加密离线备份，存放于不同介质/地点；备份口令独立保管。
- 正式销售前必须演练恢复：从离线备份恢复指定 Key ID，验证公钥一致，并使用固定测试向量完成签名/验签。
- App Key Ring 支持多个 Key ID；旧 Key 可退休但仍验证。泄露 Key 必须在更新版中标记 compromised，旧客户按订单核验并迁移至新 Key。
- 订单数据库与私钥备份分离；审计日志只记录操作类型、时间、订单/授权 ID、request hash 和原因，不记录签名私钥、口令或完整授权 token。

### 隐私

设备公钥、指纹、request_id 和 nonce 由 App 本地生成，不自动上传服务端。用户通过微信把申请码发给运营方时，这些字段会随申请码传出，属于可关联的设备标识数据；隐私政策应说明用途、保存范围、售后使用、保留期限和删除渠道。不能笼统声明“设备指纹不上传”。

### 商业发行阻塞项

在 Fork 文件权属证据和第三方来源许可没有审查结论之前，不得对外收费或发布收费 APK。还必须完成隐私政策、用户协议、永久授权边界、免费重签次数/退款条款、发票税务处理，以及目标分发渠道的支付政策核对。软件许可清单通过不等于版权确权。

## 8. 验收门槛

- 合法固定测试向量在 Python 签发器和 Dart 验签器均通过；两端读取同一 JSON fixture。
- 对 payload、signature、features、app_id、device fingerprint、request_id、nonce、request hash 任意改动均拒绝。
- 完整申请包含 P-256 SPKI，错误私钥/签名拒绝；issuer private key 与指定 Key ID 对应公钥不匹配时，签发器拒绝签发。
- 同一设备请求重复签发幂等；同订单换设备必须显式 reissue；订单历史保留所有签发记录。
- 原样复制凭证到第二台设备拒绝；本机 Keystore key 丢失/失效时进入 key_missing/key_invalidated。
- 系统时间前后调整不影响永久授权。
- 清除应用数据、卸载重装、系统搬家/克隆及备份恢复都不得误报已激活；原 nihaisha.db 用户数据恢复与授权库不恢复应能并存。
- Android 设备报告 SOFTWARE/TEE/StrongBox/UNKNOWN 级别；没有 TEE/StrongBox 时可按策略降级运行，不得虚报硬件证明。
- App 启动遇授权库损坏、缺 Key 或验签异常时仍进入免费版，不崩溃；激活后监听状态立即刷新。
- FeatureGate.require 接在专业版执行器/能力调度边界，失败抛出明确 FeatureNotEntitledException，UI 统一处理；底层确定性引擎保持纯计算，不被权限判断污染。
- FeatureGate 只能提高正常客户端调用路径的访问控制，不能防止用户补丁/重打包；不以过度混淆代替真正的业务边界。

## 9. 分批落地顺序

1. **协议/测试向量**：固定本规范、共享合法/非法 fixture、Python/Dart 共用验收。
2. **签发工具**：订单 1:N、审计、重签、密钥 Key ID 配对校验、私钥恢复演练流程。
3. **Dart 验证库**：Ed25519、Feature 前向兼容、request binding、denylist 接口、状态结果。
4. **Android Keystore**：P-256 生成、SPKI 导出、P-256 PoP、自检、KeyInfo 安全等级。
5. **授权 no-backup 存储**：独立库 schema v1、异常恢复、保持主数据库 v7 不变。
6. **EntitlementService / FeatureGate**：异步初始化、监听更新、执行器边界拦截。
7. **专业版激活 UI**：申请码复制、授权码粘贴、相册导入/扫码、状态提示。
8. **Find N2 真机与发行审计**：覆盖升级、离线重启、备份/恢复、重签、设备密钥丢失、费用/隐私/版权审核。

在第 1 项协议评审通过前，当前 PR #416 的代码只作为 Draft 原型；不得合并、打生产发行包或签发真实用户授权。
