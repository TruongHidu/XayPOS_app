import 'package:flutter/material.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../../domain/entities/cashbook_records.dart';
import 'cashbook_common.dart';
import 'cashbook_format.dart';

/// A receipt's value with its unit; an UNKNOWN currency gets no unit at all.
String receiptMoney(CashbookStockReceipt receipt) => receipt.currencyUnknown
    ? receipt.totalCost.format(includeCurrency: false)
    : cashbookMoney(receipt.totalCost, receipt.currencyCode);

String receiptRecorded(CashbookStockReceipt receipt) {
  final recorded = receipt.recordedExpenseAmountAllTime;
  return recorded == null ? '—' : cashbookMoney(recorded, receipt.currencyCode);
}

/// Receipts to link a voucher to. There is deliberately no "remaining" figure:
/// the backend does not cap vouchers by receipt value, so a balance would lie.
class StockReceiptPickList extends StatelessWidget {
  const StockReceiptPickList({
    super.key,
    required this.page,
    required this.timezone,
    required this.onPick,
  });

  final ReportPage<CashbookStockReceipt> page;
  final String timezone;
  final ValueChanged<CashbookStockReceipt> onPick;

  @override
  Widget build(BuildContext context) {
    if (page.isEmpty) {
      return const CashbookEmptyState(
        icon: Icons.inventory_2_outlined,
        message: 'Không có phiếu nhập đã xác nhận nào trong kỳ này.',
      );
    }
    return Column(
      children: [
        for (final receipt in page.content)
          _ReceiptRow(
            key: ValueKey(receipt.stockDocumentId),
            receipt: receipt,
            timezone: timezone,
            onTap: () => onPick(receipt),
          ),
      ],
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({
    super.key,
    required this.receipt,
    required this.timezone,
    required this.onTap,
  });

  final CashbookStockReceipt receipt;
  final String timezone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        receipt.documentCode,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (receipt.currencyUnknown)
                      CashbookBadge.unknownCurrency(theme.colorScheme),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                Text(
                  '${receipt.warehouseName} · Xác nhận ${cashbookDate(receipt.confirmedAt, timezone)}',
                  style: muted,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text('Giá trị phiếu: ${receiptMoney(receipt)}'),
                    Text(
                      'Đã ghi chi: ${receiptRecorded(receipt)} '
                      '(${receipt.linkedPostedExpenseCount} phiếu)',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
