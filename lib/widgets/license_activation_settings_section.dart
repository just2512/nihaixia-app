import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../licensing/feature_authorizer.dart';
import '../licensing/license_platform.dart';
import '../services/entitlement_service.dart';
import '../services/license_activation_request_builder.dart';
import '../theme/app_tokens.dart';
import '../utils/fold_aware_routes.dart';

class LicenseActivationSettingsSection extends StatefulWidget {
  const LicenseActivationSettingsSection({
    required this.entitlementService,
    super.key,
  });

  final EntitlementService entitlementService;

  @override
  State<LicenseActivationSettingsSection> createState() =>
      _LicenseActivationSettingsSectionState();
}

class _LicenseActivationSettingsSectionState
    extends State<LicenseActivationSettingsSection> {
  final _tokenController = TextEditingController();
  bool _busy = false;
  String? _requestCode;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _generateRequest() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final request = await LicenseActivationRequestBuilder.create(
        platform: MethodChannelLicensePlatform(),
      );
      if (!mounted) return;
      setState(() {
        _requestCode = request.code;
        _message = request.strongBoxFallback
            ? '设备密钥已创建并使用 TEE 回退；此状态仅为本机报告，不是远程硬件证明。'
            : '设备申请已生成。设备级别仅供运营核对，不构成远程硬件证明。';
        _messageIsError = false;
      });
    } on LicensePlatformFailure catch (error) {
      if (!mounted) return;
      setState(() {
        _message = _platformFailureLabel(error);
        _messageIsError = true;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _message = '设备申请生成失败。请检查设备密钥状态后重试。';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyRequest() async {
    final value = _requestCode;
    if (value == null) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    setState(() {
      _message = '设备申请码已复制，可发送给授权发行方。';
      _messageIsError = false;
    });
  }

  Future<void> _installToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _message = '请粘贴完整的 YANJI1 授权令牌。';
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      var result = await widget.entitlementService.replaceToken(
        token: token,
        allowFeatureReduction: false,
      );
      if (result.status == LicenseTokenReplacementStatus.confirmationRequired) {
        if (!mounted) return;
        final confirmed = await _confirmFeatureReduction(result.lostFeatureIds);
        if (!mounted) return;
        if (confirmed != true) {
          setState(() {
            _message = '已取消替换，当前授权保持不变。';
            _messageIsError = false;
          });
          return;
        }
        result = await widget.entitlementService.replaceToken(
          token: token,
          allowFeatureReduction: true,
        );
      }

      if (!mounted) return;
      if (result.installed) {
        _tokenController.clear();
        setState(() {
          _message = '授权令牌已验证并安装。';
          _messageIsError = false;
        });
      } else {
        setState(() {
          _message = _replacementFailureLabel(result);
          _messageIsError = true;
        });
      }
    } on Object {
      if (!mounted) return;
      setState(() {
        _message = '授权替换未完成。旧授权不会因本次失败而被主动删除。';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmFeatureReduction(Set<String> lostFeatureIds) {
    final labels = lostFeatureIds.map(_featureLabel).toList()..sort();
    return showFoldAwareDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认替换较低权益的授权'),
        content: Text('新令牌将失去以下权益：\n'
            '${labels.join('、')}\n\n'
            '确认后才会替换当前授权。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('保留当前授权'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认替换'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.entitlementService,
      builder: (context, _) {
        final snapshot = widget.entitlementService.snapshot;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('研纪专业版'),
              subtitle: Text(_statusLabel(snapshot)),
            ),
            if (snapshot.aiAccess)
              const Padding(
                padding: EdgeInsets.only(left: 56, bottom: AppSpacing.sm),
                child: Text('已授予：全部 Native LiteRT 模型访问'),
              ),
              if (snapshot.licenseId != null)
                Padding(
                  padding: const EdgeInsets.only(left: 56, bottom: AppSpacing.sm),
                  child: Text('授权编号：${snapshot.licenseId}'),
                ),
            ],
            if (snapshot.failureReason != null)
              Padding(
                padding: const EdgeInsets.only(left: 56, bottom: AppSpacing.sm),
                child: Text(
                  _reasonLabel(snapshot.failureReason),
                  style: TextStyle(color: colors.error),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _generateRequest,
                icon: const Icon(Icons.key_outlined),
                label: const Text('生成设备激活申请'),
              ),
            ),
            if (_requestCode != null) ...[
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                _requestCode!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _copyRequest,
                  icon: const Icon(Icons.copy),
                  label: const Text('复制申请码'),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _tokenController,
              enabled: !_busy,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '授权令牌',
                hintText: '粘贴发行方返回的完整 YANJI1 令牌',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _busy ? null : _installToken,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('验证并安装授权'),
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: LinearProgressIndicator(),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: _messageIsError ? colors.error : colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  static String _statusLabel(EntitlementSnapshot snapshot) {
    switch (snapshot.status) {
      case EntitlementServiceStatus.checking:
        return '正在检查本机授权状态…';
      case EntitlementServiceStatus.active:
        return '已激活 · 永久授权';
      case EntitlementServiceStatus.unlicensed:
        return '未激活 · 免费功能可正常使用';
      case EntitlementServiceStatus.temporarilyUnavailable:
        return '暂时无法确认授权 · 免费功能继续可用';
      case EntitlementServiceStatus.invalid:
        return '授权无效或设备状态不匹配 · 专业能力不会开放';
    }
  }

  static String _featureLabel(String id) {
    if (id == 'ai_access') return '全部本地 AI 模型访问';
    switch (id) {
      case 'ai_advanced':
        return 'AI 跨工具自动编排';
      case 'contextual_assistant':
        return '情境问 AI';
      default:
        return id;
    }
  }

  static String _reasonLabel(FeatureAuthorizationFailureReason? reason) {
    switch (reason) {
      case null:
        return '';
      case FeatureAuthorizationFailureReason.initializationTimeout:
        return '授权检查超时。请稍后重试；不会将超时当作永久未授权。';
      case FeatureAuthorizationFailureReason.unlicensed:
        return '当前没有已安装的授权令牌。';
      case FeatureAuthorizationFailureReason.featureNotGranted:
        return '当前令牌未授予所需专业权益。';
      case FeatureAuthorizationFailureReason.storeCorrupt:
        return '本机授权文件损坏。请使用发行方重新提供的完整令牌。';
      case FeatureAuthorizationFailureReason.storageUnavailable:
        return '本机授权存储暂时不可用。';
      case FeatureAuthorizationFailureReason.issuerUnknown:
        return '令牌签发者不在本版本信任 Key Ring 中。';
      case FeatureAuthorizationFailureReason.signatureInvalid:
        return '令牌签名无效。';
      case FeatureAuthorizationFailureReason.unsupportedRevision:
        return '令牌协议修订版本不受支持。';
      case FeatureAuthorizationFailureReason.deviceMismatch:
        return '令牌绑定的设备与当前设备不匹配。';
      case FeatureAuthorizationFailureReason.keyMissing:
        return '当前设备密钥不存在。已有令牌不会自动创建替代密钥。';
      case FeatureAuthorizationFailureReason.keyInvalidated:
        return '设备私钥不可用或挑战校验不一致。';
      case FeatureAuthorizationFailureReason.keystoreUnavailable:
        return 'Android Keystore 暂时不可用。';
      case FeatureAuthorizationFailureReason.providerError:
        return '授权平台暂时不可用，请稍后重试。';
      case FeatureAuthorizationFailureReason.licenseRevoked:
        return '该授权已被当前客户端信任策略撤销。';
      case FeatureAuthorizationFailureReason.issuerCompromised:
        return '发行者密钥已被标记为受损，令牌不能使用。';
      case FeatureAuthorizationFailureReason.invalidTokenFormat:
        return '令牌格式不正确。';
      case FeatureAuthorizationFailureReason.wrongApplication:
        return '令牌不属于当前应用。';
      case FeatureAuthorizationFailureReason.wrongProduct:
        return '令牌不属于研纪专业版商品。';
    }
  }

  static String _platformFailureLabel(LicensePlatformFailure error) {
    switch (error.code) {
      case 'keyAlreadyExists':
      case 'KEY_ALREADY_EXISTS':
        return '检测到已有设备密钥，未覆盖或重建。请重新生成申请。';
      case 'keyMissing':
      case 'KEY_MISSING':
        return '设备密钥缺失，且无法创建。请检查 Android Keystore 状态。';
      case 'keystoreUnavailable':
      case 'KEYSTORE_UNAVAILABLE':
        return 'Android Keystore 暂时不可用。';
      case 'keyInvalidated':
      case 'KEY_INVALIDATED':
        return '现有设备密钥已失效，未自动重建。需按换机/重签流程处理。';
      default:
        return '设备激活申请生成失败：${error.code}。';
    }
  }

  static String _replacementFailureLabel(
    LicenseTokenReplacementResult result,
  ) {
    if (result.status == LicenseTokenReplacementStatus.temporarilyUnavailable) {
      return '授权验证暂时不可用。旧令牌未被删除，请稍后重试。';
    }
    if (result.status == LicenseTokenReplacementStatus.storageFailure) {
      return '授权文件写入或重读失败。请检查存储状态；服务会尝试恢复旧令牌。';
    }
    if (result.status == LicenseTokenReplacementStatus.busy) {
      return '已有授权替换操作正在执行，请勿重复提交。';
    }
    final reason = _reasonLabel(result.failureReason);
    final verification = result.verification?.status.name;
    return '授权令牌未安装：${reason.isEmpty ? verification ?? '验证拒绝' : reason}';
  }
}
