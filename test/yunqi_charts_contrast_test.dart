import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/yunqi_charts.dart';

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
  test('五运六气图五行标签在浅深主题均达到普通文字 4.5:1 对比度', () {
    const wuxing = ['木', '火', '土', '金', '水'];

    for (final brightness in Brightness.values) {
      for (final element in wuxing) {
        final background = wxColorOf(element, brightness);
        final foreground = chartLabelColorOn(background);
        final ratio = _contrastRatio(foreground, background);

        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name}主题 / $element：图内标签需要至少 4.5:1，实际为 ${ratio.toStringAsFixed(2)}:1',
        );
      }
    }
  });
}
