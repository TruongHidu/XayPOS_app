import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../../core/network/exact_json.dart';
import '../../../reports/domain/entities/report_enums.dart';
import '../../../reports/domain/entities/report_meta.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../../domain/entities/reference_margin_filters.dart';
import '../../domain/entities/reference_margin_report.dart';
import '../dto/reference_margin_dto.dart';

class ReferenceMarginRemoteDataSource {
  const ReferenceMarginRemoteDataSource(this._dio);
  final Dio _dio;
  static const _prefix = '/api/v1/reports/reference-margin';

  Future<Object?> _get(String endpoint, Map<String, Object> query) async {
    try {
      final response = await _dio.get<dynamic>(
        '$_prefix/$endpoint',
        queryParameters: query,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'Accept': Headers.jsonContentType,
            'Cache-Control': 'no-store',
          },
        ),
      );
      if (response.statusCode != 200) {
        throw const FormatException('Invalid reference margin response status');
      }
      return response.data is String
          ? decodeExactJson(response.data as String)
          : response.data;
    } on DioException catch (error) {
      final raw = error.response?.data;
      if (raw is String) {
        try {
          error.response!.data = jsonDecode(raw);
        } on FormatException {
          /* Preserve unknown errors. */
        }
      }
      rethrow;
    }
  }

  Map<String, Object> _query(ReferenceMarginFilter filter) => {
    'fromDate': filter.range.fromDate.toIso8601Date(),
    'toDate': filter.range.toDate.toIso8601Date(),
    if (filter.currencyCode != null)
      'currencyCode': filter.currencyCode!.trim().toUpperCase(),
    if (filter.serviceType != null) 'serviceType': filter.serviceType!.code,
    if (filter.sourceChannel != null)
      'sourceChannel': filter.sourceChannel!.apiCode,
  };

  Future<ReportEnvelope<ReferenceMarginSummary>> getSummary(
    ReferenceMarginFilter filter,
  ) async =>
      ReferenceMarginDto.summary(await _get('summary', _query(filter)), filter);

  Future<ReportEnvelope<List<ReferenceMarginSeriesPoint>>> getSeries(
    ReferenceMarginFilter filter, {
    ReportGranularity granularity = ReportGranularity.day,
  }) async => ReferenceMarginDto.series(
    await _get('series', {
      ..._query(filter),
      'granularity': granularity.apiCode,
    }),
    filter,
    granularity,
  );

  Future<ReportEnvelope<ReportPage<ReferenceMarginOrderRow>>> getOrders(
    ReferenceMarginOrdersFilter filter,
  ) async => ReferenceMarginDto.orders(
    await _get('orders', {
      ..._query(filter.filter),
      'costCoverage': filter.costCoverage.code,
      'page': filter.page,
      'size': filter.size,
      'sortBy': filter.sortBy.code,
      'direction': filter.direction.apiCode,
    }),
    filter,
  );
}
