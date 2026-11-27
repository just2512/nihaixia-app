import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nihaisha_app/data/bencao_lecture_data.dart';
import 'package:nihaisha_app/data/bencao_lecture_index.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/data/medical_case_data.dart';
import 'package:nihaisha_app/models/herb.dart';
import 'package:nihaisha_app/screens/bencao_library_screen.dart';
import 'package:nihaisha_app/screens/herb_detail_screen.dart';
import 'package:nihaisha_app/screens/markdown_doc_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

Widget _app(Widget home) => MaterialApp(
      theme: ThemeData(useMaterial3: true, extensions: [AppColors.light]),
      home: home,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Directory? dbTempDir;
  late BenCaoLectureIndex lectureIndex;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dbTempDir = await Directory.systemTemp.createTemp('bencao_navigation_db');
    await databaseFactory.setDatabasesPath(dbTempDir!.path);

    await HerbRepository.load();
    await FormulaRepository.load();
    lectureIndex = await BenCaoLectureIndex.load();
  });

  tearDownAll(() async {
    final dir = dbTempDir;
    if (dir != null) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        // Test result does not depend on temporary database cleanup.
      }
    }
  });

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(
      () => tester.pumpAndSettle(const Duration(seconds: 30)),
    );
  }

  Future<void> pumpHerbPage(WidgetTester tester, Herb herb) async {
    final view = tester.view;
    view.physicalSize = const Size(900, 6000);
    view.devicePixelRatio = 1;
    addTearDown(() => view.resetPhysicalSize());

    // The existing herb detail screen loads related case counts asynchronously.
    await tester.runAsync(() => getAllMedicalCases());
    await tester.pumpWidget(_app(HerbDetailScreen(herb: herb)));
    await settle(tester);
  }

  testWidgets('本草阅读库点按篇目打开对应原始 Markdown 资产', (tester) async {
    final lecture = kBenCaoLectures.first;

    await tester.pumpWidget(_app(const BenCaoLibraryScreen()));
    await settle(tester);

    expect(find.text(lecture.name), findsOneWidget);
    await tester.tap(find.text(lecture.name));
    await settle(tester);

    final reader = tester.widget<MarkdownDocScreen>(
      find.byType(MarkdownDocScreen),
    );
    expect(reader.title, lecture.name);
    expect(reader.asset, lecture.asset);
    expect(reader.linkFormulas, isTrue);
  });

  testWidgets('药材详情页讲义入口可反向打开正确的本草原文', (tester) async {
    final herb = HerbRepository.getExactByName('丹砂')!;
    final hits = lectureIndex.hitsFor(herb.name);
    expect(hits, isNotEmpty);

    await pumpHerbPage(tester, herb);

    expect(find.text('讲义讲解'), findsOneWidget);
    await tester.tap(find.text('讲义讲解'));
    await settle(tester);

    expect(find.text('${herb.name} · 讲义提及'), findsOneWidget);
    final firstHit = hits.first;
    final lectureTitle = BenCaoLectureIndex.nameOf(firstHit.seq);
    await tester.tap(find.text(lectureTitle));
    await settle(tester);

    final reader = tester.widget<MarkdownDocScreen>(
      find.byType(MarkdownDocScreen),
    );
    expect(reader.title, lectureTitle);
    expect(reader.asset, BenCaoLectureIndex.assetOf(firstHit.seq));
    expect(reader.linkFormulas, isTrue);
  });
}
