import 'package:flutter/foundation.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../order/domain/entities/order_entities.dart' show ServiceType;
import '../../domain/entities/report_date.dart';
import '../../domain/entities/report_enums.dart';
import '../../domain/entities/report_filters.dart';
import '../../domain/entities/report_meta.dart';
import '../../domain/entities/report_overview.dart';
import '../../domain/use_cases/report_use_cases.dart';

class DailyReportController extends ChangeNotifier {
  final GetDailyReport _getDailyReport;

  DailyReportController({required GetDailyReport getDailyReport})
    : _getDailyReport = getDailyReport {
    _draftFilter = DailyReportFilter();
    _appliedFilter = _draftFilter;
  }

  DailyReportFilter _draftFilter = DailyReportFilter();
  DailyReportFilter _appliedFilter = DailyReportFilter();

  bool _isLoading = false;
  bool _isRefreshing = false;
  ReportEnvelope<ReportOverview>? _data;
  Failure? _failure;
  int _requestGeneration = 0;
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

  DailyReportFilter get draftFilter => _draftFilter;
  DailyReportFilter get appliedFilter => _appliedFilter;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  ReportEnvelope<ReportOverview>? get data => _data;
  Failure? get failure => _failure;

  void setDraftDate(ReportDate? date) {
    _draftFilter = _draftFilter.copyWith(date: () => date);
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
    _draftFilter = DailyReportFilter();
    applyFilters();
  }

  Future<void> applyFilters() async {
    _appliedFilter = _draftFilter;
    await load(isRefresh: false);
  }

  Future<void> refresh() async {
    await load(isRefresh: true);
  }

  Future<void> load({bool isRefresh = false}) async {
    final generation = ++_requestGeneration;

    if (isRefresh && _data != null) {
      _isRefreshing = true;
    } else {
      _isLoading = true;
      _failure = null;
    }
    notifyListeners();

    final result = await _getDailyReport(_appliedFilter);

    if (_requestGeneration != generation) {
      return;
    }

    switch (result) {
      case Success(:final value):
        _data = value;
        _failure = null;
        _isLoading = false;
        _isRefreshing = false;
        // Sync draft date if server resolved default date
        if (_appliedFilter.date == null) {
          _appliedFilter = _appliedFilter.copyWith(
            date: () => value.meta.fromDate,
          );
          _draftFilter = _draftFilter.copyWith(date: () => value.meta.fromDate);
        }
        notifyListeners();
      case Error(:final failure):
        _failure = failure;
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
    }
  }
}
