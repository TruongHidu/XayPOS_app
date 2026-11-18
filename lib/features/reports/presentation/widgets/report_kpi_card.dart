import 'package:flutter/material.dart';

import '../../domain/entities/report_money.dart';
import '../../../../core/ui/widgets/stat_tile.dart';

class ReportKpiCard extends StatelessWidget {
  final String title;
  final String valueText;
  final String? subtitle;
  final String? tooltip;
  final IconData icon;
  final Color? color;
  final String? secondaryText;

  const ReportKpiCard({
    super.key,
    required this.title,
    required this.valueText,
    required this.icon,
    this.subtitle,
    this.tooltip,
    this.color,
    this.secondaryText,
  });

  factory ReportKpiCard.money({
    Key? key,
    required String title,
    required ReportMoney money,
    required IconData icon,
    String? subtitle,
    String? tooltip,
    Color? color,
    String? secondaryText,
  }) {
    return ReportKpiCard(
      key: key,
      title: title,
      valueText: money.formatted,
      subtitle: subtitle,
      tooltip: tooltip,
      icon: icon,
      color: color,
      secondaryText: secondaryText,
    );
  }

  factory ReportKpiCard.count({
    Key? key,
    required String title,
    required int count,
    required IconData icon,
    String? subtitle,
    String? tooltip,
    Color? color,
    String? secondaryText,
    String unit = '',
  }) {
    final text = unit.isNotEmpty ? '$count $unit' : '$count';
    return ReportKpiCard(
      key: key,
      title: title,
      valueText: text,
      subtitle: subtitle,
      tooltip: tooltip,
      icon: icon,
      color: color,
      secondaryText: secondaryText,
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    // The outer gap the tile had as a Card, so grids keep their spacing.
    padding: const EdgeInsets.all(4),
    child: StatTile(
      label: title,
      value: valueText,
      hint: secondaryText ?? subtitle,
      icon: icon,
      color: color ?? Theme.of(context).colorScheme.primary,
      tooltip: tooltip,
      minHeight: 132,
    ),
  );
}
