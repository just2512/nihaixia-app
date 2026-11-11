import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';

/// Responsive master/detail split used by screens that have a meaningful
/// selection preview. Compact windows keep the original single-pane flow.
class AdaptiveMasterDetail extends StatelessWidget {
  const AdaptiveMasterDetail({
    super.key,
    required this.master,
    required this.detail,
    this.minMasterWidth = 248,
    this.maxMasterWidth = 360,
    this.masterWidthFactor = 0.38,
  })  : assert(minMasterWidth > 0),
        assert(maxMasterWidth >= minMasterWidth),
        assert(masterWidthFactor > 0 && masterWidthFactor < 1);

  static const double compactBreakpoint = 600;
  static const double minimumDetailWidth = 300;
  static const double foldedCreaseClearance = 24;

  final Widget master;
  final Widget detail;
  final double minMasterWidth;
  final double maxMasterWidth;
  final double masterWidthFactor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < compactBreakpoint;
        final screenSize = MediaQuery.sizeOf(context);
        final foldingFeature = _findVerticalFoldingFeature(
          MediaQuery.displayFeaturesOf(context),
          screenSize,
        );

        // Coordinate transforms are only needed when a fold feature exists.
        // During a LayoutBuilder callback, an ancestor route/sliver may still
        // be in layout; localToGlobal can assert before that ancestor has size.
        final localOriginX = foldingFeature == null
            ? 0.0
            : _safeLayoutOriginX(context);
        final featureLeft = foldingFeature == null
            ? null
            : foldingFeature.bounds.left - localOriginX;
        final featureRight = foldingFeature == null
            ? null
            : foldingFeature.bounds.right - localOriginX;
        final featureIntersectsLayout = featureLeft != null &&
            featureRight != null &&
            featureRight > 0 &&
            featureLeft < constraints.maxWidth;

        if (foldingFeature != null && featureIntersectsLayout) {
          final hasPhysicalGap = foldingFeature.bounds.width > 0;
          final creaseInset =
              hasPhysicalGap ? 0.0 : foldedCreaseClearance / 2;
          final leftRegionWidth = ((featureLeft) - creaseInset)
              .clamp(0.0, constraints.maxWidth)
              .toDouble();
          final rightRegionStart = ((featureRight) + creaseInset)
              .clamp(0.0, constraints.maxWidth)
              .toDouble();
          final rightRegionWidth =
              (constraints.maxWidth - rightRegionStart)
                  .clamp(0.0, constraints.maxWidth)
                  .toDouble();
          final hingeGapWidth = rightRegionStart - leftRegionWidth;

          if (leftRegionWidth >= minMasterWidth &&
              rightRegionWidth >= minimumDetailWidth) {
            final masterWidth = leftRegionWidth
                .clamp(minMasterWidth, maxMasterWidth)
                .toDouble();

            return Row(
              children: [
                SizedBox(
                  width: leftRegionWidth,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(width: masterWidth, child: master),
                  ),
                ),
                SizedBox(width: hingeGapWidth),
                SizedBox(width: rightRegionWidth, child: detail),
              ],
            );
          }

          // If the two physical panels cannot each host a useful pane, keep
          // the master flow inside the wider panel instead of drawing controls
          // underneath the hinge or across the crease.
          if (leftRegionWidth >= rightRegionWidth) {
            return Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(width: leftRegionWidth, child: master),
            );
          }
          return Align(
            alignment: Alignment.centerRight,
            child: SizedBox(width: rightRegionWidth, child: master),
          );
        }

        if (isCompact) {
          return SizedBox.expand(child: master);
        }

        final preferredWidth = constraints.maxWidth * masterWidthFactor;
        final masterWidth = preferredWidth
            .clamp(minMasterWidth, maxMasterWidth)
            .toDouble();

        return Row(
          children: [
            SizedBox(width: masterWidth, child: master),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: detail,
            ),
          ],
        );
      },
    );
  }

}

