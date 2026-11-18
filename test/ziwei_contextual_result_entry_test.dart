import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/ziwei_chart_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory databaseDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    databaseDirectory = await Directory.systemTemp.createTemp(
      'nihaisha-ziwei-context-snapshot-',
    );
    DatabaseHelper.configureTestDatabase(
      'ziwei_context_snapshot_test.db',
      factory: databaseFactoryFfi,
      directoryPath: databaseDirectory.path,
    );
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
    if (await databaseDirectory.exists()) {
      await databaseDirectory.delete(recursive: true);
    }
  });
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
    'a palace detail opens a field-bound contextual assistant',
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

      final palaceCell = find.byKey(const ValueKey('ziwei-palace-cell-0'));
      final pageScrollable = find.descendant(
        of: find.byKey(const ValueKey('ziwei-chart-page-scroll')),
        matching: find.byType(Scrollable),
      ).first;
      await tester.scrollUntilVisible(
        palaceCell,
        400,
        scrollable: pageScrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(palaceCell);
      await tester.pumpAndSettle();

      final fieldAsk = find.text('问 AI 解读本宫星曜');
      expect(fieldAsk, findsOneWidget);
      await tester.tap(fieldAsk);
      await tester.pumpAndSettle();

      final assistant = find.byType(LocalAiInterviewScreen);
      expect(assistant, findsOneWidget);
      final assistantWidget =
          tester.widget<LocalAiInterviewScreen>(assistant);
      final contextRef = assistantWidget.contextRef;
      expect(assistantWidget.initialPrompt, contains('fieldValue'));
      expect(assistantWidget.initialPrompt, contains('starKey'));
      expect(assistantWidget.initialPrompt, contains('palaceIndex'));
      expect(contextRef['kind'], 'field');
      expect(contextRef['fieldPath'], 'palacesByPhysicalBranch.0.stars');
      expect(contextRef['snapshotId'], isNotNull);
      expect(contextRef['snapshotId'], hasLength(64));
      expect(contextRef['anchorVersion'], contextRef['snapshotId']);
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(null);
    },
  );

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
        await tester.pumpAndSettle();

        // Resolve the Scrollable that actually contains the Ask AI action.
        // The page has nested scrollable content, so selecting the first
        // descendant can observe a different viewport from the owning ListView.
        final sourcePageScrollable = find.ancestor(
          of: askAi,
          matching: find.byType(Scrollable),
        ).first;
        final sourcePageScrollableWidget =
            tester.widget<Scrollable>(sourcePageScrollable);
        final sourcePageController = sourcePageScrollableWidget.controller;
        final sourcePagePosition =
            tester.state<ScrollableState>(sourcePageScrollable).position;
        final pageOffsetBeforeOpen = sourcePagePosition.pixels;

        await tester.tap(askAi);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        final assistant = find.byType(LocalAiInterviewScreen);
        expect(assistant, findsOneWidget);
        final contextRef =
            tester.widget<LocalAiInterviewScreen>(assistant).contextRef;
        final snapshotId = contextRef['snapshotId'];
        expect(snapshotId, isNotNull);
        expect(snapshotId, hasLength(64));

        Navigator.of(
          tester.element(assistant),
          rootNavigator: true,
        ).pop();
        await tester.pumpAndSettle();
        expect(
          find.byType(ZiweiChartScreen),
          findsOneWidget,
          reason: '关闭情境助手必须返回原排盘页，不能退出排盘路由',
        );
        final restoredScrollable = find.ancestor(
          of: askAi,
          matching: find.byType(Scrollable),
        ).first;
        final restoredScrollableWidget =
            tester.widget<Scrollable>(restoredScrollable);
        final restoredController = restoredScrollableWidget.controller;
        final restoredPosition =
            tester.state<ScrollableState>(restoredScrollable).position;
        final pageOffsetAfterClose = restoredPosition.pixels;
        final sameScrollController =
            identical(sourcePageController, restoredController);
        final sameScrollPosition =
            identical(sourcePagePosition, restoredPosition);
        final pageViewInsets =
            MediaQuery.viewInsetsOf(tester.element(find.byType(ZiweiChartScreen)));
        expect(
          pageOffsetAfterClose,
          closeTo(pageOffsetBeforeOpen, 0.5),
          reason: '情境助手关闭后必须保留原排盘页的滚动位置；'
              'before=${pageOffsetBeforeOpen}, after=${pageOffsetAfterClose}, '
              'max=${restoredPosition.maxScrollExtent}, '
              'viewport=${restoredPosition.viewportDimension}, '
              'viewInsets=$pageViewInsets, '
              'sameController=$sameScrollController, '
              'samePosition=$sameScrollPosition, '
              'controllerOffset=${restoredController is ScrollController ? restoredController.offset : "none"}',
        );
        return snapshotId!;
      }

      final originalSnapshot = await readAskAiSnapshot();

      // Opening Ask AI may scroll the long result page near its bottom. The
      // birth inputs live in a lazily built ListView child, so return to the
      // top before locating the longitude field.
      final chartScroll = find.descendant(
        of: find.byType(ZiweiChartScreen),
        matching: find.byType(Scrollable),
      ).first;
      await tester.drag(chartScroll, const Offset(0, 2400));
      await tester.pumpAndSettle();

      final longitudeField = find.descendant(
        of: find.byType(ZiweiChartScreen),
        matching: find.byType(TextField),
      );
      expect(longitudeField, findsOneWidget);
      expect(
        tester.widget<TextField>(longitudeField).decoration?.labelText,
        startsWith('出生地经度'),
      );
      expect(tester.widget<TextField>(longitudeField).enabled, isTrue);
      await tester.ensureVisible(longitudeField);
      await tester.enterText(longitudeField, '118.00');
      await tester.pump();

      // Editing the form is not a calculation. Ask AI must keep the captured
      // inputs and formatted result from the last successful calculation.
      final editedButNotRecalculatedSnapshot = await readAskAiSnapshot();
      expect(editedButNotRecalculatedSnapshot, originalSnapshot);

      // The contextual assistant must now preserve the page offset. The
      // calculate action is near the top of this lazy ListView, so return to
      // the top explicitly before locating the button for the third snapshot.
      await tester.drag(chartScroll, const Offset(0, 2400));
      await tester.pumpAndSettle();

      final calculateButton = find.text('开始排盘');
      expect(calculateButton, findsOneWidget,
          reason: '返回列表顶部后应重新构建排盘按钮');
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
