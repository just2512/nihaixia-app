import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/theme/yanji_palette.dart';
import 'package:nihaisha_app/screens/yunqi_charts.dart';

double _linearize(double channel) {
  return channel <= 0.04045
      ? channel / 12.92
      : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
}

double _relativeLuminance(Color color) {
  return 0.2126 * _linearize(color.r) +
      0.7152 * _linearize(color.g) +
      0.0722 * _linearize(color.b);
}

/// WCAG relative-luminance contrast ratio. Values are never rounded.
double _contrast(Color foreground, Color background) {
  final a = _relativeLuminance(foreground);
  final b = _relativeLuminance(background);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

Color _composite(Color overlay, Color background, double opacity) {
  return Color.alphaBlend(overlay.withValues(alpha: opacity), background);
}

void main() {
  final lightSurfaces = <String, Color>{
    'Scaffold coldWhite': YanjiPalette.coldWhite,
    'Card white': YanjiPalette.white,
    'Text-field fill white': YanjiPalette.white,
    'surfaceContainerLow': YanjiPalette.lightSurfaceContainerLow,
    'surfaceContainer': YanjiPalette.lightSurfaceContainer,
    'surfaceContainerHigh': YanjiPalette.lightSurfaceContainerHigh,
    'surfaceContainerHighest': YanjiPalette.lightSurfaceContainerHighest,
  };

  final darkSurfaces = <String, Color>{
    'Scaffold darkBackground': YanjiPalette.darkBackground,
    'surfaceContainerLow': YanjiPalette.darkSurfaceContainerLow,
    'Card darkSurface': YanjiPalette.darkSurface,
    'surfaceContainerHigh': YanjiPalette.darkSurfaceContainerHigh,
    'surfaceContainerHighest': YanjiPalette.darkSurfaceContainer,
  };

  group('研纪 WCAG 2.2 对比度门禁（未四舍五入）', () {
    test('浅色主题文字、链接和风险语义在全部基础表面达到 4.5:1', () {
      final colors = AppColors.light;
      for (final entry in lightSurfaces.entries) {
        final background = entry.value;
        expect(
          _contrast(colors.onSurface, background),
          greaterThanOrEqualTo(4.5),
          reason: '主文字 / ${entry.key}',
        );
        expect(
          _contrast(colors.onSurfaceVariant, background),
          greaterThanOrEqualTo(4.5),
          reason: '次级文字 / ${entry.key}',
        );
        expect(
          _contrast(colors.link, background),
          greaterThanOrEqualTo(4.5),
          reason: '链接文字 / ${entry.key}',
        );
        expect(
          _contrast(colors.danger, background),
          greaterThanOrEqualTo(4.5),
          reason: '风险/错误文字 / ${entry.key}',
        );
        expect(
          _contrast(colors.warning, background),
          greaterThanOrEqualTo(4.5),
          reason: '警告文字 / ${entry.key}',
        );
      }

      expect(_contrast(colors.onPrimary, colors.primary), greaterThanOrEqualTo(4.5));
      expect(_contrast(colors.onWarning, colors.warning), greaterThanOrEqualTo(4.5));
      expect(_contrast(colors.onDanger, colors.danger), greaterThanOrEqualTo(4.5));
      expect(
        _contrast(colors.onPrimaryContainer, colors.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('浅色主题功能图形和控件边界在全部基础表面达到内部阈值 3.3:1', () {
      final colors = AppColors.light;
      for (final entry in lightSurfaces.entries) {
        expect(
          _contrast(colors.outline, entry.value),
          greaterThanOrEqualTo(3.3),
          reason: '功能边界 / ${entry.key}',
        );
        expect(
          _contrast(colors.primary, entry.value),
          greaterThanOrEqualTo(3.0),
          reason: '品牌图形 / ${entry.key}',
        );
      }
      expect(
        _contrast(YanjiPalette.silverGray, YanjiPalette.coldWhite),
        lessThan(3.0),
        reason: '银灰明确作为装饰分割线，不得用于控件边界。',
      );
    });

    test('深色主题文字、链接和风险语义在全部基础表面达到 4.5:1', () {
      final colors = AppColors.dark;
      for (final entry in darkSurfaces.entries) {
        final background = entry.value;
        expect(
          _contrast(colors.onSurface, background),
          greaterThanOrEqualTo(4.5),
          reason: '主文字 / ${entry.key}',
        );
        expect(
          _contrast(colors.onSurfaceVariant, background),
          greaterThanOrEqualTo(4.5),
          reason: '次级文字 / ${entry.key}',
        );
        expect(
          _contrast(colors.link, background),
          greaterThanOrEqualTo(4.5),
          reason: '链接文字 / ${entry.key}',
        );
        expect(
          _contrast(colors.danger, background),
          greaterThanOrEqualTo(4.5),
          reason: '风险/错误文字 / ${entry.key}',
        );
        expect(
          _contrast(colors.warning, background),
          greaterThanOrEqualTo(4.5),
          reason: '警告文字 / ${entry.key}',
        );
      }

      expect(_contrast(colors.onPrimary, colors.primary), greaterThanOrEqualTo(4.5));
      expect(_contrast(colors.onWarning, colors.warning), greaterThanOrEqualTo(4.5));
      expect(_contrast(colors.onDanger, colors.danger), greaterThanOrEqualTo(4.5));
      expect(
        _contrast(colors.onPrimaryContainer, colors.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('深色主题功能图形和控件边界在全部基础表面达到内部阈值 3.3:1', () {
      final colors = AppColors.dark;
      for (final entry in darkSurfaces.entries) {
        expect(
          _contrast(colors.outline, entry.value),
          greaterThanOrEqualTo(3.3),
          reason: '功能边界 / ${entry.key}',
        );
        expect(
          _contrast(colors.primary, entry.value),
          greaterThanOrEqualTo(3.0),
          reason: '品牌图形 / ${entry.key}',
        );
      }
    });

    test('悬停与按下状态先合成透明状态层，再验证前景对比度', () {
      // Light state layers use brandRed at 8% hover and 12% pressed.
      // In these tinted states, use primary/onSurface/link; do not reuse
      // functionalGray or secondary text on a brand-tinted container.
      for (final entry in lightSurfaces.entries) {
        for (final opacity in [0.08, 0.12]) {
          final composite = _composite(
            YanjiPalette.brandRed,
            entry.value,
            opacity,
          );
          expect(
            _contrast(YanjiPalette.charcoal, composite),
            greaterThanOrEqualTo(4.5),
            reason: '浅色状态层主文字 / ${entry.key} / $opacity',
          );
          expect(
            _contrast(YanjiPalette.redOnLight, composite),
            greaterThanOrEqualTo(4.5),
            reason: '浅色状态层链接 / ${entry.key} / $opacity',
          );
          expect(
            _contrast(YanjiPalette.brandRed, composite),
            greaterThanOrEqualTo(3.0),
            reason: '浅色状态层选中图形 / ${entry.key} / $opacity',
          );
        }
      }

      // Dark state layers use darkPrimary; all normal text, links and
      // functional outlines must remain distinguishable after compositing.
      for (final entry in darkSurfaces.entries) {
        for (final opacity in [0.08, 0.12]) {
          final composite = _composite(
            YanjiPalette.darkPrimary,
            entry.value,
            opacity,
          );
          expect(
            _contrast(YanjiPalette.darkOnSurface, composite),
            greaterThanOrEqualTo(4.5),
            reason: '深色状态层主文字 / ${entry.key} / $opacity',
          );
          expect(
            _contrast(YanjiPalette.darkTextSecondary, composite),
            greaterThanOrEqualTo(4.5),
            reason: '深色状态层次级文字 / ${entry.key} / $opacity',
          );
          expect(
            _contrast(YanjiPalette.darkLink, composite),
            greaterThanOrEqualTo(4.5),
            reason: '深色状态层链接 / ${entry.key} / $opacity',
          );
          expect(
            _contrast(YanjiPalette.darkOutline, composite),
            greaterThanOrEqualTo(3.3),
            reason: '深色状态层控件边界 / ${entry.key} / $opacity',
          );
        }
      }
    });

    test('Material 3 ColorScheme 显式定义所有组件会读取的角色', () {
      final light = AppColors.colorSchemeFor(Brightness.light);
      final dark = AppColors.colorSchemeFor(Brightness.dark);

      expect(light.surface, YanjiPalette.white);
      expect(dark.surface, YanjiPalette.darkSurface);
      expect(light.primary, YanjiPalette.brandRed);
      expect(light.onPrimary, YanjiPalette.white);
      expect(light.secondary, YanjiPalette.lightSecondary);
      expect(light.onSecondary, YanjiPalette.white);
      expect(light.secondaryContainer, YanjiPalette.lightSecondaryContainer);
      expect(light.tertiaryContainer, YanjiPalette.lightTertiaryContainer);
      expect(light.errorContainer, YanjiPalette.lightErrorContainer);
      expect(light.onErrorContainer, YanjiPalette.lightOnErrorContainer);
      expect(light.surfaceContainerLowest, YanjiPalette.white);
      expect(light.surfaceContainer, YanjiPalette.lightSurfaceContainer);
      expect(light.surfaceContainerHigh, YanjiPalette.lightSurfaceContainerHigh);
      expect(light.surfaceContainerHighest, YanjiPalette.lightSurfaceContainerHighest);
      expect(light.inverseSurface, YanjiPalette.lightInverseSurface);
      expect(light.onInverseSurface, YanjiPalette.lightOnInverseSurface);
      expect(light.inversePrimary, YanjiPalette.lightInversePrimary);
      expect(light.surfaceTint, YanjiPalette.transparent);

      expect(dark.primary, YanjiPalette.darkPrimary);
      expect(dark.onPrimary, YanjiPalette.darkOnPrimary);
      expect(dark.secondary, YanjiPalette.darkSecondary);
      expect(dark.onSecondary, YanjiPalette.darkOnSecondary);
      expect(dark.secondaryContainer, YanjiPalette.darkSecondaryContainer);
      expect(dark.tertiaryContainer, YanjiPalette.darkTertiaryContainer);
      expect(dark.errorContainer, YanjiPalette.darkErrorContainer);
      expect(dark.onErrorContainer, YanjiPalette.darkOnErrorContainer);
      expect(dark.surfaceContainerLowest, YanjiPalette.darkBackground);
      expect(dark.surfaceContainerHigh, YanjiPalette.darkSurfaceContainerHigh);
      expect(dark.surfaceContainerHighest, YanjiPalette.darkSurfaceContainer);
      expect(dark.inverseSurface, YanjiPalette.darkInverseSurface);
      expect(dark.onInverseSurface, YanjiPalette.darkOnInverseSurface);
      expect(dark.inversePrimary, YanjiPalette.darkInversePrimary);
      expect(dark.surfaceTint, YanjiPalette.transparent);

      // M3 fixed roles are stable across brightness.
      expect(light.primaryFixed, dark.primaryFixed);
      expect(light.secondaryFixed, dark.secondaryFixed);
      expect(light.tertiaryFixed, dark.tertiaryFixed);
    });
    test('语义容器和 Material 3 Fixed 角色使用正确的前景配对', () {
      final light = AppColors.light;
      final lightScheme = AppColors.colorSchemeFor(Brightness.light);

      expect(
        _contrast(light.warning, light.warningContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(light.danger, lightScheme.errorContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(lightScheme.onErrorContainer, lightScheme.errorContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(lightScheme.onSecondaryContainer, lightScheme.secondaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(lightScheme.onSecondary, lightScheme.secondary),
        greaterThanOrEqualTo(4.5),
        reason: '浅色 secondary 实心表面不得使用低对比度功能灰。',
      );
      expect(
        _contrast(lightScheme.onTertiary, lightScheme.tertiary),
        greaterThanOrEqualTo(4.5),
        reason: '浅色 tertiary 实心表面必须具备普通文字对比度。',
      );
      expect(
        _contrast(lightScheme.onTertiaryContainer, lightScheme.tertiaryContainer),
        greaterThanOrEqualTo(4.5),
      );

      final dark = AppColors.dark;
      final darkScheme = AppColors.colorSchemeFor(Brightness.dark);

      expect(
        _contrast(dark.warning, dark.warningContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(darkScheme.onErrorContainer, darkScheme.errorContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(dark.danger, darkScheme.errorContainer),
        lessThan(4.5),
        reason: '深色 dangerDark 不得直接作为 darkErrorContainer 的正文前景。',
      );
      expect(
        _contrast(darkScheme.onSecondaryContainer, darkScheme.secondaryContainer),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(darkScheme.onSecondary, darkScheme.secondary),
        greaterThanOrEqualTo(4.5),
        reason: '深色 secondary 实心表面必须具备普通文字对比度。',
      );
      expect(
        _contrast(darkScheme.onTertiary, darkScheme.tertiary),
        greaterThanOrEqualTo(4.5),
        reason: '深色 tertiary 实心表面必须具备普通文字对比度。',
      );
      expect(
        _contrast(darkScheme.onTertiaryContainer, darkScheme.tertiaryContainer),
        greaterThanOrEqualTo(4.5),
      );

      for (final pair in [
        (lightScheme.onPrimaryFixed, lightScheme.primaryFixed),
        (lightScheme.onPrimaryFixedVariant, lightScheme.primaryFixedDim),
        (lightScheme.onSecondaryFixed, lightScheme.secondaryFixed),
        (lightScheme.onSecondaryFixedVariant, lightScheme.secondaryFixedDim),
        (lightScheme.onTertiaryFixed, lightScheme.tertiaryFixed),
        (lightScheme.onTertiaryFixedVariant, lightScheme.tertiaryFixedDim),
        (darkScheme.onPrimaryFixed, darkScheme.primaryFixed),
        (darkScheme.onPrimaryFixedVariant, darkScheme.primaryFixedDim),
        (darkScheme.onSecondaryFixed, darkScheme.secondaryFixed),
        (darkScheme.onSecondaryFixedVariant, darkScheme.secondaryFixedDim),
        (darkScheme.onTertiaryFixed, darkScheme.tertiaryFixed),
        (darkScheme.onTertiaryFixedVariant, darkScheme.tertiaryFixedDim),
      ]) {
        expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      }
    });

  });
  group('五运六气五行领域色 Token', () {
    const lightExpected = <String, Color>{
      '木': YanjiPalette.fiveElementWoodLight,
      '火': YanjiPalette.fiveElementFireLight,
      '土': YanjiPalette.fiveElementEarthLight,
      '金': YanjiPalette.fiveElementMetalLight,
      '水': YanjiPalette.fiveElementWaterLight,
    };
    const darkExpected = <String, Color>{
      '木': YanjiPalette.fiveElementWoodDark,
      '火': YanjiPalette.fiveElementFireDark,
      '土': YanjiPalette.fiveElementEarthDark,
      '金': YanjiPalette.fiveElementMetalDark,
      '水': YanjiPalette.fiveElementWaterDark,
    };

    test('浅深主题保持既有五行映射与未知值兜底', () {
      for (final entry in lightExpected.entries) {
        expect(wxColorOf(entry.key, Brightness.light), entry.value);
      }
      for (final entry in darkExpected.entries) {
        expect(wxColorOf(entry.key, Brightness.dark), entry.value);
      }
      expect(
        wxColorOf('未知', Brightness.light),
        YanjiPalette.fiveElementFallbackLight,
      );
      expect(
        wxColorOf('未知', Brightness.dark),
        YanjiPalette.fiveElementFallbackDark,
      );
    });

    test('五行标签前景对实际领域底色满足普通文字 AA', () {
      for (final colors in [lightExpected, darkExpected]) {
        for (final background in colors.values) {
          final foreground = chartLabelColorOn(background);
          expect(
            _contrast(foreground, background),
            greaterThanOrEqualTo(4.5),
            reason: '五行图领域色上的普通文字必须达到 4.5:1。',
          );
        }
      }
    });
    test('未知五行兜底底色上的标签前景也满足普通文字 AA', () {
      final cases = <({String name, Color background})>[
        (
          name: '浅色兜底',
          background: YanjiPalette.fiveElementFallbackLight,
        ),
        (
          name: '深色兜底',
          background: YanjiPalette.fiveElementFallbackDark,
        ),
      ];
      for (final item in cases) {
        final foreground = chartLabelColorOn(item.background);
        expect(
          _contrast(foreground, item.background),
          greaterThanOrEqualTo(4.5),
          reason: '${item.name}五行兜底底色上的普通文字必须达到 4.5:1。',
        );
      }
    });
  });

}
