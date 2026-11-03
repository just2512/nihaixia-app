import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'adaptive_master_detail.dart';

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

class AdaptiveHomeNavigation extends StatefulWidget {
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
  State<AdaptiveHomeNavigation> createState() => _AdaptiveHomeNavigationState();
}

class _AdaptiveHomeNavigationState extends State<AdaptiveHomeNavigation> {
  // The same keyed screen subtree moves between the compact, expanded and
  // hinge-aware layouts. Reparenting it preserves each tab's State, including
  // scroll positions, filters and in-progress input, when the device unfolds.
  final GlobalKey _screensKey = GlobalKey();

  NavigationRail _buildRail({required bool extended}) {
    return NavigationRail(
      selectedIndex: widget.currentIndex,
      onDestinationSelected: widget.onDestinationSelected,
      labelType:
          extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      extended: extended,
      destinations: [
        for (final destination in widget.destinations)
          NavigationRailDestination(
            icon: destination.icon,
            selectedIcon: destination.selectedIcon,
            label: Text(destination.label),
          ),
      ],
    );
  }

  NavigationBar _buildBottomNavigationBar(BuildContext context) {
    return NavigationBar(
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      backgroundColor: Theme.of(context).colorScheme.surface,
      indicatorColor: Theme.of(context).colorScheme.primaryContainer,
      selectedIndex: widget.currentIndex,
      onDestinationSelected: widget.onDestinationSelected,
      destinations: [
        for (final destination in widget.destinations)
          NavigationDestination(
            icon: destination.icon,
            selectedIcon: destination.selectedIcon,
            label: destination.label,
          ),
      ],
    );
  }

  Widget _buildScreens() => IndexedStack(
        key: _screensKey,
        index: widget.currentIndex,
        children: widget.screens,
      );

  DisplayFeature? _findVerticalFoldingFeature(
    BuildContext context,
    Size screenSize,
  ) {
    DisplayFeature? nearestFeature;
    var nearestDistance = double.infinity;

    for (final feature in MediaQuery.displayFeaturesOf(context)) {
      if (feature.type != DisplayFeatureType.hinge &&
          feature.type != DisplayFeatureType.fold) {
        continue;
      }
      // A flat fold is a continuous unfolded canvas, not two independent
      // panes. Splitting it leaves half of an inner display unused; only a
      // physical hinge or a non-flat fold posture requires pane isolation.
      if (feature.type == DisplayFeatureType.fold &&
          feature.state != DisplayFeatureState.postureHalfOpened) {
        continue;
      }
      final bounds = feature.bounds;
      if (bounds.height < screenSize.height - 1 ||
          bounds.left <= 0 ||
          bounds.right >= screenSize.width) {
        continue;
      }
      final distance = (bounds.center.dx - screenSize.width / 2).abs();
      if (distance < nearestDistance) {
        nearestFeature = feature;
        nearestDistance = distance;
      }
    }
    return nearestFeature;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = MediaQuery.sizeOf(context);
        final feature = _findVerticalFoldingFeature(context, screenSize);

        if (feature != null) {
          // The root tab content uses the complete unfolded window. Splitting
          // the app into two half-width panes made the chat composer and message
          // column too narrow, and nested AdaptiveSinglePane widgets could
          // select a different half and leave the other display black.
          // Keep navigation compact; hide the hinge from the tab subtree so
          // nested pages inherit the full window constraints consistently.
          final fullWindowMedia = MediaQuery.of(context).copyWith(
            displayFeatures: const [],
          );
          return Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildRail(extended: false),
                Expanded(
                  child: MediaQuery(
                    key: const ValueKey('full-window-content-media-query'),
                    data: fullWindowMedia,
                    child: _buildScreens(),
                  ),
                ),
              ],
            ),
          );
        }

        final useNavigationRail =
            constraints.maxWidth >= AdaptiveHomeNavigation.compactBreakpoint;
        final useExtendedRail =
            constraints.maxWidth >= AdaptiveHomeNavigation.expandedBreakpoint;

        return Scaffold(
          body: Row(
            children: [
              if (useNavigationRail) _buildRail(extended: useExtendedRail),
              Expanded(child: _buildScreens()),
            ],
          ),
          bottomNavigationBar: useNavigationRail
              ? null
              : _buildBottomNavigationBar(context),
        );
      },
    );
  }
}
