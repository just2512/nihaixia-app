import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/ziwei_chart_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/utils/fold_aware_routes.dart';

final _testTheme = ThemeData(
  colorScheme: AppColors.colorSchemeFor(Brightness.light),
  useMaterial3: true,
  extensions: [AppColors.light],
);

void main() {
  testWidgets('紫微命盘在展开内屏限制盘面宽度并居中', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(760, 1100);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme,
        home: ZiweiChartScreen(initialSolar: DateTime(2000, 8, 16, 10)),
      ),
    );
    await tester.pumpAndSettle();
    // Initial chart calculation is scheduled in a microtask from initState.
    // Pump once more so the completed chart and its expanded summary are built.
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ziwei-expanded-input-summary')), findsOneWidget);
    final plate = find.byKey(const ValueKey('ziwei-chart-plate-width'));
    // The chart is below the input and summary sections in a lazy ListView.
    // Scroll it into the build/cache region before asserting its constraints.
    await tester.scrollUntilVisible(
      plate,
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(plate, findsOneWidget);
    expect(tester.getSize(plate).width, 640);
    expect(tester.getRect(plate).center.dx, closeTo(380, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('紫微命盘在外屏不强行撑宽', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 850);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme,
        home: ZiweiChartScreen(initialSolar: DateTime(2000, 8, 16, 10)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ziwei-expanded-input-summary')), findsNothing);
    final plate = find.byKey(const ValueKey('ziwei-chart-plate-width'));
    // The chart is lazily built only after scrolling past the form and summary.
    await tester.scrollUntilVisible(
      plate,
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(plate, findsOneWidget);
    expect(tester.getSize(plate).width, lessThanOrEqualTo(370));
    expect(tester.takeException(), isNull);
  });
  testWidgets('紫微摘要双栏断点在 640dp 精确切换且边界无溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final scenario in [
      (639.0, false),
      (640.0, true),
    ]) {
      tester.view.physicalSize = Size(scenario.$1, 1000);
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('ziwei-summary-${scenario.$1}'),
          theme: _testTheme,
          home: ZiweiChartScreen(initialSolar: DateTime(2000, 8, 16, 10)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('ziwei-expanded-input-summary')),
        scenario.$2 ? findsOneWidget : findsNothing,
        reason: '窗口宽度 ${scenario.$1}dp 的双栏状态不符合 640dp 断点',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('紫微排盘在物理铰链设备上完整约束到单侧面板', (tester) async {
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

    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme,
        home: ZiweiChartScreen(initialSolar: DateTime(2000, 8, 16, 10)),
      ),
    );
    await tester.pumpAndSettle();

    final page = tester.getRect(find.byType(Scaffold).first);
    expect(page.width, lessThanOrEqualTo(388));
    expect(page.right, lessThanOrEqualTo(388));
    expect(
      find.byKey(const ValueKey('ziwei-expanded-input-summary')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });


  testWidgets('紫微命盘横屏展开布局不越界且盘面保持限宽', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 760);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme,
        home: ZiweiChartScreen(initialSolar: DateTime(2000, 8, 16, 10)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('ziwei-expanded-input-summary')), findsOneWidget);
    final plate = find.byKey(const ValueKey('ziwei-chart-plate-width'));
    await tester.scrollUntilVisible(
      plate,
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(plate, findsOneWidget);
    expect(tester.getSize(plate).width, 640);
    expect(tester.getRect(plate).center.dx, closeTo(500, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('紫微排盘横屏遇到水平铰链时完整留在触发入口所在屏区', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(0, 368, 1000, 24),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final scenario in [
      (Alignment.topCenter, true),
      (Alignment.bottomCenter, false),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('ziwei-hinge-${scenario.$1}'),
          theme: _testTheme,
          home: Scaffold(
            body: Align(
              alignment: scenario.$1,
              child: Builder(
                builder: (sourceContext) => TextButton(
                  onPressed: () => Navigator.of(sourceContext).push(
                    FoldAwareMaterialPageRoute<void>(
                      sourceContext: sourceContext,
                      builder: (_) => ZiweiChartScreen(
                        initialSolar: DateTime(2000, 8, 16, 10),
                      ),
                    ),
                  ),
                  child: const Text('打开紫微排盘'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开紫微排盘'));
      await tester.pumpAndSettle();

      final page = tester.getRect(find.byType(Scaffold).last);
      if (scenario.$2) {
        expect(page.top, greaterThanOrEqualTo(0));
        expect(page.bottom, lessThanOrEqualTo(368));
      } else {
        expect(page.top, greaterThanOrEqualTo(392));
        expect(page.bottom, lessThanOrEqualTo(760));
      }
      expect(page.width, 1000);
      expect(tester.takeException(), isNull);
      Navigator.of(tester.element(find.byType(ZiweiChartScreen))).pop();
      await tester.pumpAndSettle();
    }
  });


  testWidgets('紫微命盘从右侧物理屏区打开宫位详情时底部面板留在右屏', (tester) async {
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

    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme,
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 412),
              Expanded(
                child: Builder(
                  builder: (sourceContext) => Center(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(sourceContext).push(
                        FoldAwareMaterialPageRoute<void>(
                          sourceContext: sourceContext,
                          builder: (_) => ZiweiChartScreen(
                            initialSolar: DateTime(2000, 8, 16, 10),
                          ),
                        ),
                      ),
                      child: const Text('从右屏打开紫微排盘'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('从右屏打开紫微排盘'));
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pumpAndSettle();

    final plate = find.byKey(const ValueKey('ziwei-chart-plate-width'));
    await tester.scrollUntilVisible(
      plate,
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(plate, findsOneWidget);
    final plateRect = tester.getRect(plate);
    expect(plateRect.left, greaterThanOrEqualTo(412));
    expect(plateRect.right, lessThanOrEqualTo(800));

    // The scroll viewport itself must stay inside the right physical panel;
    // checking only the chart's left edge would miss cross-hinge overflow.
    final chartViewport = tester.getRect(find.byType(Scrollable).first);
    expect(chartViewport.left, greaterThanOrEqualTo(412));
    expect(chartViewport.right, lessThanOrEqualTo(800));

    final palaceCell = find.descendant(
      of: plate,
      matching: find.byType(GestureDetector),
    ).first;
    await tester.tap(palaceCell);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    final sheetRect = tester.getRect(sheet);
    expect(sheetRect.left, greaterThanOrEqualTo(412));
    expect(sheetRect.right, lessThanOrEqualTo(800));
    expect(tester.takeException(), isNull);
  });


  testWidgets('紫微命盘从横向折叠屏下侧面板打开宫位详情时底部面板留在下屏', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(0, 368, 1000, 24),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Builder(
              builder: (sourceContext) => ElevatedButton(
                onPressed: () => Navigator.of(sourceContext).push(
                  FoldAwareMaterialPageRoute<void>(
                    sourceContext: sourceContext,
                    builder: (_) => ZiweiChartScreen(
                      initialSolar: DateTime(2000, 8, 16, 10),
                    ),
                  ),
                ),
                child: const Text('从下屏打开紫微排盘'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('从下屏打开紫微排盘'));
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pumpAndSettle();

    final page = tester.getRect(find.byType(Scaffold).last);
    expect(page.top, greaterThanOrEqualTo(392));
    expect(page.bottom, lessThanOrEqualTo(760));

    final plate = find.byKey(const ValueKey('ziwei-chart-plate-width'));
    await tester.scrollUntilVisible(
      plate,
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    // The chart plate is taller than the lower panel in tabletop posture;
    // it must remain scrollable inside that panel rather than be clipped by
    // the physical hinge or forced to shrink its chart cells.
    expect(tester.getRect(plate).top, greaterThanOrEqualTo(392));
    final viewport = tester.getRect(find.byType(Scrollable).first);
    expect(viewport.top, greaterThanOrEqualTo(392));
    expect(viewport.bottom, lessThanOrEqualTo(760));

    final palaceCell = find.descendant(
      of: plate,
      matching: find.byType(GestureDetector),
    ).first;
    await tester.tap(palaceCell);
    await tester.pumpAndSettle();

    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    final sheetRect = tester.getRect(sheet);
    expect(sheetRect.top, greaterThanOrEqualTo(392));
    expect(sheetRect.bottom, lessThanOrEqualTo(760));

    final sheetScrollView = find.descendant(
      of: sheet,
      matching: find.byType(Scrollable),
    ).first;
    await tester.scrollUntilVisible(
      find.text('宫位主管出自倪师《天纪·天机道》· 民俗文化参考'),
      80,
      scrollable: sheetScrollView,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

}
