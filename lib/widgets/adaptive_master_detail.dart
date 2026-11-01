import 'dart:ui' show DisplayFeature, DisplayFeatureType;

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
/// a vertical hinge/crease, the whole child (including its app bar) is placed
/// in the wider physical panel so controls do not cross the fold.
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
    return LayoutBuilder(
      builder: (context, constraints) {
        if (preferredAnchorPoint != null) {
          final screenSize = MediaQuery.sizeOf(context);
          final feature = _findVerticalFoldingFeature(
            MediaQuery.displayFeaturesOf(context),
            screenSize,
          );
          if (feature == null) {
            return Center(
              child: ConstrainedBox(
                key: contentKey,
                constraints: BoxConstraints(
                  maxWidth: maxWidth < constraints.maxWidth
                      ? maxWidth
                      : constraints.maxWidth,
                ),
                child: child,
              ),
            );
          }

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

          // A physical hinge may already have caused DialogRoute to constrain
          // this route to one sub-screen. A zero-width fold may not produce a
          // separate route constraint, so split the full-width route here.
          if (constraints.maxWidth <= largestPanelWidth + 1) {
            return Center(
              child: ConstrainedBox(
                key: contentKey,
                constraints: BoxConstraints(
                  maxWidth: maxWidth < constraints.maxWidth
                      ? maxWidth
                      : constraints.maxWidth,
                ),
                child: child,
              ),
            );
          }

          final useLeftPanel =
              preferredAnchorPoint!.dx < feature.bounds.center.dx;
          final panelWidth = useLeftPanel
              ? leftPanelWidth
              : rightPanelWidth;
          final panelMaxWidth = maxWidth < panelWidth ? maxWidth : panelWidth;
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

        final feature = _findVerticalFoldingFeature(
          MediaQuery.displayFeaturesOf(context),
          MediaQuery.sizeOf(context),
        );

        final renderObject = context.findRenderObject();
        final localOriginX = renderObject is RenderBox && renderObject.hasSize
            ? renderObject.localToGlobal(Offset.zero).dx
            : 0.0;
        final featureLeft =
            feature == null ? null : feature.bounds.left - localOriginX;
        final featureRight =
            feature == null ? null : feature.bounds.right - localOriginX;
        final featureIntersectsLayout = featureLeft != null &&
            featureRight != null &&
            featureRight > 0 &&
            featureLeft < constraints.maxWidth;

        if (feature == null || !featureIntersectsLayout) {
          return Center(
            child: ConstrainedBox(
              key: contentKey,
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          );
        }

        final creaseInset =
            feature.bounds.width > 0 ? 0.0 : foldedCreaseClearance / 2;
        final leftWidth = ((featureLeft) - creaseInset)
            .clamp(0.0, constraints.maxWidth)
            .toDouble();
        final rightStart = ((featureRight) + creaseInset)
            .clamp(0.0, constraints.maxWidth)
            .toDouble();
        final rightWidth = (constraints.maxWidth - rightStart)
            .clamp(0.0, constraints.maxWidth)
            .toDouble();
        final anchorPoint = preferredAnchorPoint;
        final useLeftPanel = anchorPoint != null
            ? anchorPoint.dx < feature.bounds.center.dx
            : leftWidth >= rightWidth;
        final availablePanelWidth = useLeftPanel ? leftWidth : rightWidth;
        final contentMaxWidth = maxWidth < availablePanelWidth
            ? maxWidth
            : availablePanelWidth;

        return Align(
          alignment:
              useLeftPanel ? Alignment.centerLeft : Alignment.centerRight,
          child: ConstrainedBox(
            key: contentKey,
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: child,
          ),
        );
      },
    );
  }
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
