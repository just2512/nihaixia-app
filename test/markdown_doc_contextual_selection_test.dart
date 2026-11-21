import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/screens/classic_library_screen.dart';
import 'package:nihaisha_app/data/classic_lecture_data.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  testWidgets('contextual selection is enabled only for a fully anchored reading block',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      home: MarkdownDocScreen(
        title: '伤寒论条文样板',
        content: '#### 条文2\n\n> 太阳病，发热，汗出，恶风，脉缓者，名为中风。',
        contextualAskModuleId: 'shanghan',
        contextualAskAnchorId: 'shanghan:clause:002',
        contextualAskSourceId: 'assets/shanghan/clause_001.md',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.text('伤寒论条文样板'), findsOneWidget);

    final passageText = find.textContaining('太阳病', findRichText: true);
    expect(passageText, findsOneWidget);
    await tester.longPress(passageText);
    await tester.pumpAndSettle();
    expect(find.text('问 AI'), findsOneWidget);
  });

  testWidgets('commentary outside the anchored clause cannot start a contextual ask',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      home: MarkdownDocScreen(
        title: '伤寒论条文样板',
        content: '#### 条文2\n\n> 太阳病，发热，汗出，恶风，脉缓者，名为中风。\n\n这段是讲解者的补充说明，不属于原文条文。',
        contextualAskModuleId: 'shanghan',
        contextualAskAnchorId: 'shanghan:clause:002',
        contextualAskSourceId: 'assets/shanghan/clause_001.md',
      ),
    ));
    await tester.pumpAndSettle();

    final commentary = find.textContaining('讲解者的补充说明');
    expect(commentary, findsOneWidget);
    await tester.longPress(commentary);
    await tester.pumpAndSettle();
    expect(find.text('问 AI'), findsNothing);
  });

  testWidgets('multiple quote blocks expose separate contextual passages and distinct anchors',
      (tester) async {
    await tester.pumpWidget(
      ContextualAiConversationStoreScope(
        conversationStore: InMemoryAssistantConversationStore(),
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: MarkdownDocScreen(
            title: '多条文阅读页',
            content: '> 第一条原文。\n\n解释文字。\n\n> 第二条原文。',
            contextualAskModuleId: 'shanghan',
            contextualAskAnchorId: 'shanghan:document:multi',
            contextualAskSourceId: 'assets/shanghan/multi.md',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsNWidgets(2));
    expect(find.textContaining('解释文字'), findsOneWidget);

    await tester.longPress(
      find.textContaining('第一条原文', findRichText: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('问 AI'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    var assistantFinder = find.byType(LocalAiInterviewScreen);
    expect(assistantFinder, findsOneWidget);
    var assistant = tester.widget<LocalAiInterviewScreen>(assistantFinder);
    expect(assistant.contextRef['anchorId'], 'shanghan:document:multi:passage:0');
    expect(assistant.contextRef['selectedText'], contains('第一条原文'));
    Navigator.of(tester.element(assistantFinder), rootNavigator: true).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.longPress(
      find.textContaining('第二条原文', findRichText: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('问 AI'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    assistantFinder = find.byType(LocalAiInterviewScreen);
    expect(assistantFinder, findsOneWidget);
    assistant = tester.widget<LocalAiInterviewScreen>(assistantFinder);
    expect(assistant.contextRef['anchorId'], 'shanghan:document:multi:passage:1');
    expect(assistant.contextRef['selectedText'], contains('第二条原文'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('classic library passes the stable asset path to its contextual document reader',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      home: ClassicLibraryScreen(
        title: '伤寒论阅读库',
        lectures: const [
          ClassicLecture(
            seq: 1,
            name: '太阳病中风',
            asset: 'assets/shanghan/clause_001.md',
          ),
        ],
        contextualAskModuleId: 'shanghan',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('太阳病中风'));
    await tester.pumpAndSettle();
    final docFinder = find.byType(MarkdownDocScreen);
    expect(docFinder, findsOneWidget);
    final doc = tester.widget<MarkdownDocScreen>(docFinder);
    expect(doc.contextualAskModuleId, 'shanghan');
    expect(doc.contextualAskAnchorId, 'shanghan:clause:002');
    expect(doc.contextualAskSourceId, 'assets/shanghan/clause_001.md');
    expect(find.byType(SelectionArea), findsOneWidget);
  });

  testWidgets('a two-quote Jingui asset enables one scoped action per local quote',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      home: ClassicLibraryScreen(
        title: '金匮要略阅读库',
        lectures: const [
          ClassicLecture(
            seq: 450,
            name: '大病差复',
            asset: 'assets/jingui/clause_450.md',
          ),
        ],
        contextualAskModuleId: 'jingui',
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('大病差复'));
    await tester.pumpAndSettle();
    final docFinder = find.byType(MarkdownDocScreen);
    expect(docFinder, findsOneWidget);
    final doc = tester.widget<MarkdownDocScreen>(docFinder);
    expect(doc.contextualAskModuleId, 'jingui');
    expect(doc.contextualAskAnchorId, 'jingui:passage:assets/jingui/clause_450.md');
    expect(doc.contextualAskSourceId, 'assets/jingui/clause_450.md');
    expect(find.byType(SelectionArea), findsNWidgets(2));
  });

  testWidgets('ordinary markdown reading keeps its existing selectable behavior',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      home: MarkdownDocScreen(
        title: '普通阅读页',
        content: '这是一段普通的可选择正文。',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsNothing);
    expect(find.text('普通阅读页'), findsOneWidget);
  });

  testWidgets('incomplete reading provenance does not expose contextual menu area',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      home: MarkdownDocScreen(
        title: '缺少来源的阅读页',
        content: '这段文字没有完整来源锚点。',
        contextualAskModuleId: 'shanghan',
        contextualAskAnchorId: 'shanghan:clause:002',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsNothing);
  });

  testWidgets('contextual ask menu retains platform copy and select-all actions',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        platform: TargetPlatform.android,
        extensions: [AppColors.light],
      ),
      home: MarkdownDocScreen(
        title: '伤寒论条文样板',
        content: '#### 条文2\n\n> 太阳病，发热，汗出，恶风，脉缓者，名为中风。',
        contextualAskModuleId: 'shanghan',
        contextualAskAnchorId: 'shanghan:clause:002',
        contextualAskSourceId: 'assets/shanghan/clause_001.md',
      ),
    ));
    await tester.pumpAndSettle();

    final passageText = find.textContaining('太阳病', findRichText: true);
    await tester.longPress(passageText);
    await tester.pumpAndSettle();

    expect(find.text('问 AI'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget,
        reason: 'Adding contextual ask must not remove the platform copy action');
    expect(find.text('Select all'), findsOneWidget,
        reason: 'Adding contextual ask must preserve select-all behavior');
  });

  testWidgets(
    'Shanghan selection opens the existing learning assistant with exact passage provenance',
    (tester) async {
      const passage =
          '太阳病，发热，汗出，恶风，脉缓者，名为中风。';
      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            home: MarkdownDocScreen(
              title: '伤寒论条文样板',
              content: '#### 条文2\n\n> $passage',
              contextualAskModuleId: 'shanghan',
              contextualAskAnchorId: 'shanghan:clause:002',
              contextualAskSourceId: 'assets/shanghan/clause_001.md',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final passageText = find.textContaining('太阳病', findRichText: true);
      await tester.longPress(passageText);
      await tester.pumpAndSettle();
      final ask = find.text('问 AI');
      expect(ask, findsOneWidget);
      await tester.tap(ask);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final assistant = find.byType(LocalAiInterviewScreen);
      expect(assistant, findsOneWidget);
      final widget = tester.widget<LocalAiInterviewScreen>(assistant);
      expect(widget.initialMode, AssistantMode.learning);
      expect(widget.contextualExplanationOnly, isTrue);
      expect(widget.contextRef['kind'], 'classic');
      expect(widget.contextRef['moduleId'], 'shanghan');
      expect(widget.contextRef['anchorId'], 'shanghan:clause:002');
      expect(widget.contextRef['sourceId'],
          'shanghan:assets/shanghan/clause_001.md');
      expect(widget.contextRef['anchorVersion'], hasLength(64));
      final selected = widget.contextRef['selectedText'];
      expect(selected, isNotNull);
      expect(selected, isNotEmpty);
      expect(widget.initialPrompt, contains(selected!));
      expect(widget.initialPrompt, contains(passage));
      expect(widget.initialPrompt, contains('shanghan:clause:002'));
      expect(tester.takeException(), isNull);
    },
  );

}
