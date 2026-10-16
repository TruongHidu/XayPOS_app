import 'package:flutter/material.dart';

import '../../domain/entities/report_money.dart';

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = color ?? theme.colorScheme.primary;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 140),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: cardColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: cardColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (tooltip != null) ...[
                          const SizedBox(width: 4),
                          Tooltip(
                            message: tooltip!,
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            textStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade900,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.info_outline,
                              size: 16,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                valueText,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              if (secondaryText != null || subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  secondaryText ?? subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
