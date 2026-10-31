import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/result/result.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../../domain/entities/cashbook_filters.dart';
import '../../domain/entities/cashbook_meta.dart';
import '../../domain/entities/cashbook_records.dart';
import '../../domain/use_cases/cashbook_use_cases.dart';
import 'cashbook_base_controller.dart';

/// Confirmed stock receipts, filtered by confirmation date, with the vouchers
/// recorded against them over all time. Also backs the receipt picker.
class CashbookReceiptsController extends CashbookBaseController {
  CashbookReceiptsController({
    required super.session,
    required super.range,
    required GetCashbookStockReceipts getReceipts,
    super.onAccessDenied,
    super.changes,
    CashbookReceiptFilter filter = const CashbookReceiptFilter(),
  }) : _getReceipts = getReceipts,
       _filter = filter;

  final GetCashbookStockReceipts _getReceipts;
  CashbookReceiptFilter _filter;
  String _queryText = '';
  int _generation = 0;

  CashbookPanel<CashbookEnvelope<ReportPage<CashbookStockReceipt>>> page =
      const CashbookPanel();

  CashbookReceiptFilter get filter => _filter;
  String get queryText => _queryText;

  @override
  bool canRead(AppSession? session) =>
      AccessPolicy.canReconcileCashbookReceipts(session);

  @override
  void onRangeChanged() => _filter = _filter.copyWith(page: 0);

  @override
  Future<void> refresh() async {
    if (!allowed) return;
    final range = this.range, filter = _filter;
    final generation = ++_generation;
    page = page.start(keepValue: true);
    changed();
    await run(
      fetch: () => _getReceipts(range, filter),
      valid: () => generation == _generation,
      write: (result) => page = switch (result) {
        Success(:final value) => CashbookPanel(value: value),
        Error(:final failure) => page.failed(failure, keepValue: false),
      },
    );
  }

  Future<void> _change(CashbookReceiptFilter next) async {
    if (!allowed || next == _filter) return;
    _filter = next;
    changed();
    await refresh();
  }

  Future<void> setIncludeUnknownCurrency(bool value) =>
      _change(_filter.copyWith(includeUnknownCurrency: value, page: 0));

  void setQuery(String value) {
    _queryText = value;
    debounceSearch(
      () => _change(_filter.copyWith(q: () => normalizedQuery(value), page: 0)),
    );
  }

  Future<void> setPage(int value) async {
    if (value < 0 || value == _filter.page) return;
    await _change(_filter.copyWith(page: value));
  }

  Future<void> setPageSize(int value) =>
      _change(_filter.copyWith(size: value, page: 0));

  @override
  void onAccessLost() {
    ++_generation;
    page = const CashbookPanel();
  }
}
