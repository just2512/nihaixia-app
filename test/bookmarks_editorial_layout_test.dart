import 'dart:async';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType, Rect;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/models/bookmark.dart';
import 'package:nihaisha_app/screens/bookmarks_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    DatabaseHelper.configureTestDatabase(
      'bookmarks_editorial_${DateTime.now().microsecondsSinceEpoch}.db',
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  Future<int> seedFormulaBookmark() async {
    final db = DatabaseHelper.instance;
    await db.database;
    final folderId = await db.insertFolder('常用经方');
    await db.insertBookmark(
      Bookmark(
        title: '桂枝汤',
        content: '解肌发表，调和营卫。用于学习经典原文与方剂结构。',
        category: '方剂',
        source: '伤寒论',
        createdAt: DateTime(2026, 11, 1),
      ),
    );
    await db.insertBookmark(
      Bookmark(
        title: '黄芪',
        content: '补气药条目，用于检查分类筛选。',
        category: '本草',
        source: '本草学习笔记',
        createdAt: DateTime(2026, 11, 2),
      ),
    );
    return folderId;
  }

  Future<void> pumpBookmarks(
    WidgetTester tester, {
    required Size size,
    required ValueChanged<List<Bookmark>> onDataLoaded,
    double textScale = 1,
    List<DisplayFeature> displayFeatures = const [],
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.displayFeatures = displayFeatures;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: AppColors.colorSchemeFor(Brightness.light),
          extensions: [AppColors.light],
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
            displayFeatures: displayFeatures,
          ),
          child: BookmarksScreen(onDataLoaded: onDataLoaded),
        ),
      ),
    );
    await tester.pump();
  }

  Future<List<Bookmark>> waitForLoad(
    WidgetTester tester,
    Completer<List<Bookmark>> load,
  ) async {
    // Do not await the completer inside runAsync: the widget's async database
    // continuation may need another tester frame before its callback is
    // observable. Advance real IO and the fake widget clock in bounded steps.
    for (var frame = 0; frame < 50 && !load.isCompleted; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    expect(
      load.isCompleted,
      isTrue,
      reason: '收藏数据加载回调应在 5 秒内完成',
    );
    return load.future;
  }


  testWidgets('收藏分类、文件夹移动与删除在紧凑屏和200%字号下可用',
      (tester) async {
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await seedFormulaBookmark();
      expect((await DatabaseHelper.instance.getAllBookmarks()).length, 2);
    });

    final pendingLoads = <Completer<List<Bookmark>>>[];
    void onDataLoaded(List<Bookmark> rows) {
      if (pendingLoads.isNotEmpty && !pendingLoads.first.isCompleted) {
        pendingLoads.removeAt(0).complete(rows);
      }
    }

    final initialLoad = Completer<List<Bookmark>>();
    pendingLoads.add(initialLoad);
    await pumpBookmarks(
      tester,
      size: const Size(402, 900),
      textScale: 2,
      onDataLoaded: onDataLoaded,
    );
    final initialRows = await waitForLoad(tester, initialLoad);
    expect(initialRows.map((row) => row.title).toSet(), {'桂枝汤', '黄芪'});
    expect(find.text('暂无收藏'), findsNothing);
    expect(find.text('桂枝汤'), findsOneWidget);
    expect(find.text('黄芪'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final filterLoad = Completer<List<Bookmark>>();
    pendingLoads.add(filterLoad);
    await tester.tap(find.widgetWithText(FilterChip, '本草'));
    final filteredRows = await waitForLoad(tester, filterLoad);
    expect(filteredRows.map((row) => row.title).toList(), ['黄芪']);
    expect(find.text('黄芪'), findsOneWidget);
    expect(find.text('桂枝汤'), findsNothing);

    final clearFilterLoad = Completer<List<Bookmark>>();
    pendingLoads.add(clearFilterLoad);
    await tester.tap(find.widgetWithText(FilterChip, '本草'));
    final allRows = await waitForLoad(tester, clearFilterLoad);
    expect(allRows.length, 2);
    expect(find.text('桂枝汤'), findsOneWidget);

    // 对桂枝汤执行移动到文件夹。
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动到文件夹'));
    await tester.pumpAndSettle();
    final moveLoad = Completer<List<Bookmark>>();
    pendingLoads.add(moveLoad);
    await tester.tap(find.text('常用经方').last);
    await tester.pumpAndSettle();
    final afterMove = await waitForLoad(tester, moveLoad);
    expect(afterMove.where((row) => row.title == '桂枝汤').single.folderId,
        isNotNull);

    final folderLoad = Completer<List<Bookmark>>();
    pendingLoads.add(folderLoad);
    await tester.tap(find.widgetWithText(FilterChip, '常用经方'));
    final folderRows = await waitForLoad(tester, folderLoad);
    expect(folderRows.map((row) => row.title).toList(), ['桂枝汤']);
    expect(find.text('桂枝汤'), findsOneWidget);
    expect(find.text('黄芪'), findsNothing);

    // 删除动作仍需二次确认。
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    final deleteLoad = Completer<List<Bookmark>>();
    pendingLoads.add(deleteLoad);
    await tester.tap(find.text('删除').last);
    final remainingRows = await waitForLoad(tester, deleteLoad);
    expect(remainingRows, isEmpty);
    expect(find.text('暂无收藏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('内屏零宽折痕与200%字号下收藏主从预览保持可读',
      (tester) async {
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await seedFormulaBookmark();
      expect((await DatabaseHelper.instance.getAllBookmarks()).length, 2);
    });

    final initialLoad = Completer<List<Bookmark>>();
    await pumpBookmarks(
      tester,
      size: const Size(775, 900),
      textScale: 2,
      displayFeatures: [
        DisplayFeature(
          bounds: const Rect.fromLTWH(387.5, 0, 0, 900),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureFlat,
        ),
      ],
      onDataLoaded: (rows) {
        if (!initialLoad.isCompleted) initialLoad.complete(rows);
      },
    );
    final rows = await waitForLoad(tester, initialLoad);
    expect(rows.length, 2);
    expect(find.text('桂枝汤'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: '展开主从列表在选择收藏之前不应横向溢出');

    await tester.tap(find.text('桂枝汤'));
    await tester.pumpAndSettle();

    expect(find.text('来源：伤寒论'), findsOneWidget);
    expect(find.text('打开完整详情'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: '展开主从详情在200%字号下不应横向溢出');
  });

}
