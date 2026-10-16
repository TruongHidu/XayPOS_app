import 'package:dio/dio.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/payment_method_report_row.dart';
import '../../domain/entities/report_enums.dart';
import '../../domain/entities/report_filters.dart';
import '../../domain/entities/report_meta.dart';
import '../../domain/entities/report_order_row.dart';
import '../../domain/entities/report_overview.dart';
import '../../domain/entities/report_page.dart';
import '../../domain/entities/revenue_series_point.dart';
import '../../domain/entities/top_item_report_row.dart';
import '../../domain/repositories/report_repository.dart';
import '../data_sources/report_remote_data_source.dart';

class ReportRepositoryImpl implements ReportRepository {
  const ReportRepositoryImpl(this.remote);
  final ReportRemoteDataSource remote;

  Future<Result<T>> _result<T>(Future<T> Function() call) async {
    try {
      return Success(await call());
    } on FormatException catch (e) {
      return Error(
        Failure(
          type: FailureType.internal,
          code: 'INVALID_REPORT_RESPONSE',
          message: e.message.isNotEmpty
              ? e.message
              : 'Dữ liệu báo cáo trả về không đúng định dạng.',
        ),
      );
    } on Object catch (e) {
      if (e is DioException && (e.response?.statusCode ?? 0) >= 500) {
        final mapped = ApiErrorMapper.fromException(e);
        return Error(
          Failure(
            type: FailureType.internal,
            code: mapped.code,
            fieldErrors: mapped.fieldErrors,
            message:
                'Máy chủ báo cáo đang bận hoặc gặp lỗi. Vui lòng thử lại sau.',
          ),
        );
      }
      return Error(ApiErrorMapper.fromException(e));
    }
  }

  @override
  Future<Result<ReportEnvelope<ReportOverview>>> getDailyReport(
    DailyReportFilter filter,
  ) => _result(() => remote.getDailyReport(filter));

  @override
  Future<Result<ReportEnvelope<ReportOverview>>> getReportSummary(
    ReportRangeFilter filter,
  ) {
    final validationError = filter.dateRange.validate();
    if (validationError != null) {
      return Future.value(
        Error(
          Failure(
            type: FailureType.validation,
            code: 'INVALID_REPORT_DATE_RANGE',
            message: validationError,
          ),
        ),
      );
    }
    return _result(() => remote.getReportSummary(filter));
  }

  @override
  Future<Result<ReportEnvelope<List<RevenueSeriesPoint>>>> getRevenueSeries(
    ReportRangeFilter filter, {
    ReportGranularity granularity = ReportGranularity.day,
  }) {
    final validationError = filter.dateRange.validate();
    if (validationError != null) {
      return Future.value(
        Error(
          Failure(
            type: FailureType.validation,
            code: 'INVALID_REPORT_DATE_RANGE',
            message: validationError,
          ),
        ),
      );
    }
    return _result(
      () => remote.getRevenueSeries(filter, granularity: granularity),
    );
  }

  @override
  Future<Result<ReportEnvelope<List<PaymentMethodReportRow>>>>
  getPaymentMethods(ReportRangeFilter filter) {
    final validationError = filter.dateRange.validate();
    if (validationError != null) {
      return Future.value(
        Error(
          Failure(
            type: FailureType.validation,
            code: 'INVALID_REPORT_DATE_RANGE',
            message: validationError,
          ),
        ),
      );
    }
    return _result(() => remote.getPaymentMethods(filter));
  }

  @override
  Future<Result<ReportEnvelope<ReportPage<TopItemReportRow>>>> getTopItems(
    TopItemsFilter filter,
  ) {
    final validationError = filter.dateRange.validate();
    if (validationError != null) {
      return Future.value(
        Error(
          Failure(
            type: FailureType.validation,
            code: 'INVALID_REPORT_DATE_RANGE',
            message: validationError,
          ),
        ),
      );
    }
    return _result(() => remote.getTopItems(filter));
  }

  @override
  Future<Result<ReportEnvelope<ReportPage<ReportOrderRow>>>> getReportOrders(
    ReportOrdersFilter filter,
  ) {
    final validationError = filter.dateRange.validate();
    if (validationError != null) {
      return Future.value(
        Error(
          Failure(
            type: FailureType.validation,
            code: 'INVALID_REPORT_DATE_RANGE',
            message: validationError,
          ),
        ),
      );
    }
    return _result(() => remote.getReportOrders(filter));
  }
}
