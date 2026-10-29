import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/result/result.dart';
import '../../../reports/domain/entities/report_enums.dart';
import '../../../reports/domain/entities/report_meta.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../../domain/entities/reference_margin_filters.dart';
import '../../domain/entities/reference_margin_report.dart';
import '../../domain/repositories/reference_margin_repository.dart';
import '../data_sources/reference_margin_remote_data_source.dart';

class ReferenceMarginRepositoryImpl implements ReferenceMarginRepository {
  const ReferenceMarginRepositoryImpl(this.remote);
  final ReferenceMarginRemoteDataSource remote;

  Future<Result<T>> _read<T>(
    String? validation,
    Future<T> Function() action,
  ) async {
    if (validation != null) {
      return Error(
        Failure(
          type: FailureType.validation,
          code: 'INVALID_REFERENCE_MARGIN_FILTER',
          message: validation,
        ),
      );
    }
    try {
      return Success(await action());
    } on FormatException {
      return const Error(
        Failure(
          type: FailureType.internal,
          code: 'INVALID_REFERENCE_MARGIN_RESPONSE',
          message:
              'Dữ liệu báo cáo giá vốn chưa hợp lệ. Hãy tải lại để đối soát.',
        ),
      );
    } on Object catch (error) {
      Failure mapped;
      try {
        mapped = ApiErrorMapper.fromException(error);
      } on Object {
        return const Error(
          Failure(
            type: FailureType.internal,
            code: 'INVALID_REFERENCE_MARGIN_ERROR',
            message: 'Chưa đọc được lỗi báo cáo từ máy chủ. Hãy thử lại.',
          ),
        );
      }
      const messages = {
        'INVALID_REPORT_DATE_RANGE': 'Khoảng ngày báo cáo không hợp lệ.',
        'REPORT_RANGE_TOO_LARGE': 'Chỉ xem tối đa 366 ngày trong một lần.',
        'INVALID_REPORT_CURRENCY': 'Mã tiền tệ báo cáo không hợp lệ.',
        'INVALID_REPORT_SORT': 'Lựa chọn sắp xếp báo cáo không hợp lệ.',
        'INVALID_REPORT_TIMEZONE':
            'Múi giờ nhà hàng chưa hợp lệ. Hãy đối soát cấu hình và thử lại.',
        'REPORT_COST_DATA_CONFLICT':
            'Snapshot giá vốn có dữ liệu bất nhất. Hãy đối soát rồi tải lại báo cáo.',
      };
      final message = messages[mapped.code];
      if (message == null) {
        return Error(mapped);
      }
      return Error(
        Failure(
          type:
              const {
                'INVALID_REPORT_TIMEZONE',
                'REPORT_COST_DATA_CONFLICT',
              }.contains(mapped.code)
              ? FailureType.conflict
              : FailureType.validation,
          code: mapped.code,
          message: message,
          fieldErrors: mapped.fieldErrors,
        ),
      );
    }
  }

  @override
  Future<Result<ReportEnvelope<ReferenceMarginSummary>>> getSummary(
    ReferenceMarginFilter filter,
  ) => _read(filter.validate(), () => remote.getSummary(filter));
  @override
  Future<Result<ReportEnvelope<List<ReferenceMarginSeriesPoint>>>> getSeries(
    ReferenceMarginFilter filter, {
    ReportGranularity granularity = ReportGranularity.day,
  }) => _read(
    filter.validate(),
    () => remote.getSeries(filter, granularity: granularity),
  );
  @override
  Future<Result<ReportEnvelope<ReportPage<ReferenceMarginOrderRow>>>> getOrders(
    ReferenceMarginOrdersFilter filter,
  ) => _read(filter.validate(), () => remote.getOrders(filter));
}
