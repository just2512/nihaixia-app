import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/screens/festival_lookup_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  Future<void> pumpFestival(
    WidgetTester tester, {
    required double width,
    required Brightness brightness,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    await tester.pumpWidget(
      MaterialApp(
        key: ValueKey('festival-${width.toInt()}-${brightness.name}'),
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
        home: const FestivalLookupScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final pageContext = tester.element(find.byType(FestivalLookupScreen));
    expect(
      MediaQuery.textScalerOf(pageContext).scale(1),
      2,
      reason: '节日检索页必须真实运行在200%字号',
    );
  }

  testWidgets('节日列表在402/775dp、浅深主题和200%字号下无横向溢出',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final brightness in Brightness.values) {
      for (final width in [402.0, 775.0]) {
        await pumpFestival(
          tester,
          width: width,
          brightness: brightness,
        );
        expect(find.text('农历节日 · 神诞'), findsOneWidget);
        expect(find.byType(Card), findsNothing,
            reason: '连续节日列表应使用平面条目和分隔线');
        expect(find.text('潮汕 · 玉匣记'), findsWidgets,
            reason: '双来源条目必须显示来源标记');
        expect(find.textContaining('公历'), findsWidgets,
            reason: '条目应保留当年公历换算结果');
        expect(tester.takeException(), isNull,
            reason: '${width.toInt()}dp / ${brightness.name} / 200% 不应溢出');
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets('节日检索支持名称过滤、清空筛选并恢复列表',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpFestival(
      tester,
      width: 402,
      brightness: Brightness.light,
    );

    await tester.enterText(find.byType(TextField), '妈祖');
    await tester.pumpAndSettle();
    expect(find.textContaining('妈祖'), findsWidgets);
    expect(find.textContaining('春节'), findsNothing);
    expect(find.byTooltip('清空'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('清空'));
    await tester.pumpAndSettle();
    expect(find.textContaining('春节'), findsWidgets);
    expect(find.textContaining('妈祖'), findsWidgets);
    expect(find.text('农历节日 · 神诞'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
