import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

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
      expect(scheme.surface, tokens.background);
      expect(scheme.surfaceContainerLowest, tokens.surface);
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

    test('dark scheme uses the dark semantic tokens', () {
      final tokens = AppColors.dark;
      final scheme = AppColors.colorSchemeFor(Brightness.dark);

      expect(scheme.brightness, Brightness.dark);
      expect(scheme.primary, tokens.primary);
      expect(scheme.onPrimary, tokens.onPrimary);
      expect(scheme.primaryContainer, tokens.primaryContainer);
      expect(scheme.onPrimaryContainer, tokens.onPrimaryContainer);
      expect(scheme.surface, tokens.background);
      expect(scheme.surfaceContainerLowest, tokens.surface);
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
