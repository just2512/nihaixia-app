import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/data/medical_case_data.dart';
import 'package:nihaisha_app/screens/formula_detail_screen.dart';
import 'package:nihaisha_app/screens/herb_detail_screen.dart';
import 'package:nihaisha_app/screens/medical_case_detail_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

late MedicalCase _sampleCase;
var _databaseSequence = 0;

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await FormulaRepository.load();
    await HerbRepository.load();

    final cases = await loadMedicalCasesFromAssets();
    _sampleCase = cases.firstWhere(
      (item) =>
          item.patient.isNotEmpty &&
          item.diagnosis.isNotEmpty &&
          item.mechanism.isNotEmpty,
      orElse: () => throw StateError(
        'Expected at least one real medical case with the core recorded fields',
      ),
    );
  });

  setUp(() {
    DatabaseHelper.configureTestDatabase(
      'phase2_detail_layout_${_databaseSequence++}.db',
      factory: databaseFactoryFfi,
    );
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  Future<void> pumpDetail(
    WidgetTester tester, {
    required Widget page,
    required String key,
    required double width,
    required Brightness brightness,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    final tokens =
        brightness == Brightness.dark ? AppColors.dark : AppColors.light;
    await tester.pumpWidget(
      MaterialApp(
        key: ValueKey(key),
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
        home: page,
      ),
    );
    // These detail pages start asynchronous bookmark/index reads. Do not use
    // pumpAndSettle on FormulaDetailScreen: its classic-source section has an
    // intentional indeterminate loading indicator while the 833 source assets
    // are indexed. The assertions below target the stable first-frame content.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('方剂详情在402/775dp、浅深主题与200%字号下保持内容可读',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final formula = FormulaRepository.getAll().first;
    expect(formula.name, isNotEmpty);

    for (final brightness in Brightness.values) {
      for (final width in [402.0, 775.0]) {
        await pumpDetail(
          tester,
          page: FormulaDetailScreen(formula: formula),
          key: 'formula-${width.toInt()}-${brightness.name}',
          width: width,
          brightness: brightness,
        );
        final context = tester.element(find.byType(FormulaDetailScreen));
        expect(MediaQuery.textScalerOf(context).scale(1), 2);
        expect(find.text(formula.name), findsWidgets);
        expect(find.text('组成'), findsOneWidget);
        expect(find.text('适应证'), findsOneWidget);
        expect(find.text('见于经典'), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: '方剂详情在${width.toInt()}dp / ${brightness.name} / 200% 不应溢出');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }
  });

  testWidgets('本草详情在402/775dp、浅深主题与200%字号下保持内容可读',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final herb = HerbRepository.getAll().first;
    expect(herb.name, isNotEmpty);

    for (final brightness in Brightness.values) {
      for (final width in [402.0, 775.0]) {
        await pumpDetail(
          tester,
          page: HerbDetailScreen(herb: herb),
          key: 'herb-${width.toInt()}-${brightness.name}',
          width: width,
          brightness: brightness,
        );
        final context = tester.element(find.byType(HerbDetailScreen));
        expect(MediaQuery.textScalerOf(context).scale(1), 2);
        expect(find.text(herb.name), findsWidgets);
        // Verify the in-viewport header data. Related-content action cards
        // follow the herb's long-form sections and are covered by navigation
        // tests; they are not required to be lazily built on the first frame.
        expect(find.text(herb.category), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: '本草详情在${width.toInt()}dp / ${brightness.name} / 200% 不应溢出');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }
  });

  testWidgets('医案详情在402/775dp、浅深主题与200%字号下保持字段完整',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final brightness in Brightness.values) {
      for (final width in [402.0, 775.0]) {
        await pumpDetail(
          tester,
          page: MedicalCaseDetailScreen(
            c: _sampleCase,
            allCases: [_sampleCase],
          ),
          key: 'medical-case-${width.toInt()}-${brightness.name}',
          width: width,
          brightness: brightness,
        );
        final context = tester.element(find.byType(MedicalCaseDetailScreen));
        expect(MediaQuery.textScalerOf(context).scale(1), 2);
        expect(find.text('主要诊断'), findsOneWidget);
        expect(find.text('中医病机'), findsOneWidget);
        expect(
          find.text('#${_sampleCase.seq}  ${_sampleCase.displayName}'),
          findsOneWidget,
          reason: '详情页保留 App 内部医案编号和条目标题作为本地回链',
        );
        expect(find.textContaining('原始来源账本'), findsNothing);
        expect(tester.takeException(), isNull,
            reason: '医案详情在${width.toInt()}dp / ${brightness.name} / 200% 不应溢出');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }
  });
}
