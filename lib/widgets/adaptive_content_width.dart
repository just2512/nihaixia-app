import 'package:flutter/material.dart';

/// Centers long-form content on expanded windows without widening compact
/// foldable panels or changing their available scroll height.
class AdaptiveContentWidth extends StatelessWidget {
  const AdaptiveContentWidth({
    super.key,
    required this.child,
    this.maxWidth = 720,
  }) : assert(maxWidth > 0);

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final contentWidth = availableWidth < maxWidth
            ? availableWidth
            : maxWidth;
        return Center(
          child: SizedBox(
            width: contentWidth,
            child: child,
          ),
        );
      },
    );
  }
}
