import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:nihaisha_app/data/medical_case_data.dart';
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

  test('medical-case context resolves an exact internal row and retains source-ledger states', () async {
    final medicalCase = _medicalCases.singleWhere((item) => item.seq == 2);
    final ref = AiContextResolver.buildMedicalCaseContextRef(medicalCase);
    final resolved =
        await AiContextResolver.resolveMedicalCase(ref: ref);

    expect(ref.kind, AiContextKind.caseRecord);
    expect(ref.moduleId, 'medical-cases');
    expect(ref.anchorId, 'medical-case:2');
    expect(
      ref.sourceId,
      'app-data:assets/medical_cases/cases_table.md#seq=2',
    );
    expect(resolved.isResolved, isTrue);
    expect(
      resolved.value?.content['diagnosis'],
      medicalCase.diagnosis,
    );
    expect(
      resolved.value?.content['sourceTextVerificationStatus'],
      'VERIFIED',
    );
    expect(
      resolved.value?.content['bibliographicLocatorStatus'],
      'MISSING',
      reason: '网页原文匹配不能自动升级为纸本/影印本卷页核验',
    );

    final prompt = AiContextPromptBuilder.buildMedicalCaseKnowledgeEntry(
      entry: resolved.value!,
    );
    expect(prompt, contains('内部序号只用于定位'));
    expect(prompt, contains('原文 VERIFIED 只表示'));
    expect(prompt, contains('不得依据该历史病例为用户生成个人诊断'));
    expect(prompt, contains('source_ledger.json'));
    expect(prompt, contains('UNKNOWN'));

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
        MaterialApp(
          home: MedicalCaseDetailScreen(
            c: medicalCase,
            allCases: [medicalCase],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MedicalCaseDetailScreen), findsOneWidget);
      expect(find.text('问 AI 解读当前医案'), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
