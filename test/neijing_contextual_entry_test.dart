import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/neijing_entries.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/neijing_entries_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';
void main() {
  test('Neijing context resolves only by exact entry ID and source version', () {
    final entry = kNeijingEntries.first;
    final ref = AiContextResolver.buildNeijingEntryContextRef(entry);
    final resolved = AiContextResolver.resolveNeijingEntry(ref: ref);

    expect(ref.kind, AiContextKind.classic);
    expect(ref.moduleId, 'neijing-entries');
    expect(ref.anchorId, 'neijing:${entry.id}');
    expect(ref.sourceId, 'app-data:lib/data/neijing_entries.dart#${entry.id}');
    expect(resolved.isResolved, isTrue);
    expect(resolved.value?.content['original'], entry.original);
    expect(resolved.value?.content['nishi'], entry.nishi);

    final prompt = AiContextPromptBuilder.buildNeijingKnowledgeEntry(
      entry: resolved.value!,
    );
    expect(prompt, contains(entry.original));
    expect(prompt, contains('【推断】'));
    expect(prompt, contains('辨证思路'));
    expect(prompt, contains('不得编造经文'));

    final stale = AiContextRef(
      kind: AiContextKind.classic,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: 'lib/data/neijing_entries.dart@STALE',
      sourceId: ref.sourceId,
      title: entry.title,
    );
    expect(
      AiContextResolver.resolveNeijingEntry(ref: stale).status,
      AiContextResolutionStatus.unknown,
    );

    final mismatchedTitle = AiContextRef(
      kind: AiContextKind.classic,
      moduleId: ref.moduleId,
      anchorId: ref.anchorId,
      anchorVersion: ref.anchorVersion,
      sourceId: ref.sourceId,
      title: '错误标题',
    );
    expect(
      AiContextResolver.resolveNeijingEntry(ref: mismatchedTitle).status,
      AiContextResolutionStatus.unknown,
    );

    final missing = AiContextRef(
      kind: AiContextKind.classic,
      moduleId: ref.moduleId,
      anchorId: 'neijing:not-a-real-entry',
      anchorVersion: ref.anchorVersion,
      sourceId: 'app-data:lib/data/neijing_entries.dart#not-a-real-entry',
      title: '不存在',
    );
    expect(
      AiContextResolver.resolveNeijingEntry(ref: missing).status,
      AiContextResolutionStatus.missing,
    );
  });

  testWidgets(
    'expanded Neijing entry exposes a contextual Ask AI action without auto-opening',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1200);
      addTearDown(tester.view.reset);
      const entryId = 'zx-01';
      final entry = kNeijingEntries.singleWhere((item) => item.id == entryId);
      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: const MaterialApp(
            home: NeijingEntriesScreen(initialEntryId: entryId),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(entry.title), findsOneWidget);
      expect(find.text(entry.original), findsOneWidget);
      expect(find.text('问 AI 解读当前内经条目'), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
      final ask = find.text('问 AI 解读当前内经条目');
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
      expect(widget.contextRef['kind'], 'classic');
      expect(widget.contextRef['moduleId'], 'neijing-entries');
      expect(widget.contextRef['anchorId'], 'neijing:${entry.id}');
      expect(widget.contextRef['sourceId'],
          'app-data:lib/data/neijing_entries.dart#${entry.id}');
      expect(widget.initialPrompt, isNull);
      expect(widget.initialUserMessage, contains('经典条文'));
      expect(widget.autoSendInitialMessage, isTrue);
      expect(widget.resolveContextualKnowledgeEntry, isTrue);
      expect(tester.takeException(), isNull);

    },
  );
}
