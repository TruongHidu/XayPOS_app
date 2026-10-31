import 'package:flutter/material.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../../reports/domain/entities/report_money.dart';
import '../../domain/entities/cashbook_records.dart';
import 'cashbook_common.dart';
import 'cashbook_format.dart';

/// Income, expense and their difference. The expense breakdown lines are
/// parts of the total, so they are drawn as sub-rows, never as extra cards.
class CashbookSummaryCards extends StatelessWidget {
  const CashbookSummaryCards({
    super.key,
    required this.summary,
    required this.currency,
  });

  final CashbookSummary summary;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final net = summary.netCashFlowAmount;
    return ResponsiveColumns(
      minColumnWidth: 260,
      children: [
        _KpiCard(
          key: const ValueKey('cashbook-kpi-income'),
          icon: Icons.south_west,
          color: CashbookColors.income(colors),
          label: 'Tổng thu',
          value: cashbookMoney(summary.totalIncomeAmount, currency),
          caption: '${summary.incomeEntryCount} giao dịch thu',
          rows: [
            ('Thu bán hàng', cashbookMoney(summary.saleIncomeAmount, currency)),
          ],
        ),
        _KpiCard(
          key: const ValueKey('cashbook-kpi-expense'),
          icon: Icons.north_east,
          color: CashbookColors.expense(colors),
          label: 'Tổng chi',
          value: cashbookMoney(summary.totalExpenseAmount, currency),
          caption: '${summary.expenseEntryCount} phiếu chi hiệu lực',
          rows: [
            (
              'Chi nhập hàng (có phiếu nhập)',
              cashbookMoney(summary.receiptLinkedExpenseAmount, currency),
            ),
            ('Chi khác', cashbookMoney(summary.otherExpenseAmount, currency)),
          ],
        ),
        _KpiCard(
          key: const ValueKey('cashbook-kpi-net'),
          icon: Icons.swap_vert,
          color: net.isNegative ? colors.error : colors.primary,
          label: 'Chênh lệch thu chi',
          value: _signed(net, currency),
          caption: 'Tổng thu trừ tổng chi trong kỳ',
          tooltip:
              'Chỉ là dòng tiền vào trừ dòng tiền ra đã ghi sổ. Không phải lợi nhuận hay số dư quỹ.',
        ),
      ],
    );
  }

  static String _signed(ReportMoney value, String currency) => value.isPositive
      ? '+${cashbookMoney(value, currency)}'
      : cashbookMoney(value, currency);
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.caption,
    this.rows = const [],
    this.tooltip,
  });

  final IconData icon;
  final Color color;
  final String label, value, caption;
  final List<(String, String)> rows;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return CashbookCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(color: muted),
                ),
              ),
              if (tooltip != null)
                Tooltip(
                  message: tooltip!,
                  triggerMode: TooltipTriggerMode.tap,
                  child: Icon(Icons.info_outline, size: 18, color: muted),
                ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
          if (rows.isNotEmpty) ...[
            const Divider(height: 20),
            for (final (name, amount) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      amount,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
