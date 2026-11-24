import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/theme/yanji_status_semantics.dart';

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('研纪民俗状态标签语义色', () {
    for (final theme in <({String name, AppColors colors})>[
      (name: '浅色', colors: AppColors.light),
      (name: '深色', colors: AppColors.dark),
    ]) {
      test('${theme.name}主题的吉凶标签映射保留语义且文字达到 AA', () {
        final cases = <({String level, Color background})>[
          (level: '大吉', background: theme.colors.successContainer),
          (level: '吉', background: theme.colors.successContainer),
          (level: '平', background: theme.colors.surfaceContainerHighest),
          (level: '凶', background: theme.colors.warningContainer),
          (level: '大凶', background: theme.colors.dangerContainer),
          (level: '未知', background: theme.colors.surfaceContainerHighest),
        ];
        for (final item in cases) {
          final pair = dreamAuspiciousChipColors(item.level, theme.colors);
          expect(pair.foreground, theme.colors.onSurface);
          expect(pair.background, item.background);
          expect(
            _contrast(pair.foreground, pair.background),
            greaterThanOrEqualTo(4.5),
            reason: '${theme.name}主题/${item.level}文字必须达到 4.5:1',
          );
        }
      });

      test('${theme.name}主题的关煞严重度映射保留语义且文字达到 AA', () {
        final cases = <({String severity, Color background})>[
          (severity: '重关', background: theme.colors.dangerContainer),
          (severity: '中关', background: theme.colors.warningContainer),
          (severity: '轻关', background: theme.colors.surfaceContainerHighest),
          (severity: '未知', background: theme.colors.surfaceContainerHighest),
        ];
        for (final item in cases) {
          final pair = guanshaSeverityChipColors(item.severity, theme.colors);
          expect(pair.foreground, theme.colors.onSurface);
          expect(pair.background, item.background);
          expect(
            _contrast(pair.foreground, pair.background),
            greaterThanOrEqualTo(4.5),
            reason: '${theme.name}主题/${item.severity}文字必须达到 4.5:1',
          );
        }
      });
    }

    test('两个页面使用共享语义映射，不再直接调用 Flutter Material 颜色', () {
      final dream = File('lib/screens/dream_screen.dart').readAsStringSync();
      final guansha = File('lib/screens/guansha_screen.dart').readAsStringSync();

      expect(dream, contains('dreamAuspiciousChipColors('));
      expect(guansha, contains('guanshaSeverityChipColors('));
      expect(dream, isNot(contains('Colors.green')));
      expect(dream, isNot(contains('Colors.red')));
      expect(dream, isNot(contains('Colors.orange')));
      expect(guansha, isNot(contains('Colors.red')));
      expect(guansha, isNot(contains('Colors.orange')));
      expect(dream, isNot(contains('withValues(alpha: 0.18)')));
      expect(guansha, isNot(contains('withValues(alpha: 0.18)')));
    });
  });
}
