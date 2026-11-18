import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/neijing_entries.dart';
import 'package:nihaisha_app/models/ai_context_ref.dart';
import 'package:nihaisha_app/screens/neijing_entries_screen.dart';
import 'package:nihaisha_app/services/ai_context_prompt_builder.dart';
import 'package:nihaisha_app/services/ai_context_resolver.dart';

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
      const entryId = 'zx-01';
      final entry = kNeijingEntries.singleWhere((item) => item.id == entryId);
      await tester.pumpWidget(
        const MaterialApp(
          home: NeijingEntriesScreen(initialEntryId: entryId),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(entry.title), findsOneWidget);
      expect(find.text(entry.original), findsOneWidget);
      expect(find.text('问 AI 解读当前内经条目'), findsOneWidget);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
