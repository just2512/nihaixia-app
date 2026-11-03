import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nihaisha_app/widgets/adaptive_home_navigation.dart';

const _destinations = [
  AppNavigationDestination(
    icon: Icon(Icons.fact_check_outlined),
    selectedIcon: Icon(Icons.fact_check),
    label: '问诊',
  ),
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
    icon: Icon(Icons.bookmark_border),
    selectedIcon: Icon(Icons.bookmark),
    label: '收藏',
  ),
  AppNavigationDestination(
    icon: Icon(Icons.settings_outlined),
    selectedIcon: Icon(Icons.settings),
    label: '设置',
  ),
];

List<Widget> _screens() => List.generate(
      _destinations.length,
      (index) => Scaffold(
        body: Center(child: Text('内容页 $index')),
      ),
    );

class _CounterScreen extends StatefulWidget {
  const _CounterScreen();

  @override
  State<_CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<_CounterScreen> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('计数：$_count'),
            ElevatedButton(
              onPressed: () => setState(() => _count++),
              child: const Text('增加'),
            ),
          ],
        ),
      ),
    );
  }
}

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
      expect(selectedIndex, 2);
      expect(find.text('内容页 2'), findsOneWidget);

      // Approximate logical window dimensions derived from OPPO's published
      // panel PPI/resolution. Runtime layout always uses actual window width.
      tester.view.physicalSize = const Size(775, 829);
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex,
        2,
      );
      expect(find.text('内容页 2'), findsOneWidget);
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

  testWidgets('vertical hinge keeps the selected tab across the full unfolded window', (tester) async {
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

    final navigation = tester.getRect(find.byType(NavigationRail));
    final content = tester.getRect(find.byType(IndexedStack));
    final contentMedia = tester.widget<MediaQuery>(
      find.byKey(const ValueKey('full-window-content-media-query')),
    );
    expect(navigation.left, 0);
    expect(navigation.width, lessThan(100));
    expect(content.left, navigation.right);
    expect(content.right, 800);
    expect(content.width, greaterThan(700));
    expect(contentMedia.data.displayFeatures, isEmpty);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('内容页 1'), findsOneWidget);
  });

  testWidgets('flat unfolded inner display uses the full width instead of splitting at the crease', (tester) async {
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
    expect(rail.left, 0);
    expect(content.left, rail.right);
    expect(content.right, 800);
    expect(content.width, greaterThan(700));
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('half-open zero-width fold does not constrain tab content to one panel', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(400, 0, 0, 900),
        type: DisplayFeatureType.fold,
        state: DisplayFeatureState.postureHalfOpened,
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
    expect(content.left, rail.right);
    expect(content.right, 800);
    expect(content.width, greaterThan(700));
    expect(
      tester.widget<MediaQuery>(
        find.byKey(const ValueKey('full-window-content-media-query')),
      ).data.displayFeatures,
      isEmpty,
    );
  });

  testWidgets('narrow half-open windows still use all available width', (tester) async {
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

    final rail = tester.getRect(find.byType(NavigationRail));
    final content = tester.getRect(find.byType(IndexedStack));
    expect(content.left, rail.right);
    expect(content.right, 560);
    expect(content.width, greaterThan(450));
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('内容页 2'), findsOneWidget);
  });

  testWidgets('unknown fold posture keeps the unfolded inner display available', (tester) async {
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
    expect(rail.left, 0);
    expect(content.left, rail.right);
    expect(content.right, 800);
    expect(content.width, greaterThan(700));
    expect(find.text('内容页 0'), findsOneWidget);
  });

  testWidgets('preserves a tab state across outer-inner-outer layout changes', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(402, 790);
    tester.view.displayFeatures = [];
    addTearDown(tester.view.resetDisplayFeatures);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveHomeNavigation(
          currentIndex: 0,
          onDestinationSelected: (_) {},
          destinations: _destinations,
          screens: [
            const _CounterScreen(),
            ..._screens().skip(1),
          ],
        ),
      ),
    );

    await tester.tap(find.text('增加'));
    await tester.pumpAndSettle();
    expect(find.text('计数：1'), findsOneWidget);

    tester.view.physicalSize = const Size(800, 900);
    tester.view.displayFeatures = [
      DisplayFeature(
        bounds: const Rect.fromLTWH(388, 0, 24, 900),
        type: DisplayFeatureType.hinge,
        state: DisplayFeatureState.postureHalfOpened,
      ),
    ];
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fold-navigation-panel')), findsOneWidget);
    expect(find.text('计数：1'), findsOneWidget);

    tester.view.physicalSize = const Size(402, 790);
    tester.view.displayFeatures = [];
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('计数：1'), findsOneWidget);
  });
}
