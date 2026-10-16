import '../../../order/domain/entities/order_entities.dart'
    show OrderPaymentStatus, OrderStatus, ServiceType;
import 'report_date.dart';
import 'report_enums.dart';

/// Filters for GET /api/v1/reports/daily
class DailyReportFilter {
  const DailyReportFilter({
    this.date,
    this.currencyCode,
    this.serviceType,
    this.sourceChannel,
  });

  /// Optional date. If null, server defaults to today in restaurant timezone.
  final ReportDate? date;
  final String? currencyCode;
  final ServiceType? serviceType;
  final ReportSourceChannel? sourceChannel;

  DailyReportFilter copyWith({
    ReportDate? Function()? date,
    String? Function()? currencyCode,
    ServiceType? Function()? serviceType,
    ReportSourceChannel? Function()? sourceChannel,
  }) {
    return DailyReportFilter(
      date: date != null ? date() : this.date,
      currencyCode: currencyCode != null ? currencyCode() : this.currencyCode,
      serviceType: serviceType != null ? serviceType() : this.serviceType,
      sourceChannel: sourceChannel != null
          ? sourceChannel()
          : this.sourceChannel,
    );
  }

  String toQueryKey() =>
      'daily:${date?.toIso8601Date() ?? "today"}:$currencyCode:$serviceType:$sourceChannel';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyReportFilter &&
          other.date == date &&
          other.currencyCode == currencyCode &&
          other.serviceType == serviceType &&
          other.sourceChannel == sourceChannel;

  @override
  int get hashCode =>
      Object.hash(date, currencyCode, serviceType, sourceChannel);
}

/// Common filters for date-range reports (summary, revenue series, payment methods).
class ReportRangeFilter {
  const ReportRangeFilter({
    ReportDateRange? dateRange,
    ReportDateRange? range,
    this.currencyCode,
    this.serviceType,
    this.sourceChannel,
  }) : dateRange =
           dateRange ??
           range ??
           const ReportDateRange(
             fromDate: ReportDate(2026, 1, 1),
             toDate: ReportDate(2026, 1, 1),
           );

  final ReportDateRange dateRange;
  ReportDateRange get range => dateRange;
  final String? currencyCode;
  final ServiceType? serviceType;
  final ReportSourceChannel? sourceChannel;

  ReportRangeFilter copyWith({
    ReportDateRange? dateRange,
    String? Function()? currencyCode,
    ServiceType? Function()? serviceType,
    ReportSourceChannel? Function()? sourceChannel,
  }) {
    return ReportRangeFilter(
      dateRange: dateRange ?? this.dateRange,
      currencyCode: currencyCode != null ? currencyCode() : this.currencyCode,
      serviceType: serviceType != null ? serviceType() : this.serviceType,
      sourceChannel: sourceChannel != null
          ? sourceChannel()
          : this.sourceChannel,
    );
  }

  String toQueryKey([String? extra]) =>
      'range:${dateRange.fromDate.toIso8601Date()}:${dateRange.toDate.toIso8601Date()}:$currencyCode:$serviceType:$sourceChannel${extra != null ? ":$extra" : ""}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportRangeFilter &&
          other.dateRange == dateRange &&
          other.currencyCode == currencyCode &&
          other.serviceType == serviceType &&
          other.sourceChannel == sourceChannel;

  @override
  int get hashCode =>
      Object.hash(dateRange, currencyCode, serviceType, sourceChannel);
}

/// Query parameters for top items.
class TopItemsFilter {
  const TopItemsFilter({
    ReportDateRange? dateRange,
    ReportDateRange? range,
    this.currencyCode,
    this.serviceType,
    this.sourceChannel,
    this.page = 0,
    this.size = 20,
    this.sortBy = TopItemSortBy.quantity,
    this.direction = ReportSortDirection.desc,
  }) : dateRange =
           dateRange ??
           range ??
           const ReportDateRange(
             fromDate: ReportDate(2026, 1, 1),
             toDate: ReportDate(2026, 1, 1),
           );

  final ReportDateRange dateRange;
  ReportDateRange get range => dateRange;
  final String? currencyCode;
  final ServiceType? serviceType;
  final ReportSourceChannel? sourceChannel;
  final int page;
  final int size;
  final TopItemSortBy sortBy;
  final ReportSortDirection direction;

