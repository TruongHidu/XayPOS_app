import 'package:flutter/foundation.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../order/domain/entities/order_entities.dart' show ServiceType;
import '../../domain/entities/payment_method_report_row.dart';
import '../../domain/entities/report_date.dart';
import '../../domain/entities/report_enums.dart';
import '../../domain/entities/report_filters.dart';
import '../../domain/entities/report_meta.dart';
import '../../domain/entities/report_overview.dart';
import '../../domain/entities/revenue_series_point.dart';
import '../../domain/use_cases/report_use_cases.dart';

class ReportSummaryController extends ChangeNotifier {
  final GetReportSummary _getReportSummary;
  final GetRevenueSeries _getRevenueSeries;
  final GetPaymentMethodReport _getPaymentMethodReport;

  ReportSummaryController({
    required GetReportSummary getReportSummary,
    required GetRevenueSeries getRevenueSeries,
    required GetPaymentMethodReport getPaymentMethodReport,
    ReportDateRange? initialRange,
  }) : _getReportSummary = getReportSummary,
       _getRevenueSeries = getRevenueSeries,
       _getPaymentMethodReport = getPaymentMethodReport {
    final range = initialRange ?? ReportDateRange.last7Days();
    _draftFilter = ReportRangeFilter(range: range);
    _appliedFilter = _draftFilter;
  }

  late ReportRangeFilter _draftFilter;
  late ReportRangeFilter _appliedFilter;

  ReportGranularity _granularity = ReportGranularity.day;
  bool _showCollectedSeries = true;
  bool _showCompletedSeries = true;
  bool _isSeriesTableView = false;

  // Panel 1: Summary Overview
  bool _summaryLoading = false;
  bool _summaryRefreshing = false;
  ReportEnvelope<ReportOverview>? _summaryData;
  Failure? _summaryFailure;

  // Panel 2: Revenue Series
  bool _seriesLoading = false;
  bool _seriesRefreshing = false;
  ReportEnvelope<List<RevenueSeriesPoint>>? _seriesData;
  Failure? _seriesFailure;

  // Panel 3: Payment Methods
  bool _paymentsLoading = false;
  bool _paymentsRefreshing = false;
  ReportEnvelope<List<PaymentMethodReportRow>>? _paymentsData;
  Failure? _paymentsFailure;

  int _summaryGeneration = 0;
  int _seriesGeneration = 0;
  int _paymentsGeneration = 0;
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  // Getters
  ReportRangeFilter get draftFilter => _draftFilter;
  ReportRangeFilter get appliedFilter => _appliedFilter;
  ReportGranularity get granularity => _granularity;
  bool get showCollectedSeries => _showCollectedSeries;
  bool get showCompletedSeries => _showCompletedSeries;
  bool get isSeriesTableView => _isSeriesTableView;

  bool get summaryLoading => _summaryLoading;
  bool get summaryRefreshing => _summaryRefreshing;
  ReportEnvelope<ReportOverview>? get summaryData => _summaryData;
  Failure? get summaryFailure => _summaryFailure;

  bool get seriesLoading => _seriesLoading;
  bool get seriesRefreshing => _seriesRefreshing;
  ReportEnvelope<List<RevenueSeriesPoint>>? get seriesData => _seriesData;
  Failure? get seriesFailure => _seriesFailure;

  bool get paymentsLoading => _paymentsLoading;
  bool get paymentsRefreshing => _paymentsRefreshing;
  ReportEnvelope<List<PaymentMethodReportRow>>? get paymentsData =>
      _paymentsData;
  Failure? get paymentsFailure => _paymentsFailure;

  bool get isAnyLoading =>
      _summaryLoading || _seriesLoading || _paymentsLoading;
  bool get isAnyRefreshing =>
      _summaryRefreshing || _seriesRefreshing || _paymentsRefreshing;

  // Draft Mutators
  void setDraftRange(ReportDateRange range) {
    _draftFilter = _draftFilter.copyWith(dateRange: range);
    notifyListeners();
  }

  void setDraftCurrencyCode(String? currencyCode) {
    _draftFilter = _draftFilter.copyWith(
      currencyCode: () =>
          currencyCode?.trim().isEmpty == true ? null : currencyCode?.trim(),
    );
    notifyListeners();
  }

