import 'package:flutter/material.dart';

import '../licensing/license_model.dart';
import '../licensing/license_verifier.dart';
import '../services/entitlement_service.dart';
import '../theme/app_colors.dart';
import '../theme/yanji_status_semantics.dart';

/// User-visible presentation only. This mapping never grants or denies access.
@immutable
class LicenseStatusPresentation {
  const LicenseStatusPresentation({
    required this.tone,
    required this.icon,
    required this.label,
  });

  final YanjiStatusTone tone;
  final IconData icon;
  final String label;
}

LicenseStatusPresentation licenseStatusPresentation(
  EntitlementSnapshot snapshot,
) {
  switch (snapshot.status) {
    case EntitlementServiceStatus.checking:
      return const LicenseStatusPresentation(
        tone: YanjiStatusTone.neutral,
        icon: Icons.hourglass_top_outlined,
        label: '检查中',
      );
    case EntitlementServiceStatus.active:
      return const LicenseStatusPresentation(
        tone: YanjiStatusTone.success,
        icon: Icons.verified_outlined,
        label: '已激活',
      );
    case EntitlementServiceStatus.unlicensed:
      return const LicenseStatusPresentation(
        tone: YanjiStatusTone.neutral,
        icon: Icons.lock_outline,
        label: '未授权',
      );
    case EntitlementServiceStatus.temporarilyUnavailable:
      return const LicenseStatusPresentation(
        tone: YanjiStatusTone.neutral,
        icon: Icons.sync_problem_outlined,
        label: '暂不可用',
      );
    case EntitlementServiceStatus.invalid:
      final reason = snapshot.failureReason;
      if (_isRecoverableLicenseReason(reason)) {
        return const LicenseStatusPresentation(
          tone: YanjiStatusTone.warning,
          icon: Icons.warning_amber_outlined,
          label: '待恢复',
        );
      }
      if (_isTrustFailure(reason)) {
        return const LicenseStatusPresentation(
          tone: YanjiStatusTone.danger,
          icon: Icons.error_outline,
          label: '授权异常',
        );
      }
      return const LicenseStatusPresentation(
        tone: YanjiStatusTone.warning,
        icon: Icons.warning_amber_outlined,
        label: '需处理',
      );
  }
}

bool _isRecoverableLicenseReason(LicenseFailureReason? reason) {
  return switch (reason) {
    LicenseFailureReason.keyMissing ||
    LicenseFailureReason.keyInvalidated ||
    LicenseFailureReason.deviceMismatch ||
    LicenseFailureReason.storeCorrupt =>
      true,
    _ => false,
  };
}

bool _isTrustFailure(LicenseFailureReason? reason) {
  return switch (reason) {
    LicenseFailureReason.signatureInvalid ||
    LicenseFailureReason.issuerUnknown ||
    LicenseFailureReason.issuerCompromised ||
    LicenseFailureReason.licenseRevoked =>
      true,
    _ => false,
  };
}

YanjiStatusTone licenseTokenReplacementTone(
  LicenseTokenReplacementResult result,
) {
  if (result.status == LicenseTokenReplacementStatus.temporarilyUnavailable ||
      result.status == LicenseTokenReplacementStatus.storageFailure ||
      result.status == LicenseTokenReplacementStatus.busy) {
    return YanjiStatusTone.warning;
  }

  switch (result.failureReason) {
    case LicenseFailureReason.signatureInvalid:
    case LicenseFailureReason.issuerUnknown:
    case LicenseFailureReason.issuerCompromised:
    case LicenseFailureReason.licenseRevoked:
      return YanjiStatusTone.danger;
    default:
      break;
  }

  return switch (result.verification?.status) {
    LicenseVerificationStatus.invalidSignature ||
    LicenseVerificationStatus.invalidIssuerKey ||
    LicenseVerificationStatus.unknownIssuer ||
    LicenseVerificationStatus.issuerCompromised ||
    LicenseVerificationStatus.revoked =>
      YanjiStatusTone.danger,
    _ => YanjiStatusTone.warning,
  };
}

Color licenseStatusToneForeground(
  YanjiStatusTone tone,
  AppColors colors,
) {
  return switch (tone) {
    YanjiStatusTone.success => colors.success,
    YanjiStatusTone.warning => colors.warning,
    YanjiStatusTone.danger => colors.danger,
    YanjiStatusTone.neutral => colors.onSurfaceVariant,
  };
}
