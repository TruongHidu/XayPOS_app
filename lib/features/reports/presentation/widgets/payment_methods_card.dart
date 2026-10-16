import 'package:flutter/material.dart';

import '../../domain/entities/payment_method_report_row.dart';
import '../../domain/entities/report_enums.dart';

class PaymentMethodsCard extends StatelessWidget {
  final List<PaymentMethodReportRow> rows;
  final String currencyCode;

  const PaymentMethodsCard({
    super.key,
    required this.rows,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final cashRow = rows
        .where((r) => r.paymentMethod == ReportPaymentMethod.cash)
        .firstOrNull;
    final transferRow = rows
        .where((r) => r.paymentMethod == ReportPaymentMethod.transfer)
        .firstOrNull;

    final cashAmount = cashRow?.collectedAmount.toDouble() ?? 0.0;
    final transferAmount = transferRow?.collectedAmount.toDouble() ?? 0.0;
    final hasCollections = (cashAmount + transferAmount) > 0;

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
                  Icons.pie_chart_outline,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Phương thức thanh toán',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!hasCollections)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 36),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.money_off_outlined,
                      size: 40,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Chưa có phát sinh thu tiền',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              // Ratio Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 16,
                  child: Row(
                    children: [
                      if (cashRow != null && cashRow.percentage > 0)
                        Flexible(
                          flex: (cashRow.percentage * 10).round().clamp(
                            1,
                            1000,
                          ),
                          child: Container(
                            color: const Color(0xFF10B981), // Emerald Green
                          ),
                        ),
                      if (transferRow != null && transferRow.percentage > 0)
                        Flexible(
                          flex: (transferRow.percentage * 10).round().clamp(
                            1,
                            1000,
                          ),
                          child: Container(
                            color: const Color(0xFF6366F1), // Indigo
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Breakdown items
              _buildMethodRow(
                context: context,
                color: const Color(0xFF10B981),
                title: 'Tiền mặt (CASH)',
                row: cashRow,
              ),
              const Divider(height: 20),
              _buildMethodRow(
                context: context,
                color: const Color(0xFF6366F1),
                title: 'Chuyển khoản (TRANSFER)',
                row: transferRow,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMethodRow({
    required BuildContext context,
    required Color color,
    required String title,
    required PaymentMethodReportRow? row,
  }) {
    final theme = Theme.of(context);
    final amountText = row?.collectedAmount.formatted ?? '0 $currencyCode';
    final count = row?.successfulPaymentCount ?? 0;
    final percentage = row?.percentage ?? 0.0;

    final labelContent = Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$count giao dịch thành công',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final amountContent = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          amountText,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${percentage.toStringAsFixed(1)}%',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < 420 * textScale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelContent,
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 22),
                child: amountContent,
              ),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: labelContent),
            const SizedBox(width: 12),
            Flexible(child: amountContent),
          ],
        );
      },
    );
  }
}
