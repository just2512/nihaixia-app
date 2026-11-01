import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/utils/fold_aware_routes.dart';

Widget _foldableApp({
  required DisplayFeature feature,
}) {
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
      _foldableApp(
        feature: const DisplayFeature(
          bounds: Rect.fromLTWH(388, 0, 24, 900),
          type: DisplayFeatureType.hinge,
          state: DisplayFeatureState.postureHalfOpened,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();

    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(dialog.left, greaterThanOrEqualTo(412));
    expect(dialog.right, lessThanOrEqualTo(800));
  });

  testWidgets('dialog reserves a safe right panel around a zero-width flat fold', (tester) async {
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
      _foldableApp(
        feature: const DisplayFeature(
          bounds: Rect.fromLTWH(400, 0, 0, 900),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureFlat,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-dialog')));
    await tester.pumpAndSettle();

    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(dialog.left, greaterThanOrEqualTo(412));
    expect(dialog.right, lessThanOrEqualTo(800));
  });
}
