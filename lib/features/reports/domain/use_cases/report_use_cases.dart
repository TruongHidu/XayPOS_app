import '../../../../core/result/result.dart';
import '../entities/payment_method_report_row.dart';
import '../entities/report_enums.dart';
import '../entities/report_filters.dart';
import '../entities/report_meta.dart';
import '../entities/report_order_row.dart';
import '../entities/report_overview.dart';
import '../entities/report_page.dart';
import '../entities/revenue_series_point.dart';
import '../entities/top_item_report_row.dart';
import '../repositories/report_repository.dart';

class GetDailyReport {
  const GetDailyReport(this._repository);
  final ReportRepository _repository;

  Future<Result<ReportEnvelope<ReportOverview>>> call(
    DailyReportFilter filter,
  ) => _repository.getDailyReport(filter);
}

class GetReportSummary {
  const GetReportSummary(this._repository);
  final ReportRepository _repository;

  Future<Result<ReportEnvelope<ReportOverview>>> call(
    ReportRangeFilter filter,
  ) => _repository.getReportSummary(filter);
}

class GetRevenueSeries {
  const GetRevenueSeries(this._repository);
  final ReportRepository _repository;

  Future<Result<ReportEnvelope<List<RevenueSeriesPoint>>>> call(
    ReportRangeFilter filter, {
    ReportGranularity granularity = ReportGranularity.day,
  }) => _repository.getRevenueSeries(filter, granularity: granularity);
}

class GetPaymentMethodReport {
  const GetPaymentMethodReport(this._repository);
  final ReportRepository _repository;

  Future<Result<ReportEnvelope<List<PaymentMethodReportRow>>>> call(
    ReportRangeFilter filter,
  ) => _repository.getPaymentMethods(filter);
}

class GetTopItemsReport {
  const GetTopItemsReport(this._repository);
  final ReportRepository _repository;

  Future<Result<ReportEnvelope<ReportPage<TopItemReportRow>>>> call(
    TopItemsFilter filter,
  ) => _repository.getTopItems(filter);
}

class GetReportOrders {
  const GetReportOrders(this._repository);
  final ReportRepository _repository;

  Future<Result<ReportEnvelope<ReportPage<ReportOrderRow>>>> call(
    ReportOrdersFilter filter,
  ) => _repository.getReportOrders(filter);
}
