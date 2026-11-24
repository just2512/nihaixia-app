import 'package:flutter/material.dart';

import '../theme/yanji_status_semantics.dart';

/// A compact, accessible status label that consumes an existing semantic
/// foreground/background pair. It never defines or derives colors itself.
class YanjiStatusBadge extends StatelessWidget {
  const YanjiStatusBadge({
    super.key,
    required this.label,
    required this.colors,
    this.fontSize = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  final String label;
  final YanjiStatusChipColors colors;
  final double fontSize;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '状态：$label',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: borderRadius,
          ),
          child: Padding(
            padding: padding,
            child: Text(
              label,
              softWrap: true,
              style: TextStyle(
                color: colors.foreground,
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
