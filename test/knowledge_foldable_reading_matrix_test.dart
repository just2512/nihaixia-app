import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/screens/formula_detail_screen.dart';
import 'package:nihaisha_app/screens/herb_detail_screen.dart';
import 'package:nihaisha_app/screens/knowledge_screen.dart';
import 'package:nihaisha_app/screens/home_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

var _databaseSequence = 0;

List<Widget> _foldableHomeScreens() => const [
      Scaffold(body: Center(child: Text('AI 测试页'))),
      Scaffold(body: Center(child: Text('工具测试页'))),
      KnowledgeScreen(),
      Scaffold(body: Center(child: Text('收藏测试页'))),
      Scaffold(body: Center(child: Text('设置测试页'))),
    ];

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await FormulaRepository.load();
    await HerbRepository.load();
  });

  setUp(() async {
    DatabaseHelper.configureTestDatabase(
      'knowledge_foldable_reading_${_databaseSequence++}.db',
      factory: databaseFactoryFfi,
    );
    // Detail screens query bookmark state in initState. Open the test DB
    // before the first route is mounted, avoiding a lazy-open race.
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  Future<void> pumpKnowledge(
    WidgetTester tester, {
    required Brightness brightness,
    required Size size,
    bool halfFolded = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.displayFeatures = halfFolded
        ? [
            DisplayFeature(
              bounds: const Rect.fromLTWH(388, 0, 24, 900),
              type: DisplayFeatureType.hinge,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ]
        : const [];

    final tokens =
        brightness == Brightness.dark ? AppColors.dark : AppColors.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: AppColors.colorSchemeFor(brightness),
          extensions: [tokens],
          cardTheme: const CardThemeData(elevation: 0),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        // Exercise the production root-navigation fold path, not a standalone
        // AdaptiveSinglePane wrapper. The test-only page fixtures keep unrelated
        // SQLite/native screens from participating in this route-layout check.
        home: halfFolded
            ? HomeScreen(testScreens: _foldableHomeScreens())
            : const KnowledgeScreen(),
      ),
    );
    await tester.pumpAndSettle();
    if (halfFolded) {
      // In half-open posture the root shell keeps navigation and content on
      // the selected physical panel. Select the real Knowledge tab first.
      await tester.tap(find.text('知识').last);
      await tester.pumpAndSettle();
    }

    final pageContext = tester.element(find.byType(KnowledgeScreen));
    expect(
      MediaQuery.textScalerOf(pageContext).scale(1),
      2,
      reason: '知识页必须实际继承200%系统字号',
    );
    expect(tester.takeException(), isNull);
  }

Future<void> _waitForBookmarkLookup(
  WidgetTester tester,
  String title,
) async {
  // Detail screens start this lookup in initState. Run a second lookup outside
  // FakeAsync so sqflite_ffi's real isolate work and serialized DB queue finish
  // before the test disposes the route and closes its database.
  final result = await tester.runAsync<bool>(
    () => DatabaseHelper.instance.isBookmarked(title),
  );
  expect(result, isNotNull);
  await tester.pump();
}

Future<void> _pumpUntilRouteAnimationCompletes(
  WidgetTester tester,
  Finder pageFinder,
) async {
  // The pushed route may not be mounted in the first frame after the tap.
  // Wait for its page widget before asking the widget tree for its ModalRoute.
  ModalRoute<dynamic>? route;
  var animationCompleted = false;
  for (var frame = 0; frame < 120; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (pageFinder.evaluate().isEmpty) continue;

    route = ModalRoute.of(tester.element(pageFinder));
    if (route?.animation?.status == AnimationStatus.completed) {
      animationCompleted = true;
      break;
    }
  }

  expect(pageFinder, findsOneWidget);
  expect(route, isNotNull);
  expect(
    animationCompleted,
    isTrue,
    reason: '详情路由必须完成进入动画后再验收物理面板边界',
  );
  // Allow bookmark / classic-source async work to reach a stable frame; the
  // detail page intentionally contains an indeterminate loading indicator.
  await tester.pump(const Duration(milliseconds: 100));
}

  testWidgets(
    '知识页方剂与本草主从预览在775dp浅深主题及200%字号下保持分区',
    (tester) async {
      addTearDown(tester.view.reset);

      for (final brightness in Brightness.values) {
        await pumpKnowledge(
          tester,
          brightness: brightness,
          size: const Size(775, 900),
        );

        await tester.tap(find.text('方剂'));
        await tester.pumpAndSettle();
        final formula = FormulaRepository.getAll().first;
        final formulaRow = find.text(formula.name).first;
        await tester.ensureVisible(formulaRow);
        final formulaSource = find.ancestor(
          of: formulaRow,
          matching: find.byType(ListTile),
        ).first;
        final formulaSourceRect = tester.getRect(formulaSource);
        expect(
          formulaSourceRect.right,
          lessThanOrEqualTo(388),
          reason: '方剂列表触发行必须位于左侧安全面板：$formulaSourceRect',
        );
        await tester.tap(formulaRow);
        await tester.pumpAndSettle();

        expect(find.text('打开完整详情'), findsOneWidget);
        expect(find.text('适应证'), findsOneWidget);
        expect(find.text('组成'), findsOneWidget);
        final formulaListTile = find.ancestor(
          of: find.text(formula.name).first,
          matching: find.byType(ListTile),
        ).first;
        final formulaMasterRect = tester.getRect(formulaListTile);
        final formulaPreviewRect = tester.getRect(find.text('打开完整详情'));
        expect(
          formulaPreviewRect.left,
          greaterThan(formulaMasterRect.right),
          reason: '方剂预览应位于列表主栏右侧，不与列表重叠',
        );
        expect(
          tester.widgetList<Card>(find.byType(Card)).every(
                (card) => card.elevation == null || card.elevation == 0,
              ),
          isTrue,
          reason: '方剂浏览页面不应重新引入卡片阴影',
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('本草'));
        await tester.pumpAndSettle();
        final herb = HerbRepository.getAll().first;
        final herbRow = find.text(herb.name).first;
        await tester.ensureVisible(herbRow);
        final herbSource = find.ancestor(
          of: herbRow,
          matching: find.byType(ListTile),
        ).first;
        final herbSourceRect = tester.getRect(herbSource);
        expect(
          herbSourceRect.right,
          lessThanOrEqualTo(388),
          reason: '本草列表触发行必须位于左侧安全面板：$herbSourceRect',
        );
        await tester.tap(herbRow);
        await tester.pumpAndSettle();

        expect(find.text('打开完整详情'), findsOneWidget);
        expect(find.text(herb.name).last, findsOneWidget);
        final herbListTile = find.ancestor(
          of: find.text(herb.name).first,
          matching: find.byType(ListTile),
        ).first;
        final herbMasterRect = tester.getRect(herbListTile);
        final herbPreviewRect = tester.getRect(find.text('打开完整详情'));
        expect(
          herbPreviewRect.left,
          greaterThan(herbMasterRect.right),
          reason: '本草预览应位于列表主栏右侧，不与列表重叠',
        );
        expect(
          tester.widgetList<Card>(find.byType(Card)).every(
                (card) => card.elevation == null || card.elevation == 0,
              ),
          isTrue,
          reason: '本草浏览页面不应重新引入卡片阴影',
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'Find N2 半折叠面板内的方剂与本草详情路由在浅深主题及200%字号下不越过铰链',
    (tester) async {
      addTearDown(tester.view.reset);

      for (final brightness in Brightness.values) {
        await pumpKnowledge(
          tester,
          brightness: brightness,
          size: const Size(800, 900),
          halfFolded: true,
        );

        await tester.tap(find.text('方剂'));
        await tester.pumpAndSettle();
        final formula = FormulaRepository.getAll().first;
        final formulaRow = find.text(formula.name).first;
        await tester.ensureVisible(formulaRow);
        final formulaSource = find.ancestor(
          of: formulaRow,
          matching: find.byType(ListTile),
        ).first;
        final formulaSourceRect = tester.getRect(formulaSource);
        expect(
          formulaSourceRect.right,
          lessThanOrEqualTo(388),
          reason: '方剂列表触发行必须位于左侧安全面板：$formulaSourceRect',
        );
        await tester.tap(formulaRow);
        // Do not measure the Scaffold while MaterialPageRoute is still sliding in.
        await _pumpUntilRouteAnimationCompletes(
          tester,
          find.byType(FormulaDetailScreen),
        );
        await _waitForBookmarkLookup(tester, formula.name);

        expect(find.byType(FormulaDetailScreen), findsOneWidget);
        expect(find.text('组成'), findsOneWidget);
        expect(find.text('适应证'), findsOneWidget);
        final formulaScaffold = find.descendant(
          of: find.byType(FormulaDetailScreen),
          matching: find.byType(Scaffold),
        ).first;
        final formulaPage = tester.getRect(formulaScaffold);
        expect(
          formulaPage.left,
          greaterThanOrEqualTo(0),
          reason: '方剂详情页面左边界异常：$formulaPage',
        );
        expect(
          formulaPage.right,
          lessThanOrEqualTo(388),
          reason:
              '半折叠方剂详情必须留在左侧物理面板；详情=$formulaPage，触发行=$formulaSourceRect',
        );
        final formulaContext = tester.element(find.byType(FormulaDetailScreen));
        expect(MediaQuery.textScalerOf(formulaContext).scale(1), 2);
        expect(tester.takeException(), isNull);

        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('本草').first);
        await tester.pumpAndSettle();
        final herb = HerbRepository.getAll().first;
        final herbRow = find.text(herb.name).first;
        await tester.ensureVisible(herbRow);
        final herbSource = find.ancestor(
          of: herbRow,
          matching: find.byType(ListTile),
        ).first;
        final herbSourceRect = tester.getRect(herbSource);
        expect(
          herbSourceRect.right,
          lessThanOrEqualTo(388),
          reason: '本草列表触发行必须位于左侧安全面板：$herbSourceRect',
        );
        await tester.tap(herbRow);
        await _pumpUntilRouteAnimationCompletes(
          tester,
          find.byType(HerbDetailScreen),
        );
        await _waitForBookmarkLookup(tester, herb.name);

        expect(find.byType(HerbDetailScreen), findsOneWidget);
        expect(find.text(herb.category), findsOneWidget);
        final herbScaffold = find.descendant(
          of: find.byType(HerbDetailScreen),
          matching: find.byType(Scaffold),
        ).first;
        final herbPage = tester.getRect(herbScaffold);
        expect(
          herbPage.left,
          greaterThanOrEqualTo(0),
          reason: '本草详情页面左边界异常：$herbPage',
        );
        expect(
          herbPage.right,
          lessThanOrEqualTo(388),
          reason:
              '半折叠本草详情必须留在左侧物理面板；详情=$herbPage，触发行=$herbSourceRect',
        );
        final herbContext = tester.element(find.byType(HerbDetailScreen));
        expect(MediaQuery.textScalerOf(herbContext).scale(1), 2);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );
}