  TopItemsFilter copyWith({
    ReportDateRange? dateRange,
    ReportDateRange? range,
    String? Function()? currencyCode,
    ServiceType? Function()? serviceType,
    ReportSourceChannel? Function()? sourceChannel,
    int? page,
    int? size,
    TopItemSortBy? sortBy,
    ReportSortDirection? direction,
  }) {
    return TopItemsFilter(
      dateRange: dateRange ?? range ?? this.dateRange,
      currencyCode: currencyCode != null ? currencyCode() : this.currencyCode,
      serviceType: serviceType != null ? serviceType() : this.serviceType,
      sourceChannel: sourceChannel != null
          ? sourceChannel()
          : this.sourceChannel,
      page: page ?? this.page,
      size: size ?? this.size,
      sortBy: sortBy ?? this.sortBy,
      direction: direction ?? this.direction,
    );
  }

  String toQueryKey() =>
      'top-items:${dateRange.fromDate.toIso8601Date()}:${dateRange.toDate.toIso8601Date()}:$currencyCode:$serviceType:$sourceChannel:$page:$size:${sortBy.apiCode}:${direction.apiCode}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TopItemsFilter &&
          other.dateRange == dateRange &&
          other.currencyCode == currencyCode &&
          other.serviceType == serviceType &&
          other.sourceChannel == sourceChannel &&
          other.page == page &&
          other.size == size &&
          other.sortBy == sortBy &&
          other.direction == direction;

  @override
  int get hashCode => Object.hash(
    dateRange,
    currencyCode,
    serviceType,
    sourceChannel,
    page,
    size,
    sortBy,
    direction,
  );
}

/// Query parameters for reconciliation orders list.
class ReportOrdersFilter {
  const ReportOrdersFilter({
    ReportDateRange? dateRange,
    ReportDateRange? range,
    this.dateBasis = ReportDateBasis.created,
    this.status,
    this.paymentStatus,
    this.currencyCode,
    this.serviceType,
    this.sourceChannel,
    this.page = 0,
    this.size = 20,
    this.sortBy = ReportOrderSortBy.reportEventAt,
    this.direction = ReportSortDirection.desc,
  }) : dateRange =
           dateRange ??
           range ??
           const ReportDateRange(
             fromDate: ReportDate(2026, 1, 1),
             toDate: ReportDate(2026, 1, 1),
           );

  final ReportDateRange dateRange;
  ReportDateRange get range => dateRange;
  final String? currencyCode;
  final ServiceType? serviceType;
  final ReportSourceChannel? sourceChannel;
  final ReportDateBasis dateBasis;
  final OrderStatus? status;
  final OrderPaymentStatus? paymentStatus;
  final int page;
  final int size;
  final ReportOrderSortBy sortBy;
  final ReportSortDirection direction;

  ReportOrdersFilter copyWith({
    ReportDateRange? dateRange,
    ReportDateBasis? dateBasis,
    OrderStatus? Function()? status,
    OrderPaymentStatus? Function()? paymentStatus,
    String? Function()? currencyCode,
    ServiceType? Function()? serviceType,
    ReportSourceChannel? Function()? sourceChannel,
    int? page,
    int? size,
    ReportOrderSortBy? sortBy,
    ReportSortDirection? direction,
  }) {
    return ReportOrdersFilter(
      dateRange: dateRange ?? this.dateRange,
      dateBasis: dateBasis ?? this.dateBasis,
      status: status != null ? status() : this.status,
      paymentStatus: paymentStatus != null
          ? paymentStatus()
          : this.paymentStatus,
      currencyCode: currencyCode != null ? currencyCode() : this.currencyCode,
      serviceType: serviceType != null ? serviceType() : this.serviceType,
      sourceChannel: sourceChannel != null
          ? sourceChannel()
          : this.sourceChannel,
      page: page ?? this.page,
      size: size ?? this.size,
      sortBy: sortBy ?? this.sortBy,
      direction: direction ?? this.direction,
    );
  }

  String toQueryKey() =>
      'orders:${dateRange.fromDate.toIso8601Date()}:${dateRange.toDate.toIso8601Date()}:${dateBasis.apiCode}:$status:$paymentStatus:$currencyCode:$serviceType:$sourceChannel:$page:$size:${sortBy.apiCode}:${direction.apiCode}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportOrdersFilter &&
          other.dateRange == dateRange &&
          other.dateBasis == dateBasis &&
          other.status == status &&
          other.paymentStatus == paymentStatus &&
          other.currencyCode == currencyCode &&
          other.serviceType == serviceType &&
          other.sourceChannel == sourceChannel &&
          other.page == page &&
          other.size == size &&
          other.sortBy == sortBy &&
          other.direction == direction;

  @override
  int get hashCode => Object.hash(
    dateRange,
    dateBasis,
    status,
    paymentStatus,
    currencyCode,
    serviceType,
    sourceChannel,
    page,
    size,
    sortBy,
    direction,
  );
}
