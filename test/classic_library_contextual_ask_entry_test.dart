import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/classic_lecture_data.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/classic_library_screen.dart';
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/screens/shanghan_jingui_screen.dart';
import 'package:nihaisha_app/services/classic_search_service.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    '生产入口：伤寒论阅读库的真实篇目打开学习助手并保留精确来源锚点',
    (tester) async {
      const asset = 'assets/shanghan/clause_001.md';
      const sourceId = 'shanghan:$asset';
      final indexedSource = await ClassicSearchService.findBySourceId(sourceId);

      expect(indexedSource, isNotNull);
      expect(indexedSource!.sourceId, sourceId);
      expect(indexedSource.asset, asset);
      expect(indexedSource.localBacklink, asset);
      expect(indexedSource.hasLocalBacklink, isTrue);

      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              platform: TargetPlatform.android,
              extensions: [AppColors.light],
            ),
            home: const ShangHanJinguiScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Follow the actual production route rather than constructing the
      // ClassicLibraryScreen or MarkdownDocScreen directly.
      await tester.tap(find.text('伤寒论'));
      await tester.pumpAndSettle();
      expect(find.byType(ClassicLibraryScreen), findsOneWidget);

      final lecture = kShangHanLectures[1];
      expect(lecture.asset, asset);
      await tester.tap(find.text(lecture.name));
      await tester.pumpAndSettle();

      final readerFinder = find.byType(MarkdownDocScreen);
      expect(readerFinder, findsOneWidget);
      final reader = tester.widget<MarkdownDocScreen>(readerFinder);
      expect(reader.contextualAskModuleId, 'shanghan');
      expect(reader.contextualAskAnchorId, 'shanghan:clause:002');
      expect(reader.contextualAskSourceId, asset);
      expect(reader.contextualAskParagraphs, isTrue);
      expect(find.byType(SelectionArea), findsWidgets);

      final originalClause =
          find.textContaining('太阳病', findRichText: true).first;
      await tester.ensureVisible(originalClause);
      await tester.longPress(originalClause);
      await tester.pumpAndSettle();

      expect(find.text('问 AI'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);

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
      expect(assistant.contextRef['moduleId'], 'shanghan');
      expect(assistant.contextRef['anchorId'], 'shanghan:clause:002');
      expect(assistant.contextRef['sourceId'], sourceId);
      expect(assistant.contextRef['anchorVersion'], hasLength(64));

      final selectedText = assistant.contextRef['selectedText'] as String?;
      expect(selectedText, isNotNull);
      expect(selectedText, isNotEmpty);
      expect('「太阳病」，发热，汗出，恶风，脉缓者，名为「中风」。',
          contains(selectedText!));
      expect(assistant.initialPrompt, contains(selectedText));
      expect(assistant.initialPrompt, contains('太阳病'));
      expect(assistant.initialPrompt, contains(sourceId));
      expect(tester.takeException(), isNull);

      Navigator.of(
        tester.element(assistantFinder),
        rootNavigator: true,
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(MarkdownDocScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('相邻真实篇目使用不同的规范锚点，不继承第一条文来源', () {
    final firstAnchor = ClassicSearchService.contextualAnchorIdForReaderAsset(
      moduleId: 'shanghan',
      asset: 'assets/shanghan/clause_001.md',
    );
    final nextAnchor = ClassicSearchService.contextualAnchorIdForReaderAsset(
      moduleId: 'shanghan',
      asset: 'assets/shanghan/clause_002.md',
    );

    expect(firstAnchor, 'shanghan:clause:002');
    expect(nextAnchor, 'shanghan:passage:assets/shanghan/clause_002.md');
    expect(nextAnchor, isNot(firstAnchor));
  });
}
