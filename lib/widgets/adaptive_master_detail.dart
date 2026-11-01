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
          return master;
        }

        final preferredWidth =
            constraints.maxWidth * masterWidthFactor;
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
