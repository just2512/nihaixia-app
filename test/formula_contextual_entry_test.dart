import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/classic_lecture_data.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/formula_detail_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/in_memory_assistant_conversation_store.dart';
import 'support/allow_context_authorizer.dart';

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
      AiContextResolver.resolveFormula(ref: staleRef).isResolved,
      isFalse,
    );
  });

  testWidgets(
    'formula detail exposes a contextual Ask AI entry without opening it automatically',
    (tester) async {
      final formula = FormulaRepository.getByName('桂枝汤')!;
      expect(formula, isNotNull);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(775, 900);
      tester.view.displayFeatures = const <DisplayFeature>[];

      await tester.pumpWidget(
        TestAuthorizedFeatureScope(child: ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: AppColors.colorSchemeFor(Brightness.light),
              extensions: [AppColors.light],
            ),
            home: FormulaDetailScreen(formula: formula),
          ),
        )),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(FormulaDetailScreen), findsOneWidget);
      expect(find.text('问 AI 解读当前方剂'), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
      final ask = find.text('问 AI 解读当前方剂');
      await tester.ensureVisible(ask);
      await tester.pumpAndSettle();
      await tester.tap(ask);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final assistant = find.byType(LocalAiInterviewScreen);
      expect(assistant, findsOneWidget);
      final widget = tester.widget<LocalAiInterviewScreen>(assistant);
      expect(widget.initialMode, AssistantMode.learning);
      expect(widget.contextualExplanationOnly, isTrue);
      expect(widget.contextRef['kind'], 'formula');
      expect(widget.contextRef['moduleId'], 'formula');
      expect(widget.contextRef['anchorId'], 'formula:${formula.id}');
      expect(widget.contextRef['sourceId'], 'formula:${formula.id}');
      expect(widget.initialPrompt, contains(formula.name));
      expect(tester.takeException(), isNull);

      Navigator.of(
        tester.element(assistant),
        rootNavigator: true,
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(() async {
        // FormulaDetailScreen indexes linked Shanghan/Jingui assets
        // asynchronously; wait for the lookup instead of inspecting loading.
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pump();

      await tester.scrollUntilVisible(find.text('见于经典'), 300);
      final sourceLecture = kShangHanLectures.singleWhere(
        (lecture) => lecture.asset == 'assets/shanghan/clause_001.md',
      );
      final linkedLecture = find.text(sourceLecture.name);
      expect(linkedLecture, findsOneWidget);
      await tester.ensureVisible(linkedLecture);
      await tester.tap(linkedLecture);
      await tester.pumpAndSettle();

      final reader = tester.widget<MarkdownDocScreen>(
        find.byType(MarkdownDocScreen),
      );
      expect(reader.contextualAskModuleId, 'shanghan');
      expect(reader.contextualAskAnchorId, 'shanghan:clause:002');
      expect(
        reader.contextualAskSourceId,
        'assets/shanghan/clause_001.md',
      );
      expect(reader.contextualAskParagraphs, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
