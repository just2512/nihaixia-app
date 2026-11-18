import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/formula_detail_screen.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

var _databaseSequence = 0;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await FormulaRepository.load();
  });

  setUp(() async {
    DatabaseHelper.configureTestDatabase(
      'formula_contextual_entry_${_databaseSequence++}.db',
      factory: databaseFactoryFfi,
    );
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  test('formula context resolves only against the verified asset version', () {
    final formula = FormulaRepository.getAll().first;
    final ref = AiContextResolver.buildFormulaContextRef(formula);
    final resolved = AiContextResolver.resolveFormula(
      ref: ref,
      formula: formula,
    );

    expect(ref.kind, AiContextKind.formula);
    expect(ref.sourceId, 'formula:${formula.id}');
    expect(ref.anchorId, 'formula:${formula.id}');
    expect(resolved.isResolved, isTrue);
    expect(resolved.value?.content['name'], formula.name);

    final staleRef = AiContextRef(
      kind: AiContextKind.formula,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: 'assets/data/formulas.json@STALE',
      sourceId: ref.sourceId,
      title: formula.name,
    );
    expect(
      AiContextResolver.resolveFormula(ref: staleRef, formula: formula).isResolved,
      isFalse,
    );
  });

  testWidgets(
    'formula detail exposes a contextual Ask AI entry without opening it automatically',
    (tester) async {
      final formula = FormulaRepository.getAll().first;
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(775, 900);
      tester.view.displayFeatures = const <DisplayFeature>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: AppColors.colorSchemeFor(Brightness.light),
            extensions: [AppColors.light],
          ),
          home: FormulaDetailScreen(formula: formula),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(FormulaDetailScreen), findsOneWidget);
      expect(find.text('问 AI 解读当前方剂'), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
