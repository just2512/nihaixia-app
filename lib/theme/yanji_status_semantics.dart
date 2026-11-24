import 'package:flutter/material.dart';

import 'app_colors.dart';

/// A status chip uses a semantic container for its state and neutral on-surface
/// text. The visible label remains the primary state identifier; color is
/// deliberately not the only signal.
typedef YanjiStatusChipColors = ({
  Color foreground,
  Color background,
});

YanjiStatusChipColors dreamAuspiciousChipColors(
  String level,
  AppColors colors,
) {
  final background = switch (level) {
    '大吉' || '吉' => colors.successContainer,
    '平' => colors.surfaceContainerHighest,
    '凶' => colors.warningContainer,
    '大凶' => colors.dangerContainer,
    _ => colors.surfaceContainerHighest,
  };
  return (foreground: colors.onSurface, background: background);
}

YanjiStatusChipColors guanshaSeverityChipColors(
  String severity,
  AppColors colors,
) {
  final background = switch (severity) {
    '重关' => colors.dangerContainer,
    '中关' => colors.warningContainer,
    _ => colors.surfaceContainerHighest,
  };
  return (foreground: colors.onSurface, background: background);
}
