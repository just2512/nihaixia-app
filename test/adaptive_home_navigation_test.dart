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
}
