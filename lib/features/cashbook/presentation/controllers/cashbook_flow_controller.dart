import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/paging/endless_pages.dart';
import '../../../../core/result/result.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../../domain/entities/cashbook_enums.dart';
import '../../domain/entities/cashbook_filters.dart';
import '../../domain/entities/cashbook_meta.dart';
import '../../domain/entities/cashbook_records.dart';
import '../../domain/use_cases/cashbook_use_cases.dart';
import 'cashbook_base_controller.dart';

/// The effective cash flow tab. Summary, series and the entry list are always
/// read with the same criteria, so the totals describe exactly those rows.
class CashbookFlowController extends CashbookBaseController {
  CashbookFlowController({
    required super.session,
    required super.range,
    required GetCashbookSummary getSummary,
    required GetCashbookSeries getSeries,
    required GetCashbookEntries getEntries,
    super.onAccessDenied,
    super.changes,
    this.onMeta,
    Listenable? paymentEvents,
  }) : _getSummary = getSummary,
       _getSeries = getSeries,
       _getEntries = getEntries,
       _paymentEvents = paymentEvents {
    _granularity = _autoGranularity();
    _paymentEvents?.addListener(_paymentsChanged);
  }

  final GetCashbookSummary _getSummary;
  final GetCashbookSeries _getSeries;
  final GetCashbookEntries _getEntries;
  final ValueChanged<CashbookMeta>? onMeta;
  final Listenable? _paymentEvents;

  CashbookEntryFilter _filter = const CashbookEntryFilter();
  late CashbookGranularity _granularity;
  bool _granularityPinned = false;
  String _queryText = '';
  int _summaryGeneration = 0, _seriesGeneration = 0, _entriesGeneration = 0;
  Timer? _paymentTimer;

  CashbookPanel<CashbookEnvelope<CashbookSummary>> summary =
      const CashbookPanel();
  CashbookPanel<CashbookEnvelope<List<CashbookSeriesPoint>>> series =
      const CashbookPanel();
  CashbookPanel<CashbookEnvelope<ReportPage<CashbookEntry>>> entries =
      const CashbookPanel();
  final endless = EndlessPages<CashbookEntry>(
    (entry) => (entry.sourceType, entry.sourceId, entry.occurredAt),
  );

  CashbookEntryFilter get filter => _filter;
  CashbookGranularity get granularity => _granularity;
  String get queryText => _queryText;
  bool get loading => summary.loading || series.loading || entries.loading;

  @override
  bool canRead(AppSession? session) =>
      AccessPolicy.canCashbook(session, 'CASHBOOK_VIEW');

  /// Long ranges are unreadable day by day; months keep the chart legible.
  CashbookGranularity _autoGranularity() => range.range.inclusiveDays > 62
      ? CashbookGranularity.month
      : CashbookGranularity.day;

  @override
  void onRangeChanged() {
    _filter = _filter.copyWith(page: 0);
    if (!_granularityPinned) _granularity = _autoGranularity();
  }

  @override
  Future<void> refresh() async {
    if (!allowed) return;
    await Future.wait([loadSummary(), loadSeries(), loadEntries()]);
  }

  Future<void> loadSummary() async {
    if (!allowed) return;
    final range = this.range, filter = _filter;
    final generation = ++_summaryGeneration;
    summary = summary.start(keepValue: true);
    changed();
    await run(
      fetch: () => _getSummary(range, filter),
      valid: () => generation == _summaryGeneration,
      write: (result) => summary = switch (result) {
        Success(:final value) => _report(CashbookPanel(value: value)),
        Error(:final failure) => summary.failed(failure, keepValue: false),
      },
    );
  }

  Future<void> loadSeries() async {
    if (!allowed) return;
    final range = this.range, filter = _filter, grain = _granularity;
    final generation = ++_seriesGeneration;
    series = series.start(keepValue: true);
    changed();
    await run(
      fetch: () => _getSeries(range, filter, grain),
      valid: () => generation == _seriesGeneration,
      write: (result) => series = switch (result) {
        Success(:final value) => CashbookPanel(value: value),
        Error(:final failure) => series.failed(failure, keepValue: false),
      },
    );
  }

  Future<void> loadEntries() async {
    if (!allowed) return;
    final range = this.range, filter = _filter;
    final generation = ++_entriesGeneration;
    entries = entries.start(keepValue: true);
    changed();
    await run(
      fetch: () => endless.read(
        page: filter.page,
        fetch: (page) => _getEntries(range, filter.copyWith(page: page)),
        content: (value) => value.data.content,
        totalPages: (value) => value.data.totalPages,
        active: () => allowed && generation == _entriesGeneration,
      ),
      valid: () => generation == _entriesGeneration,
      write: (result) => entries = switch (result) {
        Success(:final value) => _report(
          CashbookPanel(value: _joined(value.last, value.rows, value.lastPage)),
        ),
        Error(:final failure) => entries.failed(failure, keepValue: false),
      },
    );
    // A page emptied by a concurrent void steps back instead of looking blank.
    final page = entries.value?.data;
    if (page != null && page.isEmpty && page.page > 0 && allowed) {
      await setPage(page.totalPages > 0 ? page.totalPages - 1 : 0);
    }
  }

