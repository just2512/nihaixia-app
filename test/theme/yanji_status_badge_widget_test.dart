import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/theme/yanji_status_semantics.dart';
import 'package:nihaisha_app/widgets/yanji_status_badge.dart';

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

ThemeData _theme(Brightness brightness, AppColors colors) {
  return ThemeData(
    colorScheme: AppColors.colorSchemeFor(brightness),
    extensions: <ThemeExtension<dynamic>>[colors],
  );
}

void main() {
  group('YanjiStatusBadge', () {
    for (final theme in <({String name, Brightness brightness, AppColors colors})>[
      (name: '浅色', brightness: Brightness.light, colors: AppColors.light),
      (name: '深色', brightness: Brightness.dark, colors: AppColors.dark),
    ]) {
      for (final tone in YanjiStatusTone.values) {
        testWidgets('${theme.name}主题/${tone.name}状态保留文字与语义容器', (tester) async {
          const label = '状态标签';
          final pair = yanjiStatusChipColors(tone, theme.colors);

          await tester.pumpWidget(
            MaterialApp(
              theme: _theme(theme.brightness, theme.colors),
              home: Scaffold(
                body: Center(
                  child: YanjiStatusBadge(label: label, colors: pair),
                ),
              ),
            ),
          );

          final badge = find.byType(YanjiStatusBadge);
          expect(badge, findsOneWidget);
          final decoration = tester.widget<DecoratedBox>(
            find.descendant(of: badge, matching: find.byType(DecoratedBox)),
          ).decoration as BoxDecoration;
          final text = tester.widget<Text>(find.text(label));

          expect(decoration.color, pair.background);
          expect(text.style?.color, pair.foreground);
          expect(
            _contrast(pair.foreground, pair.background),
            greaterThanOrEqualTo(4.5),
            reason: '${theme.name}主题/${tone.name}普通文字必须达到 4.5:1',
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('屏幕阅读器可识别状态名称', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(Brightness.light, AppColors.light),
          home: Scaffold(
            body: YanjiStatusBadge(
              label: '大凶',
              colors: yanjiStatusChipColors(
                YanjiStatusTone.danger,
                AppColors.light,
              ),
            ),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(YanjiStatusBadge)).label,
        '状态：大凶',
      );
      semantics.dispose();
    });

    testWidgets('窄屏下长标签自然换行且不产生布局溢出', (tester) async {
      const label = '传统民俗文化参考状态标签';
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(Brightness.light, AppColors.light),
          home: Scaffold(
            body: SizedBox(
              width: 100,
              child: Wrap(
                children: [
                  YanjiStatusBadge(
                    label: label,
                    colors: yanjiStatusChipColors(
                      YanjiStatusTone.neutral,
                      AppColors.light,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final theme in <({String name, Brightness brightness, AppColors colors})>[
      (name: '浅色', brightness: Brightness.light, colors: AppColors.light),
      (name: '深色', brightness: Brightness.dark, colors: AppColors.dark),
    ]) {
      testWidgets('${theme.name}主题下 200% 字体缩放仍可读取且不溢出',
          (tester) async {
        const label = '大凶（传统民俗文化参考）';
        await tester.pumpWidget(
          MaterialApp(
            theme: _theme(theme.brightness, theme.colors),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
              child: Scaffold(
                body: SizedBox(
                  width: 120,
                  child: Wrap(
                    children: [
                      YanjiStatusBadge(
                        label: label,
                        colors: yanjiStatusChipColors(
                          YanjiStatusTone.danger,
                          theme.colors,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text(label), findsOneWidget);
        expect(
          tester.getSize(find.byType(YanjiStatusBadge)).height,
          greaterThan(28),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
