import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/screens/zhenjiu_library_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 40,
}) async {
  for (var attempt = 0;
      attempt < maxAttempts && finder.evaluate().isEmpty;
      attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    'Zhenjiu lecture paragraphs open Ask AI with exact asset and line anchor',
    (tester) async {
      const sourceId =
          'assets/zhenjiu_lecture/00_第一章针灸的使用时机.md';
      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            home: const ZhenjiuLibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final entry = find.text('第一章·针灸的使用时机');
      expect(entry, findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(entry);
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 1200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final reader = tester.widget<MarkdownDocScreen>(
        find.byType(MarkdownDocScreen),
      );
      expect(reader.contextualAskModuleId, 'zhenjiu-reading');
      expect(reader.contextualAskParagraphs, isTrue);
      expect(reader.contextualAskSourceId, sourceId);

      final paragraph =
          find.textContaining('针可以用在所有的疾病上面', findRichText: true);
      await pumpUntilFound(tester, paragraph);
      expect(paragraph, findsOneWidget);
      expect(find.text('原文加载失败'), findsNothing);
      await tester.scrollUntilVisible(
        paragraph,
        180,
        scrollable: find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.longPress(paragraph);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('问 AI'), findsOneWidget);
      await tester.tap(find.text('问 AI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final assistantFinder = find.byType(LocalAiInterviewScreen);
      expect(assistantFinder, findsOneWidget);
      final assistant =
          tester.widget<LocalAiInterviewScreen>(assistantFinder);
      expect(assistant.initialMode, AssistantMode.learning);
      expect(assistant.contextualExplanationOnly, isTrue);
      expect(assistant.contextRef['kind'], 'classic');
      expect(assistant.contextRef['moduleId'], 'zhenjiu-reading');
      expect(
        assistant.contextRef['sourceId'],
        'zhenjiu-reading:$sourceId',
      );
      expect(
        assistant.contextRef['anchorId'],
        'zhenjiu-reading:passage:$sourceId:paragraph:13-13',
      );
      expect(assistant.contextRef['selectedText'], isNotEmpty);
      expect(
        assistant.initialPrompt,
        contains('针可以用在所有的疾病上面'),
      );
      expect(assistant.initialPrompt, isNot(contains('灸，即jiǔ')));
      expect(tester.takeException(), isNull);
    },
  );
}
