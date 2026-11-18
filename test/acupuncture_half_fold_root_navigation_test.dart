import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/acupuncture_repository.dart';
import 'package:nihaisha_app/data/acupoint_repository.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/screens/acupuncture_screen.dart';
import 'package:nihaisha_app/screens/home_screen.dart';
import 'package:nihaisha_app/screens/knowledge_screen.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await FormulaRepository.load();
    await HerbRepository.load();
    await AcupunctureRepository.load();
    await AcupointRepository.load();
  });

  setUp(() async {
    DatabaseHelper.configureTestDatabase(
      'acupuncture_half_fold_${_databaseSequence++}.db',
      factory: databaseFactoryFfi,
    );
    // The real KnowledgeScreen can initialize asynchronous data reads.
    // Open the isolated test database before mounting the root shell.
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      '真实根导航下针灸四个子页在半折叠388dp安全面板、${brightness.name}主题及200%字号下可用',
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

        final tokens = brightness == Brightness.dark
            ? AppColors.dark
            : AppColors.light;
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
            // Use the production HomeScreen / AdaptiveHomeNavigation / KnowledgeScreen.
            // Unrelated AI, tools, bookmarks and settings pages are inert fixtures.
            home: HomeScreen(testScreens: _foldableHomeScreens()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('知识').last);
        await tester.pumpAndSettle();
        expect(find.byType(KnowledgeScreen), findsOneWidget);

        final knowledgeScaffold = find.descendant(
          of: find.byType(KnowledgeScreen),
          matching: find.byType(Scaffold),
        ).first;
        final knowledgeRect = tester.getRect(knowledgeScaffold);
        expect(
          knowledgeRect.right,
          lessThanOrEqualTo(388),
          reason: '知识页面必须处于左侧物理安全面板：$knowledgeRect',
        );

        await tester.tap(find.text('针灸').last);
        await tester.pumpAndSettle();
        expect(find.byType(AcupunctureScreen), findsOneWidget);

        final acupunctureContext =
            tester.element(find.byType(AcupunctureScreen));
        expect(
          MediaQuery.textScalerOf(acupunctureContext).scale(1),
          2,
          reason: '针灸页必须继承200%字号，不能在导航或Tab路由中回落',
        );
        final acupunctureColumn = find.descendant(
          of: find.byType(AcupunctureScreen),
          matching: find.byType(Column),
        ).first;
        final acupunctureRect = tester.getRect(acupunctureColumn);
        expect(
          acupunctureRect.right,
          lessThanOrEqualTo(388),
          reason: '针灸内容列不得越过物理铰链：$acupunctureRect',
        );

        for (final tab in ['穴位处方', '透针透穴', '穴位讲解', '耳穴']) {
          await tester.tap(find.text(tab).last);
          await tester.pump();
          if (tab == '耳穴') {
            // Ear-point data is loaded asynchronously from the bundled asset.
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 1)),
            );
            await tester.pump();
          }
          await tester.pumpAndSettle();

          expect(find.byType(AcupunctureScreen), findsOneWidget);
          expect(
            tester.getRect(acupunctureColumn).right,
            lessThanOrEqualTo(388),
            reason: '$tab 内容不得跨越半折叠物理铰链',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$tab / 388dp / ${brightness.name} / 200% 不应出现布局异常',
          );
        }
      },
    );
  }
}
