import 'package:flutter/material.dart';

/// Top-level navigation that changes with the app window, not the device model.
///
/// Compact windows keep bottom navigation for one-handed use. Wider windows
/// move navigation to the side so the content can use the additional width.
class AppNavigationDestination {
  const AppNavigationDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final Widget icon;
  final Widget selectedIcon;
  final String label;
}

class AdaptiveHomeNavigation extends StatelessWidget {
  const AdaptiveHomeNavigation({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.screens,
    required this.destinations,
  }) : assert(screens.length == destinations.length),
       assert(screens.length > 0);

  static const double compactBreakpoint = 600;
  static const double expandedBreakpoint = 840;

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> screens;
  final List<AppNavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useNavigationRail = constraints.maxWidth >= compactBreakpoint;
        final useExtendedRail = constraints.maxWidth >= expandedBreakpoint;

        return Scaffold(
          body: Row(
            children: [
              if (useNavigationRail)
                NavigationRail(
                  selectedIndex: currentIndex,
                  onDestinationSelected: onDestinationSelected,
                  labelType: useExtendedRail
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  extended: useExtendedRail,
                  destinations: [
                    for (final destination in destinations)
                      NavigationRailDestination(
                        icon: destination.icon,
                        selectedIcon: destination.selectedIcon,
                        label: Text(destination.label),
                      ),
                  ],
                ),
              Expanded(
                child: IndexedStack(
                  index: currentIndex,
                  children: screens,
                ),
              ),
            ],
          ),
          bottomNavigationBar: useNavigationRail
              ? null
              : NavigationBar(
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  indicatorColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  selectedIndex: currentIndex,
                  onDestinationSelected: onDestinationSelected,
                  destinations: [
                    for (final destination in destinations)
                      NavigationDestination(
                        icon: destination.icon,
                        selectedIcon: destination.selectedIcon,
                        label: destination.label,
                      ),
                  ],
                ),
        );
      },
    );
  }
}
