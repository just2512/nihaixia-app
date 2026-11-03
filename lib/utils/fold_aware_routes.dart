import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';

import '../widgets/adaptive_master_detail.dart';

/// Returns a window-space anchor point from the widget that opened a route.
///
/// Flutter's default LTR dialog anchor is the top-left corner. On a foldable,
/// that can send a dialog opened from the right-hand app pane to the left
/// navigation pane. Using the invoking render box keeps the route near its
/// source control.
Offset? foldAwareRouteAnchorPoint(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) return null;
  return renderObject.localToGlobal(
    renderObject.size.center(Offset.zero),
  );
}

/// Material page route that keeps its content on the physical panel
/// containing the control that opened it.
///
/// Use this instead of a bare [MaterialPageRoute] for full-page navigation.
/// Dialogs should continue to use [showFoldAwareDialog].
class FoldAwareMaterialPageRoute<T> extends MaterialPageRoute<T> {
  FoldAwareMaterialPageRoute({
    required BuildContext sourceContext,
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool maintainState = true,
    bool fullscreenDialog = false,
    bool allowSnapshotting = true,
  })  : _anchorPoint = foldAwareRouteAnchorPoint(sourceContext),
        super(
          builder: builder,
          settings: settings,
          maintainState: maintainState,
          fullscreenDialog: fullscreenDialog,
          allowSnapshotting: allowSnapshotting,
        );

  final Offset? _anchorPoint;

  @override
  Widget buildContent(BuildContext context) {
    return AdaptiveSinglePane(
      preferredAnchorPoint: _anchorPoint,
      child: super.buildContent(context),
    );
  }
}

/// Shows a dialog in the physical panel containing the invoking widget.
///
/// DialogRoute uses the anchor for physical sub-screen selection. The
/// original window MediaQuery is also retained so AdaptiveSinglePane can
/// manually constrain routes when a zero-width fold is not split by the
/// platform route implementation.
Future<T?> showFoldAwareDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  bool? requestFocus,
  AnimationStyle? animationStyle,
}) {
  final originalMediaQuery = MediaQuery.of(context);
  final anchorPoint = foldAwareRouteAnchorPoint(context);
  final blockingFeature = _hasPhysicalPanelFeature(
    originalMediaQuery.displayFeatures,
    originalMediaQuery.size,
  );

  Widget buildAnchoredDialog(BuildContext dialogContext) {
    final dialog = builder(dialogContext);
    return MediaQuery(
      data: originalMediaQuery,
      child: AdaptiveSinglePane(
        preferredAnchorPoint: anchorPoint,
        child: useSafeArea ? SafeArea(child: dialog) : dialog,
      ),
    );
  }

  // For a physical hinge, use DialogRoute's native anchor-point sub-screen
  // selection. This prevents the dialog's internal Center from painting into
  // the left pane when its source control is on the right. A flat zero-width
  // crease is one continuous display, so retain the full-width raw route.
  if (blockingFeature) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      anchorPoint: anchorPoint,
      requestFocus: requestFocus,
      animationStyle: animationStyle,
      builder: buildAnchoredDialog,
    );
  }

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor ?? Colors.black54,
    barrierLabel: barrierLabel ??
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    requestFocus: requestFocus,
    transitionDuration: animationStyle?.duration ??
        const Duration(milliseconds: 200),
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        buildAnchoredDialog(dialogContext),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}


bool _hasPhysicalPanelFeature(
  List<DisplayFeature> features,
  Size screenSize,
) {
  return features.any((feature) {
    if (feature.type != DisplayFeatureType.hinge &&
        feature.type != DisplayFeatureType.fold) {
      return false;
    }
    if (feature.type == DisplayFeatureType.fold &&
        feature.state != DisplayFeatureState.postureHalfOpened) {
      return false;
    }
    final bounds = feature.bounds;
    return bounds.height >= screenSize.height - 1 &&
        bounds.left > 0 &&
        bounds.right < screenSize.width;
  });
}
