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
        if (constraints.maxWidth < compactBreakpoint) {
          return SizedBox.expand(child: master);
        }

        final screenSize = MediaQuery.sizeOf(context);
        final foldingFeature = _findVerticalFoldingFeature(
          MediaQuery.displayFeaturesOf(context),
          screenSize,
        );

        if (foldingFeature != null) {
          final hasPhysicalGap = foldingFeature.bounds.width > 0;
          final creaseInset =
              hasPhysicalGap ? 0.0 : foldedCreaseClearance / 2;
          final leftRegionWidth = (foldingFeature.bounds.left - creaseInset)
              .clamp(0.0, constraints.maxWidth)
              .toDouble();
          final rightRegionStart = (foldingFeature.bounds.right + creaseInset)
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
}
