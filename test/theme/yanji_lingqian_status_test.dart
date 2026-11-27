import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/sanshan_lingqian_data.dart';
import 'package:nihaisha_app/screens/sanshan_lingqian_screen.dart';
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
  group('三山灵签吉凶状态语义色', () {
    const expectedTones = <LingqianLuck, YanjiStatusTone>{
      LingqianLuck.daJi: YanjiStatusTone.success,
      LingqianLuck.ping: YanjiStatusTone.neutral,
      LingqianLuck.xiong: YanjiStatusTone.danger,
      LingqianLuck.pingAn: YanjiStatusTone.success,
    };

    for (final theme in <({String name, AppColors colors})>[
      (name: '浅色', colors: AppColors.light),
      (name: '深色', colors: AppColors.dark),
    ]) {
      test('${theme.name}主题四类签运映射到正确的语义容器并达到 AA', () {
        for (final entry in expectedTones.entries) {
          expect(lingqianLuckStatusTone(entry.key), entry.value);
          final pair = yanjiStatusChipColors(entry.value, theme.colors);
          final expectedBackground = switch (entry.value) {
            YanjiStatusTone.success => theme.colors.successContainer,
            YanjiStatusTone.warning => theme.colors.warningContainer,
            YanjiStatusTone.danger => theme.colors.dangerContainer,
            YanjiStatusTone.neutral => theme.colors.surfaceContainerHighest,
          };
          expect(pair.foreground, theme.colors.onSurface);
          expect(pair.background, expectedBackground);
          expect(
            _contrast(pair.foreground, pair.background),
            greaterThanOrEqualTo(4.5),
            reason: '${theme.name}主题/${entry.key.label}签运标签必须达到 4.5:1',
          );
        }
      });
    }

    test('92签数据类别完整，四种签运均被覆盖', () {
      expect(kSanShanLingqian, hasLength(92));
      expect(kSanShanLingqian.map((e) => e.luck).toSet(),
          equals(LingqianLuck.values.toSet()));
    });

    test('签卡与列表编号共用语义 Token，不再使用独立红绿青色', () {
      final source =
          File('lib/screens/sanshan_lingqian_screen.dart').readAsStringSync();
      expect(source, contains('lingqianLuckStatusTone(sign.luck)'));
      expect(source, contains('YanjiStatusBadge('));
      expect(source, contains('status.background'));
      expect(source, contains('status.foreground'));
      expect(source, isNot(contains('Colors.green')));
      expect(source, isNot(contains('Colors.red')));
      expect(source, isNot(contains('Colors.teal')));
      expect(source, isNot(contains('_luckColor(')));
    });
  });
}
