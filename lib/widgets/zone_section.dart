import 'dart:ui' show DisplayFeature, DisplayFeatureType;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 工具页分区枚举：通用 / 中医 / 玄学。
enum Zone { general, tcm, metaphysics }

/// 工具页（ToolsScreen）中一组功能卡片的可视化分区容器。
///
/// 每个分区带一个彩色标题（图标 + 文案）与一层轻微着色背景，
/// 使「通用区 / 中医区 / 玄学区」在视觉上彼此独立、层次清晰。
/// 在紧凑窗口使用单列；可用宽度足够时将同一分区卡片排成两列。
class ZoneSection extends StatelessWidget {
  final Zone zone;
  final String title;
  final IconData icon;
  final List<Widget> children;

  const ZoneSection({
    super.key,
    required this.zone,
    required this.title,
    required this.icon,
    required this.children,
  });

  /// 根据分区类型返回对应的主题色。
  Color _color(BuildContext context) {
    switch (zone) {
      case Zone.general:
        return Theme.of(context).colorScheme.primary;
      case Zone.tcm:
        return context.colors.tcmZone;
      case Zone.metaphysics:
        return context.colors.metaphysicsZone;
    }
  }


  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          padding: const EdgeInsets.all(8),
          child: _FoldAwareZoneCards(children: children),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}


/// Builds tool cards after the layout tree has completed its first frame so
/// the fold's window-space bounds can be converted to this nested viewport.
class _FoldAwareZoneCards extends StatefulWidget {
  const _FoldAwareZoneCards({required this.children});

  final List<Widget> children;

  @override
  State<_FoldAwareZoneCards> createState() => _FoldAwareZoneCardsState();
}

class _FoldAwareZoneCardsState extends State<_FoldAwareZoneCards> {
  final GlobalKey _layoutKey = GlobalKey();
  double _localOriginX = 0.0;
  bool _originMeasurementQueued = false;

  bool _isVerticalSeparator(Widget child) =>
      child is SizedBox && child.height != null && child.width == null;

  DisplayFeature? _findVerticalFoldingFeature(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    DisplayFeature? nearestFeature;
    var nearestDistance = double.infinity;

    for (final feature in MediaQuery.displayFeaturesOf(context)) {
      if (feature.type != DisplayFeatureType.hinge &&
          feature.type != DisplayFeatureType.fold) {
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

  void _scheduleOriginMeasurement() {
    if (_originMeasurementQueued) return;
    _originMeasurementQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _originMeasurementQueued = false;
      if (!mounted) return;
      final renderObject = _layoutKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) return;
      try {
        final measuredOriginX = renderObject.localToGlobal(Offset.zero).dx;
        if (!measuredOriginX.isFinite ||
            (measuredOriginX - _localOriginX).abs() < 0.5) {
          return;
        }
        setState(() => _localOriginX = measuredOriginX);
      } on FlutterError {
        // Keep the first-frame fallback; a later layout can retry measurement.
      } on AssertionError {
        // An ancestor can still be in a transient layout phase.
      }
    });
  }

  Widget _buildCardColumn(List<Widget> cards, double width) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < cards.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == cards.length - 1 ? 0 : 12,
              ),
              child: SizedBox(width: width, child: cards[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildCards(BuildContext context, BoxConstraints constraints) {
    final cards = widget.children
        .where((child) => !_isVerticalSeparator(child))
        .toList(growable: false);
    final feature = _findVerticalFoldingFeature(context);

    if (feature != null) {
      _scheduleOriginMeasurement();
    }
    final featureLeft =
        feature == null ? null : feature.bounds.left - _localOriginX;
    final featureRight =
        feature == null ? null : feature.bounds.right - _localOriginX;
    final featureIntersectsLayout = featureLeft != null &&
        featureRight != null &&
        featureRight > 0 &&
        featureLeft < constraints.maxWidth;

    if (feature != null && featureIntersectsLayout) {
      final creaseInset = feature.bounds.width > 0 ? 0.0 : 12.0;
      final leftWidth = (featureLeft - creaseInset)
          .clamp(0.0, constraints.maxWidth)
          .toDouble();
      final rightStart = (featureRight + creaseInset)
          .clamp(0.0, constraints.maxWidth)
          .toDouble();
      final rightWidth = (constraints.maxWidth - rightStart)
          .clamp(0.0, constraints.maxWidth)
          .toDouble();
      final hingeGapWidth = rightStart - leftWidth;

      if (leftWidth >= 240 && rightWidth >= 240) {
        final leftCards = <Widget>[];
        final rightCards = <Widget>[];
        for (var index = 0; index < cards.length; index++) {
          (index.isEven ? leftCards : rightCards).add(cards[index]);
        }
        return Row(
          children: [
            _buildCardColumn(leftCards, leftWidth),
            SizedBox(width: hingeGapWidth),
            _buildCardColumn(rightCards, rightWidth),
          ],
        );
      }

      final useLeftPanel = leftWidth >= rightWidth;
      final panelWidth = useLeftPanel ? leftWidth : rightWidth;
      return Align(
        alignment:
            useLeftPanel ? Alignment.centerLeft : Alignment.centerRight,
        child: _buildCardColumn(cards, panelWidth),
      );
    }

    final useTwoColumns = constraints.maxWidth >= 600;
    if (!useTwoColumns) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in widget.children)
            if (_isVerticalSeparator(child))
              child
            else
              SizedBox(width: constraints.maxWidth, child: child),
        ],
      );
    }

    final cardWidth = (constraints.maxWidth - 12) / 2;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final card in cards)
          SizedBox(width: cardWidth, child: card),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: _layoutKey,
      builder: _buildCards,
    );
  }
}
