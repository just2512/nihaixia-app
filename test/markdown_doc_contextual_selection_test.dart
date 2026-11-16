import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

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
  });

  testWidgets('ordinary markdown reading keeps its existing selectable behavior',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
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
    await tester.pumpWidget(const MaterialApp(
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
