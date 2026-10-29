import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/reference_margin_reports/data/dto/reference_margin_dto.dart';
import 'package:pos_saas_app/features/reference_margin_reports/domain/entities/reference_margin_enums.dart';
import 'package:pos_saas_app/features/reference_margin_reports/domain/entities/reference_margin_filters.dart';
import 'package:pos_saas_app/features/reference_margin_reports/domain/entities/reference_margin_report.dart';
import 'package:pos_saas_app/features/reference_margin_reports/domain/repositories/reference_margin_repository.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_date.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_enums.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_meta.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_page.dart';

ReferenceMarginFilter marginFilter({
  String? currencyCode = 'VND',
  ServiceType? serviceType,
  ReportSourceChannel? sourceChannel,
}) => ReferenceMarginFilter(
  range: const ReportDateRange(
    fromDate: ReportDate(2026, 10, 1),
    toDate: ReportDate(2026, 10, 2),
  ),
  currencyCode: currencyCode,
  serviceType: serviceType,
  sourceChannel: sourceChannel,
);

Map<String, dynamic> marginMetaJson([
  ReferenceMarginFilter? filter,
  ReportGranularity? granularity,
]) {
  final query = filter ?? marginFilter();
  return {
    'fromDate': query.range.fromDate.toIso8601Date(),
    'toDate': query.range.toDate.toIso8601Date(),
    'timezone': 'Asia/Ho_Chi_Minh',
    'currencyCode': query.currencyCode?.trim().toUpperCase() ?? 'VND',
    'generatedAt': '2026-10-28T12:00:00Z',
    'serviceType': query.serviceType?.code,
    'sourceChannel': query.sourceChannel?.apiCode,
    'granularity': granularity?.apiCode,
    'dateBasis': 'COMPLETED',
  };
}

Map<String, dynamic> marginSummaryJson({
  String coverage = 'PARTIAL',
  bool negative = false,
}) {
  final empty = coverage == 'NO_DATA', unavailable = coverage == 'UNAVAILABLE';
  final covered = empty || unavailable
      ? 0
      : coverage == 'COMPLETE'
      ? 10
      : 8;
  return {
    'costBasis': 'CATALOG_REFERENCE_AT_ACCEPTANCE',
    'marginScope': 'FULLY_COSTED_COMPLETED_ORDERS',
    'costCoverageStatus': coverage,
    'completedOrderCount': empty ? 0 : 10,
    'fullyCostedOrderCount': covered,
    'excludedOrderCount': empty ? 0 : 10 - covered,
    'orderCoveragePercent': empty ? null : covered * 10,
    'subtotalAmount': empty ? 0 : 1050000,
    'discountAmount': empty ? 0 : 50000,
    'taxAmount': empty ? 0 : 80000,
    'serviceChargeAmount': empty ? 0 : 20000,
    'salesAmount': empty ? 0 : 1100000,
    'netSalesAmount': empty ? 0 : 1000000,
    'coveredNetSalesAmount': covered == 0 ? 0 : 800000,
    'coveredReferenceCostAmount': covered == 0
        ? 0
        : negative
        ? 900000
        : 300000,
    'coveredReferenceMarginAmount': covered == 0
        ? 0
        : negative
        ? -100000
        : 500000,
    'coveredReferenceMarginPercent': covered == 0
        ? null
        : negative
        ? -12.50
        : 62.50,
    'costIssues': empty || coverage == 'COMPLETE'
        ? <Object>[]
        : [
            {
              'code': 'INCOMPLETE',
              'orderCount': 10 - covered,
              'itemCount': 10 - covered,
            },
          ],
  };
}

Map<String, dynamic> marginOrderJson({
  String id = 'order-1',
  bool excluded = false,
  bool negative = false,
}) => {
  'orderId': id,
  'orderCode': 'OD-$id',
  'completedAt': '2026-10-01T08:15:00Z',
  'serviceType': 'DINE_IN',
  'sourceChannel': 'CASHIER',
  'subtotalAmount': 105000,
  'discountAmount': 5000,
  'taxAmount': 8000,
  'serviceChargeAmount': 2000,
  'salesAmount': 110000,
  'netSalesAmount': 100000,
  'eligibleItemCount': 2,
  'fullyCostedItemCount': excluded ? 1 : 2,
  'costCoverageStatus': excluded ? 'PARTIAL' : 'COMPLETE',
  'costIssues': excluded
      ? [
          {'code': 'LEGACY_UNAVAILABLE', 'orderCount': 1, 'itemCount': 1},
        ]
      : <Object>[],
  'referenceCostAmount': excluded
      ? null
      : negative
      ? 120000
      : 40000,
  'referenceMarginAmount': excluded
      ? null
      : negative
      ? -20000
      : 60000,
  'referenceMarginPercent': excluded
      ? null
      : negative
      ? -20
      : 60,
};

