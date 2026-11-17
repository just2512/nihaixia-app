import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/screens/guji_library_screen.dart';
import 'package:nihaisha_app/screens/tools_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

void main() {
  Future<void> pumpTools(
    WidgetTester tester, {
    required double width,
    required Brightness brightness,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    tester.view.displayFeatures = const [];
    await tester.pumpWidget(
      MaterialApp(
        key: ValueKey('tools-${width.toInt()}-${brightness.name}'),
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
        home: const ToolsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final pageContext = tester.element(find.byType(ToolsScreen));
    expect(
      MediaQuery.textScalerOf(pageContext).scale(1),
      2,
      reason: '工具页测试必须真实运行在200%字号',
    );
  }

  testWidgets('工具卡片标题和摘要在402/775dp、浅深主题与200%字号下自然换行',
      (tester) async {
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final brightness in Brightness.values) {
      for (final width in [402.0, 775.0]) {
        await pumpTools(
          tester,
          width: width,
          brightness: brightness,
        );

        expect(find.text('实用工具'), findsOneWidget);
        expect(find.text('中医区'), findsOneWidget);

        final scrollable = find.byType(Scrollable).first;
        final longTitle = find.text('中医时辰开穴综合计算器');
        await tester.scrollUntilVisible(
          longTitle,
          260,
          scrollable: scrollable,
        );
        final titleWidget = tester.widget<Text>(longTitle);
        expect(titleWidget.maxLines, isNull,
            reason: '工具标题不应被固定为一行');
        expect(titleWidget.overflow, isNull,
            reason: '工具标题不应以省略号隐藏内容');
        expect(tester.getRect(longTitle).right, lessThanOrEqualTo(width));
        expect(tester.takeException(), isNull,
            reason: '标题在${width.toInt()}dp / ${brightness.name} / 200%下不应溢出');

        final longSubtitleText =
            '血癌/红斑狼疮/脑瘤/肾衰竭/乳癌/肝癌 · 倪师重症思路';
        final longSubtitle = find.text(longSubtitleText);
        await tester.scrollUntilVisible(
          longSubtitle,
          260,
          scrollable: scrollable,
        );
        final subtitleWidget = tester.widget<Text>(longSubtitle);
        expect(subtitleWidget.maxLines, isNull,
            reason: '工具摘要不应被固定为两行');
        expect(subtitleWidget.overflow, isNull,
            reason: '工具摘要不应以省略号隐藏内容');
        expect(
          tester.getRect(longSubtitle).right,
          lessThanOrEqualTo(width),
        );
        expect(tester.takeException(), isNull,
            reason: '摘要在${width.toInt()}dp / ${brightness.name} / 200%下不应溢出');

        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });

  testWidgets('古籍原文工具入口仍保留原有详情路由', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpTools(
      tester,
      width: 402,
      brightness: Brightness.light,
    );

    final scrollable = find.byType(Scrollable).first;
    final gujiEntry = find.text('古籍原文');
    await tester.scrollUntilVisible(gujiEntry, 260, scrollable: scrollable);
    await tester.tap(gujiEntry);
    await tester.pumpAndSettle();

    expect(find.byType(GujiLibraryScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
