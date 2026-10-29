import '../../../../core/result/result.dart';
import '../../../reports/domain/entities/report_enums.dart';
import '../../../reports/domain/entities/report_meta.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../entities/reference_margin_filters.dart';
import '../entities/reference_margin_report.dart';

abstract interface class ReferenceMarginRepository {
  Future<Result<ReportEnvelope<ReferenceMarginSummary>>> getSummary(
    ReferenceMarginFilter filter,
  );
  Future<Result<ReportEnvelope<List<ReferenceMarginSeriesPoint>>>> getSeries(
    ReferenceMarginFilter filter, {
    ReportGranularity granularity = ReportGranularity.day,
  });
  Future<Result<ReportEnvelope<ReportPage<ReferenceMarginOrderRow>>>> getOrders(
    ReferenceMarginOrdersFilter filter,
  );
}
