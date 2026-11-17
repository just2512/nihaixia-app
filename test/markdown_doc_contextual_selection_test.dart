import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import '../lib/theme/app_colors.dart';

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
        content: '#### 条文2\\n\\n> 太阳病，发热，汗出，恶风，脉缓者，名为中风。\\n\\n这段是讲解者的补充说明，不属于原文条文。',
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

  testWidgets('multiple independent blockquotes disable the single-clause contextual action',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      home: MarkdownDocScreen(
        title: '多条文阅读页',
        content: '> 第一条原文。\\n\\n解释文字。\\n\\n> 第二条原文。',
        contextualAskModuleId: 'shanghan',
        contextualAskAnchorId: 'shanghan:clause:002',
        contextualAskSourceId: 'assets/shanghan/clause_001.md',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SelectionArea), findsNothing);
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
}
