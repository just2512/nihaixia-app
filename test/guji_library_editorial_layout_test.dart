import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/data/acupoint_repository.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/guji_data.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/screens/guji_library_screen.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

String _fixtureFor(GujiBook book) {
  final buffer = StringBuffer('《${book.title}》测试前言\n');
  for (var index = 0; index < book.chapterCount; index++) {
    final serial = (index + 1).toString().padLeft(3, '0');
    buffer
      ..writeln('====')
      ..writeln('第${serial}章')
      ..writeln('====')
      ..writeln(
        '章节${(index + 1).toString().padLeft(3, '0')}：'
        '${book.id} 原文内容，用于检索、显示和布局回归。',
      );
  }
  return buffer.toString();
}

class _GujiTestAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final books = kGujiBooks.where((book) => book.asset == key);
    if (books.isEmpty) {
      throw FlutterError('Unexpected test asset request: $key');
    }
    final bytes = Uint8List.fromList(utf8.encode(_fixtureFor(books.first)));
    return ByteData.sublistView(bytes);
  }
}

void main() {
  setUpAll(() async {
    await FormulaRepository.load();
    await HerbRepository.load();
    await AcupointRepository.load();
  });

  setUp(() {
    GujiRepository.clearCache();
  });

  tearDown(() {
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
        key: ValueKey('guji-${width.toInt()}-${brightness.name}'),
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: AppColors.colorSchemeFor(brightness),
          extensions: [
            brightness == Brightness.dark ? AppColors.dark : AppColors.light,
          ],
        ),
        builder: (context, child) => DefaultAssetBundle(
          // This sits above Navigator so pushed chapter routes use the same
          // deterministic in-memory assets as the library root page.
          bundle: _GujiTestAssetBundle(),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
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
    final bookTitle = find.text(book.title).first;
    await tester.ensureVisible(bookTitle);
    await tester.pump();
    await tester.tap(bookTitle);
    // The in-memory bundle completes after Flutter pumps the route. A bounded
    // frame loop avoids waiting for an indeterminate progress indicator.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    for (var frame = 0;
        frame < 20 && find.text('第001章').evaluate().isEmpty;
        frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(GujiBookScreen), findsOneWidget);
    expect(find.text('第001章'), findsOneWidget);
    final chapters = await GujiRepository.chaptersOf(book);
    expect(chapters, hasLength(book.chapterCount));
    expect(find.text(chapters.first.title), findsWidgets);
    final chapterContext = tester.element(find.byType(GujiBookScreen));
    expect(
      MediaQuery.textScalerOf(chapterContext).scale(1),
      2,
      reason: '章节目录路由也必须继承200%字号',
    );
    return chapters;
  }

  Future<void> returnToLibrary(WidgetTester tester) async {
    final routeContext = tester.element(find.byType(GujiBookScreen));
    Navigator.of(routeContext).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
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
      final chapters = await openBookAndLoad(tester, book);
      final route = tester.widget<GujiBookScreen>(
        find.byType(GujiBookScreen),
      );
      expect(route.book.id, book.id,
          reason: '每个书目入口必须携带自身稳定 ID');
      expect(chapters, hasLength(book.chapterCount));
      // The previous route remains in the Navigator's overlay while the
      // pushed chapter route is active, so the book title can be rendered
      // both in the list below and in the current AppBar.
      expect(find.text(book.title), findsWidgets);
      expect(find.byType(Card), findsNothing,
          reason: '章节目录不应重新引入重复 Card');
      expect(tester.takeException(), isNull);

      // Recreate the Navigator between book cases. The test is verifying the
      // two independent entry routes and their stable book IDs, not coupling
      // both assertions to Flutter's overlapping route transition overlays.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await pumpLibrary(
        tester,
        width: 402,
        brightness: Brightness.light,
      );
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
      maxScrolls: book.chapterCount,
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

      final bodyText = firstChapter.body.trim();
      expect(bodyText.length, greaterThan(3));
      await tester.enterText(
        find.byType(TextField),
        bodyText.substring(0, 5),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(firstChapter.title), findsWidgets,
          reason: '应能按章节正文内容命中该章节');
      expect(find.text('没有匹配的章节'), findsNothing);

      await tester.enterText(find.byType(TextField), firstChapter.title);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(firstChapter.title), findsWidgets,
          reason: '应能按章节标题检索');

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(firstChapter.title), findsWidgets);

      final chapterTitle = find.text(firstChapter.title).last;
      await tester.ensureVisible(chapterTitle);
      await tester.tap(chapterTitle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(MarkdownDocScreen), findsOneWidget);
      expect(find.textContaining('原文出自'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Isolate the next viewport/theme scenario from the previous Navigator
      // transition and its retained Back tooltip.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
