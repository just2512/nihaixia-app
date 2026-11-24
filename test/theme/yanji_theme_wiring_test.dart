import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/theme/yanji_palette.dart';

void main() {
  group('研纪 ThemeData 表面与颜色角色接线', () {
    test('生产主题显式区分 Scaffold 背景和 ColorScheme.surface', () {
      final source = File('lib/main.dart').readAsStringSync();

      expect(
        source,
        contains('scaffoldBackgroundColor: tokens.background'),
        reason: 'Scaffold 背景不能隐式回退到 ColorScheme.surface。',
      );
      expect(source, contains('colorScheme: scheme'));
      expect(AppColors.light.background, YanjiPalette.coldWhite);
      expect(AppColors.light.surface, YanjiPalette.white);
      expect(AppColors.dark.background, YanjiPalette.darkBackground);
      expect(AppColors.dark.surface, YanjiPalette.darkSurface);
    });

    test('M3 surface tint 不会给卡片和对话框重新染色', () {
      final source = File('lib/main.dart').readAsStringSync();
      final scheme = AppColors.colorSchemeFor(Brightness.light);

      expect(scheme.surfaceTint, YanjiPalette.transparent);
      expect(
        source,
        contains('surfaceTintColor: scheme.surfaceTint'),
        reason: 'CardTheme 必须沿用显式透明 surfaceTint。',
      );
      expect(
        source,
        contains('surfaceTintColor: Colors.transparent'),
        reason: 'Dialog / BottomSheet 不应额外叠加 elevation tint。',
      );
    });

    test('交互控件边界不使用装饰性银灰 outlineVariant', () {
      final source = File('lib/main.dart').readAsStringSync();

      expect(source, contains('borderSide: BorderSide(color: scheme.outline)'));
      expect(source, contains('side: BorderSide(color: scheme.outline)'));
      expect(
        source,
        contains('color: scheme.outlineVariant'),
        reason: 'outlineVariant 只保留给装饰性分割线等低语义边界。',
      );
      expect(
        source,
        contains('indicatorColor: scheme.primaryContainer'),
        reason: 'NavigationBar/NavigationRail 选中指示器必须使用浅红 primaryContainer。',
      );
      expect(source, contains('selected ? scheme.onPrimaryContainer'));
      expect(source, contains('selected ? FontWeight.w700 : FontWeight.w500'));
    });
  });
}
