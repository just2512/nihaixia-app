import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nihaisha_app/screens/guansha_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

Future<void> _pumpGuanshaWiki(
  WidgetTester tester, {
  required double width,
  required Brightness brightness,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 900);
  tester.view.displayFeatures = const [];

  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey('guansha-wiki-${width.toInt()}-${brightness.name}'),
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
      home: const GuanshaScreen(),
    ),
  );
  await tester.pumpAndSettle();

  final pageContext = tester.element(find.byType(GuanshaScreen));
  expect(
    MediaQuery.textScalerOf(pageContext).scale(1),
    2,
    reason: '小儿关煞百科布局测试必须真实运行在200%字号',
  );

  await tester.tap(find.text('百科'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('关煞百科连续条目在402/775dp、浅深主题和200%字号下使用轻列表',
      (tester) async {
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final brightness in Brightness.values) {
      for (final width in [402.0, 775.0]) {
        await _pumpGuanshaWiki(
          tester,
          width: width,
          brightness: brightness,
        );

        expect(find.byType(ListView), findsOneWidget);
        expect(find.byType(Card), findsNothing,
            reason: '百科连续条目应使用平面列表，不应重复堆叠高阴影 Card');
        expect(find.text('将军箭'), findsOneWidget);
        expect(find.text('阎王关'), findsOneWidget);
        expect(find.text('本条目为传统民俗文化参考'), findsNothing,
            reason: '完整免责声明只应在条目详情中显示');
        expect(tester.takeException(), isNull,
            reason: '${width.toInt()}dp / ${brightness.name} / 200% 列表不得溢出');

        final entry = find.text('将军箭');
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();

        expect(find.text('口诀'), findsOneWidget);
        expect(find.text('查法'), findsOneWidget);
        expect(find.textContaining('一箭伤人三岁死'), findsOneWidget);
        expect(find.textContaining('儿童健康请务必咨询正规医疗机构'), findsOneWidget);
        expect(tester.takeException(), isNull,
            reason: '${width.toInt()}dp / ${brightness.name} / 200% 详情弹层不得溢出');

        await tester.pageBack();
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), '阎罗关');
        await tester.pumpAndSettle();
        expect(find.text('阎王关'), findsOneWidget,
            reason: '别名检索应仍命中原有条目');
        expect(find.text('将军箭'), findsNothing,
            reason: '搜索结果应过滤掉不匹配条目');
        expect(tester.takeException(), isNull,
            reason: '${width.toInt()}dp / ${brightness.name} / 200% 搜索不得溢出');

        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
  });
}
