import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart' show authControllerProvider;
import '../../../reports/domain/entities/report_date.dart';
import '../../domain/entities/cashbook_filters.dart';
import '../../domain/entities/cashbook_records.dart';
import '../../domain/use_cases/cashbook_use_cases.dart';
import '../controllers/cashbook_receipts_controller.dart';
import '../providers/cashbook_providers.dart';
import 'cashbook_common.dart';
import 'cashbook_dialog_frame.dart';
import 'cashbook_format.dart';
import 'stock_receipts_table.dart';

Future<CashbookStockReceipt?> showStockReceiptPicker(BuildContext context) =>
    showDialog<CashbookStockReceipt>(
      context: context,
      builder: (_) => const StockReceiptPickerDialog(),
    );

/// Finds a confirmed receipt to link. Payments often trail the receipt by
/// weeks, so the picker looks back further than the cashbook's own range.
class StockReceiptPickerDialog extends ConsumerStatefulWidget {
  const StockReceiptPickerDialog({super.key});

  @override
  ConsumerState<StockReceiptPickerDialog> createState() =>
      _StockReceiptPickerDialogState();
}

class _StockReceiptPickerDialogState
    extends ConsumerState<StockReceiptPickerDialog> {
  static const _lookbacks = [30, 90, 180, 366];
  late final CashbookReceiptsController _controller;
  int _days = 90;
  late ReportDate _today;

  CashbookRangeFilter _range(int days) => CashbookRangeFilter(
    range: ReportDateRange(
      fromDate: _today.subtractDays(days - 1),
      toDate: _today,
    ),
  );

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authControllerProvider);
    _today = cashbookToday(ref.read(cashbookRangeProvider).meta?.timezone);
    _controller = CashbookReceiptsController(
      session: () => auth.state.session,
      range: _range(_days),
      getReceipts: GetCashbookStockReceipts(
        ref.read(cashbookRepositoryProvider),
      ),
      onAccessDenied: (_) => auth.revalidateAccess(),
      filter: const CashbookReceiptFilter(size: 10),
    );
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CashbookDialogFrame(
      title: 'Chọn phiếu nhập',
      subtitle: 'Phiếu nhập đã xác nhận, lọc theo ngày xác nhận',
      icon: Icons.inventory_2_outlined,
      maxWidth: 640,
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final c = _controller;
          if (c.accessFailure != null) {
            return CashbookNotice(
              message: c.accessFailure!.message,
              tone: CashbookNoticeTone.error,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final days in _lookbacks)
                    ChoiceChip(
                      label: Text(days == 366 ? '1 năm' : '$days ngày'),
                      selected: _days == days,
                      onSelected: (_) {
                        setState(() => _days = days);
                        c.setRange(_range(days));
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              CashbookSearchField(
                initial: c.queryText,
                hint: 'Tìm mã phiếu nhập',
                onChanged: c.setQuery,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 4,
                child: c.page.loading
                    ? const LinearProgressIndicator()
                    : const SizedBox.shrink(),
              ),
              CashbookPanelView(
                panel: c.page,
                onRetry: c.refresh,
                builder: (value) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StockReceiptPickList(
                      page: value.data,
                      timezone: value.meta.timezone,
                      onPick: (receipt) => Navigator.of(context).pop(receipt),
                    ),
                    const SizedBox(height: 8),
                    CashbookPager(
                      page: value.data,
                      busy: c.page.loading,
                      onPage: c.setPage,
                      onSize: c.setPageSize,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
