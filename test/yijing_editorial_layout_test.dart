import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/screens/yijing_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  Future<void> pumpYiJing(
    WidgetTester tester, {
    required double width,
    required Brightness brightness,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    await tester.pumpWidget(
      MaterialApp(
        key: ValueKey('yijing-${width.toInt()}-${brightness.name}'),
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: AppColors.colorSchemeFor(brightness),
          extensions: [
            brightness == Brightness.dark ? AppColors.dark : AppColors.light,
          ],
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: const YiJingScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final pageContext = tester.element(find.byType(YiJingScreen));
    expect(
      MediaQuery.textScalerOf(pageContext).scale(1),
      2,
      reason: '易经工具测试必须真实运行在200%字号',
    );
  }

  testWidgets('起卦方法保留独立分组但不再使用额外 Card 阴影',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final brightness in Brightness.values) {
      for (final width in [402.0, 775.0]) {
        await pumpYiJing(
          tester,
          width: width,
          brightness: brightness,
        );

        expect(find.text('易经六十四卦'), findsOneWidget);
        expect(find.text('铜钱摇卦（六爻）'), findsOneWidget);

        final scrollable = find.byType(Scrollable).first;
        final timeMethod = find.text('时间起卦（梅花易数）');
        await tester.scrollUntilVisible(
          timeMethod,
          260,
          scrollable: scrollable,
        );
        expect(timeMethod, findsOneWidget);

        final numberMethod = find.text('数字起卦');
        await tester.scrollUntilVisible(
          numberMethod,
          260,
          scrollable: scrollable,
        );
        expect(numberMethod, findsOneWidget);

        final manualMethod = find.text('手动选卦');
        await tester.scrollUntilVisible(
          manualMethod,
          260,
          scrollable: scrollable,
        );
        expect(manualMethod, findsOneWidget);

        final elevatedCards = tester
            .widgetList<Card>(find.byType(Card))
            .where((card) => (card.elevation ?? 0) > 0)
            .toList(growable: false);
        expect(
          elevatedCards,
          isEmpty,
          reason: '方法分组保留，但不额外叠加高 elevation 阴影',
        );
        expect(tester.takeException(), isNull,
            reason: '${width.toInt()}dp / ${brightness.name} / 200% 不应出现布局异常');

        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets('三个功能 Tab 仍可切换，四柱命卦入口与讲义按钮仍可见',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpYiJing(
      tester,
      width: 402,
      brightness: Brightness.light,
    );

    await tester.tap(find.text('四柱命卦').first);
    await tester.pumpAndSettle();
    expect(find.text('四柱命卦计算器'), findsOneWidget);
    expect(find.text('浏览讲义'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('起卦').first);
    await tester.pumpAndSettle();
    expect(find.text('铜钱摇卦（六爻）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
