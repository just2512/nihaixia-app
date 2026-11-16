import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/data/critical_illness_data.dart';
import 'package:nihaisha_app/screens/critical_illness_list_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  testWidgets('闭门课重症列表在内外屏宽度与双主题200%字号下完整呈现',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetDisplayFeatures);

    for (final brightness in [Brightness.light, Brightness.dark]) {
      for (final size in [const Size(402, 900), const Size(775, 900)]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: AppColors.colorSchemeFor(brightness),
              extensions: [
                brightness == Brightness.dark
                    ? AppColors.dark
                    : AppColors.light,
              ],
              cardTheme: const CardThemeData(elevation: 0),
            ),
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(2),
              ),
              child: const CriticalIllnessListScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('闭门课 · 重症临床'), findsOneWidget);
        for (final illness in kCriticalIllnesses) {
          expect(find.text(illness.title), findsOneWidget);
          expect(find.text(illness.subtitle), findsOneWidget);
        }

        expect(find.byType(Card), findsNWidgets(kCriticalIllnesses.length));
        expect(
          Theme.of(tester.element(find.byType(CriticalIllnessListScreen)))
              .cardTheme
              .elevation,
          0,
        );
        for (final card in tester.widgetList<Card>(find.byType(Card))) {
          expect(
            card.elevation == null || card.elevation == 0,
            isTrue,
            reason: '普通列表卡片不应覆盖全局零 elevation 基线',
          );
        }
        expect(
          tester.takeException(),
          isNull,
          reason:
              '重症列表在 ${brightness.name}、${size.width.toInt()}dp、200% 字号下不应溢出',
        );
      }
    }
  });
}
