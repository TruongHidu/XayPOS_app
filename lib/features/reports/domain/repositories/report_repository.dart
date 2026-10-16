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

abstract class ReportRepository {
  /// GET /api/v1/reports/daily
  Future<Result<ReportEnvelope<ReportOverview>>> getDailyReport(
    DailyReportFilter filter,
  );

  /// GET /api/v1/reports/summary
  Future<Result<ReportEnvelope<ReportOverview>>> getReportSummary(
    ReportRangeFilter filter,
  );

  /// GET /api/v1/reports/revenue-series
  Future<Result<ReportEnvelope<List<RevenueSeriesPoint>>>> getRevenueSeries(
    ReportRangeFilter filter, {
    ReportGranularity granularity = ReportGranularity.day,
  });

  /// GET /api/v1/reports/payment-methods
  Future<Result<ReportEnvelope<List<PaymentMethodReportRow>>>>
  getPaymentMethods(ReportRangeFilter filter);

  /// GET /api/v1/reports/top-items
  Future<Result<ReportEnvelope<ReportPage<TopItemReportRow>>>> getTopItems(
    TopItemsFilter filter,
  );

  /// GET /api/v1/reports/orders
  Future<Result<ReportEnvelope<ReportPage<ReportOrderRow>>>> getReportOrders(
    ReportOrdersFilter filter,
  );
}
