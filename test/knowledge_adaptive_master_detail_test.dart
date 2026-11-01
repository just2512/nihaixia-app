import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/screens/knowledge_screen.dart';

void main() {
  setUpAll(() async {
    await FormulaRepository.load();
    await HerbRepository.load();
  });

  testWidgets(
    'expanded formula tab selects a row and displays the preview pane',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(775, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: KnowledgeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('方剂'));
      await tester.pumpAndSettle();

      expect(find.text('选择一首方剂'), findsOneWidget);
      final formula = FormulaRepository.getAll().first;
      await tester.tap(find.text(formula.name).first);
      await tester.pumpAndSettle();

      expect(find.text('打开完整详情'), findsOneWidget);
      expect(find.text('适应证'), findsOneWidget);
      expect(find.text('组成'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    },
  );

  testWidgets(
    'expanded herb tab selects a row and displays the preview pane',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(775, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(home: KnowledgeScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('本草'));
      await tester.pumpAndSettle();

      expect(find.text('选择一味本草'), findsOneWidget);
      final herb = HerbRepository.getAll().first;
      await tester.tap(find.text(herb.name).first);
      await tester.pumpAndSettle();

      expect(find.text('打开完整详情'), findsOneWidget);
      expect(find.text(herb.name).last, findsOneWidget);
    },
  );
}
