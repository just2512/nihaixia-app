import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/data/acupuncture_repository.dart';
import 'package:nihaisha_app/data/acupoint_repository.dart';
import 'package:nihaisha_app/screens/acupuncture_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AcupunctureRepository.load();
    await AcupointRepository.load();
  });

  testWidgets(
    '针灸知识四个子页面在402/775dp、浅深主题及200%字号下无布局溢出',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;

      for (final brightness in Brightness.values) {
        for (final width in [402.0, 775.0]) {
          tester.view.physicalSize = Size(width, 900);
          final tokens =
              brightness == Brightness.dark ? AppColors.dark : AppColors.light;

          await tester.pumpWidget(
            MaterialApp(
              key: ValueKey('acupuncture-${width.toInt()}-${brightness.name}'),
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
              home: const Scaffold(body: AcupunctureScreen()),
            ),
          );
          await tester.pumpAndSettle();

          final pageContext = tester.element(find.byType(AcupunctureScreen));
          expect(
            MediaQuery.textScalerOf(pageContext).scale(1),
            2,
            reason: '针灸知识页必须实际继承200%系统字号',
          );

          for (final tab in ['穴位处方', '透针透穴', '穴位讲解', '耳穴']) {
            await tester.tap(find.text(tab).last);
            await tester.pump();
            if (tab == '耳穴') {
              // The ear-point list is loaded from a real asset in initState.
              // Let that asynchronous asset read finish before settling frames.
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(seconds: 1)),
              );
              await tester.pump();
            }
            await tester.pumpAndSettle();

            expect(find.text(tab).last, findsOneWidget);
            expect(
              tester.widgetList<Card>(find.byType(Card)).every(
                    (card) => card.elevation == null || card.elevation == 0,
                  ),
              isTrue,
              reason: '针灸子页卡片应继承零阴影主题',
            );
            expect(
              tester.takeException(),
              isNull,
              reason:
                  '${tab} / ${width.toInt()}dp / ${brightness.name} / 200% 不应布局溢出',
            );

            final expandable = find.byType(ExpansionTile);
            if (expandable.evaluate().isNotEmpty &&
                (tab == '穴位处方' || tab == '透针透穴' || tab == '耳穴')) {
              await tester.tap(expandable.first);
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason:
                    '${tab} 展开内容在 ${width.toInt()}dp / ${brightness.name} / 200% 不应溢出',
              );
            }
          }

          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }
      }
    },
  );
}
