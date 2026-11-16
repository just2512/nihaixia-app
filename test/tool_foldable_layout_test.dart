import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/screens/assistant_tool_router.dart';
import 'package:nihaisha_app/theme/app_colors.dart';
import 'package:nihaisha_app/utils/fold_aware_routes.dart';

final _testTheme = ThemeData(
  colorScheme: AppColors.colorSchemeFor(Brightness.light),
  useMaterial3: true,
  extensions: [AppColors.light],
);

void main() {
  final tools = AssistantToolRouter.all
      .where((tool) => tool.id != 'structured_diagnosis')
      .toList(growable: false);

  for (final tool in tools) {
    testWidgets(
      '${tool.id} 工具页从右侧物理面板打开时不跨 hinge 且无布局异常',
      (tester) async {
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
                                  child: tool.builder(),
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
        await tester.pumpAndSettle();

        final route = find.byKey(routeKey);
        expect(route, findsOneWidget, reason: tool.id);
        final bounds = tester.getRect(route);
        expect(bounds.left, greaterThanOrEqualTo(412), reason: tool.id);
        expect(bounds.right, lessThanOrEqualTo(800), reason: tool.id);
        expect(
          tester.takeException(),
          isNull,
          reason: '${tool.id} 在单侧物理面板内存在布局异常',
        );
      },
    );
  }
}
