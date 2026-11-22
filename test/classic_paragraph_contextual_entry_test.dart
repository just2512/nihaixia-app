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
    'Neijing and Bencao lecture libraries pass paragraph-mode source identities',
    (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: const NeijingLibraryScreen(),
      ));
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
      await tester.tap(neijingEntry);
      // The reader keeps an indeterminate loading animation alive; advance the
      // route transition and asset load without waiting for global settlement.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));

      final neijingReader = tester.widget<MarkdownDocScreen>(
        find.byType(MarkdownDocScreen),
      );
      expect(neijingReader.contextualAskModuleId, 'neijing-reading');
      expect(neijingReader.contextualAskParagraphs, isTrue);
      expect(neijingReader.contextualAskSourceId,
          'assets/neijing/01_上古天真论.md');

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: const BenCaoLibraryScreen(),
      ));
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
      await tester.tap(bencaoEntry);
      // Match the Neijing route's bounded transition/asset-load pumping.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));

      final bencaoReader = tester.widget<MarkdownDocScreen>(
        find.byType(MarkdownDocScreen),
      );
      expect(bencaoReader.contextualAskModuleId, 'bencao-reading');
      expect(bencaoReader.contextualAskParagraphs, isTrue);
      expect(bencaoReader.contextualAskSourceId,
          'assets/bencao_lecture/023_上经人参.md');
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
