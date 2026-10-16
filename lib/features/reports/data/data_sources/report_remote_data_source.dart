import 'package:dio/dio.dart';
import '../../domain/entities/payment_method_report_row.dart';
import '../../domain/entities/report_enums.dart';
import '../../domain/entities/report_filters.dart';
import '../../domain/entities/report_meta.dart';
import '../../domain/entities/report_order_row.dart';
import '../../domain/entities/report_overview.dart';
import '../../domain/entities/report_page.dart';
import '../../domain/entities/revenue_series_point.dart';
import '../../domain/entities/top_item_report_row.dart';
import '../dto/report_dto.dart';

class ReportRemoteDataSource {
  const ReportRemoteDataSource(this.dio);
  final Dio dio;

  static const _acceptHeaders = {'Accept': 'application/json'};

  Future<ReportEnvelope<ReportOverview>> getDailyReport(
    DailyReportFilter filter,
  ) async {
    final queryParams = <String, dynamic>{};
    if (filter.date != null) {
      queryParams['date'] = filter.date!.toIso8601Date();
    }
    if (filter.currencyCode != null && filter.currencyCode!.trim().isNotEmpty) {
      queryParams['currencyCode'] = filter.currencyCode!.trim().toUpperCase();
    }
    if (filter.serviceType != null) {
      queryParams['serviceType'] = filter.serviceType!.code;
    }
    if (filter.sourceChannel != null) {
      queryParams['sourceChannel'] = filter.sourceChannel!.apiCode;
    }

    final response = await dio.get<Object?>(
      '/api/v1/reports/daily',
      queryParameters: queryParams,
      options: Options(headers: _acceptHeaders),
    );
    if (response.statusCode != 200) {
      throw const FormatException(
        'Trạng thái phản hồi báo cáo ngày không hợp lệ',
      );
    }
    return ReportDto.parseOverviewEnvelope(response.data);
  }

  Future<ReportEnvelope<ReportOverview>> getReportSummary(
    ReportRangeFilter filter,
  ) async {
    final queryParams = _buildRangeQueryParams(filter);

    final response = await dio.get<Object?>(
      '/api/v1/reports/summary',
      queryParameters: queryParams,
      options: Options(headers: _acceptHeaders),
    );
    if (response.statusCode != 200) {
      throw const FormatException(
        'Trạng thái phản hồi tổng quan báo cáo không hợp lệ',
      );
    }
    return ReportDto.parseOverviewEnvelope(response.data);
  }

  Future<ReportEnvelope<List<RevenueSeriesPoint>>> getRevenueSeries(
    ReportRangeFilter filter, {
    ReportGranularity granularity = ReportGranularity.day,
  }) async {
    final queryParams = _buildRangeQueryParams(filter);
    queryParams['granularity'] = granularity.apiCode;

    final response = await dio.get<Object?>(
      '/api/v1/reports/revenue-series',
      queryParameters: queryParams,
      options: Options(headers: _acceptHeaders),
    );
    if (response.statusCode != 200) {
      throw const FormatException(
        'Trạng thái phản hồi chuỗi doanh thu không hợp lệ',
      );
    }
    return ReportDto.parseRevenueSeriesEnvelope(response.data);
  }

  Future<ReportEnvelope<List<PaymentMethodReportRow>>> getPaymentMethods(
    ReportRangeFilter filter,
  ) async {
    final queryParams = _buildRangeQueryParams(filter);

    final response = await dio.get<Object?>(
      '/api/v1/reports/payment-methods',
      queryParameters: queryParams,
      options: Options(headers: _acceptHeaders),
    );
    if (response.statusCode != 200) {
      throw const FormatException(
        'Trạng thái phản hồi phương thức thanh toán không hợp lệ',
      );
    }
    return ReportDto.parsePaymentMethodsEnvelope(response.data);
  }

  Future<ReportEnvelope<ReportPage<TopItemReportRow>>> getTopItems(
    TopItemsFilter filter,
  ) async {
    final queryParams = <String, dynamic>{
      'fromDate': filter.dateRange.fromDate.toIso8601Date(),
      'toDate': filter.dateRange.toDate.toIso8601Date(),
      'page': filter.page,
      'size': filter.size,
      'sortBy': filter.sortBy.apiCode,
      'direction': filter.direction.apiCode,
    };
    if (filter.currencyCode != null && filter.currencyCode!.trim().isNotEmpty) {
      queryParams['currencyCode'] = filter.currencyCode!.trim().toUpperCase();
    }
    if (filter.serviceType != null) {
      queryParams['serviceType'] = filter.serviceType!.code;
    }
    if (filter.sourceChannel != null) {
      queryParams['sourceChannel'] = filter.sourceChannel!.apiCode;
    }

    final response = await dio.get<Object?>(
      '/api/v1/reports/top-items',
      queryParameters: queryParams,
      options: Options(headers: _acceptHeaders),
    );
    if (response.statusCode != 200) {
      throw const FormatException(
        'Trạng thái phản hồi món bán chạy không hợp lệ',
      );
    }
    return ReportDto.parseTopItemsEnvelope(response.data);
  }

  Future<ReportEnvelope<ReportPage<ReportOrderRow>>> getReportOrders(
    ReportOrdersFilter filter,
  ) async {
    final queryParams = <String, dynamic>{
      'fromDate': filter.dateRange.fromDate.toIso8601Date(),
      'toDate': filter.dateRange.toDate.toIso8601Date(),
      'dateBasis': filter.dateBasis.apiCode,
      'page': filter.page,
      'size': filter.size,
      'sortBy': filter.sortBy.apiCode,
      'direction': filter.direction.apiCode,
    };
    if (filter.status != null) {
      queryParams['status'] = filter.status!.code;
    }
    if (filter.paymentStatus != null) {
      queryParams['paymentStatus'] = filter.paymentStatus!.code;
    }
    if (filter.currencyCode != null && filter.currencyCode!.trim().isNotEmpty) {
      queryParams['currencyCode'] = filter.currencyCode!.trim().toUpperCase();
    }
    if (filter.serviceType != null) {
      queryParams['serviceType'] = filter.serviceType!.code;
    }
    if (filter.sourceChannel != null) {
      queryParams['sourceChannel'] = filter.sourceChannel!.apiCode;
    }

    final response = await dio.get<Object?>(
      '/api/v1/reports/orders',
      queryParameters: queryParams,
      options: Options(headers: _acceptHeaders),
    );
    if (response.statusCode != 200) {
      throw const FormatException(
        'Trạng thái phản hồi danh sách đơn đối chiếu không hợp lệ',
      );
    }
    return ReportDto.parseOrdersEnvelope(response.data);
  }

  Map<String, dynamic> _buildRangeQueryParams(ReportRangeFilter filter) {
    final params = <String, dynamic>{
      'fromDate': filter.dateRange.fromDate.toIso8601Date(),
      'toDate': filter.dateRange.toDate.toIso8601Date(),
    };
    if (filter.currencyCode != null && filter.currencyCode!.trim().isNotEmpty) {
      params['currencyCode'] = filter.currencyCode!.trim().toUpperCase();
    }
    if (filter.serviceType != null) {
      params['serviceType'] = filter.serviceType!.code;
    }
    if (filter.sourceChannel != null) {
      params['sourceChannel'] = filter.sourceChannel!.apiCode;
    }
    return params;
  }
}
