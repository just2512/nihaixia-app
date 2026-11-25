import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/acupuncture_repository.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';
import 'support/in_memory_assistant_conversation_store.dart';
import 'package:nihaisha_app/screens/acupuncture_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AcupunctureRepository.load();
  });

  testWidgets('助手针灸来源按分类 ID 和条目 ID 展开精确处方', (tester) async {
    final category = AcupunctureRepository.getAll().firstWhere(
      (item) => item.id == '01',
    );
    final entry = category.entries.firstWhere((item) => item.id == 1);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: AppColors.colorSchemeFor(Brightness.light),
          useMaterial3: true,
          extensions: [AppColors.light],
        ),
        home: Scaffold(
          body: AcupunctureScreen(
            initialCategoryId: category.id,
            initialEntryId: entry.id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(entry.symptom), findsWidgets);
    expect(find.text('别名: '), findsOneWidget);
    expect(find.text('关元'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('acupuncture prescription context resolves only one exact category entry', () {
    final category = AcupunctureRepository.getAll().singleWhere(
      (item) => item.id == '01',
    );
    final entry = category.entries.singleWhere((item) => item.id == 1);
    final ref = AiContextResolver.buildAcupunctureEntryContextRef(
      categoryId: category.id,
      entry: entry,
    );
    final resolution = AiContextResolver.resolveAcupunctureEntry(ref: ref);

    expect(ref.kind, AiContextKind.knowledgeEntry);
    expect(ref.moduleId, AiContextResolver.acupunctureModuleId);
    expect(ref.anchorId, 'acupuncture-prescriptions:01:1');
    expect(ref.sourceId, 'acupuncture:01:1');
    expect(ref.snapshotId, hasLength(64));
    expect(ref.anchorVersion, ref.snapshotId);
    expect(ref.ruleVersion, AiContextResolver.acupunctureAssetVersion);
    expect(resolution.isResolved, isTrue);
    expect(resolution.value?.title, '冠心病');
    final record = resolution.value!.content['entry']! as Map;
    expect(record['symptom'], '冠心病');
    expect(record['source'], 'nihaisha+bbxx');
    expect(record['acupoints'], isA<List>());

    final prompt = AiContextPromptBuilder.buildAcupunctureKnowledgeEntry(
      entry: resolution.value!,
    );
    expect(prompt, contains('冠心病'));
    expect(prompt, contains('nihaisha+bbxx'));
    expect(prompt, isNot(contains('独立核验')),
        reason: '针灸条目保留 App 原始来源标记，不再附加外部独立考证要求');
    expect(prompt, contains('原始来源标记'));
    expect(prompt, contains('不得提供个人诊断'));
    expect(prompt, contains('不得扩展为针对个人'));
    expect(prompt, contains('token 计数：UNKNOWN'));
    expect(prompt, contains('MISSING'));
    expect(prompt, contains('UNKNOWN'));

    final wrongSource = AiContextRef(
      kind: ref.kind,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'acupuncture:02:1',
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveAcupunctureEntry(ref: wrongSource).status,
      AiContextResolutionStatus.unknown,
    );

    final staleVersion = AiContextRef(
      kind: ref.kind,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: 'assets/data/acupuncture.json@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveAcupunctureEntry(ref: staleVersion).status,
      AiContextResolutionStatus.stale,
    );

    // The same numeric entry ID exists in more than one category; the category
    // ID is part of the canonical identity and the snapshot.
    final otherCategory = AcupunctureRepository.getAll().singleWhere(
      (item) => item.id == '08',
    );
    final sameNumericId = otherCategory.entries.singleWhere(
      (item) => item.id == entry.id,
    );
    final otherCategoryRef =
        AiContextResolver.buildAcupunctureEntryContextRef(
      categoryId: otherCategory.id,
      entry: sameNumericId,
    );
    expect(otherCategoryRef.anchorId, 'acupuncture-prescriptions:08:1');
    expect(otherCategoryRef.sourceId, 'acupuncture:08:1');
    expect(otherCategoryRef.snapshotId, isNot(ref.snapshotId));
    expect(
      AiContextResolver.resolveAcupunctureEntry(ref: otherCategoryRef).isResolved,
      isTrue,
    );
    final crossCategorySnapshot = AiContextRef(
      kind: ref.kind,
      moduleId: ref.moduleId,
      anchorId: otherCategoryRef.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: otherCategoryRef.sourceId,
      title: otherCategoryRef.title,
    );
    expect(
      AiContextResolver.resolveAcupunctureEntry(ref: crossCategorySnapshot).status,
      AiContextResolutionStatus.stale,
    );

    // A parseable ID is not enough: anchor IDs must use canonical decimal form.
    final nonCanonicalAnchor = AiContextRef(
      kind: ref.kind,
      moduleId: ref.moduleId,
      anchorId: 'acupuncture-prescriptions:01:01',
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveAcupunctureEntry(ref: nonCanonicalAnchor).status,
      AiContextResolutionStatus.unknown,
    );

    const alteredDigest =
        '0000000000000000000000000000000000000000000000000000000000000000';
    final alteredSnapshot = AiContextRef(
      kind: ref.kind,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: alteredDigest,
      snapshotId: alteredDigest,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveAcupunctureEntry(ref: alteredSnapshot).status,
      AiContextResolutionStatus.stale,
    );

    final missing = AiContextRef(
      kind: AiContextKind.knowledgeEntry,
      moduleId: AiContextResolver.acupunctureModuleId,
      anchorId: 'acupuncture-prescriptions:01:999999',
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'acupuncture:01:999999',
      title: '不存在的针灸条目',
    );
    expect(
      AiContextResolver.resolveAcupunctureEntry(ref: missing).status,
      AiContextResolutionStatus.missing,
    );

    expect(
      () => AiContextResolver.buildAcupunctureEntryContextRef(
        categoryId: 'missing-category',
        entry: entry,
      ),
      throwsArgumentError,
    );
  });

  testWidgets(
    'acupuncture prescription entry opens a source-bound learning assistant at 402 and 775dp',
    (tester) async {
      addTearDown(tester.view.reset);
      final category = AcupunctureRepository.getAll().singleWhere(
        (item) => item.id == '01',
      );
      final entry = category.entries.singleWhere((item) => item.id == 1);
      final actionKey = ValueKey(
        'acupuncture-prescription-context-' + category.id + '-' +
            entry.id.toString(),
      );

      for (final width in [402.0, 775.0]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpWidget(
          ContextualAiConversationStoreScope(
            conversationStore: InMemoryAssistantConversationStore(),
            child: MaterialApp(
              theme: ThemeData(
                colorScheme: AppColors.colorSchemeFor(Brightness.light),
                useMaterial3: true,
                extensions: [AppColors.light],
              ),
              home: Scaffold(
                body: AcupunctureScreen(
                  initialCategoryId: category.id,
                  initialEntryId: entry.id,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(AcupunctureScreen), findsOneWidget);
        final actionFinder = find.byKey(actionKey);
        expect(actionFinder, findsOneWidget);
        await tester.ensureVisible(actionFinder);
        await tester.pump();
        await tester.tap(actionFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final assistantFinder = find.byType(LocalAiInterviewScreen);
        expect(assistantFinder, findsOneWidget);
        final assistant =
            tester.widget<LocalAiInterviewScreen>(assistantFinder);
        expect(assistant.initialMode, AssistantMode.learning);
        expect(assistant.contextualExplanationOnly, isTrue);
        expect(assistant.contextRef['kind'], 'knowledgeEntry');
        expect(
          assistant.contextRef['moduleId'],
          AiContextResolver.acupunctureModuleId,
        );
        expect(
          assistant.contextRef['anchorId'],
          'acupuncture-prescriptions:01:1',
        );
        expect(assistant.contextRef['snapshotId'], hasLength(64));
        expect(assistant.contextRef['sourceId'], 'acupuncture:01:1');
        expect(assistant.initialPrompt, contains('冠心病'));
        expect(assistant.initialPrompt, contains('不得提供个人诊断'));
        expect(tester.takeException(), isNull);

        Navigator.of(
          tester.element(assistantFinder),
          rootNavigator: true,
        ).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(AcupunctureScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

}
