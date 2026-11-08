import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/ziwei_cases_list_screen.dart';
import 'package:nihaisha_app/utils/fold_aware_routes.dart';
import 'package:nihaisha_app/widgets/adaptive_content_width.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

void main() {
  testWidgets('案例库页渲染总论/宫详解/案例分组', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ZiweiCasesListScreen()),
    );

    expect(find.text('倪师紫微案例与十二宫'), findsOneWidget);
    expect(find.text('十二宫总论'), findsOneWidget);
    expect(find.text('紫微十二宫详解（按紫微所在宫）'), findsOneWidget);

    // 顶部可见：总论 + 前言
    expect(find.text('总'), findsOneWidget);
    expect(find.text('紫微十二宫详解·前言'), findsOneWidget);

    // 滚动到案例分组
    await tester.scrollUntilVisible(find.text('案例库（按命宫地支分组）'), 400);
    expect(find.text('案例库（按命宫地支分组）'), findsOneWidget);
  });
  testWidgets('展开窗口的案例列表限制最大阅读宽度并居中', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1100);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: ZiweiCasesListScreen()));
    final content = find.byType(AdaptiveContentWidth);
    expect(tester.getSize(content).width, 1000);
    final list = find.byType(ListView).first;
    expect(tester.getSize(list).width, 680);
    expect(tester.getRect(list).center.dx, closeTo(500, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('右侧物理屏区的案例列表进入原文后仍留在右屏', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(388, 0, 24, 1000),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Row(children: [
      const SizedBox(width: 412),
      Expanded(child: Builder(builder: (source) => Center(child: ElevatedButton(
        onPressed: () => Navigator.of(source).push(FoldAwareMaterialPageRoute<void>(
          sourceContext: source, builder: (_) => const ZiweiCasesListScreen(),
        )),
        child: const Text('打开紫微案例库'),
      )))),
    ]))));
    await tester.tap(find.text('打开紫微案例库'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '进入案例列表页时发生异常');
    final list = tester.getRect(find.byType(ListView).first);
    expect(list.left, greaterThanOrEqualTo(412));
    expect(list.right, lessThanOrEqualTo(800));
    await tester.tap(find.text('紫微十二宫详解·前言'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    final markdown = tester.getRect(find.byType(Markdown));
    final detailError = tester.takeException();
    expect(detailError, isNull, reason: '从案例列表进入原文详情时发生异常：$detailError');
    expect(markdown.left, greaterThanOrEqualTo(412));
    expect(markdown.right, lessThanOrEqualTo(800));
  });
}
