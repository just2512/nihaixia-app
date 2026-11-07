import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/ziwei_chart_screen.dart';
import 'package:nihaisha_app/theme/app_colors.dart';

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

}
