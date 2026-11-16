import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/data/acupoint_repository.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/guji_data.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/screens/guji_library_screen.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  setUpAll(() async {
    await FormulaRepository.load();
    await HerbRepository.load();
    await AcupointRepository.load();
    GujiRepository.clearCache();
  });

  Future<void> pumpLibrary(
    WidgetTester tester, {
    required double width,
    required Brightness brightness,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: AppColors.colorSchemeFor(brightness),
          extensions: [
            brightness == Brightness.dark ? AppColors.dark : AppColors.light,
          ],
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 900),
            textScaler: const TextScaler.linear(2),
          ),
          child: const GujiLibraryScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('古籍书目在402/775dp、浅深主题与200%字号下可读且无重复卡片',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final width in [402.0, 775.0]) {
        await pumpLibrary(
          tester,
          width: width,
          brightness: brightness,
        );
        expect(find.text('古籍原文'), findsOneWidget);
        for (final book in kGujiBooks) {
          expect(find.text(book.title), findsOneWidget);
        }
        expect(find.byType(Card), findsNothing,
            reason: '连续书目列表应使用平面条目和细分隔线');
        expect(tester.takeException(), isNull,
            reason: '${width.toInt()}dp / ${brightness.name} / 200% 不应溢出');
      }
    }
  });

  testWidgets('两个书目都跳转到各自的章节目录', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpLibrary(
      tester,
      width: 402,
      brightness: Brightness.light,
    );

    for (final book in kGujiBooks) {
      await tester.tap(find.text(book.title).first);
      await tester.pumpAndSettle();

      expect(find.byType(GujiBookScreen), findsOneWidget);
      final route = tester.widget<GujiBookScreen>(
        find.byType(GujiBookScreen),
      );
      expect(route.book.id, book.id,
          reason: '每个书目入口必须携带自身稳定 ID');
      expect(find.text(book.title), findsOneWidget);
      expect(find.byType(Card), findsNothing,
          reason: '章节目录不应重新引入重复 Card');
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('章节目录支持正文搜索、清除筛选与原文阅读跳转',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in [402.0, 775.0]) {
      await pumpLibrary(
        tester,
        width: width,
        brightness: Brightness.dark,
      );
      final book = kGujiBooks.first;
      await tester.tap(find.text(book.title));
      await tester.pumpAndSettle();

      final chapters = await GujiRepository.chaptersOf(book);
      final firstChapter = chapters.first;
      expect(find.text(firstChapter.title), findsWidgets);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), firstChapter.title);
      await tester.pumpAndSettle();
      expect(find.text(firstChapter.title), findsWidgets);
      expect(find.text('没有匹配的章节'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.text(firstChapter.title), findsWidgets);

      await tester.ensureVisible(find.text(firstChapter.title).last);
      await tester.tap(find.text(firstChapter.title).last);
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownDocScreen), findsOneWidget);
      expect(find.textContaining('原文出自'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });
}
