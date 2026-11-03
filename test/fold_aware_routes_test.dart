import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/utils/fold_aware_routes.dart';

Widget _foldableApp() {
  return MaterialApp(
    home: Scaffold(
      body: Row(
        children: [
          const SizedBox(width: 412),
          SizedBox(
            width: 388,
            child: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const ValueKey('open-dialog'),
                  onPressed: () {
                    showFoldAwareDialog<void>(
                      context: context,
                      builder: (_) => const AlertDialog(
                        title: Text('右屏弹窗'),
                        content: Text('应留在触发按钮所在的右物理屏'),
                      ),
                    );
                  },
                  child: const Text('打开弹窗'),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('dialog opened from right panel stays on the right side of a hinge', (tester) async {
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
      _foldableApp(),
    );
    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();

    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(dialog.left, greaterThanOrEqualTo(412));
    expect(dialog.right, lessThanOrEqualTo(800));
  });

  testWidgets('dialog uses the full inner display around a zero-width flat fold', (tester) async {
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
      _foldableApp(),
    );
    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();

    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(dialog.left, greaterThanOrEqualTo(0));
    expect(dialog.right, lessThanOrEqualTo(800));
  });


  testWidgets('full-page route stays on the right physical panel of its source control', (tester) async {
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
              Expanded(
                child: Builder(
                  builder: (sourceContext) => Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(sourceContext).push<void>(
                          FoldAwareMaterialPageRoute<void>(
                            sourceContext: sourceContext,
                            builder: (_) => Scaffold(
                              body: SizedBox.expand(
                                key: const ValueKey('fold-aware-route-content'),
                              ),
                            ),
                          ),
                        );
                      },
                      child: const Text('打开右侧页面'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开右侧页面'));
    await tester.pumpAndSettle();

    final page = tester.getRect(find.byKey(const ValueKey('fold-aware-route-content')));
    expect(page.left, greaterThanOrEqualTo(412));
    expect(page.right, 800);
    expect(page.width, 388);
  });

  testWidgets('full-page route uses the full available width when no fold is reported', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 790);
    tester.view.displayFeatures = [];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (sourceContext) => Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(sourceContext).push<void>(
                    FoldAwareMaterialPageRoute<void>(
                      sourceContext: sourceContext,
                      builder: (_) => Scaffold(
                        body: SizedBox.expand(
                          key: const ValueKey('ordinary-route-content'),
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('打开普通页面'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开普通页面'));
    await tester.pumpAndSettle();

    final page = tester.getRect(find.byKey(const ValueKey('ordinary-route-content')));
    expect(page.left, 0);
    expect(page.right, 402);
    expect(page.width, 402);
  });


  testWidgets('full-page route uses the full inner display around a zero-width flat fold', (tester) async {
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
          body: Row(
            children: [
              const SizedBox(width: 412),
              Expanded(
                child: Builder(
                  builder: (sourceContext) => Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(sourceContext).push<void>(
                          FoldAwareMaterialPageRoute<void>(
                            sourceContext: sourceContext,
                            builder: (_) => Scaffold(
                              body: SizedBox.expand(
                                key: const ValueKey('flat-fold-route-content'),
                              ),
                            ),
                          ),
                        );
                      },
                      child: const Text('打开折痕右侧页面'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开折痕右侧页面'));
    await tester.pumpAndSettle();

    final page = tester.getRect(find.byKey(const ValueKey('flat-fold-route-content')));
    expect(page.left, 0);
    expect(page.right, 800);
    expect(page.width, 800);
  });

  testWidgets('unknown fold posture does not split a full-width dialog', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(400, 0, 0, 900),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.unknown,
      ),
    ];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_foldableApp());
    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();

    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(dialog.left, lessThan(400));
    expect(dialog.right, lessThanOrEqualTo(800));
  });

  testWidgets('full-page route stays on the left physical panel when opened there', (tester) async {
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
              SizedBox(
                width: 388,
                child: Builder(
                  builder: (sourceContext) => Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(sourceContext).push<void>(
                          FoldAwareMaterialPageRoute<void>(
                            sourceContext: sourceContext,
                            builder: (_) => Scaffold(
                              body: SizedBox.expand(
                                key: const ValueKey('left-route-content'),
                              ),
                            ),
                          ),
                        );
                      },
                      child: const Text('打开左侧页面'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开左侧页面'));
    await tester.pumpAndSettle();

    final page = tester.getRect(find.byKey(const ValueKey('left-route-content')));
    expect(page.left, 0);
    expect(page.right, 388);
    expect(page.width, 388);
  });

}
