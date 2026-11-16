import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/acupoint_repository.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/screens/critical_illness_list_screen.dart';
import 'package:nihaisha_app/screens/formula_detail_screen.dart';
import 'package:nihaisha_app/screens/herb_detail_screen.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await FormulaRepository.load();
    await HerbRepository.load();
    await AcupointRepository.load();
  });

  setUp(() {
    DatabaseHelper.configureTestDatabase(
      'critical_illness_layout_${DateTime.now().microsecondsSinceEpoch}.db',
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  Future<void> pumpList(
    WidgetTester tester, {
    required double width,
    required Brightness brightness,
  }) async {
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
        home: const CriticalIllnessListScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(
    WidgetTester tester,
    String title,
  ) async {
    final scrollable = find.descendant(
      of: find.byType(Scaffold),
      matching: find.byType(Scrollable),
    ).first;
    await tester.scrollUntilVisible(
      find.text(title),
      320,
      scrollable: scrollable,
    );
  }

  testWidgets(
    '七条闭门课条目在402/775dp、浅深主题与200%字号下均可滚动阅读',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const titles = [
        '闭门课总览',
        '血癌',
        '红斑性狼疮',
        '脑瘤',
        '肾衰竭尿毒症',
        '乳癌',
        '肝癌',
      ];

      for (final brightness in [Brightness.light, Brightness.dark]) {
        for (final width in [402.0, 775.0]) {
          await pumpList(
            tester,
            width: width,
            brightness: brightness,
          );
          expect(find.text('闭门课 · 重症临床'), findsOneWidget);
          expect(
            find.byType(Card),
            findsNothing,
            reason: '连续列表使用轻表面和分隔线，不应重复堆叠 Card',
          );

          for (final title in titles) {
            await reveal(tester, title);
            expect(find.text(title), findsOneWidget);
            expect(tester.takeException(), isNull,
                reason: '$title 在${width.toInt()}dp / ${brightness.name} / 200% 下不应溢出');
          }
        }
      }
    },
  );

  testWidgets('总览和疾病条目仍可打开原文 Markdown', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpList(
      tester,
      width: 402,
      brightness: Brightness.light,
    );

    await tester.tap(find.text('闭门课总览'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownDocScreen), findsOneWidget);
    expect(find.textContaining('视频课程可在B站观看'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await reveal(tester, '血癌');
    await tester.tap(find.text('血癌'));
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownDocScreen), findsOneWidget);
    expect(find.text('血癌'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('标签仍按精确药材优先、方剂其次跳转详情', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpList(
      tester,
      width: 402,
      brightness: Brightness.light,
    );

    final herbChip = find.widgetWithText(ActionChip, '生附子').first;
    await tester.ensureVisible(herbChip);
    await tester.tap(herbChip);
    await tester.pumpAndSettle();
    expect(find.byType(HerbDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();

    final formulaChip = find.widgetWithText(ActionChip, '四逆汤').first;
    await tester.ensureVisible(formulaChip);
    await tester.tap(formulaChip);
    await tester.pumpAndSettle();
    expect(find.byType(FormulaDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
