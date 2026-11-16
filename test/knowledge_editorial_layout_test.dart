import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/neijing_knowledge_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/theme/app_tokens.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [402.0, 775.0]) {
      testWidgets(
        'Neijing editorial surfaces remain flat and readable at 200% '
        '($brightness, ${width.toInt()} dp)',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 790);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final tokens =
              brightness == Brightness.dark ? AppColors.dark : AppColors.light;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                colorScheme: AppColors.colorSchemeFor(brightness),
                extensions: [tokens],
                cardTheme: CardThemeData(
                  color: tokens.surface,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                useMaterial3: true,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                ),
                child: child!,
              ),
              home: const NeijingKnowledgeScreen(),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('黄帝内经 · 速查'), findsOneWidget);
          expect(
            tester.widgetList<Card>(find.byType(Card)).every(
              (card) => card.elevation == 0,
            ),
            isTrue,
          );
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('望诊'));
          await tester.pumpAndSettle();
          expect(find.text('五色 · 正常与病色'), findsOneWidget);
          expect(
            tester.widgetList<Card>(find.byType(Card)).every(
              (card) => card.elevation == 0,
            ),
            isTrue,
          );
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('脉诊'));
          await tester.pumpAndSettle();
          expect(find.text('平人脉标准'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
