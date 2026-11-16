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
          child: const BookmarksScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('收藏分类、文件夹移动与删除在紧凑屏和200%字号下可用',
      (tester) async {
    await tester.runAsync(() => seedFormulaBookmark());
    await pumpBookmarks(
      tester,
      size: const Size(402, 900),
      textScale: 2,
    );

    expect(find.text('桂枝汤'), findsOneWidget);
    expect(find.text('黄芪'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilterChip, '本草'));
    await tester.pumpAndSettle();
    expect(find.text('黄芪'), findsOneWidget);
    expect(find.text('桂枝汤'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, '本草'));
    await tester.pumpAndSettle();

    // 对桂枝汤执行移动到文件夹。
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('移动到文件夹'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('常用经方').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterChip, '常用经方'));
    await tester.pumpAndSettle();
    expect(find.text('桂枝汤'), findsOneWidget);
    expect(find.text('黄芪'), findsNothing);

    // 删除动作仍需二次确认。
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(find.text('暂无收藏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('内屏零宽折痕与200%字号下收藏主从预览保持可读',
      (tester) async {
    await tester.runAsync(() => seedFormulaBookmark());
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
    );

    await tester.tap(find.text('桂枝汤'));
    await tester.pumpAndSettle();

    expect(find.text('来源：伤寒论'), findsOneWidget);
    expect(find.text('打开完整详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
