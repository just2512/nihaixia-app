import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/widgets/adaptive_master_detail.dart';

Widget _testPage() {
  return const MaterialApp(
    home: Scaffold(
      body: AdaptiveMasterDetail(
        master: ColoredBox(
          key: ValueKey('master-pane'),
          color: Colors.blue,
          child: Text('收藏列表'),
        ),
        detail: ColoredBox(
          key: ValueKey('detail-pane'),
          color: Colors.orange,
          child: Text('收藏预览'),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('compact width keeps the single-pane master flow', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 790);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testPage());

    expect(find.byKey(const ValueKey('master-pane')), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-pane')), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('master-pane'))).width, 402);
  });

  testWidgets('expanded width shows list and detail in separate panes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(695, 830);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testPage());

    final master = tester.getRect(find.byKey(const ValueKey('master-pane')));
    final detail = tester.getRect(find.byKey(const ValueKey('detail-pane')));
    expect(find.byType(VerticalDivider), findsOneWidget);
    expect(master.width, greaterThanOrEqualTo(248));
    expect(detail.width, greaterThan(300));
    expect(detail.left, greaterThan(master.right));
    expect((master.top - detail.top).abs(), lessThan(1));
  });
}
