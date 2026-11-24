import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/licensing/feature_authorizer.dart';
import 'package:nihaisha_app/licensing/license_verifier.dart';
import 'package:nihaisha_app/services/entitlement_service.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/theme/yanji_status_semantics.dart';
import 'package:nihaisha_app/widgets/license_status_presentation.dart';

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('专业版授权状态的视觉语义映射', () {
    test('中性、成功、警告与危险状态按授权状态和失败原因分类', () {
      final cases = <({
        EntitlementSnapshot snapshot,
        YanjiStatusTone tone,
        String label,
        IconData icon,
      })>[
        (
          snapshot: EntitlementSnapshot(
            status: EntitlementServiceStatus.checking,
          ),
          tone: YanjiStatusTone.neutral,
          label: '检查中',
          icon: Icons.hourglass_top_outlined,
        ),
        (
          snapshot: EntitlementSnapshot(
            status: EntitlementServiceStatus.active,
          ),
          tone: YanjiStatusTone.success,
          label: '已激活',
          icon: Icons.verified_outlined,
        ),
        (
          snapshot: EntitlementSnapshot(
            status: EntitlementServiceStatus.unlicensed,
          ),
          tone: YanjiStatusTone.neutral,
          label: '未授权',
          icon: Icons.lock_outline,
        ),
        (
          snapshot: EntitlementSnapshot(
            status: EntitlementServiceStatus.temporarilyUnavailable,
            failureReason: FeatureAuthorizationFailureReason.providerError,
          ),
          tone: YanjiStatusTone.neutral,
          label: '暂不可用',
          icon: Icons.sync_problem_outlined,
        ),
        for (final reason in <FeatureAuthorizationFailureReason>[
          FeatureAuthorizationFailureReason.keyMissing,
          FeatureAuthorizationFailureReason.keyInvalidated,
          FeatureAuthorizationFailureReason.deviceMismatch,
          FeatureAuthorizationFailureReason.storeCorrupt,
        ])
          (
            snapshot: EntitlementSnapshot(
              status: EntitlementServiceStatus.invalid,
              failureReason: reason,
            ),
            tone: YanjiStatusTone.warning,
            label: '待恢复',
            icon: Icons.warning_amber_outlined,
          ),
        for (final reason in <FeatureAuthorizationFailureReason>[
          FeatureAuthorizationFailureReason.signatureInvalid,
          FeatureAuthorizationFailureReason.issuerUnknown,
          FeatureAuthorizationFailureReason.issuerCompromised,
          FeatureAuthorizationFailureReason.licenseRevoked,
        ])
          (
            snapshot: EntitlementSnapshot(
              status: EntitlementServiceStatus.invalid,
              failureReason: reason,
            ),
            tone: YanjiStatusTone.danger,
            label: '授权异常',
            icon: Icons.error_outline,
          ),
        (
          snapshot: EntitlementSnapshot(
            status: EntitlementServiceStatus.invalid,
            failureReason: FeatureAuthorizationFailureReason.wrongProduct,
          ),
          tone: YanjiStatusTone.warning,
          label: '需处理',
          icon: Icons.warning_amber_outlined,
        ),
      ];

      for (final item in cases) {
        final presentation = licenseStatusPresentation(item.snapshot);
        expect(presentation.tone, item.tone);
        expect(presentation.label, item.label);
        expect(presentation.icon, item.icon);
      }
    });

    test('令牌替换失败优先读取验签结果区分信任错误', () {
      expect(
        licenseTokenReplacementTone(
          const LicenseTokenReplacementResult(
            status: LicenseTokenReplacementStatus.temporarilyUnavailable,
          ),
        ),
        YanjiStatusTone.warning,
      );
      expect(
        licenseTokenReplacementTone(
          const LicenseTokenReplacementResult(
            status: LicenseTokenReplacementStatus.rejected,
            failureReason: FeatureAuthorizationFailureReason.keyMissing,
          ),
        ),
        YanjiStatusTone.warning,
      );
      expect(
        licenseTokenReplacementTone(
          const LicenseTokenReplacementResult(
            status: LicenseTokenReplacementStatus.rejected,
            verification: LicenseVerificationResult(
              LicenseVerificationStatus.invalidSignature,
            ),
          ),
        ),
        YanjiStatusTone.danger,
      );
      expect(
        licenseTokenReplacementTone(
          const LicenseTokenReplacementResult(
            status: LicenseTokenReplacementStatus.rejected,
            verification: LicenseVerificationResult(
              LicenseVerificationStatus.unknownIssuer,
            ),
          ),
        ),
        YanjiStatusTone.danger,
      );
    });

    test('所有状态徽标在浅深主题的语义容器上满足普通文字 AA', () {
      final cases = <EntitlementSnapshot>[
        EntitlementSnapshot(status: EntitlementServiceStatus.checking),
        EntitlementSnapshot(status: EntitlementServiceStatus.active),
        EntitlementSnapshot(status: EntitlementServiceStatus.unlicensed),
        EntitlementSnapshot(
          status: EntitlementServiceStatus.temporarilyUnavailable,
        ),
        EntitlementSnapshot(
          status: EntitlementServiceStatus.invalid,
          failureReason: FeatureAuthorizationFailureReason.keyMissing,
        ),
        EntitlementSnapshot(
          status: EntitlementServiceStatus.invalid,
          failureReason: FeatureAuthorizationFailureReason.signatureInvalid,
        ),
      ];

      for (final colors in <AppColors>[AppColors.light, AppColors.dark]) {
        for (final snapshot in cases) {
          final presentation = licenseStatusPresentation(snapshot);
          final pair = yanjiStatusChipColors(presentation.tone, colors);
          expect(
            _contrast(pair.foreground, pair.background),
            greaterThanOrEqualTo(4.5),
            reason: '${presentation.label} 标签正文必须达到 4.5:1。',
          );
          expect(
            _contrast(
              licenseStatusToneForeground(presentation.tone, colors),
              colors.surface,
            ),
            greaterThanOrEqualTo(4.5),
            reason: '${presentation.label} 状态图标前景必须可辨。',
          );
        }
      }
    });
  });
}
