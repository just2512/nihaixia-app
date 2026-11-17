import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/yunqi_charts.dart';

void main() {
  test('五行徽章背景高度应容纳 200% TextPainter 字高并保留内边距', () {
    const labels = <String>['岁运·太火', '客运·少土', '司天', '客气·太阳寒水'];
    const baseFontSize = 8.5;
    const padding = 4.2;
    final scaler = TextScaler.linear(2.0);

    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: baseFontSize,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
        ellipsis: '…',
      )..layout();

      final backgroundHeight = wuxingBadgeBackgroundHeight(painter.height);
      expect(
        backgroundHeight,
        closeTo(painter.height + padding, 0.001),
        reason: '$label 在 200% 字号下背景高度必须使用实际 TextPainter 字高并保留 $padding dp 内边距',
      );
      expect(
        backgroundHeight,
        greaterThan(baseFontSize + padding),
        reason: '$label 的背景高度必须随 200% TextScaler 增长，不能继续使用未缩放字号',
      );
      painter.dispose();
    }
  });
}
