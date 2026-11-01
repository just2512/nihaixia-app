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

  bool _isVerticalSeparator(Widget child) =>
      child is SizedBox && child.height != null && child.width == null;

  Widget _buildCards(BuildContext context, BoxConstraints constraints) {
    final useTwoColumns = constraints.maxWidth >= 600;
    if (!useTwoColumns) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final child in children)
            if (_isVerticalSeparator(child))
              child
            else
              SizedBox(width: constraints.maxWidth, child: child),
        ],
      );
    }

    final cards = children.where((child) => !_isVerticalSeparator(child));
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
          child: LayoutBuilder(
            builder: _buildCards,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
