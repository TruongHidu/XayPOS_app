import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/paging/endless_pages.dart';
import '../../../../core/result/result.dart';
import '../../../order/domain/entities/order_entities.dart' show ServiceType;
import '../../../order/presentation/controllers/order_events.dart';
import '../../../reports/domain/entities/report_date.dart';
import '../../../reports/domain/entities/report_enums.dart';
import '../../../reports/domain/entities/report_meta.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../../domain/entities/reference_margin_enums.dart';
import '../../domain/entities/reference_margin_filters.dart';
import '../../domain/entities/reference_margin_report.dart';
import '../../domain/use_cases/reference_margin_use_cases.dart';

/// Values are retained only for the same query. An unsuccessful refresh never
/// changes the date/currency attribution of a previously successful response.
class MarginPanel<T> {
  const MarginPanel({
    this.value,
    this.loading = false,
    this.stale = false,
    this.failure,
    this.queryKey,
  });
  final ReportEnvelope<T>? value;
  final bool loading, stale;
  final Failure? failure;
  final String? queryKey;

  MarginPanel<T> start(String key) => MarginPanel(
    value: queryKey == key ? value : null,
    loading: true,
    stale: queryKey == key && value != null,
    queryKey: key,
  );
  MarginPanel<T> markStale() => MarginPanel(
    value: value,
    stale: value != null,
    failure: failure,
    queryKey: queryKey,
  );
  MarginPanel<T> failed(Failure error, String key) => MarginPanel(
    value: queryKey == key ? value : null,
    stale: queryKey == key && value != null,
    failure: error,
    queryKey: key,
  );
}

class ReferenceMarginReportsController extends ChangeNotifier {
  ReferenceMarginReportsController({
    required this.session,
    required GetReferenceMarginSummary getSummary,
    required GetReferenceMarginSeries getSeries,
    required GetReferenceMarginOrders getOrders,
    required this.events,
    this.onAccessDenied,
    ReferenceMarginFilter? initialFilter,
  }) : _getSummary = getSummary,
       _getSeries = getSeries,
       _getOrders = getOrders,
       _scope = AccessPolicy.referenceMarginScope(session()) {
    _draftFilter =
        initialFilter ??
        ReferenceMarginFilter(range: ReportDateRange.last7Days());
    _appliedFilter = _draftFilter;
    _ordersFilter = ReferenceMarginOrdersFilter(filter: _appliedFilter);
    _eventRevision = events.revision;
    events.addListener(_orderChanged);
  }
  final AppSession? Function() session;
  final GetReferenceMarginSummary _getSummary;
  final GetReferenceMarginSeries _getSeries;
  final GetReferenceMarginOrders _getOrders;
  final OrderEvents events;
  final Future<void> Function(Failure)? onAccessDenied;
  final Object? _scope;
  late ReferenceMarginFilter _draftFilter, _appliedFilter;
  late ReferenceMarginOrdersFilter _ordersFilter;
  ReferenceMarginFilter get draftFilter => _draftFilter;
  ReferenceMarginFilter get appliedFilter => _appliedFilter;
  ReferenceMarginOrdersFilter get ordersFilter => _ordersFilter;
  ReportGranularity _granularity = ReportGranularity.day;
  ReportGranularity get granularity => _granularity;
  MarginPanel<ReferenceMarginSummary> _summary = const MarginPanel();
  MarginPanel<List<ReferenceMarginSeriesPoint>> _series = const MarginPanel();
  MarginPanel<ReportPage<ReferenceMarginOrderRow>> _orders =
      const MarginPanel();
  MarginPanel<ReferenceMarginSummary> get summary =>
      allowed ? _summary : const MarginPanel();
  MarginPanel<List<ReferenceMarginSeriesPoint>> get series =>
      allowed ? _series : const MarginPanel();
  MarginPanel<ReportPage<ReferenceMarginOrderRow>> get orders =>
      allowed ? _orders : const MarginPanel();
  final _orderPages = EndlessPages<ReferenceMarginOrderRow>(
    (row) => row.orderId,
  );
  Failure? get ordersLoadMoreFailure => _orderPages.failure;
  bool _disposed = false, _initialized = false, _ordersOpened = false;
  bool _visible = true, _foreground = true, _refreshNeeded = false;
  bool _reportedDenial = false, _checkingAccess = false;
  int _summaryGeneration = 0, _seriesGeneration = 0, _ordersGeneration = 0;
  int _inFlight = 0;
  late int _eventRevision;
  Timer? _refreshTimer;
  Failure? _accessFailure;
  String? validationError;
  bool get current =>
      !_disposed && _scope == AccessPolicy.referenceMarginScope(session());
  bool get _canRead =>
      current && AccessPolicy.canViewReferenceMarginReports(session());
  bool get allowed => _canRead && _accessFailure == null;
  bool get _canFetch => allowed && _visible && _foreground;
  bool get ordersOpened => _ordersOpened;
  bool get checkingAccess => _checkingAccess;
  Failure? get accessFailure => _accessFailure;

