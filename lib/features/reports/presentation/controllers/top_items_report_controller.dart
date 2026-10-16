import 'package:flutter/foundation.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/report_date.dart';
import '../../domain/entities/report_enums.dart';
import '../../domain/entities/report_filters.dart';
import '../../domain/entities/report_meta.dart';
import '../../domain/entities/report_page.dart';
import '../../domain/entities/top_item_report_row.dart';
import '../../domain/use_cases/report_use_cases.dart';

class TopItemsReportController extends ChangeNotifier {
  final GetTopItemsReport _getTopItemsReport;

  TopItemsReportController({
    required GetTopItemsReport getTopItemsReport,
    ReportRangeFilter? initialFilter,
  }) : _getTopItemsReport = getTopItemsReport {
    final range = initialFilter?.range ?? ReportDateRange.last7Days();
    _filter = TopItemsFilter(
      range: range,
      currencyCode: initialFilter?.currencyCode,
      serviceType: initialFilter?.serviceType,
      sourceChannel: initialFilter?.sourceChannel,
      page: 0,
      size: 20,
      sortBy: TopItemSortBy.itemSalesAmount,
      direction: ReportSortDirection.desc,
    );
  }

  late TopItemsFilter _filter;
  bool _isLoading = false;
  bool _isRefreshing = false;
  ReportEnvelope<ReportPage<TopItemReportRow>>? _data;
  Failure? _failure;
  int _generation = 0;
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

  TopItemsFilter get filter => _filter;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  ReportEnvelope<ReportPage<TopItemReportRow>>? get data => _data;
  Failure? get failure => _failure;

  void updateParentFilter(ReportRangeFilter parentFilter) {
    final changed =
        _filter.range != parentFilter.range ||
        _filter.currencyCode != parentFilter.currencyCode ||
        _filter.serviceType != parentFilter.serviceType ||
        _filter.sourceChannel != parentFilter.sourceChannel;

    if (changed) {
      _filter = _filter.copyWith(
        range: parentFilter.range,
        currencyCode: () => parentFilter.currencyCode,
        serviceType: () => parentFilter.serviceType,
        sourceChannel: () => parentFilter.sourceChannel,
        page: 0,
      );
      load(isRefresh: false);
    } else if (_data == null && !_isLoading) {
      load(isRefresh: false);
    }
  }

  void setSortBy(TopItemSortBy sortBy) {
    if (_filter.sortBy == sortBy) return;
    _filter = _filter.copyWith(sortBy: sortBy, page: 0);
    load(isRefresh: false);
  }

  void setDirection(ReportSortDirection direction) {
    if (_filter.direction == direction) return;
    _filter = _filter.copyWith(direction: direction, page: 0);
    load(isRefresh: false);
  }

  void toggleSortDirection() {
    final newDir = _filter.direction == ReportSortDirection.desc
        ? ReportSortDirection.asc
        : ReportSortDirection.desc;
    setDirection(newDir);
  }

  void setPage(int page) {
    if (page < 0 || page == _filter.page) return;
    final totalPages = _data?.data.totalPages;
    if (totalPages != null && page >= totalPages && totalPages > 0) return;
    _filter = _filter.copyWith(page: page);
    load(isRefresh: false);
  }

  void setSize(int size) {
    if (size <= 0 || size == _filter.size) return;
    _filter = _filter.copyWith(size: size.clamp(1, 100), page: 0);
    load(isRefresh: false);
  }

  Future<void> retry() => load(isRefresh: false);
  Future<void> refresh() => load(isRefresh: true);

  Future<void> load({bool isRefresh = false}) async {
    final gen = ++_generation;

    if (isRefresh && _data != null) {
      _isRefreshing = true;
    } else {
      _isLoading = true;
      _failure = null;
    }
    notifyListeners();

    final result = await _getTopItemsReport(_filter);
    if (_generation != gen) return;

    switch (result) {
      case Success(:final value):
        _data = value;
        _failure = null;
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
      case Error(:final failure):
        _failure = failure;
        _isLoading = false;
        _isRefreshing = false;
        notifyListeners();
    }
  }
}
