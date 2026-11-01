import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/widgets/zone_section.dart';

Widget _section() {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ZoneSection(
          zone: Zone.general,
          title: '工具分区',
          icon: Icons.widgets_outlined,
          children: [
            Card(
              key: const ValueKey('tool-one'),
              child: const SizedBox(height: 88, child: Center(child: Text('工具一'))),
            ),
            const SizedBox(height: 12),
            Card(
              key: const ValueKey('tool-two'),
              child: const SizedBox(height: 88, child: Center(child: Text('工具二'))),
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('compact windows keep tool cards in one full-width column', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 790);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_section());

    final first = tester.getRect(find.byKey(const ValueKey('tool-one')));
    final second = tester.getRect(find.byKey(const ValueKey('tool-two')));
    expect(first.width, greaterThan(350));
    expect((first.left - second.left).abs(), lessThan(1));
    expect(second.top, greaterThan(first.bottom));
  });

  testWidgets('expanded windows arrange tool cards in two columns', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(700, 830);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_section());

    final first = tester.getRect(find.byKey(const ValueKey('tool-one')));
    final second = tester.getRect(find.byKey(const ValueKey('tool-two')));
    expect(first.width, greaterThan(250));
    expect(second.width, first.width);
    expect(second.left, greaterThan(first.right));
    expect((first.top - second.top).abs(), lessThan(1));
  });
}
