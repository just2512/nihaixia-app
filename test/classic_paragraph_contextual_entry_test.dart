import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/bencao_library_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/screens/neijing_library_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 30,
}) async {
  for (var attempt = 0;
      attempt < maxAttempts && finder.evaluate().isEmpty;
      attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    'lecture paragraphs open Ask AI with exact source, passage and line-range anchor',
    (tester) async {
      const first = '第一段讲稿正文包含一个独立的上下文锚点与明确的解释范围。';
      const second = '第二段讲稿正文拥有另一份独立锚点，不能混入第一段。';
      const markdown = '''
# 阅读标题

$first
第二行仍然属于第一段。

- 列表项不应获得情境入口

> 资料编者说明不应作为正文段落

章节结构标题不应获得情境入口
====

| 字段 | 内容 |
| --- | --- |
| 说明 | 表格不应获得情境入口 |

<div>块级 HTML 不应获得情境入口</div>

<div class="note">

多行 HTML 块中的普通文本不应获得情境入口。

<section>
嵌套 HTML 块中的文本同样不应获得情境入口。
</section>
</div>

<!--

HTML 注释块中的普通文本不应获得情境入口。

-->

\$\$
x = 1

y = 2
\$\$

\\[
x + y = 3

x - y = 1
\\]

\\begin{aligned}
a &= 1
b &= 2
\\end{aligned}

本句包含 <em>行内 HTML</em>，也不应获得情境入口。

```text
代码块不应获得情境入口
```

$second
''';
      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            home: const MarkdownDocScreen(
              title: '内经讲稿样板',
              content: markdown,
              contextualAskModuleId: 'neijing-reading',
              contextualAskAnchorId:
                  'neijing-reading:passage:assets/neijing/sample.md',
              contextualAskSourceId: 'assets/neijing/sample.md',
              contextualAskParagraphs: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SelectionArea), findsNWidgets(2));
      final firstText = find.textContaining('第一段讲稿正文', findRichText: true);
      expect(firstText, findsOneWidget);
      await tester.longPress(firstText);
      await tester.pumpAndSettle();
      expect(find.text('问 AI'), findsOneWidget);
      await tester.tap(find.text('问 AI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final assistant = tester.widget<LocalAiInterviewScreen>(
        find.byType(LocalAiInterviewScreen),
      );
      expect(assistant.initialMode, AssistantMode.learning);
      expect(assistant.contextualExplanationOnly, isTrue);
      expect(assistant.contextRef['kind'], 'classic');
      expect(assistant.contextRef['moduleId'], 'neijing-reading');
      expect(
        assistant.contextRef['anchorId'],
        'neijing-reading:passage:assets/neijing/sample.md:paragraph:3-4',
      );
      expect(
        assistant.contextRef['sourceId'],
        'neijing-reading:assets/neijing/sample.md',
      );
      expect(assistant.contextRef['selectedText'], isNotEmpty);
      expect(assistant.initialPrompt, contains(first));
      expect(assistant.initialPrompt, isNot(contains('第二段讲稿正文')));
      expect(assistant.initialPrompt, isNot(contains('- 列表项')));
      expect(assistant.initialPrompt, contains('sample.md'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'repeated identical lecture paragraphs retain the selected line-range anchor',
    (tester) async {
      const repeated = '同一句话在这份讲稿里重复出现，用于验证来源锚点。';
      const markdown = '# 重复文本样板\n\n$repeated\n\n$repeated';
      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            home: const MarkdownDocScreen(
              title: '重复段落阅读',
              content: markdown,
              contextualAskModuleId: 'neijing-reading',
              contextualAskAnchorId:
                  'neijing-reading:passage:assets/neijing/repeated.md',
              contextualAskSourceId: 'assets/neijing/repeated.md',
              contextualAskParagraphs: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final repeatedParagraphs = find.text(repeated, findRichText: true);
      expect(repeatedParagraphs, findsNWidgets(2));
      expect(find.byType(SelectionArea), findsNWidgets(2));
      final secondParagraph = repeatedParagraphs.last;
      await tester.ensureVisible(secondParagraph);
      await tester.longPress(secondParagraph);
      await tester.pumpAndSettle();
      expect(find.text('问 AI'), findsOneWidget);
      await tester.tap(find.text('问 AI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final assistant = tester.widget<LocalAiInterviewScreen>(
        find.byType(LocalAiInterviewScreen),
      );
      expect(
        assistant.contextRef['anchorId'],
        'neijing-reading:passage:assets/neijing/repeated.md:paragraph:5-5',
      );
      expect(
        assistant.contextRef['sourceId'],
        'neijing-reading:assets/neijing/repeated.md',
      );
      expect(assistant.contextRef['selectedText'], isNotEmpty);
      expect(assistant.initialPrompt, contains(repeated));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Neijing and Bencao lecture libraries pass real paragraph contexts',
    (tester) async {
      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            home: const NeijingLibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final neijingEntry = find.text('上古天真论');
      await tester.scrollUntilVisible(
        neijingEntry,
        240,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ).first,
      );
      expect(neijingEntry, findsOneWidget);
      // rootBundle.loadString must start inside runAsync's real zone; otherwise
      // the asset future can remain pending in the widget-test fake async zone.
      await tester.runAsync(() async {
        await tester.tap(neijingEntry);
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 1200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final neijingReader = tester.widget<MarkdownDocScreen>(
        find.byType(MarkdownDocScreen),
      );
      expect(neijingReader.contextualAskModuleId, 'neijing-reading');
      expect(neijingReader.contextualAskParagraphs, isTrue);
      expect(neijingReader.contextualAskSourceId,
          'assets/neijing/01_上古天真论.md');
      final neijingParagraph =
          find.textContaining('今天开始第一堂课这个', findRichText: true);
      // Asset loading is asynchronous; wait for the real paragraph widget before
      // asserting the contextual SelectionArea has been mounted.
      await pumpUntilFound(tester, neijingParagraph);
      expect(
        find.byType(SelectionArea),
        findsWidgets,
        reason: 'Real Neijing asset and injected links must retain paragraph mapping',
      );
      expect(find.text('原文加载失败'), findsNothing);
      expect(neijingParagraph, findsOneWidget);
      await tester.scrollUntilVisible(
        neijingParagraph,
        200,
        scrollable: find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.longPress(neijingParagraph);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('问 AI'), findsOneWidget);
      await tester.tap(find.text('问 AI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final neijingAssistantFinder =
          find.byType(LocalAiInterviewScreen);
      expect(neijingAssistantFinder, findsOneWidget);
      final neijingAssistant =
          tester.widget<LocalAiInterviewScreen>(neijingAssistantFinder);
      expect(neijingAssistant.initialMode, AssistantMode.learning);
      expect(neijingAssistant.contextualExplanationOnly, isTrue);
      expect(
        neijingAssistant.contextRef['sourceId'],
        'neijing-reading:assets/neijing/01_上古天真论.md',
      );
      expect(
        neijingAssistant.contextRef['anchorId'],
        startsWith(
          'neijing-reading:passage:assets/neijing/01_上古天真论.md:paragraph:',
        ),
      );
      expect(neijingAssistant.contextRef['selectedText'], isNotEmpty);
      expect(neijingAssistant.initialPrompt, contains('今天开始第一堂课这个'));
      Navigator.of(
        tester.element(neijingAssistantFinder),
        rootNavigator: true,
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            key: const ValueKey('bencao-library-test-app'),
            theme: ThemeData(extensions: [AppColors.light]),
            home: const BenCaoLibraryScreen(),
          ),
        ),
      );
      // The library contains an indeterminate loading indicator, so use
      // bounded frame pumping instead of waiting for global settlement.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final bencaoEntry = find.text('上经·人参');
      await tester.scrollUntilVisible(
        bencaoEntry,
        240,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ).first,
      );
      expect(bencaoEntry, findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(bencaoEntry);
        await tester.pump();
        await Future.delayed(const Duration(milliseconds: 1200));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final bencaoReader = tester.widget<MarkdownDocScreen>(
        find.byType(MarkdownDocScreen),
      );
      expect(bencaoReader.contextualAskModuleId, 'bencao-reading');
      expect(bencaoReader.contextualAskParagraphs, isTrue);
      expect(bencaoReader.contextualAskSourceId,
          'assets/bencao_lecture/023_上经人参.md');
      final bencaoParagraph =
          find.textContaining('人参顾名思义，因为他这个根长的象人的形状', findRichText: true);
      await pumpUntilFound(tester, bencaoParagraph);
      expect(
        find.byType(SelectionArea),
        findsWidgets,
        reason: 'Real Bencao asset and injected links must retain paragraph mapping',
      );
      expect(find.text('原文加载失败'), findsNothing);
      expect(bencaoParagraph, findsOneWidget);
      await tester.scrollUntilVisible(
        bencaoParagraph,
        200,
        scrollable: find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(Scrollable),
        ).first,
      );
      await tester.longPress(bencaoParagraph);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('问 AI'), findsOneWidget);
      await tester.tap(find.text('问 AI'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final bencaoAssistantFinder =
          find.byType(LocalAiInterviewScreen);
      expect(bencaoAssistantFinder, findsOneWidget);
      final bencaoAssistant =
          tester.widget<LocalAiInterviewScreen>(bencaoAssistantFinder);
      expect(bencaoAssistant.initialMode, AssistantMode.learning);
      expect(bencaoAssistant.contextualExplanationOnly, isTrue);
      expect(
        bencaoAssistant.contextRef['sourceId'],
        'bencao-reading:assets/bencao_lecture/023_上经人参.md',
      );
      expect(
        bencaoAssistant.contextRef['anchorId'],
        startsWith(
          'bencao-reading:passage:assets/bencao_lecture/023_上经人参.md:paragraph:',
        ),
      );
      expect(bencaoAssistant.contextRef['selectedText'], isNotEmpty);
      expect(bencaoAssistant.initialPrompt, contains('人参顾名思义'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'paragraph mode fails closed without complete source provenance',
    (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: const MarkdownDocScreen(
          title: '缺少来源的讲稿',
          content: '这段正文没有完整的来源身份和锚点。',
          contextualAskModuleId: 'neijing-reading',
          contextualAskAnchorId: 'neijing-reading:passage:missing.md',
          contextualAskParagraphs: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(SelectionArea), findsNothing);
    },
  );
}