  /// Appends the next page; a failure keeps the entries already shown.
  Future<void> loadMoreEntries() async {
    final shown = entries.value?.data;
    if (!allowed ||
        shown == null ||
        !shown.hasNextPage ||
        entries.loading ||
        endless.loadingMore) {
      return;
    }
    final range = this.range, filter = _filter.copyWith(page: shown.page + 1);
    final generation = ++_entriesGeneration;
    endless.begin();
    changed();
    await run(
      fetch: () => _getEntries(range, filter),
      valid: () => generation == _entriesGeneration,
      write: (result) {
        switch (result) {
          case Success(:final value):
            _filter = _filter.copyWith(page: filter.page);
            final rows = endless.append(shown.content, value.data.content);
            entries = _report(
              CashbookPanel(value: _joined(value, rows, filter.page)),
            );
          case Error(:final failure):
            endless.fail(failure);
        }
      },
    );
  }

  CashbookEnvelope<ReportPage<CashbookEntry>> _joined(
    CashbookEnvelope<ReportPage<CashbookEntry>> value,
    List<CashbookEntry> rows,
    int page,
  ) =>
      CashbookEnvelope(meta: value.meta, data: value.data.withRows(rows, page));

  CashbookPanel<CashbookEnvelope<T>> _report<T>(
    CashbookPanel<CashbookEnvelope<T>> panel,
  ) {
    final meta = panel.value?.meta;
    if (meta != null) onMeta?.call(meta);
    return panel;
  }

  /// Criteria changes reload every panel so totals and rows never diverge.
  Future<void> _changeCriteria(CashbookEntryFilter next) async {
    if (!allowed || next == _filter) return;
    _filter = next.copyWith(page: 0);
    changed();
    await refresh();
  }

  Future<void> setType(CashbookEntryType? value) => _changeCriteria(
    _filter.copyWith(
      type: () => value,
      // Category lists are typed; keep only a category of the chosen type.
      categoryCode: value == null ? null : () => null,
    ),
  );

  Future<void> setCategory(String? value) =>
      _changeCriteria(_filter.copyWith(categoryCode: () => value));

  Future<void> setPaymentMethod(CashbookPaymentMethod? value) =>
      _changeCriteria(_filter.copyWith(paymentMethod: () => value));

  void setQuery(String value) {
    _queryText = value;
    debounceSearch(
      () => _changeCriteria(_filter.copyWith(q: () => normalizedQuery(value))),
    );
  }

  Future<void> clearCriteria() async {
    _queryText = '';
    await _changeCriteria(
      CashbookEntryFilter(size: _filter.size, sortBy: _filter.sortBy),
    );
  }

  Future<void> setPage(int page) async {
    if (!allowed || page < 0 || page == _filter.page) return;
    _filter = _filter.copyWith(page: page);
    changed();
    await loadEntries();
  }

  Future<void> setPageSize(int size) async {
    if (!allowed || size == _filter.size) return;
    _filter = _filter.copyWith(size: size, page: 0);
    changed();
    await loadEntries();
  }

  Future<void> setSort(CashbookEntrySort sortBy) async {
    if (!allowed) return;
    final direction = sortBy == _filter.sortBy
        ? (_filter.direction == CashbookSortDirection.desc
              ? CashbookSortDirection.asc
              : CashbookSortDirection.desc)
        : CashbookSortDirection.desc;
    _filter = _filter.copyWith(sortBy: sortBy, direction: direction, page: 0);
    changed();
    await loadEntries();
  }

  Future<void> setGranularity(CashbookGranularity value) async {
    if (!allowed || value == _granularity) return;
    _granularity = value;
    _granularityPinned = true;
    series = const CashbookPanel();
    changed();
    await loadSeries();
  }

  /// Payments arrive in bursts; one read after they settle is enough.
  void _paymentsChanged() {
    if (!initialized || !allowed) return;
    _paymentTimer?.cancel();
    _paymentTimer = Timer(const Duration(milliseconds: 600), () {
      if (allowed) unawaited(refresh());
    });
  }

  @override
  void onAccessLost() {
    ++_summaryGeneration;
    ++_seriesGeneration;
    ++_entriesGeneration;
    summary = const CashbookPanel();
    series = const CashbookPanel();
    entries = const CashbookPanel();
  }

  @override
  void dispose() {
    _paymentTimer?.cancel();
    _paymentEvents?.removeListener(_paymentsChanged);
    super.dispose();
  }
}
