import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/dosage_converter_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

Future<void> _pumpDosageConverter(
  WidgetTester tester, {
  required double width,
  required Brightness brightness,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  tester.view.displayFeatures = const [];
  addTearDown(tester.view.resetDisplayFeatures);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: AppColors.colorSchemeFor(brightness),
        extensions: [
          brightness == Brightness.dark ? AppColors.dark : AppColors.light,
        ],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
        ),
        child: child!,
      ),
      home: const DosageConverterScreen(),
    ),
  );
  await tester.pumpAndSettle();

  final pageContext = tester.element(find.byType(DosageConverterScreen));
  expect(
    MediaQuery.textScalerOf(pageContext).scale(1),
    2,
    reason: '剂量换算器布局测试必须真实运行在 200% 字号',
  );
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('剂量换算器在 402/775dp、浅深主题与 200% 字号下可滚动阅读',
      (tester) async {
    for (final brightness in Brightness.values) {
      for (final width in [402.0, 775.0]) {
        await _pumpDosageConverter(
          tester,
          width: width,
          brightness: brightness,
        );

        expect(find.text('经方剂量换算器'), findsOneWidget);
        expect(find.text('度量标准'), findsOneWidget);
        expect(find.byType(SegmentedButton<int>), findsOneWidget);
        expect(find.text('1 两'), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: '${width.toInt()}dp / ${brightness.name} / 200% 初始布局');

        final firstTableTitle = find.text('药物特殊换算（容积→重量）');
        await tester.scrollUntilVisible(
          firstTableTitle,
          240,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(firstTableTitle);
        await tester.pumpAndSettle();

        final lastVolumeRow = find.text('葶苈子');
        await tester.scrollUntilVisible(
          lastVolumeRow,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(lastVolumeRow, findsOneWidget);
        final volumeText = tester.widget<Text>(lastVolumeRow);
        expect(volumeText.maxLines, isNull,
            reason: '容积换算表药名不得锁定单行');
        expect(volumeText.overflow, isNull,
            reason: '容积换算表药名不得通过省略隐藏');
        expect(tester.takeException(), isNull,
            reason: '${width.toInt()}dp / ${brightness.name} / 200% 容积表');

        final secondTableTitle = find.text('药物特殊换算（枚数→重量）');
        await tester.scrollUntilVisible(
          secondTableTitle,
          220,
          scrollable: find.byType(Scrollable).first,
        );
        // The target may be built while its center is still a few pixels
        // outside the root view; explicitly align it before pointer input.
        await tester.ensureVisible(secondTableTitle);
        await tester.pumpAndSettle();
        final secondTitleBounds = tester.getRect(secondTableTitle);
        expect(secondTitleBounds.top, greaterThanOrEqualTo(0));
        expect(secondTitleBounds.bottom, lessThanOrEqualTo(900));
        await tester.tap(secondTableTitle);
        await tester.pumpAndSettle();

        final longCountRow = find.text('强乌头（小者）');
        await tester.scrollUntilVisible(
          longCountRow,
          260,
          scrollable: find.byType(Scrollable).first,
        );
        expect(longCountRow, findsOneWidget);
        final countText = tester.widget<Text>(longCountRow);
        expect(countText.maxLines, isNull,
            reason: '枚数换算表药名不得锁定单行');
        expect(countText.overflow, isNull,
            reason: '枚数换算表药名不得通过省略隐藏');
        expect(tester.takeException(), isNull,
            reason: '${width.toInt()}dp / ${brightness.name} / 200% 枚数表');

        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}
