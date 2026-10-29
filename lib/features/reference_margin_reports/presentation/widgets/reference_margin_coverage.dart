import 'package:flutter/material.dart';
import '../../domain/entities/reference_margin_enums.dart';
import '../../domain/entities/reference_margin_report.dart';
import 'reference_margin_common.dart';
import 'reference_margin_format.dart';

/// States the scope of every covered figure before the figures themselves.
class MarginCoverageCard extends StatelessWidget {
  const MarginCoverageCard({
    super.key,
    required this.value,
    required this.onExcluded,
  });
  final ReferenceMarginSummary value;
  final VoidCallback onExcluded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = value.costCoverageStatus;
    final style = marginCoverageStyle(theme.colorScheme, status);
    final completed = value.completedOrderCount;
    final progress = completed == 0
        ? 0.0
        : (value.fullyCostedOrderCount / completed).clamp(0.0, 1.0);
    final textStyle = TextStyle(color: style.foreground);
    return MarginSectionCard(
      color: style.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(style.icon, color: style.foreground, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mức độ đủ giá vốn',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: style.foreground,
                      ),
                    ),
                    Text(
                      status.label,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: style.foreground,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: style.foreground,
              backgroundColor: style.foreground.withValues(alpha: 0.15),
              semanticsLabel: 'Tỷ lệ đơn đủ giá vốn',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tỷ lệ đơn đủ giá vốn: ${marginPercent(value.orderCoveragePercent)}',
            style: textStyle.copyWith(fontWeight: FontWeight.w600),
          ),
          Text(
            'Đủ giá vốn: ${value.fullyCostedOrderCount} · Bị loại: ${value.excludedOrderCount}',
            style: textStyle,
          ),
          if (status == CostCoverageStatus.partial ||
              status == CostCoverageStatus.unavailable) ...[
            const SizedBox(height: 8),
            Text(
              'Đơn thiếu giá vốn vẫn thuộc tổng toàn bộ đơn, nhưng không được tính vào lãi tham chiếu.',
              style: textStyle,
            ),
          ],
          if (status == CostCoverageStatus.noData) ...[
            const SizedBox(height: 8),
            Text(
              'Chưa có đơn hoàn tất trong bộ lọc này. Các tổng bằng 0 và tỷ lệ không áp dụng.',
              style: textStyle,
            ),
          ],
          if (value.costIssues.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final issue in value.costIssues)
                  Tooltip(
                    message: issue.code,
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: theme.colorScheme.surface,
                      side: BorderSide.none,
                      label: Text(
                        '${issue.label} · ${issue.orderCount} đơn · ${issue.itemCount} dòng',
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (value.costIssues.length > 1) ...[
            const SizedBox(height: 6),
            Text(
              'Một đơn có thể có nhiều nguyên nhân; không cộng số đơn ở các nguyên nhân với nhau.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: style.foreground,
              ),
            ),
          ],
          if (value.excludedOrderCount > 0) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                key: const ValueKey('margin-view-excluded'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  backgroundColor: theme.colorScheme.surface,
                  foregroundColor: theme.colorScheme.onSurface,
                ),
                onPressed: onExcluded,
                icon: const Icon(Icons.search),
                label: const Text('Xem đơn thiếu giá vốn'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
