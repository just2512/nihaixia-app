import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/data/herb_repository.dart';
import 'package:nihaisha_app/screens/formula_detail_screen.dart';
import 'package:nihaisha_app/screens/herb_detail_screen.dart';
import 'package:nihaisha_app/screens/knowledge_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/widgets/adaptive_master_detail.dart';

void main() {
  setUpAll(() async {
    await FormulaRepository.load();
    await HerbRepository.load();
  });

  Future<void> pumpKnowledge(
    WidgetTester tester, {
    required Brightness brightness,
    required Size size,
    bool halfFolded = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.displayFeatures = halfFolded
        ? [
            DisplayFeature(
              bounds: const Rect.fromLTWH(388, 0, 24, 900),
              type: DisplayFeatureType.hinge,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ]
        : const [];

    final tokens =
        brightness == Brightness.dark ? AppColors.dark : AppColors.light;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: AppColors.colorSchemeFor(brightness),
          extensions: [tokens],
          cardTheme: const CardThemeData(elevation: 0),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        // A half-open Find N2 root keeps the page on one physical panel.
        // This mirrors AdaptiveHomeNavigation's single-pane shell behavior.
        home: halfFolded
            ? const AdaptiveSinglePane(child: KnowledgeScreen())
            : const KnowledgeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final pageContext = tester.element(find.byType(KnowledgeScreen));
    expect(
      MediaQuery.textScalerOf(pageContext).scale(1),
      2,
      reason: '知识页必须实际继承200%系统字号',
    );
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    '知识页方剂与本草主从预览在775dp浅深主题及200%字号下保持分区',
    (tester) async {
      addTearDown(tester.view.reset);

      for (final brightness in Brightness.values) {
        await pumpKnowledge(
          tester,
          brightness: brightness,
          size: const Size(775, 900),
        );

        await tester.tap(find.text('方剂'));
        await tester.pumpAndSettle();
        final formula = FormulaRepository.getAll().first;
        final formulaRow = find.text(formula.name).first;
        await tester.ensureVisible(formulaRow);
        await tester.tap(formulaRow);
        await tester.pumpAndSettle();

        expect(find.text('打开完整详情'), findsOneWidget);
        expect(find.text('适应证'), findsOneWidget);
        expect(find.text('组成'), findsOneWidget);
        final formulaListTile = find.ancestor(
          of: find.text(formula.name).first,
          matching: find.byType(ListTile),
        ).first;
        final formulaMasterRect = tester.getRect(formulaListTile);
        final formulaPreviewRect = tester.getRect(find.text('打开完整详情'));
        expect(
          formulaPreviewRect.left,
          greaterThan(formulaMasterRect.right),
          reason: '方剂预览应位于列表主栏右侧，不与列表重叠',
        );
        expect(
          tester.widgetList<Card>(find.byType(Card)).every(
                (card) => card.elevation == null || card.elevation == 0,
              ),
          isTrue,
          reason: '方剂浏览页面不应重新引入卡片阴影',
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('本草'));
        await tester.pumpAndSettle();
        final herb = HerbRepository.getAll().first;
        final herbRow = find.text(herb.name).first;
        await tester.ensureVisible(herbRow);
        await tester.tap(herbRow);
        await tester.pumpAndSettle();

        expect(find.text('打开完整详情'), findsOneWidget);
        expect(find.text(herb.name).last, findsOneWidget);
        final herbListTile = find.ancestor(
          of: find.text(herb.name).first,
          matching: find.byType(ListTile),
        ).first;
        final herbMasterRect = tester.getRect(herbListTile);
        final herbPreviewRect = tester.getRect(find.text('打开完整详情'));
        expect(
          herbPreviewRect.left,
          greaterThan(herbMasterRect.right),
          reason: '本草预览应位于列表主栏右侧，不与列表重叠',
        );
        expect(
          tester.widgetList<Card>(find.byType(Card)).every(
                (card) => card.elevation == null || card.elevation == 0,
              ),
          isTrue,
          reason: '本草浏览页面不应重新引入卡片阴影',
        );
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'Find N2 半折叠面板内的方剂与本草详情路由在浅深主题及200%字号下不越过铰链',
    (tester) async {
      addTearDown(tester.view.reset);

      for (final brightness in Brightness.values) {
        await pumpKnowledge(
          tester,
          brightness: brightness,
          size: const Size(800, 900),
          halfFolded: true,
        );

        await tester.tap(find.text('方剂'));
        await tester.pumpAndSettle();
        final formula = FormulaRepository.getAll().first;
        final formulaRow = find.text(formula.name).first;
        await tester.ensureVisible(formulaRow);
        await tester.tap(formulaRow);
        await tester.pumpAndSettle();

        expect(find.byType(FormulaDetailScreen), findsOneWidget);
        expect(find.text('组成'), findsOneWidget);
        expect(find.text('适应证'), findsOneWidget);
        final formulaPage = tester.getRect(find.byType(Scaffold).last);
        expect(formulaPage.left, greaterThanOrEqualTo(0));
        expect(
          formulaPage.right,
          lessThanOrEqualTo(388),
          reason: '半折叠方剂详情必须留在左侧物理面板',
        );
        final formulaContext = tester.element(find.byType(FormulaDetailScreen));
        expect(MediaQuery.textScalerOf(formulaContext).scale(1), 2);
        expect(tester.takeException(), isNull);

        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('本草').first);
        await tester.pumpAndSettle();
        final herb = HerbRepository.getAll().first;
        final herbRow = find.text(herb.name).first;
        await tester.ensureVisible(herbRow);
        await tester.tap(herbRow);
        await tester.pumpAndSettle();

        expect(find.byType(HerbDetailScreen), findsOneWidget);
        expect(find.text(herb.category), findsOneWidget);
        final herbPage = tester.getRect(find.byType(Scaffold).last);
        expect(herbPage.left, greaterThanOrEqualTo(0));
        expect(
          herbPage.right,
          lessThanOrEqualTo(388),
          reason: '半折叠本草详情必须留在左侧物理面板',
        );
        final herbContext = tester.element(find.byType(HerbDetailScreen));
        expect(MediaQuery.textScalerOf(herbContext).scale(1), 2);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );
}