DisplayFeature? _findVerticalFoldingFeature(
  List<DisplayFeature> features,
  Size screenSize,
) {
  DisplayFeature? nearestFeature;
  var nearestDistance = double.infinity;

  for (final feature in features) {
    if (feature.type != DisplayFeatureType.hinge &&
        feature.type != DisplayFeatureType.fold) {
      continue;
    }
    // Unknown posture is not enough evidence to isolate a single panel.
    // A flat fold remains useful as a master/detail divider, while
    // AdaptiveSinglePane separately treats it as one continuous canvas.
    if (feature.type == DisplayFeatureType.fold &&
        feature.state == DisplayFeatureState.unknown) {
      continue;
    }

    final bounds = feature.bounds;
    final spansScreenHeight = bounds.height >= screenSize.height - 1;
    final separatesTwoPanels =
        bounds.left > 0 && bounds.right < screenSize.width;
    if (!spansScreenHeight || !separatesTwoPanels) continue;

    final distanceFromCenter =
        (bounds.center.dx - screenSize.width / 2).abs();
    if (distanceFromCenter < nearestDistance) {
      nearestFeature = feature;
      nearestDistance = distanceFromCenter;
    }
  }

  return nearestFeature;
}

/// A single, full-page experience that must remain on one physical panel.
///
/// On ordinary windows the child uses the available width. On a foldable with
/// a vertical or horizontal hinge, the whole child (including its app bar) is
/// placed in the selected physical panel so controls do not cross the fold.
class AdaptiveSinglePane extends StatelessWidget {
  const AdaptiveSinglePane({
    super.key,
    required this.child,
    this.maxWidth = double.infinity,
    this.contentKey,
    this.foldedCreaseClearance = 24,
    this.preferredAnchorPoint,
  })  : assert(maxWidth > 0),
        assert(foldedCreaseClearance >= 0);

