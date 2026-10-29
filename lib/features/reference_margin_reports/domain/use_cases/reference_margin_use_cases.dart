import '../../../../core/result/result.dart';
import '../../../reports/domain/entities/report_enums.dart';
import '../../../reports/domain/entities/report_meta.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../entities/reference_margin_filters.dart';
import '../entities/reference_margin_report.dart';
import '../repositories/reference_margin_repository.dart';

class GetReferenceMarginSummary {
  const GetReferenceMarginSummary(this.repository);
  final ReferenceMarginRepository repository;
  Future<Result<ReportEnvelope<ReferenceMarginSummary>>> call(
    ReferenceMarginFilter filter,
  ) => repository.getSummary(filter);
}

class GetReferenceMarginSeries {
  const GetReferenceMarginSeries(this.repository);
  final ReferenceMarginRepository repository;
  Future<Result<ReportEnvelope<List<ReferenceMarginSeriesPoint>>>> call(
    ReferenceMarginFilter filter, {
    ReportGranularity granularity = ReportGranularity.day,
  }) => repository.getSeries(filter, granularity: granularity);
}

class GetReferenceMarginOrders {
  const GetReferenceMarginOrders(this.repository);
  final ReferenceMarginRepository repository;
  Future<Result<ReportEnvelope<ReportPage<ReferenceMarginOrderRow>>>> call(
    ReferenceMarginOrdersFilter filter,
  ) => repository.getOrders(filter);
}
