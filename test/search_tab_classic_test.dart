// 全局搜索「经典」分组端到端：输入关键词 → 异步索引命中 → 结果区出现「经典」。
// 运行：flutter test test/search_tab_classic_test.dart
//
// ⚠️ 索引加载走 rootBundle 真实 IO，widget 测试的假异步区不会推进它，
// 必须用 tester.runAsync 给真实时间，再补 pump 触发重建（同 ear_points_tab_test）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/acupoint_repository.dart';
import 'package:nihaisha_app/data/acupuncture_repository.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/screens/search_tab.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    databaseFactory = databaseFactoryFfi;
    await FormulaRepository.load();
    await HerbRepository.load();
    await AcupunctureRepository.load();
    await AcupointRepository.load();
  });

  testWidgets('输入「标幽赋」后出现经典分组并命中针灸大成', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: AppColors.colorSchemeFor(Brightness.light),
          extensions: [AppColors.light],
        ),
        home: const Scaffold(body: SearchTab()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '标幽赋');
    await tester.pump(const Duration(milliseconds: 350)); // 触发 300ms 防抖

    // 经典索引首次解压是真实 IO，给真实时间跑完
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('经典 ('), findsOneWidget,
        reason: '命中经典后应出现「经典 (n)」分组标题');
    expect(find.textContaining('针灸大成'), findsWidgets,
        reason: '「标幽赋」应命中针灸大成章节');

  });

  testWidgets('全局经典搜索打开本草命中时绑定本草讲稿来源', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: AppColors.colorSchemeFor(Brightness.light),
          extensions: [AppColors.light],
        ),
        home: const Scaffold(body: SearchTab()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '丹砂');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final sourceLabel = find.text('本草讲稿').first;
    expect(sourceLabel, findsOneWidget);
    final resultTile = find.ancestor(
      of: sourceLabel,
      matching: find.byType(ListTile),
    ).first;
    await tester.tap(resultTile);
    await tester.pumpAndSettle();

    final reader = tester.widget<MarkdownDocScreen>(
      find.byType(MarkdownDocScreen),
    );
    expect(reader.contextualAskModuleId, 'bencao-reading');
    expect(reader.contextualAskSourceId, reader.asset);
    expect(reader.contextualAskAnchorId,
        'bencao-reading:passage:${reader.asset}');
    expect(reader.contextualAskParagraphs, isTrue);
    expect(tester.takeException(), isNull);
  });

}
