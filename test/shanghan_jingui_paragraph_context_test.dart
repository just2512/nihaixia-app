import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/classic_library_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/screens/shanghan_jingui_screen.dart';
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

Future<void> openBook(
  WidgetTester tester, {
  required String bookName,
  required String entryName,
  required String paragraphText,
  required String moduleId,
  required String sourceId,
  required String expectedAnchorId,
}) async {
  await tester.pumpWidget(
    ContextualAiConversationStoreScope(
      conversationStore: InMemoryAssistantConversationStore(),
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: const ShangHanJinguiScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text(bookName));
  await tester.pumpAndSettle();
  expect(find.byType(ClassicLibraryScreen), findsOneWidget);

  final entry = find.textContaining(entryName);
  await tester.scrollUntilVisible(
    entry,
    240,
    scrollable: find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    ).first,
  );
  expect(entry, findsOneWidget);
  // rootBundle.loadString must start in the real async zone, matching the
  // existing Neijing library smoke-test contract.
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
  expect(reader.contextualAskModuleId, moduleId);
  expect(reader.contextualAskParagraphs, isTrue);
  expect(reader.contextualAskSourceId, sourceId);

  final paragraph = find.textContaining(paragraphText, findRichText: true);
  await pumpUntilFound(tester, paragraph);
  expect(find.text('原文加载失败'), findsNothing);
  expect(paragraph, findsOneWidget);
  expect(find.byType(SelectionArea), findsWidgets);

  await tester.scrollUntilVisible(
    paragraph,
    200,
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
  expect(assistant.contextRef['moduleId'], moduleId);
  expect(assistant.contextRef['sourceId'], '$moduleId:$sourceId');
  expect(assistant.contextRef['anchorId'], expectedAnchorId);
  expect(assistant.contextRef['selectedText'], isNotEmpty);
  expect(assistant.initialPrompt, contains(paragraphText));
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'Shanghan lecture prose opens Ask AI with its own paragraph source anchor',
    (tester) async {
      await openBook(
        tester,
        bookName: '伤寒论',
        entryName: '太阳·太阳病中风',
        paragraphText: '有下面的症状',
        moduleId: 'shanghan',
        sourceId: 'assets/shanghan/clause_001.md',
        expectedAnchorId:
            'shanghan:clause:002:paragraph:5-5',
      );
    },
  );

  testWidgets(
    'Jingui lecture prose opens Ask AI with its own paragraph source anchor',
    (tester) async {
      await openBook(
        tester,
        bookName: '金匮要略',
        entryName: '藏府经络先后病·概述',
        paragraphText: '杂病的范围牵扯很广',
        moduleId: 'jingui',
        sourceId: 'assets/jingui/clause_001.md',
        expectedAnchorId:
            'jingui:passage:assets/jingui/clause_001.md:paragraph:3-3',
      );
    },
  );
}
