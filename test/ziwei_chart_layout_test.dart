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
}
