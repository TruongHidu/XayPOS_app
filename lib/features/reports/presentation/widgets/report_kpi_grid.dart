import 'package:flutter/material.dart';

import '../../../../core/ui/widgets/responsive_columns.dart';
import 'report_kpi_card.dart';

/// Keeps KPI cards readable as the available width and system text size change.
class ReportKpiGrid extends StatelessWidget {
  const ReportKpiGrid({super.key, required this.children});

  final List<ReportKpiCard> children;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

    return ResponsiveColumns(
      minColumnWidth: 240 * textScale.clamp(1.0, double.infinity),
      maxColumns: 4,
      spacing: 12,
      children: children,
    );
  }
}
