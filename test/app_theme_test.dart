import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/main.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  test('default bottom sheets use the active surface token in both themes', () {
    for (final brightness in Brightness.values) {
      final theme = buildAppTheme(brightness);
      final colors = theme.extension<AppColors>();

      expect(colors, isNotNull);
      expect(
        theme.bottomSheetTheme.backgroundColor,
        colors!.surface,
        reason: 'Bottom sheets must use the active theme surface token.',
      );
      expect(
        theme.bottomSheetTheme.backgroundColor,
        isNot(Colors.transparent),
      );
    }
  });
}
