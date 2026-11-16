import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/data/classic_lecture_data.dart';
import 'package:nihaisha_app/screens/classic_library_screen.dart';
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
          void expectFlatCardSurface() {
            final pageContext =
                tester.element(find.byType(NeijingKnowledgeScreen));
            expect(Theme.of(pageContext).cardTheme.elevation, 0);
            final localElevations = tester
                .widgetList<Card>(find.byType(Card))
                .map((card) => card.elevation);
            expect(
              localElevations.every(
                (elevation) => elevation == null || elevation == 0,
              ),
              isTrue,
              reason:
                  'Cards must inherit the zero-elevation theme; local overrides: $localElevations',
            );
          }

          expectFlatCardSurface();
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

  testWidgets(
    'classic library uses flat rows and preserves search at 200%',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 790);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: AppColors.colorSchemeFor(Brightness.light),
            extensions: [AppColors.light],
            cardTheme: const CardThemeData(elevation: 0),
            useMaterial3: true,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const ClassicLibraryScreen(
            title: '经典阅读测试',
            lectures: [
              ClassicLecture(
                seq: 1,
                name: '测试篇目甲',
                asset: 'assets/shanghan/clause_001.md',
              ),
              ClassicLecture(
                seq: 2,
                name: '测试篇目乙',
                asset: 'assets/shanghan/clause_002.md',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNothing);
      expect(find.text('测试篇目甲'), findsOneWidget);
      expect(find.text('测试篇目乙'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '篇目乙');
      await tester.pumpAndSettle();
      expect(find.text('测试篇目甲'), findsNothing);
      expect(find.text('测试篇目乙'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

}
