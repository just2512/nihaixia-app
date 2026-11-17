import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/data/formula_repository.dart';
import 'package:nihaisha_app/engine/diagnostic_rules.dart';
import 'package:nihaisha_app/screens/meridian_detail_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  setUpAll(() async {
    await FormulaRepository.load();
  });

  testWidgets('六经详情在402/775dp、浅深主题与200%字号下保持可读',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;

    for (final brightness in Brightness.values) {
      for (final width in [402.0, 775.0]) {
        for (final meridian in DiagnosticRules.meridianDetails.keys) {
          tester.view.physicalSize = Size(width, 900);
          final tokens =
              brightness == Brightness.dark ? AppColors.dark : AppColors.light;

          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey(
                'meridian-${meridian}-${width.toInt()}-${brightness.name}',
              ),
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
              home: MeridianDetailScreen(meridian: meridian),
            ),
          );
          await tester.pumpAndSettle();

          final pageContext = tester.element(
            find.byType(MeridianDetailScreen),
          );
          expect(
            MediaQuery.textScalerOf(pageContext).scale(1),
            2,
            reason: '六经详情必须实际运行在200%字号',
          );
          expect(find.text('${meridian}病'), findsWidgets);
          for (final section in [
            '核心症状',
            '欲解时',
            '传变规律',
            '经典条文',
            '倪海厦解读',
          ]) {
            expect(find.text(section), findsOneWidget,
                reason: '${meridian}详情缺少既有内容区块：$section');
          }
          expect(find.textContaining('常用方剂'), findsOneWidget);

          final localCards = tester.widgetList<Card>(find.byType(Card));
          expect(
            localCards.every((card) => card.elevation == null || card.elevation == 0),
            isTrue,
            reason: '详情页卡片必须继承零阴影主题，不应覆盖出重复阴影',
          );
          expect(tester.takeException(), isNull,
              reason: '${meridian} / ${width.toInt()}dp / ${brightness.name} / 200% 不应布局溢出');
        }
      }
    }
  });
}
