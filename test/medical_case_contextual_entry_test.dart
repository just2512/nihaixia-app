import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/medical_case_data.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';
import 'support/in_memory_assistant_conversation_store.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/medical_case_detail_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';

var _databaseSequence = 0;
late List<MedicalCase> _medicalCases;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _medicalCases = await getAllMedicalCases();
  });

  setUp(() async {
    DatabaseHelper.configureTestDatabase(
      'medical_case_contextual_entry_${_databaseSequence++}.db',
      factory: databaseFactoryFfi,
    );
    await DatabaseHelper.instance.database;
  });

  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  test('medical-case context resolves an exact local learning record without bibliographic gates', () async {
    final medicalCase = _medicalCases.singleWhere((item) => item.seq == 2);
    final ref = AiContextResolver.buildMedicalCaseContextRef(medicalCase);
    final resolved =
        await AiContextResolver.resolveMedicalCase(ref: ref);

    expect(ref.kind, AiContextKind.caseRecord);
    expect(ref.moduleId, 'medical-cases');
    expect(ref.anchorId, 'medical-case:2');
    expect(ref.anchorVersion, startsWith('cases_table.md@'));
    expect(ref.anchorVersion, isNot(contains('source_ledger')));
    expect(
      ref.sourceId,
      'app-data:assets/medical_cases/cases_table.md#seq=2',
    );
    expect(resolved.isResolved, isTrue);
    expect(
      resolved.value?.content['diagnosis'],
      medicalCase.diagnosis,
    );
    final prompt = AiContextPromptBuilder.buildMedicalCaseKnowledgeEntry(
      entry: resolved.value!,
    );
    expect(prompt, contains('当前 App 本地医案记录'));
    expect(prompt, contains(ref.sourceId));
    expect(prompt, contains('【医案实际记录字段】'));
    expect(prompt, contains('【学习分析要求】'));
    expect(prompt, contains('该案例进行复盘'));
    expect(prompt, contains('不得把单条历史案例直接套用'));
    expect(prompt, isNot(contains('source_ledger.json')));
    expect(prompt, isNot(contains('纸本/影印本')));
    expect(prompt, isNot(contains('bibliographicLocatorStatus')));
    expect(
      prompt,
      contains(medicalCase.diagnosis.isEmpty ? 'MISSING' : medicalCase.diagnosis),
    );
    expect(
      prompt,
      contains(medicalCase.formula.isEmpty ? 'MISSING' : medicalCase.formula),
    );

    final stale = AiContextRef(
      kind: AiContextKind.caseRecord,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: 'cases_table.md@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveMedicalCase(ref: stale)).status,
      AiContextResolutionStatus.unknown,
    );

    final sourceMismatch = AiContextRef(
      kind: AiContextKind.caseRecord,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      sourceId: 'unverified:medical-case:2',
      title: ref.title,
    );
    expect(
      (await AiContextResolver.resolveMedicalCase(ref: sourceMismatch)).status,
      AiContextResolutionStatus.unknown,
    );

    final missing = AiContextRef(
      kind: AiContextKind.caseRecord,
      moduleId: ref.moduleId,
      anchorId: 'medical-case:999999',
      anchorVersion: ref.anchorVersion,
      sourceId:
          'app-data:assets/medical_cases/cases_table.md#seq=999999',
      title: '#999999 不存在',
    );
    expect(
      (await AiContextResolver.resolveMedicalCase(ref: missing)).status,
      AiContextResolutionStatus.missing,
    );
  });

  testWidgets(
    'medical-case detail exposes contextual Ask AI without auto-opening a second chat',
    (tester) async {
      final medicalCase =
          _medicalCases.singleWhere((item) => item.seq == 2);
      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            home: MedicalCaseDetailScreen(
              c: medicalCase,
              allCases: [medicalCase],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MedicalCaseDetailScreen), findsOneWidget);
      expect(find.text('问 AI 解读当前医案'), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('问 AI 解读当前医案'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final assistant = find.byType(LocalAiInterviewScreen);
      expect(assistant, findsOneWidget);
      final assistantWidget = tester.widget<LocalAiInterviewScreen>(assistant);
      expect(assistantWidget.initialMode, AssistantMode.learning);
      expect(assistantWidget.contextualExplanationOnly, isTrue);
      expect(assistantWidget.contextRef['kind'], 'case');
      expect(assistantWidget.contextRef['moduleId'], 'medical-cases');
      expect(assistantWidget.contextRef['anchorId'], 'medical-case:2');
      expect(assistantWidget.initialPrompt, contains('当前 App 本地医案记录'));
      expect(assistantWidget.initialPrompt, contains('app-data:assets/medical_cases/cases_table.md#seq=2'));
      expect(assistantWidget.initialPrompt, contains('【医案实际记录字段】'));
      expect(assistantWidget.initialPrompt, contains('【学习分析要求】'));
      expect(
        assistantWidget.initialPrompt,
        contains(medicalCase.diagnosis.isEmpty ? 'MISSING' : medicalCase.diagnosis),
      );
      expect(
        assistantWidget.initialPrompt,
        contains(medicalCase.formula.isEmpty ? 'MISSING' : medicalCase.formula),
      );
      expect(assistantWidget.initialPrompt, isNot(contains('source_ledger.json')));
      expect(assistantWidget.initialPrompt, isNot(contains('纸本/影印本定位状态')));
      expect(tester.takeException(), isNull);
    },
  );
}
