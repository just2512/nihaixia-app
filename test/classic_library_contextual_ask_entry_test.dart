import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/classic_lecture_data.dart';
import 'package:nihaisha_app/screens/classic_library_screen.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/screens/shanghan_jingui_screen.dart';
import 'package:nihaisha_app/services/classic_search_service.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> openShanghanLibrary(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        extensions: [AppColors.light],
      ),
      home: const ShangHanJinguiScreen(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('伤寒论'));
    await tester.pumpAndSettle();
    expect(find.byType(ClassicLibraryScreen), findsOneWidget);
  }

  testWidgets(
    '伤寒论阅读库的条文2真实入口保留可解析来源并显示问AI菜单',
    (tester) async {
      const sourceId = 'shanghan:assets/shanghan/clause_001.md';
      final source = await ClassicSearchService.findBySourceId(sourceId);

      expect(source, isNotNull);
      expect(source!.sourceId, sourceId);
      expect(source.asset, 'assets/shanghan/clause_001.md');
      expect(source.localBacklink, 'assets/shanghan/clause_001.md');
      expect(source.hasLocalBacklink, isTrue);

      await openShanghanLibrary(tester);
      final clause = kShangHanLectures[1];
      expect(clause.seq, 1);
      expect(clause.asset, 'assets/shanghan/clause_001.md');

      await tester.tap(find.text(clause.name));
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownDocScreen), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.text(clause.name), findsOneWidget);

      final originalText =
          find.textContaining('太阳病', findRichText: true);
      expect(originalText, findsOneWidget);
      await tester.longPress(originalText);
      await tester.pumpAndSettle();

      expect(find.text('问 AI'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '相邻伤寒条文不会继承条文2的问AI锚点',
    (tester) async {
      await openShanghanLibrary(tester);
      final otherClause = kShangHanLectures[2];
      expect(otherClause.asset, 'assets/shanghan/clause_002.md');

      await tester.tap(find.text(otherClause.name));
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownDocScreen), findsOneWidget);
      expect(find.byType(SelectionArea), findsNothing);
      final bodyText = find.byType(Markdown);
      expect(bodyText, findsOneWidget);
      await tester.longPress(bodyText);
      await tester.pumpAndSettle();

      expect(find.text('问 AI'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
