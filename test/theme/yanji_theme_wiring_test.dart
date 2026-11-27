import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/theme/yanji_palette.dart';

void main() {
  group('研纪 ThemeData 表面与颜色角色接线', () {
    test('YanjiPalette 是应用语义颜色的唯一原始色值定义层', () {
      final source = File('lib/theme/app_colors.dart').readAsStringSync();
      expect(
        source,
        isNot(matches(RegExp(r'\bColor\s*\(\s*0x[0-9a-fA-F]{6,8}\s*\)'))),
        reason: 'AppColors 只能映射 YanjiPalette，不得内嵌原始十六进制色值。',
      );
    });

    test('生产主题显式区分 Scaffold 背景和 ColorScheme.surface', () {
      final source = File('lib/main.dart').readAsStringSync();

      expect(
        source,
        contains('scaffoldBackgroundColor: tokens.background'),
        reason: 'Scaffold 背景不能隐式回退到 ColorScheme.surface。',
      );
      expect(source, contains('colorScheme: scheme'));
      expect(
        source,
        isNot(contains('ColorScheme.fromSeed')),
        reason: '项目主题不得依赖 SDK fromSeed 自动推导颜色角色。',
      );
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
        source.split('surfaceTintColor: scheme.surfaceTint').length - 1,
        3,
        reason: 'Card / Dialog / BottomSheet 必须统一消费透明 surfaceTint Token。',
      );
      expect(
        source,
        isNot(contains('surfaceTintColor: Colors.transparent')),
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
