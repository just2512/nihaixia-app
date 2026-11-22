import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/data/medical_case_data.dart';
import 'package:nihaisha_app/screens/classic_library_screen.dart';
import 'package:nihaisha_app/screens/home_screen.dart';
import 'package:nihaisha_app/screens/knowledge_screen.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/screens/medical_case_detail_screen.dart';
import 'package:nihaisha_app/screens/medical_case_library_screen.dart';
import 'package:nihaisha_app/screens/meridian_detail_screen.dart';
import 'package:nihaisha_app/screens/tools_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/medical_case_list_card.dart';

var _databaseSequence = 0;
late List<MedicalCase> _medicalCases;

List<Widget> _homeScreens() => [
      const Scaffold(body: Center(child: Text('AI 测试页'))),
      const ToolsScreen(),
      const KnowledgeScreen(),
      const Scaffold(body: Center(child: Text('收藏测试页'))),
      const Scaffold(body: Center(child: Text('设置测试页'))),
    ];

Future<void> _advanceRoute(WidgetTester tester) async {
  // Start the route transition, then advance its finite animation. The root
  // IndexedStack keeps unrelated pages alive, so global pumpAndSettle is not
  // a reliable signal that a newly pushed route has finished entering.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 100));
}

void _expectPageInsideLeftPanel(
  WidgetTester tester, {
  required Type pageType,
  required String label,
}) {
  expect(find.byType(pageType), findsOneWidget);
  final pageScaffold = find.descendant(
    of: find.byType(pageType),
    matching: find.byType(Scaffold),
  ).first;
  final rect = tester.getRect(pageScaffold);
  expect(
    rect.left,
    greaterThanOrEqualTo(0),
    reason: '$label 左边界异常：$rect',
  );
  expect(
    rect.right,
    lessThanOrEqualTo(388),
    reason: '$label 必须完整位于半折叠左侧安全面板：$rect',
  );
  final context = tester.element(find.byType(pageType));
  expect(
    MediaQuery.textScalerOf(context).scale(1),
    2,
    reason: '$label 必须继承200%字号',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await FormulaRepository.load();
    await HerbRepository.load();
    _medicalCases = await loadMedicalCasesFromAssets();
    expect(_medicalCases, isNotEmpty);
  });

  setUp(() async {
    DatabaseHelper.configureTestDatabase(
      'phase2_remaining_fold_routes_${_databaseSequence++}.db',
      factory: databaseFactoryFfi,
    );
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      '真实根导航下六经、经典正文和医案详情在半折叠面板及200%字号下可读（${brightness.name}）',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 900);
        tester.view.displayFeatures = [
          DisplayFeature(
            bounds: const Rect.fromLTWH(388, 0, 24, 900),
            type: DisplayFeatureType.hinge,
            state: DisplayFeatureState.postureHalfOpened,
          ),
        ];
        addTearDown(tester.view.resetDisplayFeatures);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final colors =
            brightness == Brightness.dark ? AppColors.dark : AppColors.light;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: AppColors.colorSchemeFor(brightness),
              extensions: [colors],
              cardTheme: const CardThemeData(elevation: 0),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
              ),
              child: child!,
            ),
            home: HomeScreen(testScreens: _homeScreens()),
          ),
        );
        await tester.pumpAndSettle();

        // Real root navigation -> KnowledgeScreen -> MeridianDetailScreen.
        await tester.tap(find.text('知识').last);
        await tester.pumpAndSettle();
        final meridianRow = find.text('太阳病').first;
        await tester.ensureVisible(meridianRow);
        await tester.tap(meridianRow);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        // The knowledge card first expands to reveal its explicit detail
        // action; use that actual UI affordance instead of assuming the
        // ExpansionTile header also dispatches the outer InkWell route.
        if (find.byType(MeridianDetailScreen).evaluate().isEmpty) {
          final meridianCard = find.ancestor(
            of: meridianRow,
            matching: find.byType(Card),
          ).first;
          final detailAction = find.descendant(
            of: meridianCard,
            matching: find.text('查看详情'),
          );
          expect(detailAction, findsOneWidget);
          final knowledgeScrollable = find.descendant(
            of: find.byType(KnowledgeScreen),
            matching: find.byType(Scrollable),
          ).first;
          // At 200% the expanded card's detail action can be below the
          // viewport. Scroll the active KnowledgeScreen list, rather than
          // relying on ensureVisible across the nested TabBarView tree.
          await tester.scrollUntilVisible(
            detailAction,
            220,
            scrollable: knowledgeScrollable,
            maxScrolls: 12,
          );
          await tester.pump(const Duration(milliseconds: 100));
          final actionRect = tester.getRect(detailAction);
          expect(
            actionRect.bottom,
            lessThanOrEqualTo(900),
            reason: '六经详情操作应先进入视口：$actionRect',
          );
          await tester.tap(detailAction);
        }
        await _advanceRoute(tester);
        _expectPageInsideLeftPanel(
          tester,
          pageType: MeridianDetailScreen,
          label: '六经详情',
        );
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();

        // Real knowledge tab -> classical library -> actual Markdown article.
        final classicsTab = find.text('伤寒金匮').last;
        await tester.ensureVisible(classicsTab);
        await tester.pumpAndSettle();
        await tester.tap(classicsTab);
        await tester.pumpAndSettle();
        final shanghanBook = find.text('伤寒论').last;
        await tester.ensureVisible(shanghanBook);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(shanghanBook).bottom,
          lessThanOrEqualTo(tester.view.physicalSize.height),
          reason: '伤寒论入口必须先完整进入可点击视口',
        );
        await tester.tap(shanghanBook);
        await _advanceRoute(tester);
        _expectPageInsideLeftPanel(
          tester,
          pageType: ClassicLibraryScreen,
          label: '经典篇目目录',
        );
        final firstLecture = find.descendant(
          of: find.byType(ClassicLibraryScreen),
          matching: find.byType(ListTile),
        ).first;
        await tester.ensureVisible(firstLecture);
        await tester.tap(firstLecture);
        await _advanceRoute(tester);
        _expectPageInsideLeftPanel(
          tester,
          pageType: MarkdownDocScreen,
          label: '经典原文正文',
        );
        expect(tester.takeException(), isNull);
        final markdownBack = find.descendant(
          of: find.byType(MarkdownDocScreen),
          matching: find.byTooltip('Back'),
        );
        expect(markdownBack, findsOneWidget);
        await tester.tap(markdownBack);
        await tester.pumpAndSettle();

        final classicBack = find.descendant(
          of: find.byType(ClassicLibraryScreen),
          matching: find.byTooltip('Back'),
        );
        expect(classicBack, findsOneWidget);
        await tester.tap(classicBack);
        await tester.pumpAndSettle();

        // Real root navigation -> ToolsScreen -> MedicalCaseLibraryScreen
        // -> a real MedicalCaseDetailScreen route, backed by the test FFI DB.
        await tester.tap(find.text('工具').last);
        await tester.pumpAndSettle();
        final caseEntry = find.textContaining('倪师医案库').last;
        final toolsScrollable = find.descendant(
          of: find.byType(ToolsScreen),
          matching: find.byType(Scrollable),
        ).first;
        await tester.scrollUntilVisible(
          caseEntry,
          240,
          scrollable: toolsScrollable,
          maxScrolls: 20,
        );
        await tester.pump(const Duration(milliseconds: 100));
        final caseEntryRect = tester.getRect(caseEntry);
        expect(
          caseEntryRect.bottom,
          lessThanOrEqualTo(900),
          reason: '医案库入口必须先滚动进入视口：$caseEntryRect',
        );
        await tester.tap(caseEntry);
        await _advanceRoute(tester);
        expect(find.byType(MedicalCaseLibraryScreen), findsOneWidget);

        final caseCards = find.descendant(
          of: find.byType(MedicalCaseLibraryScreen),
          matching: find.byType(MedicalCaseListCard),
        );
        for (var attempt = 0;
            attempt < 60 && caseCards.evaluate().isEmpty;
            attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
        }
        expect(
          caseCards,
          findsWidgets,
          reason: '医案库必须完成真实数据加载后才能进入详情',
        );
        // MedicalCaseLibraryScreen refreshes favorites and recent history in
        // the background after its data Future completes. Drain those queued
        // FFI reads in real async time before the detail page starts its own
        // serialized recent-history write followed by bookmark lookup.
        await tester.runAsync(() async {
          await DatabaseHelper.instance.getBookmarkedMedicalCaseSeqs();
          await DatabaseHelper.instance.getRecentMedicalCaseSeqs(limit: 20);
        });
        await tester.pump();
        final firstCaseCard = caseCards.first;
        await tester.ensureVisible(firstCaseCard);
        final selectedCase = tester.widget<MedicalCaseListCard>(firstCaseCard).c;
        await tester.tap(firstCaseCard);
        await _advanceRoute(tester);
        // MedicalCaseDetailScreen serializes recent-history upsert followed
        // by bookmark lookup. Mirror the established detail-layout regression:
        // execute a bookmark read in real async time so the sqflite FFI lock
        // timer and the page's queued read finish before test DB teardown.
        final bookmarkState = await tester.runAsync<bool>(
          () => DatabaseHelper.instance.isMedicalCaseBookmarked(
            selectedCase.seq,
          ),
        );
        expect(bookmarkState, isNotNull);
        await tester.pump();
        _expectPageInsideLeftPanel(
          tester,
          pageType: MedicalCaseDetailScreen,
          label: '医案详情',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
