import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/widgets/zone_section.dart';

Widget _sectionContent() {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: SingleChildScrollView(
      child: ZoneSection(
        zone: Zone.general,
        title: '工具分区',
        icon: Icons.widgets_outlined,
        children: [
          Card(
            key: const ValueKey('tool-one'),
            child: const SizedBox(
              height: 88,
              child: Center(child: Text('工具一')),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            key: const ValueKey('tool-two'),
            child: const SizedBox(
              height: 88,
              child: Center(child: Text('工具二')),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _section() {
  return MaterialApp(
    home: Scaffold(
      body: _sectionContent(),
    ),
  );
}

void _setHinge(TestWidgetsFlutterBinding tester, Rect bounds) {
  tester.view.devicePixelRatio = 1;
  tester.view.displayFeatures = [
    DisplayFeature(
      bounds: bounds,
      type: bounds.width == 0
          ? DisplayFeatureType.fold
          : DisplayFeatureType.hinge,
      state: bounds.width == 0
          ? DisplayFeatureState.postureFlat
          : DisplayFeatureState.postureHalfOpened,
    ),
  ];
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

  testWidgets('foldable tool cards stay in separate physical panel columns', (tester) async {
    tester.view.physicalSize = const Size(800, 830);
    _setHinge(tester, const Rect.fromLTWH(388, 0, 24, 830));
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_section());

    final first = tester.getRect(find.byKey(const ValueKey('tool-one')));
    final second = tester.getRect(find.byKey(const ValueKey('tool-two')));
    expect(first.right, lessThanOrEqualTo(388));
    expect(second.left, greaterThanOrEqualTo(412));
    expect((first.top - second.top).abs(), lessThan(1));
    expect(first.width, second.width);
  });

  testWidgets('foldable tool cards keep a gutter at a zero-width crease', (tester) async {
    tester.view.physicalSize = const Size(800, 830);
    _setHinge(tester, const Rect.fromLTWH(400, 0, 0, 830));
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_section());

    final first = tester.getRect(find.byKey(const ValueKey('tool-one')));
    final second = tester.getRect(find.byKey(const ValueKey('tool-two')));
    expect(first.right, lessThanOrEqualTo(388));
    expect(second.left, greaterThanOrEqualTo(412));
  });

  testWidgets('tool cards already inside the right physical panel ignore hinge outside local bounds', (tester) async {
    tester.view.physicalSize = const Size(800, 830);
    _setHinge(tester, const Rect.fromLTWH(388, 0, 24, 830));
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 412),
              SizedBox(width: 388, child: _sectionContent()),
            ],
          ),
        ),
      ),
    );

    final first = tester.getRect(find.byKey(const ValueKey('tool-one')));
    final second = tester.getRect(find.byKey(const ValueKey('tool-two')));
    expect(first.left, greaterThanOrEqualTo(412));
    expect(first.right, lessThanOrEqualTo(800));
    expect(first.width, greaterThan(300));
    expect((first.left - second.left).abs(), lessThan(1));
    expect(second.top, greaterThan(first.bottom));
  });
}
