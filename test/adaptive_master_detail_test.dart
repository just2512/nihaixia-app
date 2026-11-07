import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

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

  testWidgets('vertical hinge keeps both panes inside their physical panels', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(388, 0, 24, 900),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testPage());

    final master = tester.getRect(find.byKey(const ValueKey('master-pane')));
    final detail = tester.getRect(find.byKey(const ValueKey('detail-pane')));
    expect(find.byType(VerticalDivider), findsNothing);
    expect(master.left, 0);
    expect(master.right, lessThanOrEqualTo(388));
    expect(detail.left, greaterThanOrEqualTo(412));
    expect(detail.right, 800);
  });


  testWidgets('horizontal hinge keeps anchored single-pane routes within the selected panel', (tester) async {
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
      (const Offset(500, 160), true),
      (const Offset(500, 600), false),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdaptiveSinglePane(
              preferredAnchorPoint: scenario.$1,
              child: SizedBox.expand(
                child: ColoredBox(
                  key: const ValueKey('horizontal-hinge-content'),
                  color: Colors.blue,
                ),
              ),
            ),
          ),
        ),
      );

      final content = tester.getRect(
        find.byKey(const ValueKey('horizontal-hinge-content')),
      );
      if (scenario.$2) {
        expect(content.top, greaterThanOrEqualTo(0));
        expect(content.bottom, lessThanOrEqualTo(368));
      } else {
        expect(content.top, greaterThanOrEqualTo(392));
        expect(content.bottom, lessThanOrEqualTo(760));
      }
      expect(content.width, 1000);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('flat horizontal fold crease remains one continuous canvas', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 760);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(0, 380, 1000, 0),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureFlat,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveSinglePane(
            preferredAnchorPoint: const Offset(500, 600),
            child: SizedBox.expand(
              child: ColoredBox(
                key: const ValueKey('flat-horizontal-fold-content'),
                color: Colors.blue,
              ),
            ),
          ),
        ),
      ),
    );

    final content = tester.getRect(
      find.byKey(const ValueKey('flat-horizontal-fold-content')),
    );
    expect(content.top, 0);
    expect(content.bottom, 760);
    expect(content.width, 1000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('flat unfolded foldable keeps single-pane routes on the full inner display', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(400, 0, 0, 900),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureFlat,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveSinglePane(
            preferredAnchorPoint: const Offset(620, 420),
            child: ColoredBox(
              key: const ValueKey('single-pane-content'),
              color: Colors.blue,
              child: const Text('完整对话窗口'),
            ),
          ),
        ),
      ),
    );

    final content = tester.getRect(find.byKey(const ValueKey('single-pane-content')));
    expect(content.left, 0);
    expect(content.right, 800);
    expect(content.width, 800);
  });


  testWidgets('zero-width flat hinge crease keeps a single-pane route full width', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(400, 0, 0, 900),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureFlat,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdaptiveSinglePane(
            preferredAnchorPoint: const Offset(620, 420),
            child: ColoredBox(
              key: const ValueKey('flat-hinge-single-pane'),
              color: Colors.blue,
              child: const Text('完整对话窗口'),
            ),
          ),
        ),
      ),
    );

    final content = tester.getRect(find.byKey(const ValueKey('flat-hinge-single-pane')));
    expect(content.left, 0);
    expect(content.right, 800);
    expect(content.width, 800);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zero-width fold crease reserves a safe gutter', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(400, 0, 0, 900),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureFlat,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testPage());

    final master = tester.getRect(find.byKey(const ValueKey('master-pane')));
    final detail = tester.getRect(find.byKey(const ValueKey('detail-pane')));
    expect(master.right, lessThanOrEqualTo(388));
    expect(detail.left, greaterThanOrEqualTo(412));
  });

  testWidgets('narrow hinge panels fall back to one pane without crossing hinge', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(560, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(270, 0, 20, 900),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_testPage());

    final master = tester.getRect(find.byKey(const ValueKey('master-pane')));
    expect(find.byKey(const ValueKey('detail-pane')), findsNothing);
    expect(master.left, 0);
    expect(master.right, lessThanOrEqualTo(270));
  });

  testWidgets('master detail nested in right panel ignores hinge outside local bounds', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(388, 0, 24, 900),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(width: 412),
              const SizedBox(
                width: 388,
                child: AdaptiveMasterDetail(
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
            ],
          ),
        ),
      ),
    );

    final master = tester.getRect(find.byKey(const ValueKey('master-pane')));
    expect(master.left, 412);
    expect(master.right, 800);
    expect(find.byKey(const ValueKey('detail-pane')), findsNothing);
  });
}
