import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart' show authControllerProvider;
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/ui/widgets/endless_list_footer.dart';
import '../../../inventory/presentation/widgets/stock_widgets.dart'
    show stockDetailLocation;
import '../../domain/entities/cashbook_enums.dart';
import '../../domain/entities/cashbook_records.dart';
import '../controllers/cashbook_flow_controller.dart';
import '../providers/cashbook_providers.dart';
import 'cashbook_common.dart';
import 'cashbook_entries_table.dart';
import 'cashbook_series_chart.dart';
import 'cashbook_summary_cards.dart';
import 'expense_detail_dialog.dart';

/// Effective cash flow: criteria first (they drive every figure below),
/// then the totals, the trend and finally the rows themselves.
class CashbookFlowTab extends ConsumerWidget {
  const CashbookFlowTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(cashbookFlowProvider);
    final categories = ref.watch(cashbookCategoriesProvider).value;
    final session = ref.watch(authControllerProvider).state.session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FlowCriteria(controller: c, categories: categories ?? const []),
        const SizedBox(height: 16),
        CashbookPanelView(
          panel: c.summary,
          onRetry: c.loadSummary,
          placeholderHeight: 150,
          builder: (value) => CashbookSummaryCards(
            summary: value.data,
            currency: value.meta.currencyCode,
          ),
        ),
        const SizedBox(height: 16),
        CashbookPanelView(
          panel: c.series,
          onRetry: c.loadSeries,
          placeholderHeight: 280,
          builder: (value) => CashbookSeriesChart(
            points: value.data,
            currency: value.meta.currencyCode,
            granularity: c.granularity,
            onGranularity: c.setGranularity,
            loading: c.series.loading,
          ),
        ),
        const SizedBox(height: 16),
        CashbookCard(
          title: 'Giao dịch thu chi',
          subtitle: 'Thu từ thanh toán thành công và phiếu chi còn hiệu lực',
          icon: Icons.receipt_long_outlined,
          child: CashbookPanelView(
            panel: c.entries,
            onRetry: c.loadEntries,
            builder: (value) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CashbookEntriesTable(
                  page: value.data,
                  timezone: value.meta.timezone,
                  sortBy: c.filter.sortBy,
                  direction: c.filter.direction,
                  onSort: c.setSort,
                  onOpen: (entry) => _open(context, entry, session),
                  sourceLink: (entry) => _link(context, entry, session),
                ),
                if (value.data.isNotEmpty)
                  EndlessListFooter(
                    hasMore: value.data.hasNextPage,
                    failureMessage: c.endless.failure?.message,
                    endLabel:
                        'Đã hiển thị tất cả ${value.data.totalElements} giao dịch',
                    onLoadMore: c.loadMoreEntries,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _open(BuildContext context, CashbookEntry entry, AppSession? session) {
    if (entry.sourceType == CashbookSourceType.expenseVoucher) {
      showExpenseDetailDialog(context, expenseId: entry.sourceId);
      return;
    }
    _link(context, entry, session)?.open?.call();
  }

  /// Opening a source still needs that screen's own permission.
  CashbookSourceLink? _link(
    BuildContext context,
    CashbookEntry entry,
    AppSession? session,
  ) {
    if (entry.orderId != null) {
      final label = entry.orderCode ?? 'Đơn hàng';
      return (
        label: label,
        open: AccessPolicy.canOrders(session, 'ORDER_VIEW')
            ? () => context.push(
                '/app/orders/${Uri.encodeComponent(entry.orderId!)}',
              )
            : null,
      );
    }
    if (entry.stockDocumentId != null) {
      return (
        label: entry.sourceDocumentCode ?? 'Phiếu nhập',
        open: AccessPolicy.canInventory(session, 'INVENTORY_VIEW')
            ? () => context.push(stockDetailLocation(entry.stockDocumentId!))
            : null,
      );
    }
    return null;
  }
}

class _FlowCriteria extends StatelessWidget {
  const _FlowCriteria({required this.controller, required this.categories});
  final CashbookFlowController controller;
  final List<CashbookCategory> categories;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final filter = c.filter;
    final typed = [
      for (final category in categories)
        if (filter.type == null || category.type == filter.type) category,
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<CashbookEntryType?>(
          key: const ValueKey('cashbook-flow-type'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: null, label: Text('Tất cả')),
            ButtonSegment(
              value: CashbookEntryType.income,
              icon: Icon(Icons.south_west, size: 16),
              label: Text('Thu'),
            ),
            ButtonSegment(
              value: CashbookEntryType.expense,
              icon: Icon(Icons.north_east, size: 16),
              label: Text('Chi'),
            ),
          ],
          selected: {filter.type},
          onSelectionChanged: (value) => c.setType(value.first),
        ),
        SizedBox(
          width: 260,
          child: CashbookSearchField(
            initial: c.queryText,
            hint: 'Tìm mã, người nhận, ghi chú…',
            onChanged: c.setQuery,
          ),
        ),
        CashbookDropdown<String>(
          label: 'Danh mục',
          value: filter.categoryCode,
          items: [
            (null, 'Tất cả danh mục'),
            for (final category in typed) (category.code, category.name),
          ],
          onChanged: c.setCategory,
        ),
        CashbookDropdown<CashbookPaymentMethod>(
          label: 'Phương thức',
          width: 170,
          value: filter.paymentMethod,
          items: [
            (null, 'Tất cả'),
            for (final m in CashbookPaymentMethod.values) (m, m.label),
          ],
          onChanged: c.setPaymentMethod,
        ),
        if (filter.hasCriteria)
          TextButton.icon(
            onPressed: c.clearCriteria,
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text('Bỏ lọc'),
          ),
      ],
    );
  }
}
