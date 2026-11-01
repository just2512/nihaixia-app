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

/// Shows a dialog in the physical panel containing the invoking widget.
///
/// The original window MediaQuery is restored inside the route builder so
/// AdaptiveSinglePane can still reserve a zero-width fold crease. For a
/// physical hinge, DialogRoute first selects the correct sub-screen using the
/// same anchor point.
Future<T?> showFoldAwareDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool fullscreenDialog = false,
  bool? requestFocus,
  AnimationStyle? animationStyle,
}) {
  final originalMediaQuery = MediaQuery.of(context);
  final anchorPoint = foldAwareRouteAnchorPoint(context);

  return showDialog<T>(
    context: context,
    anchorPoint: anchorPoint,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    traversalEdgeBehavior: traversalEdgeBehavior,
    fullscreenDialog: fullscreenDialog,
    requestFocus: requestFocus,
    animationStyle: animationStyle,
    builder: (dialogContext) => MediaQuery(
      data: originalMediaQuery,
      child: AdaptiveSinglePane(
        preferredAnchorPoint: anchorPoint,
        child: builder(dialogContext),
      ),
    ),
  );
}
