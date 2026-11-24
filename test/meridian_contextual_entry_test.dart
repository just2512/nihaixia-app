import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/engine/diagnostic_rules.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/meridian_detail_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await FormulaRepository.load();
  });

  test('all six meridian records resolve from the exact local rule data', () {
    expect(DiagnosticRules.meridianDetails.keys, hasLength(6));

    for (final meridian in DiagnosticRules.meridianDetails.keys) {
      final details = DiagnosticRules.meridianDetails[meridian]!;
      final ref = AiContextResolver.buildMeridianContextRef(
        meridian: meridian,
      );
      final resolution =
          AiContextResolver.resolveMeridianKnowledgeEntry(ref: ref);

      expect(ref.kind, AiContextKind.knowledgeEntry, reason: meridian);
      expect(ref.moduleId, AiContextResolver.meridianModuleId);
      expect(ref.anchorId, 'meridian:detail:$meridian');
      expect(ref.title, '$meridian病');
      expect(ref.sourceId, AiContextResolver.meridianSourceId);
      expect(ref.ruleVersion, AiContextResolver.meridianRuleVersion);
      expect(ref.snapshotId, hasLength(64));
      expect(ref.anchorVersion, ref.snapshotId);
      expect(resolution.isResolved, isTrue, reason: meridian);

      final entry = resolution.value!;
      expect(entry.title, '$meridian病');
      expect(entry.content['meridian'], meridian);
      expect(entry.content['nature'], details['nature']);
      expect(entry.content['organ'], details['organ']);
      expect(entry.content['keyPulse'], details['keyPulse']);
      expect(entry.content['coreSymptoms'], details['coreSymptoms']);
      expect(
        entry.content['healingTime'],
        DiagnosticRules.meridianHealingTime[meridian],
      );
      expect(entry.content['transmissionIn'], details['transmissionIn']);
      expect(entry.content['transmissionOut'], details['transmissionOut']);
      expect(entry.content['classicText'], details['classicText']);
      expect(entry.content['niNote'], details['niNote']);

      final prompt = AiContextPromptBuilder.buildMeridianKnowledgeEntry(
        entry: entry,
      );
      expect(prompt, contains('六经：$meridian病'));
      expect(prompt, contains(details['keyPulse'] as String));
      expect(prompt, contains(details['classicText'] as String));
      expect(prompt, contains(details['niNote'] as String));
      expect(prompt, contains('token 计数：UNKNOWN'));
      expect(prompt, contains('不得提供个体诊断'));
      expect(prompt, contains(ref.sourceId));
    }

    final taiyang = AiContextResolver.buildMeridianContextRef(
      meridian: '太阳',
    );
    final shaoyang = AiContextResolver.buildMeridianContextRef(
      meridian: '少阳',
    );
    expect(taiyang.snapshotId, isNot(shaoyang.snapshotId));
    expect(
      AiContextRef.matchesSameAnchor(
        taiyang.toMetadata(),
        shaoyang.toMetadata(),
      ),
      isFalse,
    );
  });

  test('meridian resolver rejects unknown, mismatched and stale references', () {
    expect(
      () => AiContextResolver.buildMeridianContextRef(meridian: '厥阴病'),
      throwsArgumentError,
    );

    final ref = AiContextResolver.buildMeridianContextRef(
      meridian: '少阳',
    );

    final wrongSource = AiContextRef(
      kind: ref.kind,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: 'unverified:meridian',
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveMeridianKnowledgeEntry(ref: wrongSource).status,
      AiContextResolutionStatus.unknown,
    );

    final wrongAnchor = AiContextRef(
      kind: ref.kind,
      moduleId: ref.moduleId,
      anchorId: 'meridian:detail:太阳',
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveMeridianKnowledgeEntry(ref: wrongAnchor)
          .status,
      AiContextResolutionStatus.unknown,
    );

    final wrongTitle = AiContextRef(
      kind: ref.kind,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: '太阳病',
    );
    expect(
      AiContextResolver.resolveMeridianKnowledgeEntry(ref: wrongTitle).status,
      AiContextResolutionStatus.unknown,
    );

    final stale = AiContextRef(
      kind: ref.kind,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: List.filled(64, '0').join(),
      snapshotId: List.filled(64, '0').join(),
      ruleVersion: ref.ruleVersion,
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveMeridianKnowledgeEntry(ref: stale).status,
      AiContextResolutionStatus.stale,
    );

    final staleRules = AiContextRef(
      kind: ref.kind,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: 'diagnostic-rules-stale',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    expect(
      AiContextResolver.resolveMeridianKnowledgeEntry(ref: staleRules).status,
      AiContextResolutionStatus.stale,
    );
  });

  testWidgets(
    'meridian detail opens the existing learning assistant with an exact contextual anchor at 402/775dp',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;

      for (final width in [402.0, 775.0]) {
        tester.view.physicalSize = Size(width, 700);
        await tester.pumpWidget(
          ContextualAiConversationStoreScope(
            conversationStore: InMemoryAssistantConversationStore(),
            child: MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: AppColors.colorSchemeFor(Brightness.light),
                extensions: [AppColors.light],
              ),
              home: const MeridianDetailScreen(meridian: '少阳'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final pageScrollable = find.descendant(
          of: find.byType(MeridianDetailScreen),
          matching: find.byType(Scrollable),
        ).first;
        await tester.ensureVisible(find.textContaining('常用方剂').first);
        await tester.pumpAndSettle();
        final pagePosition =
            tester.state<ScrollableState>(pageScrollable).position;
        final pageOffsetBeforeOpen = pagePosition.pixels;
        expect(pageOffsetBeforeOpen, greaterThan(0));

        await tester.tap(find.byTooltip('在统一助手中继续'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        final assistantFinder = find.byType(LocalAiInterviewScreen);
        expect(assistantFinder, findsOneWidget);
        final assistant =
            tester.widget<LocalAiInterviewScreen>(assistantFinder);
        expect(assistant.initialMode, AssistantMode.learning);
        expect(assistant.contextualExplanationOnly, isTrue);
        expect(assistant.contextRef['kind'], 'knowledgeEntry');
        expect(assistant.contextRef['moduleId'], 'meridian');
        expect(assistant.contextRef['anchorId'], 'meridian:detail:少阳');
        expect(assistant.contextRef['snapshotId'], hasLength(64));
        expect(
          assistant.contextRef['sourceId'],
          AiContextResolver.meridianSourceId,
        );
        expect(assistant.initialPrompt, contains('少阳病'));
        expect(assistant.initialPrompt, contains('少阳为半表半里'));
        expect(tester.takeException(), isNull);

        Navigator.of(
          tester.element(assistantFinder),
          rootNavigator: true,
        ).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.byType(MeridianDetailScreen), findsOneWidget);
        expect(
          pagePosition.pixels,
          closeTo(pageOffsetBeforeOpen, 0.5),
          reason: '关闭情境助手后应恢复六经详情页原滚动位置',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
