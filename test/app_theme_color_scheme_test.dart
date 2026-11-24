import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/theme/app_colors.dart';


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
  group('AppColors Material ColorScheme', () {
    test('light scheme uses the light semantic tokens', () {
      final tokens = AppColors.light;
      final scheme = AppColors.colorSchemeFor(Brightness.light);

      expect(scheme.brightness, Brightness.light);
      expect(scheme.primary, tokens.primary);
      expect(scheme.onPrimary, tokens.onPrimary);
      expect(scheme.primaryContainer, tokens.primaryContainer);
      expect(scheme.onPrimaryContainer, tokens.onPrimaryContainer);
      expect(scheme.surface, tokens.surface);
      expect(
        scheme.surfaceContainerLowest,
        brightness == Brightness.dark ? tokens.background : tokens.surface,
      );
      expect(scheme.surfaceContainerLow, tokens.surfaceContainerLow);
      expect(scheme.surfaceContainerHighest, tokens.surfaceContainerHighest);
      expect(scheme.onSurface, tokens.onSurface);
      expect(scheme.onSurfaceVariant, tokens.onSurfaceVariant);
      expect(scheme.outline, tokens.outline);
      expect(scheme.outlineVariant, tokens.outlineVariant);
      expect(scheme.error, tokens.danger);
      expect(scheme.onError, tokens.onDanger);
      expect(scheme.errorContainer, tokens.dangerContainer);
    });


    test('editorial palette keeps readable text contrast on theme surfaces', () {
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
          reason: 'Light primary text must remain readable on each surface.',
        );
        expect(
          _contrastRatio(light.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
          reason: 'Light secondary text must remain readable on each surface.',
        );
      }
      expect(
        _contrastRatio(light.onPrimary, light.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(light.onPrimaryContainer, light.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );

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
          reason: 'Dark primary text must remain readable on each surface.',
        );
        expect(
          _contrastRatio(dark.onSurfaceVariant, surface),
          greaterThanOrEqualTo(4.5),
          reason: 'Dark secondary text must remain readable on each surface.',
        );
      }
      expect(
        _contrastRatio(dark.onPrimary, dark.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrastRatio(dark.onPrimaryContainer, dark.primaryContainer),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('dark scheme uses the dark semantic tokens', () {
      final tokens = AppColors.dark;
      final scheme = AppColors.colorSchemeFor(Brightness.dark);

      expect(scheme.brightness, Brightness.dark);
      expect(scheme.primary, tokens.primary);
      expect(scheme.onPrimary, tokens.onPrimary);
      expect(scheme.primaryContainer, tokens.primaryContainer);
      expect(scheme.onPrimaryContainer, tokens.onPrimaryContainer);
      expect(scheme.surface, tokens.surface);
      expect(
        scheme.surfaceContainerLowest,
        brightness == Brightness.dark ? tokens.background : tokens.surface,
      );
      expect(scheme.surfaceContainerLow, tokens.surfaceContainerLow);
      expect(scheme.surfaceContainerHighest, tokens.surfaceContainerHighest);
      expect(scheme.onSurface, tokens.onSurface);
      expect(scheme.onSurfaceVariant, tokens.onSurfaceVariant);
      expect(scheme.outline, tokens.outline);
      expect(scheme.outlineVariant, tokens.outlineVariant);
      expect(scheme.error, tokens.danger);
      expect(scheme.onError, tokens.onDanger);
      expect(scheme.errorContainer, tokens.dangerContainer);
    });
  });
}
