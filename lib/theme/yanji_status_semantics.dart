import 'package:flutter/material.dart';

import 'app_colors.dart';

/// A status chip uses a semantic container for its state and neutral on-surface
/// text. The visible label remains the primary state identifier; color is
/// deliberately not the only signal.
enum YanjiStatusTone { success, warning, danger, neutral }

YanjiStatusChipColors yanjiStatusChipColors(
  YanjiStatusTone tone,
  AppColors colors,
) {
  final background = switch (tone) {
    YanjiStatusTone.success => colors.successContainer,
    YanjiStatusTone.warning => colors.warningContainer,
    YanjiStatusTone.danger => colors.dangerContainer,
    YanjiStatusTone.neutral => colors.surfaceContainerHighest,
  };
  return (foreground: colors.onSurface, background: background);
}

typedef YanjiStatusChipColors = ({
  Color foreground,
  Color background,
});

YanjiStatusChipColors dreamAuspiciousChipColors(
  String level,
  AppColors colors,
) {
  final tone = switch (level) {
    '大吉' || '吉' => YanjiStatusTone.success,
    '平' => YanjiStatusTone.neutral,
    '凶' => YanjiStatusTone.warning,
    '大凶' => YanjiStatusTone.danger,
    _ => YanjiStatusTone.neutral,
  };
  return yanjiStatusChipColors(tone, colors);
}

YanjiStatusChipColors guanshaSeverityChipColors(
  String severity,
  AppColors colors,
) {
  final tone = switch (severity) {
    '重关' => YanjiStatusTone.danger,
    '中关' => YanjiStatusTone.warning,
    _ => YanjiStatusTone.neutral,
  };
  return yanjiStatusChipColors(tone, colors);
}
