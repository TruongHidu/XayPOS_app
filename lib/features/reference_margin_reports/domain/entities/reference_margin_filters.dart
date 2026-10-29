import 'dart:convert';
import '../../../order/domain/entities/order_entities.dart' show ServiceType;
import '../../../reports/domain/entities/report_date.dart';
import '../../../reports/domain/entities/report_enums.dart';
import 'reference_margin_enums.dart';

class ReferenceMarginFilter {
  const ReferenceMarginFilter({
    required this.range,
    this.currencyCode,
    this.serviceType,
    this.sourceChannel,
  });
  final ReportDateRange range;
  final String? currencyCode;
  final ServiceType? serviceType;
  final ReportSourceChannel? sourceChannel;

  ReferenceMarginFilter copyWith({
    ReportDateRange? range,
    String? Function()? currencyCode,
    ServiceType? Function()? serviceType,
    ReportSourceChannel? Function()? sourceChannel,
  }) => ReferenceMarginFilter(
    range: range ?? this.range,
    currencyCode: currencyCode == null ? this.currencyCode : currencyCode(),
    serviceType: serviceType == null ? this.serviceType : serviceType(),
    sourceChannel: sourceChannel == null ? this.sourceChannel : sourceChannel(),
  );

  String? validate() {
    try {
      ReportDate.parse(range.fromDate.toIso8601Date());
      ReportDate.parse(range.toDate.toIso8601Date());
    } on FormatException {
      return 'Ngày báo cáo không hợp lệ.';
    }
    final dateError = range.validate();
    if (dateError != null) {
      return dateError;
    }
    final currency = currencyCode?.trim();
    if (currency != null && !RegExp(r'^[A-Za-z]{3}$').hasMatch(currency)) {
      return 'Mã tiền tệ cần gồm 3 chữ cái, ví dụ VND hoặc USD.';
    }
    return null;
  }

  String queryKey(String endpoint, {ReportGranularity? granularity}) =>
      jsonEncode([
        endpoint,
        range.fromDate.toIso8601Date(),
        range.toDate.toIso8601Date(),
        currencyCode?.trim().toUpperCase(),
        serviceType?.code,
        sourceChannel?.apiCode,
        granularity?.apiCode,
      ]);

  @override
  bool operator ==(Object other) =>
      other is ReferenceMarginFilter && queryKey('') == other.queryKey('');
  @override
  int get hashCode => queryKey('').hashCode;
}

class ReferenceMarginOrdersFilter {
  const ReferenceMarginOrdersFilter({
    required this.filter,
    this.costCoverage = CostCoverageFilter.all,
    this.page = 0,
    this.size = 20,
    this.sortBy = ReferenceMarginOrderSort.completedAt,
    this.direction = ReportSortDirection.desc,
  });
  final ReferenceMarginFilter filter;
  final CostCoverageFilter costCoverage;
  final int page, size;
  final ReferenceMarginOrderSort sortBy;
  final ReportSortDirection direction;

  ReferenceMarginOrdersFilter copyWith({
    ReferenceMarginFilter? filter,
    CostCoverageFilter? costCoverage,
    int? page,
    int? size,
    ReferenceMarginOrderSort? sortBy,
    ReportSortDirection? direction,
  }) => ReferenceMarginOrdersFilter(
    filter: filter ?? this.filter,
    costCoverage: costCoverage ?? this.costCoverage,
    page: page ?? this.page,
    size: size ?? this.size,
    sortBy: sortBy ?? this.sortBy,
    direction: direction ?? this.direction,
  );

  String? validate() =>
      filter.validate() ??
      (page < 0
          ? 'Trang không hợp lệ.'
          : size < 1 || size > 100
          ? 'Mỗi trang cần từ 1 đến 100 đơn.'
          : null);

  String queryKey() => jsonEncode([
    filter.queryKey('/api/v1/reports/reference-margin/orders'),
    costCoverage.code,
    page,
    size,
    sortBy.code,
    direction.apiCode,
  ]);

  @override
  bool operator ==(Object other) =>
      other is ReferenceMarginOrdersFilter && queryKey() == other.queryKey();
  @override
  int get hashCode => queryKey().hashCode;
}