  final Widget child;
  final double maxWidth;
  final Key? contentKey;
  final double foldedCreaseClearance;
  final Offset? preferredAnchorPoint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 半折叠时内容只占一个物理面板，另一个面板区域若透明会透出黑色窗口背景；
    // 用 surface 颜色铺满整屏，保证空面板与 app 背景一致。
    return ColoredBox(
      color: scheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
        final screenSize = MediaQuery.sizeOf(context);
        final feature = _findSinglePaneBlockingFeature(
          MediaQuery.displayFeaturesOf(context),
          screenSize,
        );
        final contentWidth = maxWidth < constraints.maxWidth
            ? maxWidth
            : constraints.maxWidth;

        if (feature == null) {
          return Center(
            child: SizedBox(
              width: contentWidth,
              child: ConstrainedBox(
                key: contentKey,
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: child,
              ),
            ),
          );
        }

        final isVertical =
            feature.bounds.height >= screenSize.height - 1;
        if (isVertical) {
          if (preferredAnchorPoint != null) {
            final creaseInset =
                feature.bounds.width > 0 ? 0.0 : foldedCreaseClearance / 2;
            final leftPanelWidth = (feature.bounds.left - creaseInset)
                .clamp(0.0, screenSize.width)
                .toDouble();
            final rightPanelStart = (feature.bounds.right + creaseInset)
                .clamp(0.0, screenSize.width)
                .toDouble();
            final rightPanelWidth = (screenSize.width - rightPanelStart)
                .clamp(0.0, screenSize.width)
                .toDouble();
            final largestPanelWidth = leftPanelWidth > rightPanelWidth
                ? leftPanelWidth
                : rightPanelWidth;

            // A platform route may already be constrained to one sub-screen.
            if (constraints.maxWidth <= largestPanelWidth + 1) {
              return Center(
                child: SizedBox(
                  width: contentWidth,
                  child: ConstrainedBox(
                    key: contentKey,
                    constraints: BoxConstraints(maxWidth: contentWidth),
                    child: child,
                  ),
                ),
              );
            }

            final useLeftPanel =
                preferredAnchorPoint!.dx < feature.bounds.center.dx;
            final panelWidth = useLeftPanel
                ? leftPanelWidth
                : rightPanelWidth;
            final panelMaxWidth =
                maxWidth < panelWidth ? maxWidth : panelWidth;
            return Align(
              alignment:
                  useLeftPanel ? Alignment.centerLeft : Alignment.centerRight,
              child: SizedBox(
                width: panelWidth,
                child: Center(
                  child: ConstrainedBox(
                    key: contentKey,
                    constraints: BoxConstraints(maxWidth: panelMaxWidth),
                    child: child,
                  ),
                ),
              ),
            );
          }

          final localOriginX = _safeLayoutOriginX(context);
          final featureLeft = feature.bounds.left - localOriginX;
          final featureRight = feature.bounds.right - localOriginX;
          final intersects = featureRight > 0 &&
              featureLeft < constraints.maxWidth;
          if (!intersects) {
            return Center(
              child: SizedBox(
                width: contentWidth,
                child: ConstrainedBox(
                  key: contentKey,
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: child,
                ),
              ),
            );
          }

          final creaseInset =
              feature.bounds.width > 0 ? 0.0 : foldedCreaseClearance / 2;
          final leftWidth = (featureLeft - creaseInset)
              .clamp(0.0, constraints.maxWidth)
              .toDouble();
          final rightStart = (featureRight + creaseInset)
              .clamp(0.0, constraints.maxWidth)
              .toDouble();
          final rightWidth = (constraints.maxWidth - rightStart)
              .clamp(0.0, constraints.maxWidth)
              .toDouble();
          final useLeftPanel = leftWidth >= rightWidth;
          final panelWidth = useLeftPanel ? leftWidth : rightWidth;
          final panelMaxWidth =
              maxWidth < panelWidth ? maxWidth : panelWidth;
          return Align(
            alignment:
                useLeftPanel ? Alignment.centerLeft : Alignment.centerRight,
            child: SizedBox(
              width: panelWidth,
              child: Center(
                child: ConstrainedBox(
                  key: contentKey,
                  constraints: BoxConstraints(maxWidth: panelMaxWidth),
                  child: child,
                ),
              ),
            ),
          );
        }

        // A landscape foldable may expose a horizontal hinge. Keep the entire
        // page (including its app bar) above or below that physical gap.
        final creaseInset =
            feature.bounds.height > 0 ? 0.0 : foldedCreaseClearance / 2;
        final topPanelHeight = (feature.bounds.top - creaseInset)
            .clamp(0.0, screenSize.height)
            .toDouble();
        final bottomPanelStart = (feature.bounds.bottom + creaseInset)
            .clamp(0.0, screenSize.height)
            .toDouble();
        final bottomPanelHeight = (screenSize.height - bottomPanelStart)
            .clamp(0.0, screenSize.height)
            .toDouble();
        final largestPanelHeight = topPanelHeight > bottomPanelHeight
            ? topPanelHeight
            : bottomPanelHeight;

        if (preferredAnchorPoint != null) {
          if (constraints.maxHeight <= largestPanelHeight + 1) {
            return Center(
              child: SizedBox(
                width: contentWidth,
                child: ConstrainedBox(
                  key: contentKey,
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: child,
                ),
              ),
            );
          }
          final useTopPanel =
              preferredAnchorPoint!.dy < feature.bounds.center.dy;
          final panelHeight =
              useTopPanel ? topPanelHeight : bottomPanelHeight;
          return Align(
            alignment:
                useTopPanel ? Alignment.topCenter : Alignment.bottomCenter,
            child: SizedBox(
              width: constraints.maxWidth,
              height: panelHeight,
              child: Center(
                child: ConstrainedBox(
                  key: contentKey,
                  constraints: BoxConstraints(maxWidth: contentWidth),
                  child: child,
                ),
              ),
            ),
          );
        }

        final localOriginY = _safeLayoutOriginY(context);
        final featureTop = feature.bounds.top - localOriginY;
        final featureBottom = feature.bounds.bottom - localOriginY;
        final intersects = featureBottom > 0 &&
            featureTop < constraints.maxHeight;
        if (!intersects) {
          return Center(
            child: SizedBox(
              width: contentWidth,
              child: ConstrainedBox(
                key: contentKey,
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: child,
              ),
            ),
          );
        }

        final localTopHeight = (featureTop - creaseInset)
            .clamp(0.0, constraints.maxHeight)
            .toDouble();
        final localBottomStart = (featureBottom + creaseInset)
            .clamp(0.0, constraints.maxHeight)
            .toDouble();
        final localBottomHeight =
            (constraints.maxHeight - localBottomStart)
                .clamp(0.0, constraints.maxHeight)
                .toDouble();
        final useTopPanel = localTopHeight >= localBottomHeight;
        final panelHeight =
            useTopPanel ? localTopHeight : localBottomHeight;
        return Align(
          alignment:
              useTopPanel ? Alignment.topCenter : Alignment.bottomCenter,
          child: SizedBox(
            width: constraints.maxWidth,
            height: panelHeight,
            child: Center(
              child: ConstrainedBox(
                key: contentKey,
                constraints: BoxConstraints(maxWidth: contentWidth),
                child: child,
              ),
            ),
          ),
        );
        },
      ),
    );
  }
}


