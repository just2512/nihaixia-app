import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/screens/diagnosis_history_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    DatabaseHelper.configureTestDatabase(
      'diagnosis_history_editorial_${DateTime.now().microsecondsSinceEpoch}.db',
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  Future<void> seedHistory() async {
    await DatabaseHelper.instance.saveDiagnosisHistory(
      '太阳',
      '太阳中风',
      '桂枝汤：桂枝、芍药、生姜、大枣、炙甘草；用于检查较长方剂名称、组成摘要与记录日期在放大字号下的换行。',
      0.82,
      '{"脉象":"浮缓"}',
    );
    await DatabaseHelper.instance.saveDiagnosisHistory(
      '阳明',
      '阳明腑实',
      '大承气汤：大黄、厚朴、枳实、芒硝；用于检查第二条记录和六经趋势。',
      0.76,
      '{"脉象":"沉实"}',
    );
  }

  Future<void> waitForHistory(WidgetTester tester) async {
    for (var frame = 0; frame < 40; frame++) {
      if (find.text('六经传变趋势').evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(find.text('六经传变趋势'), findsOneWidget,
        reason: '两条诊断历史加载后应显示六经趋势区域');
  }

  testWidgets('诊断历史在402/775dp与200%字号下不溢出且日期不挤压正文',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(seedHistory);

    for (final brightness in Brightness.values) {
      for (final width in [402.0, 775.0]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: AppColors.colorSchemeFor(brightness),
              extensions: [
                brightness == Brightness.dark ? AppColors.dark : AppColors.light,
              ],
            ),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 900),
                textScaler: const TextScaler.linear(2),
              ),
              child: const DiagnosisHistoryScreen(),
            ),
          ),
        );
        await tester.pump();
        await waitForHistory(tester);

        expect(find.textContaining('桂枝汤：桂枝、芍药、生姜'), findsOneWidget);
        expect(find.textContaining('大承气汤：大黄、厚朴'), findsOneWidget);
        expect(find.byTooltip('清空历史'), findsOneWidget);

        final firstTile = tester.widget<ListTile>(
          find.ancestor(
            of: find.text('太阳 · 太阳中风'),
            matching: find.byType(ListTile),
          ).first,
        );
        expect(firstTile.trailing, isNull,
            reason: '日期应进入次级信息行，不应作为 trailing 挤压正文');
        expect(tester.takeException(), isNull,
            reason: '${brightness.name} / ${width.toInt()}dp / 200% 诊断历史不应溢出');

        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}