  void setDraftServiceType(ServiceType? serviceType) {
    _draftFilter = _draftFilter.copyWith(serviceType: () => serviceType);
    notifyListeners();
  }

  void setDraftSourceChannel(ReportSourceChannel? sourceChannel) {
    _draftFilter = _draftFilter.copyWith(sourceChannel: () => sourceChannel);
    notifyListeners();
  }

  void resetDraftToApplied() {
    _draftFilter = _appliedFilter;
    notifyListeners();
  }

  void resetToDefaults() {
    _draftFilter = ReportRangeFilter(range: ReportDateRange.last7Days());
    applyFilters();
  }

  void setGranularity(ReportGranularity g) {
    if (_granularity == g) return;
    _granularity = g;
    notifyListeners();
    loadSeries(isRefresh: false);
  }

  void toggleShowCollected() {
    if (_showCollectedSeries && !_showCompletedSeries) {
      return;
    }
    _showCollectedSeries = !_showCollectedSeries;
    notifyListeners();
  }

  void toggleShowCompleted() {
    if (_showCompletedSeries && !_showCollectedSeries) {
      return;
    }
    _showCompletedSeries = !_showCompletedSeries;
    notifyListeners();
  }

  void toggleSeriesTableView() {
    _isSeriesTableView = !_isSeriesTableView;
    notifyListeners();
  }

  Future<void> applyFilters() async {
    _appliedFilter = _draftFilter;
    await Future.wait([
      loadSummary(isRefresh: false),
      loadSeries(isRefresh: false),
      loadPayments(isRefresh: false),
    ]);
  }

  Future<void> refreshAll() async {
    await Future.wait([
      loadSummary(isRefresh: true),
      loadSeries(isRefresh: true),
      loadPayments(isRefresh: true),
    ]);
  }

  Future<void> retrySummary() => loadSummary(isRefresh: false);
  Future<void> retrySeries() => loadSeries(isRefresh: false);
  Future<void> retryPayments() => loadPayments(isRefresh: false);

  Future<void> loadSummary({bool isRefresh = false}) async {
    final gen = ++_summaryGeneration;
    if (isRefresh && _summaryData != null) {
      _summaryRefreshing = true;
    } else {
      _summaryLoading = true;
      _summaryFailure = null;
    }
    notifyListeners();

    final result = await _getReportSummary(_appliedFilter);
    if (_summaryGeneration != gen) return;

    switch (result) {
      case Success(:final value):
        _summaryData = value;
        _summaryFailure = null;
        _summaryLoading = false;
        _summaryRefreshing = false;
        notifyListeners();
      case Error(:final failure):
        _summaryFailure = failure;
        _summaryLoading = false;
        _summaryRefreshing = false;
        notifyListeners();
    }
  }

  Future<void> loadSeries({bool isRefresh = false}) async {
    final gen = ++_seriesGeneration;
    if (isRefresh && _seriesData != null) {
      _seriesRefreshing = true;
    } else {
      _seriesLoading = true;
      _seriesFailure = null;
    }
    notifyListeners();

    final result = await _getRevenueSeries(
      _appliedFilter,
      granularity: _granularity,
    );
    if (_seriesGeneration != gen) return;

    switch (result) {
      case Success(:final value):
        _seriesData = value;
        _seriesFailure = null;
        _seriesLoading = false;
        _seriesRefreshing = false;
        notifyListeners();
      case Error(:final failure):
        _seriesFailure = failure;
        _seriesLoading = false;
        _seriesRefreshing = false;
        notifyListeners();
    }
  }

  Future<void> loadPayments({bool isRefresh = false}) async {
    final gen = ++_paymentsGeneration;
    if (isRefresh && _paymentsData != null) {
      _paymentsRefreshing = true;
    } else {
      _paymentsLoading = true;
      _paymentsFailure = null;
    }
    notifyListeners();

    final result = await _getPaymentMethodReport(_appliedFilter);
    if (_paymentsGeneration != gen) return;

    switch (result) {
      case Success(:final value):
        _paymentsData = value;
        _paymentsFailure = null;
        _paymentsLoading = false;
        _paymentsRefreshing = false;
        notifyListeners();
      case Error(:final failure):
        _paymentsFailure = failure;
        _paymentsLoading = false;
        _paymentsRefreshing = false;
        notifyListeners();
    }
  }
}
