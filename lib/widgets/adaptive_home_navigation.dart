import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';

import '../data/settings_repository.dart';
import '../theme/app_tokens.dart';
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

  // 内屏展开态下，用户可点击顶部 logo 收起整个左侧菜单栏，让内容区全屏。
  bool _railCollapsed = false;

  /// 顶部 app logo：与右侧页面标题同高，点击收起整个左侧菜单栏。
  Widget _buildLogo() {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '收起菜单栏',
      child: InkWell(
        onTap: () => setState(() => _railCollapsed = true),
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(Icons.spa_outlined, color: scheme.onPrimary, size: 22),
        ),
      ),
    );
  }

  /// 底部深浅模式循环切换按钮（浅色 <-> 深色）。
  Widget _buildThemeToggle() {
    final settings = SettingsRepository.instance;
    final isDark = settings.themeMode == ThemeMode.dark;
    return Tooltip(
      message: isDark ? '切换浅色模式' : '切换深色模式',
      child: IconButton(
        onPressed: () {
          settings.setThemeMode(
            isDark ? ThemeMode.light : ThemeMode.dark,
          );
        },
        icon: Icon(
          isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        ),
      ),
    );
  }

  /// 收起态下的微小展开按钮：贴左侧边框、位于屏高约 1/3 处。
  Widget _buildExpandButton() {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '展开菜单栏',
      child: InkWell(
        onTap: () => setState(() => _railCollapsed = false),
        child: Container(
          width: 18,
          height: 48,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(9),
              bottomRight: Radius.circular(9),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(2, 0),
              ),
            ],
          ),
          child: Icon(
            Icons.chevron_right,
            size: 16,
            color: scheme.onPrimary,
          ),
        ),
      ),
    );
  }

  /// 展开态左侧菜单栏：顶部 logo、中间图标、底部主题按钮，主题按钮沉底。
  Widget _buildRail({required bool extended}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surface,
      child: Column(
        children: [
          Expanded(
            child: NavigationRail(
              leading: Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.md,
                  bottom: AppSpacing.sm,
                ),
                child: _buildLogo(),
              ),
              selectedIndex: widget.currentIndex,
              onDestinationSelected: widget.onDestinationSelected,
              labelType: NavigationRailLabelType.none,
              extended: extended,
              destinations: [
                for (final destination in widget.destinations)
                  NavigationRailDestination(
                    icon: destination.icon,
                    selectedIcon: destination.selectedIcon,
                    label: Text(destination.label),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _buildThemeToggle(),
            ),
          ),
        ],
      ),
    );
  }

  NavigationBar _buildBottomNavigationBar(BuildContext context) {
    return NavigationBar(
      // Compact windows show only the active label; five always-visible labels
      // consume too much vertical space at large system font scales.
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
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
        sizing: StackFit.expand,
        children: widget.screens,
      );

  /// Tab subtree with a clean window MediaQuery. A flat/zero-width fold is a
  /// continuous canvas and must not leak into nested pages, otherwise the tool
  /// card grid (and other single-pane children) re-split the content and leave
  /// a half-empty panel. This mirrors the physical-hinge branch below.
  Widget _buildFullWindowScreens() {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(displayFeatures: const []),
      child: _buildScreens(),
    );
  }

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

  DisplayFeature? _findHorizontalBlockingFeature(
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
      final bounds = feature.bounds;
      if (bounds.width < screenSize.width - 1 ||
          bounds.top <= 0 ||
          bounds.bottom >= screenSize.height) {
        continue;
      }
      // A physical gap blocks content in every posture. A zero-width crease
      // splits the root only when the device reports a half-open posture.
      final hasPhysicalGap = bounds.height > 0;
      if (!hasPhysicalGap &&
          feature.state != DisplayFeatureState.postureHalfOpened) {
        continue;
      }
      final distance = (bounds.center.dy - screenSize.height / 2).abs();
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
        final horizontalFeature =
            _findHorizontalBlockingFeature(context, screenSize);

        if ((feature != null &&
                feature.state == DisplayFeatureState.postureHalfOpened) ||
            horizontalFeature != null) {
          // In tabletop/book posture, including a landscape horizontal hinge,
          // keep navigation and the active tab together on one safe panel.
          return AdaptiveSinglePane(
            child: Scaffold(
              body: _buildScreens(),
              bottomNavigationBar: _buildBottomNavigationBar(context),
            ),
          );
        }

        // 收起态：菜单栏彻底消失，内容全屏；仅左边缘 1/3 处留微小展开按钮。
        if (_railCollapsed) {
          return Stack(
            children: [
              Positioned.fill(child: _buildFullWindowScreens()),
              Positioned(
                left: 0,
                top: screenSize.height * 0.33,
                child: _buildExpandButton(),
              ),
            ],
          );
        }

        if (feature != null) {
          // Physical hinge: keep navigation compact and hide the hinge from
          // the tab subtree so nested pages inherit the full window width.
          return Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildRail(extended: false),
                Expanded(child: _buildFullWindowScreens()),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (useNavigationRail) _buildRail(extended: useExtendedRail),
              Expanded(child: _buildFullWindowScreens()),
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