DisplayFeature? _findSinglePaneBlockingFeature(
  List<DisplayFeature> features,
  Size screenSize,
) {
  final vertical = _findVerticalFoldingFeature(features, screenSize);
  final horizontal = _findHorizontalFoldingFeature(features, screenSize);
  final candidates = [if (vertical != null) vertical, if (horizontal != null) horizontal];
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final aDistance = a.bounds.height >= screenSize.height - 1
        ? (a.bounds.center.dx - screenSize.width / 2).abs()
        : (a.bounds.center.dy - screenSize.height / 2).abs();
    final bDistance = b.bounds.height >= screenSize.height - 1
        ? (b.bounds.center.dx - screenSize.width / 2).abs()
        : (b.bounds.center.dy - screenSize.height / 2).abs();
    return aDistance.compareTo(bDistance);
  });
  final feature = candidates.first;
  // A flat/unknown zero-gap crease is one continuous display. Only a physical
  // gap or an explicitly half-open posture separates single-pane routes.
  final isVertical =
      feature.bounds.height >= screenSize.height - 1;
  final hasPhysicalGap = isVertical
      ? feature.bounds.width > 0
      : feature.bounds.height > 0;
  if (!hasPhysicalGap &&
      feature.state != DisplayFeatureState.postureHalfOpened) {
    return null;
  }
  return feature;
}


DisplayFeature? _findHorizontalFoldingFeature(
  List<DisplayFeature> features,
  Size screenSize,
) {
  DisplayFeature? nearestFeature;
  var nearestDistance = double.infinity;
  for (final feature in features) {
    if (feature.type != DisplayFeatureType.hinge &&
        feature.type != DisplayFeatureType.fold) {
      continue;
    }
    if (feature.type == DisplayFeatureType.fold &&
        feature.state == DisplayFeatureState.unknown) {
      continue;
    }
    final bounds = feature.bounds;
    final spansScreenWidth = bounds.width >= screenSize.width - 1;
    final separatesTwoPanels =
        bounds.top > 0 && bounds.bottom < screenSize.height;
    if (!spansScreenWidth || !separatesTwoPanels) continue;
    final distanceFromCenter =
        (bounds.center.dy - screenSize.height / 2).abs();
    if (distanceFromCenter < nearestDistance) {
      nearestFeature = feature;
      nearestDistance = distanceFromCenter;
    }
  }
  return nearestFeature;
}


double _safeLayoutOriginX(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) return 0.0;
  try {
    return renderObject.localToGlobal(Offset.zero).dx;
  } on FlutterError {
    return 0.0;
  } on AssertionError {
    return 0.0;
  }
}

double _safeLayoutOriginY(BuildContext context) {
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) return 0.0;
  try {
    return renderObject.localToGlobal(Offset.zero).dy;
  } on FlutterError {
    return 0.0;
  } on AssertionError {
    return 0.0;
  }
}
