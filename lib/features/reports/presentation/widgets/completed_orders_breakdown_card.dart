import 'package:flutter/material.dart';

import '../../domain/entities/report_overview.dart';

class CompletedOrdersBreakdownCard extends StatelessWidget {
  final ReportOrdersSummary ordersSummary;

  const CompletedOrdersBreakdownCard({super.key, required this.ordersSummary});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_outlined,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cấu thành doanh số đơn hoàn tất',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildRow(
              context,
              'Tiền hàng (Subtotal)',
              ordersSummary.completedSubtotalAmount.formatted,
            ),
            const Divider(height: 16),
            _buildRow(
              context,
              'Tổng giảm giá (Discount)',
              '-${ordersSummary.completedDiscountAmount.formatted}',
              valueColor: Colors.red.shade700,
            ),
            const Divider(height: 16),
            _buildRow(
              context,
              'Tổng thuế (Tax)',
              '+${ordersSummary.completedTaxAmount.formatted}',
            ),
            const Divider(height: 16),
            _buildRow(
              context,
              'Phí dịch vụ (Service Charge)',
              '+${ordersSummary.completedServiceChargeAmount.formatted}',
            ),
            const Divider(height: 24, thickness: 1.5),
            _buildRow(
              context,
              'Doanh số đơn hoàn tất',
              ordersSummary.completedOrderSalesAmount.formatted,
              isBold: true,
              valueColor: const Color(0xFFEA580C),
            ),
            const SizedBox(height: 8),
            _buildRow(
              context,
              'Giá trị trung bình / đơn hoàn tất',
              ordersSummary.averageCompletedOrderValue.formatted,
              subtitle:
                  'Backend tính từ tổng doanh số / ${ordersSummary.completedOrderCount} đơn',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
    String? subtitle,
  }) {
    final theme = Theme.of(context);

    final labelContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: isBold
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ],
    );
    final valueContent = Text(
      value,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
        color:
            valueColor ??
            (isBold
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 480 * textScale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [labelContent, const SizedBox(height: 6), valueContent],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: labelContent),
            const SizedBox(width: 16),
            Flexible(child: valueContent),
          ],
        );
      },
    );
  }
}
