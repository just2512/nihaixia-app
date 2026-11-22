import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/guji_data.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/services/guji_source_anchor_resolver.dart';
import 'package:nihaisha_app/screens/guji_library_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Guji chapter paragraphs resolve to their exact original TXT source lines',
    (tester) async {
      GujiRepository.clearCache();
      final book = kGujiBooks.singleWhere((item) => item.id == 'lingshu');
      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            home: const GujiLibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bookEntry = find.text(book.title);
      expect(bookEntry, findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(bookEntry);
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 1000));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(GujiBookScreen), findsOneWidget);

      final chapters =
          await tester.runAsync(() => GujiRepository.chaptersOf(book));
      expect(chapters, isNotNull);
      expect(chapters!, hasLength(book.chapterCount));
      final chapter = chapters.first;
      final chapterTitle = find.text(chapter.title).last;
      await tester.ensureVisible(chapterTitle);
      await tester.runAsync(() async {
        await tester.tap(chapterTitle);
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 1200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final readerFinder = find.byType(MarkdownDocScreen);
      expect(readerFinder, findsOneWidget);
      final reader = tester.widget<MarkdownDocScreen>(readerFinder);
      expect(reader.contextualAskModuleId, 'guji-reading');
      expect(reader.contextualAskAnchorId, 'guji-reading:lingshu:chapter:0');
      expect(reader.contextualAskSourceId, book.asset);
      expect(reader.contextualAskParagraphs, isTrue);
      expect(reader.contextualAskSourceLineMap?.take(5), [6, -1, 7, -1, 8]);

      final firstParagraph =
          find.textContaining('昔黄帝作《内经》十八卷', findRichText: true).last;
      expect(firstParagraph, findsOneWidget);
      await tester.longPress(firstParagraph);
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
      expect(assistant.contextRef['moduleId'], 'guji-reading');
      expect(
        assistant.contextRef['sourceId'],
        'guji-reading:assets/guji/lingshu.txt',
      );
      expect(
        assistant.contextRef['anchorId'],
        'guji-reading:lingshu:chapter:0:paragraph:6-6',
      );
      expect(assistant.contextRef['selectedText'], isNotEmpty);
      expect(assistant.initialPrompt, contains('昔黄帝作《内经》十八卷'));
      expect(
        assistant.initialPrompt,
        isNot(contains('时宋绍兴乙亥仲夏望日')),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an invalid source-line map fails closed without a contextual SelectionArea',
    (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: const MarkdownDocScreen(
          title: '来源行映射异常',
          content: '这段正文虽然可读，但来源行映射不完整。',
          contextualAskModuleId: 'guji-reading',
          contextualAskAnchorId: 'guji-reading:lingshu:chapter:0',
          contextualAskSourceId: 'assets/guji/lingshu.txt',
          contextualAskParagraphs: true,
          contextualAskSourceLineMap: [-1],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SelectionArea), findsNothing);
      expect(find.textContaining('这段正文虽然可读'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('source-line resolver verifies both original Guji books', () async {
    GujiRepository.clearCache();
    final expectedFirstLine = {
      'lingshu': 6,
      'zhenjiudacheng': 8,
    };
    for (final book in kGujiBooks) {
      final chapters = await GujiRepository.chaptersOf(book);
      final chapter = chapters.first;
      final sourceLineMap =
          await GujiSourceAnchorResolver.loadSourceLineMap(
        bundle: rootBundle,
        book: book,
        chapter: chapter,
      );
      expect(sourceLineMap, isNotNull, reason: book.id);
      final mappedLines = sourceLineMap!.where((line) => line > 0).toList();
      expect(mappedLines.first, expectedFirstLine[book.id], reason: book.id);
      expect(mappedLines.length, chapter.body.split('\n').length,
          reason: '每一条归一化正文行都必须有一个原始 TXT 行号：${book.id}');
      expect(sourceLineMap.length, mappedLines.length * 2 - 1,
          reason: '每个合成段落分隔符都必须有 -1 标记：${book.id}');
    }
  });
}
