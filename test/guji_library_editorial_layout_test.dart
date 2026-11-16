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
        builder: (context, child) => MediaQuery(
          // Apply 200% scaling above Navigator so pushed chapter routes are
          // covered too, not only the library root page.
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: const GujiLibraryScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<GujiChapter>> openBookAndLoad(
    WidgetTester tester,
    GujiBook book,
  ) async {
    await tester.tap(find.text(book.title).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The chapter ListView keeps a spinning progress indicator while rootBundle
    // reads a large public-domain text asset. Await real I/O instead of
    // pumpAndSettle, which cannot settle a live indeterminate animation.
    final chapters =
        await tester.runAsync(() => GujiRepository.chaptersOf(book));
    await tester.pump();
    await tester.pump();

    expect(find.byType(GujiBookScreen), findsOneWidget);
    final chapterContext = tester.element(find.byType(GujiBookScreen));
    expect(
      MediaQuery.textScalerOf(chapterContext).scale(1),
      2,
      reason: '章节目录路由也必须继承200%字号',
    );
    expect(chapters, isNotNull);
    expect(find.text(chapters!.first.title), findsWidgets);
    return chapters;
  }

  Future<void> returnToLibrary(WidgetTester tester) async {
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
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
      await openBookAndLoad(tester, book);

      final route = tester.widget<GujiBookScreen>(
        find.byType(GujiBookScreen),
      );
      expect(route.book.id, book.id,
          reason: '每个书目入口必须携带自身稳定 ID');
      expect(find.text(book.title), findsOneWidget);
      expect(find.byType(Card), findsNothing,
          reason: '章节目录不应重新引入重复 Card');
      expect(tester.takeException(), isNull);

      await returnToLibrary(tester);
    }
  });

  testWidgets('针灸大成末章三位数编号在200%字号下自然扩宽', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpLibrary(
      tester,
      width: 402,
      brightness: Brightness.light,
    );
    final book = kGujiBooks.singleWhere(
      (item) => item.id == 'zhenjiudacheng',
    );
    final chapters = await openBookAndLoad(tester, book);
    expect(chapters, hasLength(book.chapterCount));

    final lastChapter = chapters.last;
    final chapterList = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(
      find.text(lastChapter.title),
      480,
      scrollable: chapterList,
    );
    expect(find.text(lastChapter.title), findsOneWidget);
    expect(find.text('${book.chapterCount}'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: '三位数章节号在200%字号下不应挤压标题或溢出');
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
      final chapters = await openBookAndLoad(tester, book);
      final firstChapter = chapters.first;

      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), firstChapter.title);
      await tester.pump();
      await tester.pump();
      expect(find.text(firstChapter.title), findsWidgets);
      expect(find.text('没有匹配的章节'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      await tester.pump();
      expect(find.text(firstChapter.title), findsWidgets);

      final chapterTitle = find.text(firstChapter.title).last;
      await tester.ensureVisible(chapterTitle);
      await tester.tap(chapterTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(MarkdownDocScreen), findsOneWidget);
      expect(find.textContaining('原文出自'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await returnToLibrary(tester);
    }
  });
}
