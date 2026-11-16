import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/screens/meihua_screen.dart';
import 'package:nihaisha_app/data/database_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/utils/fold_aware_routes.dart';
import 'package:sensors_plus/sensors_plus.dart' show AccelerometerEvent;

final _testTheme = ThemeData(
  colorScheme: AppColors.colorSchemeFor(Brightness.light),
  useMaterial3: true,
  extensions: [AppColors.light],
);

Stream<AccelerometerEvent> _emptyAccelerometerStream({
  Duration samplingPeriod = const Duration(milliseconds: 20),
}) => const Stream<AccelerometerEvent>.empty();

Widget _pageForTool(AssistantToolDefinition tool) {
  // Widget tests have no physical accelerometer. Keep the production page and
  // its default computed chart, but inject an empty sensor stream.
  if (tool.id == 'meihua') {
    return MeihuaScreen(
      returnResultOnComplete: true,
      accelSource: _emptyAccelerometerStream,
    );
  }
  return tool.builder();
}

Future<void> _pumpUntilRouteAnimationStatus({
  required WidgetTester tester,
  required ModalRoute<dynamic> route,
  required AnimationStatus expected,
  required String reason,
}) async {
  // saved_charts shows an indeterminate loading animation, so pumpAndSettle
  // cannot be used. Wait for the actual route transition instead of guessing
  // that a fixed frame interval has completed it.
  for (var frame = 0; frame < 40; frame++) {
    if (route.animation?.status == expected) {
      await tester.pump();
      return;
    }
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(route.animation?.status, expected, reason: reason);
}

Future<void> _openToolAndCheck({
  required WidgetTester tester,
  required AssistantToolDefinition tool,
  required Size windowSize,
  required List<DisplayFeature> displayFeatures,
  required double expectedLeft,
}) async {
  tester.view.physicalSize = windowSize;
  tester.view.displayFeatures = displayFeatures;

  final routeKey = ValueKey('tool-route-${tool.id}');
  final openKey = ValueKey('open-tool-${tool.id}');
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
                    key: openKey,
                    onPressed: () {
                      Navigator.of(sourceContext).push<void>(
                        FoldAwareMaterialPageRoute<void>(
                          sourceContext: sourceContext,
                          builder: (_) => KeyedSubtree(
                            key: routeKey,
                            child: _pageForTool(tool),
                          ),
                        ),
                      );
                    },
                    child: Text('打开 ${tool.id}'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  await tester.tap(find.byKey(openKey));
  final route = find.byKey(routeKey);
  if (tool.id == 'saved_charts') {
    // SavedChartsScreen performs an async SQLite read while showing an
    // indeterminate progress indicator. Wait for the route animation's
    // terminal state, then allow the first data frame; do not settle the
    // perpetual loading animation.
    await tester.pump();
    expect(route, findsOneWidget, reason: tool.id);
    final modalRoute = ModalRoute.of(tester.element(route));
    expect(modalRoute, isNotNull, reason: tool.id);
    await _pumpUntilRouteAnimationStatus(
      tester: tester,
      route: modalRoute!,
      expected: AnimationStatus.completed,
      reason: '${tool.id} 页面进入动画未完成',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }

  expect(route, findsOneWidget, reason: tool.id);
  final bounds = tester.getRect(route);
  expect(bounds.left, greaterThanOrEqualTo(expectedLeft), reason: tool.id);
  expect(bounds.right, lessThanOrEqualTo(windowSize.width), reason: tool.id);
  expect(
    tester.takeException(),
    isNull,
    reason: '${tool.id} 在当前屏幕姿态下存在布局异常',
  );

  // Return to the launcher before testing the second physical posture.
  final routeObject = ModalRoute.of(tester.element(route))!;
  Navigator.of(tester.element(route)).pop();
  if (tool.id == 'saved_charts') {
    await _pumpUntilRouteAnimationStatus(
      tester: tester,
      route: routeObject,
      expected: AnimationStatus.dismissed,
      reason: '${tool.id} 页面退出动画未完成',
    );
  } else {
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() {
    DatabaseHelper.configureTestDatabase(
      'tool_foldable_layout_test.db',
      factory: databaseFactoryFfi,
    );
  });
  tearDown(() async {
    await DatabaseHelper.closeTestDatabase();
  });

  final tools = AssistantToolRouter.all
      .where((tool) => tool.headlessExecutor != null)
      .toList(growable: false);

  for (final tool in tools) {
    testWidgets(
      '${tool.id} 计算工具在展开内屏和半折叠单屏内保持可布局',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDisplayFeatures);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Fully unfolded Find N2 inner display: a flat, zero-width crease is
        // one continuous canvas; page content may use the full 775dp width.
        await _openToolAndCheck(
          tester: tester,
          tool: tool,
          windowSize: const Size(775, 830),
          displayFeatures: [
            DisplayFeature(
              bounds: const Rect.fromLTWH(387.5, 0, 0, 830),
              type: DisplayFeatureType.fold,
              state: DisplayFeatureState.postureFlat,
            ),
          ],
          expectedLeft: 0,
        );

        // Half-open posture: an actual hinge separates two physical panels.
        // A tool opened from the right-side control must remain on that panel.
        await _openToolAndCheck(
          tester: tester,
          tool: tool,
          windowSize: const Size(800, 1000),
          displayFeatures: [
            DisplayFeature(
              bounds: const Rect.fromLTWH(388, 0, 24, 1000),
              type: DisplayFeatureType.hinge,
              state: DisplayFeatureState.postureHalfOpened,
            ),
          ],
          expectedLeft: 412,
        );
      },
    );
  }
}
