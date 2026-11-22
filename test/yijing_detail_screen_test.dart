import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/minggua_data.dart';
import 'package:nihaisha_app/data/yijing_data.dart';
import 'package:nihaisha_app/data/yijing_lecture_data.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart'
    show AssistantMode;
import 'package:nihaisha_app/screens/local_ai_interview_screen.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/screens/yijing_detail_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/contextual_ai_sheet.dart';

import 'support/in_memory_assistant_conversation_store.dart';

void main() {
  testWidgets('卦详情页展示倪师《人间道》讲义入口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: YiJingHexagramDetailScreen(hex: kHexagrams[0])),
    );

    // 卦名 + 卦辞 + 倪师人间道 + 讲义入口
    expect(find.text('乾为天'), findsOneWidget);
    expect(find.text('倪师《天纪·人间道》'), findsOneWidget);
    expect(find.text('倪师《天纪·人间道》讲课文稿'), findsOneWidget);

    // 六爻
    await tester.scrollUntilVisible(find.text('六爻爻辞（自下而上）'), 300);
    expect(find.text('六爻爻辞（自下而上）'), findsOneWidget);
  });

  testWidgets(
    'Yijing detail deep links keep the correct source and enable paragraph Ask AI',
    (tester) async {
      final hex = kHexagrams[0];
      final yijingAsset = yijingLectureAsset(hex.seq)!;
      final mingguaAsset = mingGuaLectureAsset(hex.seq)!;

      await tester.pumpWidget(
        ContextualAiConversationStoreScope(
          conversationStore: InMemoryAssistantConversationStore(),
          child: MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: AppColors.colorSchemeFor(Brightness.light),
              extensions: [AppColors.light],
            ),
            home: YiJingHexagramDetailScreen(hex: hex),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final yijingLink = find.text('倪师《天纪·人间道》讲课文稿');
      await tester.ensureVisible(yijingLink);
      await tester.tap(yijingLink);
      await tester.pumpAndSettle();

      final yijingReader = tester.widget<MarkdownDocScreen>(
        find.byType(MarkdownDocScreen),
      );
      expect(yijingReader.contextualAskModuleId, 'yijing-reading');
      expect(yijingReader.contextualAskAnchorId,
          'yijing-reading:passage:$yijingAsset');
      expect(yijingReader.contextualAskSourceId, yijingAsset);
      expect(yijingReader.contextualAskParagraphs, isTrue);

      Navigator.of(tester.element(find.byType(MarkdownDocScreen))).pop();
      await tester.pumpAndSettle();

      final mingguaLink = find.text('倪师《天纪·四柱命卦》讲义');
      await tester.ensureVisible(mingguaLink);
      await tester.tap(mingguaLink);
      await tester.pumpAndSettle();

      final mingguaReader = tester.widget<MarkdownDocScreen>(
        find.byType(MarkdownDocScreen),
      );
      expect(mingguaReader.contextualAskModuleId, 'minggua-reading');
      expect(mingguaReader.contextualAskAnchorId,
          'minggua-reading:passage:$mingguaAsset');
      expect(mingguaReader.contextualAskSourceId, mingguaAsset);
      expect(mingguaReader.contextualAskParagraphs, isTrue);

      final paragraph = find.textContaining(
        '有一天你在排八字的时候',
        findRichText: true,
      );
      await tester.ensureVisible(paragraph);
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
      expect(assistant.contextRef['moduleId'], 'minggua-reading');
      expect(
        assistant.contextRef['sourceId'],
        'minggua-reading:$mingguaAsset',
      );
      expect(
        assistant.contextRef['anchorId'],
        startsWith('minggua-reading:passage:$mingguaAsset:paragraph:'),
      );
      expect(assistant.contextRef['selectedText'], isNotEmpty);
      expect(
        assistant.initialPrompt,
        contains('有一天你在排八字的时候'),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