Map<String, dynamic> marginEnvelopeJson(
  Object? data, {
  ReferenceMarginFilter? filter,
  ReportGranularity? granularity,
}) => {'meta': marginMetaJson(filter, granularity), 'data': data};

class FakeReferenceMarginRepository implements ReferenceMarginRepository {
  final summaryCalls = <ReferenceMarginFilter>[];
  final seriesCalls = <(ReferenceMarginFilter, ReportGranularity)>[];
  final ordersCalls = <ReferenceMarginOrdersFilter>[];
  Map<String, dynamic> summaryJson = marginSummaryJson();
  List<Map<String, dynamic>> rows = [
    for (var i = 0; i < 10; i++)
      marginOrderJson(id: 'order-$i', excluded: i >= 8),
  ];
  Future<Result<ReportEnvelope<ReferenceMarginSummary>>> Function(
    ReferenceMarginFilter,
  )?
  onSummary;
  Future<Result<ReportEnvelope<List<ReferenceMarginSeriesPoint>>>> Function(
    ReferenceMarginFilter,
    ReportGranularity,
  )?
  onSeries;
  Future<Result<ReportEnvelope<ReportPage<ReferenceMarginOrderRow>>>> Function(
    ReferenceMarginOrdersFilter,
  )?
  onOrders;

  @override
  Future<Result<ReportEnvelope<ReferenceMarginSummary>>> getSummary(
    ReferenceMarginFilter filter,
  ) async {
    summaryCalls.add(filter);
    if (onSummary != null) {
      return onSummary!(filter);
    }
    return Success(
      ReferenceMarginDto.summary(
        marginEnvelopeJson(summaryJson, filter: filter),
        filter,
      ),
    );
  }

  @override
  Future<Result<ReportEnvelope<List<ReferenceMarginSeriesPoint>>>> getSeries(
    ReferenceMarginFilter filter, {
    ReportGranularity granularity = ReportGranularity.day,
  }) async {
    seriesCalls.add((filter, granularity));
    if (onSeries != null) {
      return onSeries!(filter, granularity);
    }
    final points = <Map<String, dynamic>>[];
    var date = granularity == ReportGranularity.day
        ? filter.range.fromDate
        : ReportDate(
            filter.range.fromDate.year,
            filter.range.fromDate.month,
            1,
          );
    while (date <= filter.range.toDate) {
      points.add({
        'bucketStartDate': date.toIso8601Date(),
        ...(points.isEmpty
            ? summaryJson
            : marginSummaryJson(coverage: 'NO_DATA')),
      });
      date = granularity == ReportGranularity.day
          ? date.addDays(1)
          : ReportDate.fromDateTime(DateTime.utc(date.year, date.month + 1, 1));
    }
    return Success(
      ReferenceMarginDto.series(
        marginEnvelopeJson(points, filter: filter, granularity: granularity),
        filter,
        granularity,
      ),
    );
  }

  @override
  Future<Result<ReportEnvelope<ReportPage<ReferenceMarginOrderRow>>>> getOrders(
    ReferenceMarginOrdersFilter filter,
  ) async {
    ordersCalls.add(filter);
    if (onOrders != null) {
      return onOrders!(filter);
    }
    final filtered = rows
        .where(
          (row) =>
              filter.costCoverage == CostCoverageFilter.all ||
              (row['costCoverageStatus'] == 'COMPLETE') ==
                  (filter.costCoverage == CostCoverageFilter.complete),
        )
        .toList();
    final pageRows = filtered
        .skip(filter.page * filter.size)
        .take(filter.size)
        .toList();
    return Success(
      ReferenceMarginDto.orders(
        marginEnvelopeJson({
          'content': pageRows,
          'page': filter.page,
          'size': filter.size,
          'totalElements': filtered.length,
          'totalPages': (filtered.length + filter.size - 1) ~/ filter.size,
        }, filter: filter.filter),
        filter,
      ),
    );
  }
}
