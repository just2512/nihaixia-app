import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/ziwei_chart_screen.dart';
import '../lib/theme/app_colors.dart';

void main() {
  testWidgets('a successful calculated chart exposes a contextual Ask AI entry',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      home: ZiweiChartScreen(
        initialSolar: DateTime(2000, 8, 16, 10),
        initialGender: true,
        initialLng: 121.47,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('问 AI 解读当前排盘'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('an invalid chart input does not expose contextual Ask AI',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      home: ZiweiChartScreen(
        initialSolar: DateTime(2000, 8, 16, 10),
        initialGender: true,
        initialLng: 181,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('经度格式不正确'), findsOneWidget);
    expect(find.text('问 AI 解读当前排盘'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });
}