  static const _invalid = Failure(
    type: FailureType.internal,
    code: 'INVALID_REFERENCE_MARGIN_RESPONSE',
    message: 'Chưa tải được báo cáo. Vui lòng thử lại.',
  );
  static const _accessTypes = {
    FailureType.unauthorized,
    FailureType.invalidRefreshToken,
    FailureType.forbidden,
    FailureType.featureNotEntitled,
    FailureType.subscriptionNotActive,
    FailureType.restaurantInactive,
  };

  void _changed() {
    if (current) notifyListeners();
  }

  Future<void> initialize() async {
    if (_initialized || !allowed) return;
    _initialized = true;
    await refresh();
  }

  void setDraftRange(ReportDateRange range) {
    if (!allowed) return;
    _draftFilter = _draftFilter.copyWith(range: range);
    validationError = null;
    _changed();
  }

  void setDraftCurrencyCode(String? value) {
    if (!allowed) return;
    _draftFilter = _draftFilter.copyWith(currencyCode: () => _currency(value));
    validationError = null;
    _changed();
  }

  static String? _currency(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim().toUpperCase();
  void setDraftServiceType(ServiceType? value) {
    if (!allowed) return;
    _draftFilter = _draftFilter.copyWith(serviceType: () => value);
    _changed();
  }

  void setDraftSourceChannel(ReportSourceChannel? value) {
    if (!allowed) return;
    _draftFilter = _draftFilter.copyWith(sourceChannel: () => value);
    _changed();
  }

  void _clearPanels() {
    ++_summaryGeneration;
    ++_seriesGeneration;
    ++_ordersGeneration;
    _summary = const MarginPanel();
    _series = const MarginPanel();
    _orders = const MarginPanel();
  }

  Future<void> applyFilters() async {
    if (!allowed) return;
    final next = _draftFilter.copyWith(
      currencyCode: () => _currency(_draftFilter.currencyCode),
    );
    validationError = next.validate();
    if (validationError != null) {
      _changed();
      return;
    }
    final changed = next != _appliedFilter;
    _appliedFilter = next;
    _draftFilter = next;
    final ordersChanged = _ordersFilter.page != 0;
    _ordersFilter = _ordersFilter.copyWith(filter: next, page: 0);
    if (changed) {
      _clearPanels();
    } else if (ordersChanged) {
      ++_ordersGeneration;
      _orders = const MarginPanel();
    }
    _changed();
    await refresh();
  }

  Future<void> resetFilters() async {
    if (!allowed) return;
    _draftFilter = ReferenceMarginFilter(range: ReportDateRange.last7Days());
    _ordersFilter = ReferenceMarginOrdersFilter(filter: _draftFilter);
    _granularity = ReportGranularity.day;
    _clearPanels();
    await applyFilters();
  }

  Future<void> refresh() async {
    if (!allowed) return;
    validationError = _appliedFilter.validate();
    if (validationError != null) {
      _changed();
      return;
    }
    if (!_canFetch) {
      _refreshNeeded = true;
      return;
    }
    _refreshTimer?.cancel();
    _refreshNeeded = false;
    await Future.wait([
      loadSummary(),
      loadSeries(),
      if (_ordersOpened) loadOrders(),
    ]);
  }

  Future<void> loadSummary() async {
    if (!_canFetch) return;
    if (!_validAppliedFilter()) return;
    final filter = _appliedFilter;
    final key = filter.queryKey('/api/v1/reports/reference-margin/summary');
    if (_summary.loading && _summary.queryKey == key) return;
    final generation = ++_summaryGeneration;
    _summary = _summary.start(key);
    _changed();
    await _run<ReferenceMarginSummary>(
      fetch: () => _getSummary(filter),
      key: key,
      valid: () => generation == _summaryGeneration,
      read: () => _summary,
      write: (panel) => _summary = panel,
    );
  }

  Future<void> loadSeries() async {
    if (!_canFetch) return;
    if (!_validAppliedFilter()) return;
    final filter = _appliedFilter, g = _granularity;
    final key = filter.queryKey(
      '/api/v1/reports/reference-margin/series',
      granularity: g,
    );
    if (_series.loading && _series.queryKey == key) return;
    final generation = ++_seriesGeneration;
    _series = _series.start(key);
    _changed();
    await _run<List<ReferenceMarginSeriesPoint>>(
      fetch: () => _getSeries(filter, granularity: g),
      key: key,
      valid: () => generation == _seriesGeneration,
      read: () => _series,
      write: (panel) => _series = panel,
    );
  }

  Future<void> loadOrders() async {
    if (!_ordersOpened || !_canFetch) return;
    final filter = _ordersFilter, key = _ordersFilter.queryKey();
    final invalid = filter.validate();
    if (invalid != null) {
      validationError = invalid;
      _changed();
      return;
    }
    if (_orders.loading && _orders.queryKey == key) return;
    final generation = ++_ordersGeneration;
    _orders = _orders.start(key);
    _changed();
    await _run<ReportPage<ReferenceMarginOrderRow>>(
      fetch: () async {
        final result = await _orderPages.read(
          page: filter.page,
          fetch: (page) => _getOrders(filter.copyWith(page: page)),
          content: (value) => value.data.content,
          totalPages: (value) => value.data.totalPages,
          active: () => allowed && generation == _ordersGeneration,
        );
        return switch (result) {
          Success(value: final pages) => Success(
            ReportEnvelope(
              meta: pages.last.meta,
              data: pages.last.data.withRows(pages.rows, pages.lastPage),
            ),
          ),
          Error(failure: final failure) => Error(failure),
        };
      },
      key: key,
      valid: () => generation == _ordersGeneration,
      read: () => _orders,
      write: (panel) => _orders = panel,
    );
  }

  /// Appends the next page; a failure keeps the orders already shown.
  Future<void> loadMoreOrders() async {
    final shown = _orders.value;
    if (shown == null ||
        !shown.data.hasNextPage ||
        !_ordersOpened ||
        !_canFetch ||
        _orders.loading ||
        _orderPages.loadingMore) {
      return;
    }
    final next = _ordersFilter.copyWith(page: shown.data.page + 1);
    final key = next.queryKey();
    final generation = ++_ordersGeneration;
    _orderPages.begin();
    _changed();
    await _run<ReportPage<ReferenceMarginOrderRow>>(
      fetch: () async => switch (await _getOrders(next)) {
        Success(value: final value) => Success(
          ReportEnvelope(
            meta: value.meta,
            data: value.data.withRows(
              _orderPages.append(shown.data.content, value.data.content),
              next.page,
            ),
          ),
        ),
        Error(failure: final failure) => Error(failure),
      },
      key: key,
      valid: () => generation == _ordersGeneration,
      read: () => _orders,
      write: (panel) {
        if (panel.failure case final failure?) {
          _orderPages.fail(failure);
        } else {
          _ordersFilter = next;
          _orders = panel;
        }
      },
    );
  }

  bool _validAppliedFilter() {
    validationError = _appliedFilter.validate();
    if (validationError == null) return true;
    _changed();
    return false;
  }

  Future<void> _run<T>({
    required Future<Result<ReportEnvelope<T>>> Function() fetch,
    required String key,
    required bool Function() valid,
    required MarginPanel<T> Function() read,
    required void Function(MarginPanel<T>) write,
  }) async {
    _inFlight++;
    try {
      Result<ReportEnvelope<T>> result;
      try {
        result = await fetch();
      } catch (_) {
        result = const Error(_invalid);
      }
      // These endpoints share one capability. A denial from an earlier query in
      // this same authority scope still revokes all private panels and dialogs.
      if (!_canRead) return;
      if (result case Error(failure: final failure)) {
        if (_accessTypes.contains(failure.type)) {
          await _deny(failure);
          return;
        }
      }
      if (!allowed || !valid()) return;
      switch (result) {
        case Success(value: final value):
          write(MarginPanel(value: value, queryKey: key));
        case Error(failure: final failure):
          write(read().failed(failure, key));
      }
      _changed();
    } finally {
      _inFlight--;
      // Mutation bursts while a slow GET is pending require one subsequent
      // read, rather than an overlapping request for every debounce window.
      if (_inFlight == 0) _scheduleRefresh();
    }
  }

  Future<void> setGranularity(ReportGranularity value) async {
    if (!allowed || _granularity == value) return;
    _granularity = value;
    ++_seriesGeneration;
    _series = const MarginPanel();
    _changed();
    await loadSeries();
  }

  Future<void> openOrders() async {
    if (!allowed) return;
    final first = !_ordersOpened;
    _ordersOpened = true;
    if (first || _orders.value == null || _orders.stale) await loadOrders();
  }

  Future<void> _changeOrders(ReferenceMarginOrdersFilter next) async {
    if (!allowed) return;
    validationError = next.validate();
    if (validationError != null) {
      _changed();
      return;
    }
    if (next == _ordersFilter) return;
    _ordersFilter = next;
    ++_ordersGeneration;
    _orders = const MarginPanel();
    _changed();
    await loadOrders();
  }

  Future<void> setCostCoverage(CostCoverageFilter value) =>
      _changeOrders(_ordersFilter.copyWith(costCoverage: value, page: 0));
  Future<void> setSort(ReferenceMarginOrderSort value) =>
      _changeOrders(_ordersFilter.copyWith(sortBy: value, page: 0));
  Future<void> setDirection(ReportSortDirection value) =>
      _changeOrders(_ordersFilter.copyWith(direction: value, page: 0));
  Future<void> setPage(int page) =>
      _changeOrders(_ordersFilter.copyWith(page: page));
  Future<void> setPageSize(int size) =>
      _changeOrders(_ordersFilter.copyWith(size: size, page: 0));

  Future<void> _deny(Failure failure) async {
    if (!_canRead) return;
    _accessFailure = failure;
    _refreshTimer?.cancel();
    _refreshNeeded = false;
    _clearPanels();
    _changed();
    if (_reportedDenial) return;
    _reportedDenial = true;
    try {
      await onAccessDenied?.call(failure);
    } catch (_) {
      // A failed access check cannot grant access to a server-denied scope.
    }
  }

  Future<void> retryAccess() async {
    if (!_canRead || _checkingAccess || _accessFailure == null) return;
    _checkingAccess = true;
    _changed();
    try {
      await onAccessDenied?.call(_accessFailure!);
      if (!_canRead) return;
      _accessFailure = null;
      _checkingAccess = false;
      _changed();
      await refresh();
    } catch (_) {
      if (current) {
        _checkingAccess = false;
        _changed();
      }
    }
  }

  void _orderChanged() {
    if (!allowed || _eventRevision == events.revision) return;
    _eventRevision = events.revision;
    _markStale();
    _changed();
    _scheduleRefresh();
  }

  void _markStale() {
    ++_summaryGeneration;
    ++_seriesGeneration;
    ++_ordersGeneration;
    _summary = _summary.markStale();
    _series = _series.markStale();
    _orders = _orders.markStale();
    _refreshNeeded = true;
  }

  void _scheduleRefresh() {
    if (!_canFetch || !_refreshNeeded || _inFlight > 0) return;
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 180), () {
      if (_canFetch && _refreshNeeded) unawaited(refresh());
    });
  }

  void setVisible(bool value) {
    if (_disposed || _visible == value) return;
    _visible = value;
    if (!value) {
      _refreshTimer?.cancel();
      // Visibility can change while a route is disposing. Fence late reads
      // without notifying a provider during widget teardown.
      if (allowed) _markStale();
    } else {
      _scheduleRefresh();
    }
  }

  void setForeground(bool value) {
    if (_disposed || _foreground == value) return;
    _foreground = value;
    if (!value) {
      _refreshTimer?.cancel();
      if (allowed) _markStale();
    } else {
      _scheduleRefresh();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _clearPanels();
    events.removeListener(_orderChanged);
    super.dispose();
  }
}
