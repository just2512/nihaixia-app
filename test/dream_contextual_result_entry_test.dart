import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/data/dream_data.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/dream_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/services/ai_tool_result_snapshot.dart';
import 'package:nihaisha_app/services/dream_result_context_executor.dart';
import 'package:nihaisha_app/services/dream_tool_executor.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const selectedId = 'action_028';

  test('只按明确选择的单条词条 ID 建立完整结构化快照', () {
    final entry = kDreamEntries.singleWhere((item) => item.id == selectedId);
    final execution = DreamResultContextExecutor.executeWithSnapshot(
      selectedEntryId: selectedId,
    );

    expect(execution.succeeded, isTrue);
    expect(execution.result.validateFor('dream'), isEmpty);
    expect(
      execution.result.validateArgumentsMatch({'entry_id': selectedId}),
      isEmpty,
    );
    expect(execution.result.sourceIds, [DreamToolExecutor.sourceId]);

    final snapshot = execution.structuredSnapshot!;
    final input = snapshot['input']! as Map<String, Object?>;
    final result = snapshot['result']! as Map<String, Object?>;
    final values = result['values']! as Map<String, Object?>;
    expect(snapshot['capabilityId'], DreamResultContextExecutor.moduleId);
    expect(
      snapshot['resultSchemaVersion'],
      DreamResultContextExecutor.resultSchemaVersion,
    );
    expect(snapshot['ruleVersion'], DreamResultContextExecutor.ruleVersion);
    expect(snapshot['executionStatus'], 'SUCCESS');
    expect(input, {
      'method': 'explicitEntrySelection',
      'selectedEntryId': selectedId,
    });
    expect(values['词条 ID'], entry.id);
    expect(values['分类'], entry.category);
    expect(values['子分类'], entry.subcategory);
    expect(values['关键词'], entry.keyword);
    expect(values['梦境词条原文'], entry.dream);
    expect(values['词条释义原文'], entry.interpretation);
    expect(values['原始吉凶标签（民俗文本）'], entry.auspicious);
    expect(values['词条来源字段'], entry.source);
    expect(snapshot['sourceIds'], [DreamToolExecutor.sourceId]);
    expect(
      AiToolResultSnapshot.createStructuredId(snapshot: snapshot),
      snapshot['snapshotId'],
    );
  });

  test('空 ID、不存在 ID 和带空白的 ID 均 fail closed', () {
    for (final id in ['', 'not-a-real-dream-entry', ' action_028 ']) {
      final execution = DreamResultContextExecutor.executeWithSnapshot(
        selectedEntryId: id,
      );
      expect(execution.succeeded, isFalse, reason: 'ID=$id');
      expect(execution.result.status.name, 'failed');
      expect(execution.structuredSnapshot, isNull);
      expect(execution.result.sourceIds, isEmpty);
    }
  });

  test('Resolver 精确重建单条词条；Prompt 不包含用户自由梦境描述或其他候选', () async {
    final execution = DreamResultContextExecutor.executeWithSnapshot(
      selectedEntryId: selectedId,
    );
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildDreamEntryContextRef(
      structuredSnapshot: snapshot,
    );
    final resolution = await AiContextResolver.resolveDreamEntryToolResult(
      ref: ref,
      structuredSnapshot: snapshot,
    );

    expect(ref.kind.name, 'toolResult');
    expect(ref.moduleId, 'dream');
    expect(ref.sourceId, DreamToolExecutor.sourceId);
    expect(ref.anchorId, contains(selectedId));
    expect(ref.snapshotId, hasLength(64));
    expect(resolution.isResolved, isTrue);

    final prompt = AiContextPromptBuilder.buildToolResult(
      ref: ref,
      structuredSnapshot: resolution.value!.structuredSnapshot,
    );
    expect(prompt, contains(selectedId));
    expect(prompt, contains('梦见考试通过'));
    expect(prompt, isNot(contains('梦见考试不及格')));
    expect(prompt, isNot(contains('梦见考试，主压力')));
    expect(prompt, contains('不是科学结论、现实事件预测或必然结果'));
    expect(prompt, contains('本次快照不包含用户自由梦境描述或搜索输入'));
    expect(prompt, contains('不得从词条推断用户的心理状态'));
  });

  test('快照篡改和规则版本变化均拒绝解析', () async {
    final execution = DreamResultContextExecutor.executeWithSnapshot(
      selectedEntryId: selectedId,
    );
    final snapshot = execution.structuredSnapshot!;
    final ref = AiContextResolver.buildDreamEntryContextRef(
      structuredSnapshot: snapshot,
    );

    final originalResult = snapshot['result']! as Map<String, Object?>;
    final originalValues = originalResult['values']! as Map<String, Object?>;
    final tampered = <String, Object?>{
      ...snapshot,
      'result': <String, Object?>{
        ...originalResult,
        'values': <String, Object?>{
          ...originalValues,
          '词条释义原文': '被篡改的释义',
        },
      },
    };
    final tamperedResolution =
        await AiContextResolver.resolveDreamEntryToolResult(
      ref: ref,
      structuredSnapshot: tampered,
    );
    expect(tamperedResolution.status, AiContextResolutionStatus.stale);

    final staleRef = AiContextRef(
      kind: AiContextKind.toolResult,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      snapshotId: ref.snapshotId,
      ruleVersion: 'dream-data-blob@STALE',
      sourceId: ref.sourceId,
      title: ref.title,
    );
    final staleResolution =
        await AiContextResolver.resolveDreamEntryToolResult(
      ref: staleRef,
      structuredSnapshot: snapshot,
    );
    expect(staleResolution.status, AiContextResolutionStatus.stale);
  });

  test('本地 412 条词条 ID 唯一', () {
    final ids = kDreamEntries.map((entry) => entry.id).toList();
    expect(kDreamEntries, hasLength(412));
    expect(ids.toSet(), hasLength(ids.length));
  });

  testWidgets('多候选搜索只解释用户点击的那一条词条', (tester) async {
    await tester.pumpWidget(
      ContextualAiConversationStoreScope(
        conversationStore: InMemoryAssistantConversationStore(),
        child: const MaterialApp(home: DreamScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '考试');
    await tester.pumpAndSettle();

    expect(find.text('梦见考试'), findsOneWidget);
    expect(find.text('梦见考试通过'), findsOneWidget);
    expect(find.text('梦见考试不及格'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ask-dream-ai-action_028')));
    await tester.pumpAndSettle();

    final ai = tester.widget<LocalAiInterviewScreen>(
      find.byType(LocalAiInterviewScreen),
    );
    expect(ai.contextRef['moduleId'], 'dream');
    expect(ai.contextRef['anchorId'], contains('action_028'));
    expect(ai.initialPrompt, contains('梦见考试通过'));
    expect(ai.initialPrompt, isNot(contains('梦见考试不及格')));
    expect(ai.initialPrompt, isNot(contains('action_027')));
    expect(ai.contextualExplanationOnly, isTrue);

    Navigator.of(
      tester.element(find.byType(LocalAiInterviewScreen)),
      rootNavigator: true,
    ).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.byType(DreamScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('402dp / 775dp 下关闭情境面板后恢复原词条列表滚动位置',
      (tester) async {
    addTearDown(tester.view.reset);
    final lastEntryId = kDreamEntries.last.id;

    for (final viewport in [const Size(402, 880), const Size(775, 1024)]) {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            home: DreamScreen(key: ValueKey('dream-${viewport.width}')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final list = find.byKey(const ValueKey('dream-results-list'));
      final ask = find.byKey(ValueKey('ask-dream-ai-$lastEntryId'));
      await tester.ensureVisible(ask);
      await tester.pumpAndSettle();

      final scrollable = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      ).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final beforeOpen = position.pixels;
      expect(beforeOpen, greaterThan(0));

      await tester.tap(ask);
      await tester.pumpAndSettle();
      expect(find.byType(LocalAiInterviewScreen), findsOneWidget);

      Navigator.of(
        tester.element(find.byType(LocalAiInterviewScreen)),
        rootNavigator: true,
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();

      expect(find.byType(DreamScreen), findsOneWidget);
      expect(position.pixels, closeTo(beforeOpen, 0.5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
