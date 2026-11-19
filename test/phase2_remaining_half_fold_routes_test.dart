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
        await tester.tap(classicsTab);
        await tester.pumpAndSettle();
        final shanghanBook = find.text('伤寒论').last;
        await tester.ensureVisible(shanghanBook);
        await tester.tap(shanghanBook);
        await _advanceRoute(tester);
        _expectPageInsideLeftPanel(
          tester,
          pageType: ClassicLibraryScreen,
          label: '经典篇目目录',
        );
        final firstLecture = find.byType(ListTile).first;
        await tester.ensureVisible(firstLecture);
        await tester.tap(firstLecture);
        await _advanceRoute(tester);
        _expectPageInsideLeftPanel(
          tester,
          pageType: MarkdownDocScreen,
          label: '经典原文正文',
        );
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();

        // Real root navigation -> ToolsScreen -> MedicalCaseLibraryScreen
        // -> a real MedicalCaseDetailScreen route, backed by the test FFI DB.
        await tester.tap(find.text('工具').last);
        await tester.pumpAndSettle();
        final caseEntry = find.textContaining('倪师医案库').last;
        await tester.ensureVisible(caseEntry);
        await tester.tap(caseEntry);
        await _advanceRoute(tester);
        expect(find.byType(MedicalCaseLibraryScreen), findsOneWidget);

        final caseCards = find.byType(MedicalCaseListCard);
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
        final firstCaseCard = caseCards.first;
        await tester.ensureVisible(firstCaseCard);
        await tester.tap(firstCaseCard);
        await _advanceRoute(tester);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 120)),
        );
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
