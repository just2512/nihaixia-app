import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/theme/yanji_palette.dart';

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('研纪品牌色板', () {
    test('基础品牌色、功能灰与文字链接红保持独立语义', () {
      expect(YanjiPalette.coldWhite, const Color(0xFFEBECEE));
      expect(YanjiPalette.silverGray, const Color(0xFFBCBBBF));
      expect(YanjiPalette.brandRed, const Color(0xFFD71019));
      expect(YanjiPalette.functionalGray, const Color(0xFF808087));
      expect(YanjiPalette.redOnLight, const Color(0xFFB30D15));

      expect(AppColors.light.primary, YanjiPalette.brandRed);
      expect(AppColors.light.background, YanjiPalette.coldWhite);
      expect(AppColors.light.outline, YanjiPalette.functionalGray);
      expect(AppColors.light.link, YanjiPalette.redOnLight);
      expect(AppColors.dark.link, YanjiPalette.darkLink);
      expect(AppColors.light.warning, YanjiPalette.warningLight);
      expect(AppColors.light.onWarning, YanjiPalette.white);
      expect(AppColors.dark.warning, YanjiPalette.warningDark);
      expect(AppColors.dark.onWarning, YanjiPalette.onWarningDark);
    });

    test('link 与主文字在浅深主题内容表面均达到 4.5:1', () {
      final light = AppColors.light;
      for (final surface in [
        light.background,
        light.surface,
        light.surfaceContainerLow,
        light.surfaceContainerHighest,
      ]) {
        expect(
          _contrastRatio(light.onSurface, surface),
          greaterThanOrEqualTo(4.5),
          reason: '浅色主题主文字必须在每种内容表面上保持可读。',
        );
        expect(
          _contrastRatio(light.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
          reason: '浅色主题辅助文字必须在每种内容表面上保持可读。',
        );
        expect(
          _contrastRatio(light.link, surface),
          greaterThanOrEqualTo(4.5),
          reason: '浅色主题链接文字必须使用独立的高对比度红色。',
        );
      }
      expect(_contrastRatio(light.onPrimary, light.primary), greaterThanOrEqualTo(4.5));
      expect(
        _contrastRatio(light.onPrimaryContainer, light.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(_contrastRatio(light.onWarning, light.warning), greaterThanOrEqualTo(4.5));

      final dark = AppColors.dark;
      for (final surface in [
        dark.background,
        dark.surface,
        dark.surfaceContainerLow,
        dark.surfaceContainerHighest,
      ]) {
        expect(
          _contrastRatio(dark.onSurface, surface),
          greaterThanOrEqualTo(4.5),
          reason: '深色主题主文字必须在每种内容表面上保持可读。',
        );
        expect(
          _contrastRatio(dark.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
          reason: '深色主题辅助文字必须在每种内容表面上保持可读。',
        );
        expect(
          _contrastRatio(dark.link, surface),
          greaterThanOrEqualTo(4.5),
          reason: '深色主题链接文字必须使用独立的高对比度颜色。',
        );
      }
      expect(_contrastRatio(dark.onPrimary, dark.primary), greaterThanOrEqualTo(4.5));
      expect(
        _contrastRatio(dark.onPrimaryContainer, dark.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(_contrastRatio(dark.onWarning, dark.warning), greaterThanOrEqualTo(4.5));
    });

    test('新增语义字段参与 copyWith 与 lerp', () {
      final copy = AppColors.light.copyWith(
        link: const Color(0xFF006400),
        onWarning: const Color(0xFF101010),
      );
      expect(copy.link, const Color(0xFF006400));
      expect(copy.onWarning, const Color(0xFF101010));

      final halfway = AppColors.light.lerp(AppColors.dark, 0.5);
      expect(halfway.link, Color.lerp(AppColors.light.link, AppColors.dark.link, 0.5));
      expect(
        halfway.onWarning,
        Color.lerp(AppColors.light.onWarning, AppColors.dark.onWarning, 0.5),
      );
    });
  });

  group('AppColors Material ColorScheme', () {
    test('light scheme binds explicit brand and surface roles', () {
      final tokens = AppColors.light;
      final scheme = AppColors.colorSchemeFor(Brightness.light);

      expect(scheme.brightness, Brightness.light);
      expect(scheme.primary, tokens.primary);
      expect(scheme.onPrimary, tokens.onPrimary);
      expect(scheme.primaryContainer, tokens.primaryContainer);
      expect(scheme.onPrimaryContainer, tokens.onPrimaryContainer);
      expect(scheme.surface, tokens.surface);
      expect(scheme.surfaceContainerLowest, YanjiPalette.white);
      expect(scheme.surfaceContainerLow, tokens.surfaceContainerLow);
      expect(scheme.surfaceContainerHighest, tokens.surfaceContainerHighest);
      expect(scheme.onSurface, tokens.onSurface);
      expect(scheme.onSurfaceVariant, tokens.onSurfaceVariant);
      expect(scheme.outline, tokens.outline);
      expect(scheme.outlineVariant, tokens.outlineVariant);
      expect(scheme.error, tokens.danger);
      expect(scheme.onError, tokens.onDanger);
      expect(scheme.errorContainer, YanjiPalette.lightErrorContainer);
      expect(scheme.primaryFixed, YanjiPalette.primaryFixed);
      expect(scheme.onPrimaryFixed, YanjiPalette.onPrimaryFixed);
      expect(scheme.inverseSurface, YanjiPalette.lightInverseSurface);
      expect(scheme.inversePrimary, YanjiPalette.lightInversePrimary);
      expect(scheme.surfaceTint, YanjiPalette.transparent);
    });

    test('dark scheme binds explicit brand and surface roles', () {
      final tokens = AppColors.dark;
      final scheme = AppColors.colorSchemeFor(Brightness.dark);

      expect(scheme.brightness, Brightness.dark);
      expect(scheme.primary, tokens.primary);
      expect(scheme.onPrimary, tokens.onPrimary);
      expect(scheme.primaryContainer, tokens.primaryContainer);
      expect(scheme.onPrimaryContainer, tokens.onPrimaryContainer);
      expect(scheme.surface, tokens.surface);
      expect(scheme.surfaceContainerLowest, YanjiPalette.darkBackground);
      expect(scheme.surfaceContainerLow, tokens.surfaceContainerLow);
      expect(scheme.surfaceContainerHighest, tokens.surfaceContainerHighest);
      expect(scheme.onSurface, tokens.onSurface);
      expect(scheme.onSurfaceVariant, tokens.onSurfaceVariant);
      expect(scheme.outline, tokens.outline);
      expect(scheme.outlineVariant, tokens.outlineVariant);
      expect(scheme.error, tokens.danger);
      expect(scheme.onError, tokens.onDanger);
      expect(scheme.errorContainer, YanjiPalette.darkErrorContainer);
      expect(scheme.primaryFixed, YanjiPalette.primaryFixed);
      expect(scheme.onPrimaryFixed, YanjiPalette.onPrimaryFixed);
      expect(scheme.inverseSurface, YanjiPalette.darkInverseSurface);
      expect(scheme.inversePrimary, YanjiPalette.darkInversePrimary);
      expect(scheme.surfaceTint, YanjiPalette.transparent);
    });
  });
}
