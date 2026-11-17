import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/ziwei_chart_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

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

  testWidgets(
    'Ask AI keeps the last successful chart snapshot until recalculation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: ZiweiChartScreen(
          initialSolar: DateTime(2000, 8, 16, 10),
          initialGender: true,
          initialLng: 121.47,
        ),
      ));
      await tester.pumpAndSettle();

      final askAi = find.text('问 AI 解读当前排盘');
      expect(askAi, findsOneWidget);

      Future<String> readAskAiSnapshot() async {
        await tester.ensureVisible(askAi);
        await tester.tap(askAi);
        await tester.pumpAndSettle();

        final assistant = find.byType(LocalAiInterviewScreen);
        expect(assistant, findsOneWidget);
        final contextRef =
            tester.widget<LocalAiInterviewScreen>(assistant).contextRef;
        final snapshotId = contextRef['snapshotId'];
        expect(snapshotId, isNotNull);
        expect(snapshotId, hasLength(64));

        Navigator.of(tester.element(assistant)).pop();
        await tester.pumpAndSettle();
        return snapshotId!;
      }

      final originalSnapshot = await readAskAiSnapshot();

      final longitudeField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText?.startsWith('出生地经度') == true,
      );
      expect(longitudeField, findsOneWidget);
      await tester.ensureVisible(longitudeField);
      await tester.enterText(longitudeField, '118.00');
      await tester.pump();

      // Editing the form is not a calculation. Ask AI must keep the captured
      // inputs and formatted result from the last successful calculation.
      final editedButNotRecalculatedSnapshot = await readAskAiSnapshot();
      expect(editedButNotRecalculatedSnapshot, originalSnapshot);

      final calculateButton = find.text('开始排盘');
      await tester.ensureVisible(calculateButton);
      await tester.tap(calculateButton);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Only a successful new calculation may establish a new result anchor.
      final recalculatedSnapshot = await readAskAiSnapshot();
      expect(recalculatedSnapshot, isNot(originalSnapshot));
      expect(tester.takeException(), isNull);
    },
  );

}
