import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/widgets/adaptive_home_navigation.dart';

const _destinations = [
  AppNavigationDestination(
    icon: Icon(Icons.library_books_outlined),
    selectedIcon: Icon(Icons.library_books),
    label: '知识',
  ),
  AppNavigationDestination(
    icon: Icon(Icons.build_outlined),
    selectedIcon: Icon(Icons.build),
    label: '工具',
  ),
  AppNavigationDestination(
    icon: Icon(Icons.fact_check_outlined),
    selectedIcon: Icon(Icons.fact_check),
    label: '问诊',
  ),
  AppNavigationDestination(
    icon: Icon(Icons.bookmark_border),
    selectedIcon: Icon(Icons.bookmark),
    label: '收藏',
  ),
];

List<Widget> _screens() => List.generate(
      _destinations.length,
      (index) => Scaffold(
        body: Center(child: Text('内容页 $index')),
      ),
    );

void main() {
  testWidgets(
    'Find N2 outer and inner window widths switch navigation without losing tab state',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 790);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var selectedIndex = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => AdaptiveHomeNavigation(
              currentIndex: selectedIndex,
              onDestinationSelected: (index) {
                setState(() => selectedIndex = index);
              },
              destinations: _destinations,
              screens: _screens(),
            ),
          ),
        ),
      );

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      await tester.tap(find.text('工具'));
      await tester.pumpAndSettle();
      expect(selectedIndex, 1);
      expect(find.text('内容页 1'), findsOneWidget);

      // Approximate logical window dimensions derived from OPPO's published
      // panel PPI/resolution. Runtime layout always uses actual window width.
      tester.view.physicalSize = const Size(775, 829);
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
        1,
      );
      expect(find.text('内容页 1'), findsOneWidget);
    },
  );

  testWidgets('wide windows use the extended rail', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHomeNavigation(
          currentIndex: 0,
          onDestinationSelected: (_) {},
          destinations: _destinations,
          screens: _screens(),
        ),
      ),
    );

    final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
    expect(rail.extended, isTrue);
  });

  testWidgets('vertical hinge puts the navigation rail and active tab on separate panels', (tester) async {
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
        home: AdaptiveHomeNavigation(
          currentIndex: 1,
          onDestinationSelected: (_) {},
          destinations: _destinations,
          screens: _screens(),
        ),
      ),
    );

    final rail = tester.getRect(find.byType(NavigationRail));
    final content = tester.getRect(find.byType(IndexedStack));
    expect(rail.left, 0);
    expect(rail.right, lessThanOrEqualTo(388));
    expect(content.left, greaterThanOrEqualTo(412));
    expect(content.right, 800);
    expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).extended, isTrue);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('内容页 1'), findsOneWidget);
  });

  testWidgets('zero-width fold keeps root navigation and content off the crease', (tester) async {
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
        home: AdaptiveHomeNavigation(
          currentIndex: 0,
          onDestinationSelected: (_) {},
          destinations: _destinations,
          screens: _screens(),
        ),
      ),
    );

    final rail = tester.getRect(find.byType(NavigationRail));
    final content = tester.getRect(find.byType(IndexedStack));
    expect(rail.right, lessThanOrEqualTo(388));
    expect(content.left, greaterThanOrEqualTo(412));
  });

  testWidgets('narrow physical panels fall back to one safe panel with bottom navigation', (tester) async {
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

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHomeNavigation(
          currentIndex: 2,
          onDestinationSelected: (_) {},
          destinations: _destinations,
          screens: _screens(),
        ),
      ),
    );

    final rootScaffold = tester.getRect(find.byType(AdaptiveHomeNavigation));
    final content = tester.getRect(find.byType(IndexedStack));
    expect(rootScaffold.width, 270);
    expect(content.right, lessThanOrEqualTo(270));
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('内容页 2'), findsOneWidget);
  });
}
