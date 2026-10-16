import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart'
    show OrderPaymentStatus, OrderStatus, ServiceType;
import 'package:pos_saas_app/features/reports/domain/entities/payment_method_report_row.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_date.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_enums.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_filters.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_meta.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_money.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_order_row.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_overview.dart';
import 'package:pos_saas_app/features/reports/domain/entities/report_page.dart';
import 'package:pos_saas_app/features/reports/domain/entities/revenue_series_point.dart';
import 'package:pos_saas_app/features/reports/domain/entities/top_item_report_row.dart';
import 'package:pos_saas_app/features/reports/domain/repositories/report_repository.dart';

ReportMeta testReportMeta({
  ReportDate? fromDate,
  ReportDate? toDate,
  String timezone = 'Asia/Ho_Chi_Minh',
  String currencyCode = 'VND',
  DateTime? generatedAt,
  ServiceType? serviceType,
  ReportSourceChannel? sourceChannel,
  ReportGranularity? granularity,
  ReportDateBasis? dateBasis,
}) {
  return ReportMeta(
    fromDate: fromDate ?? const ReportDate(2026, 10, 1),
    toDate: toDate ?? const ReportDate(2026, 10, 15),
    timezone: timezone,
    currencyCode: currencyCode,
    generatedAt: generatedAt ?? DateTime(2026, 10, 15, 12, 0, 0),
    serviceType: serviceType,
    sourceChannel: sourceChannel,
    granularity: granularity,
    dateBasis: dateBasis,
  );
}

ReportOverview testReportOverview({String currencyCode = 'VND'}) {
  return ReportOverview(
    collections: ReportCollectionsSummary(
      collectedAmount: ReportMoney.fromMajor(15000000, currencyCode),
      successfulPaymentCount: 45,
      paidOrderCount: 42,
    ),
    orders: ReportOrdersSummary(
      completedOrderSalesAmount: ReportMoney.fromMajor(14500000, currencyCode),
      completedOrderCount: 40,
      averageCompletedOrderValue: ReportMoney.fromMajor(362500, currencyCode),
      createdOrderCount: 50,
      cancelledOrderCount: 3,
      completedSubtotalAmount: ReportMoney.fromMajor(14000000, currencyCode),
      completedDiscountAmount: ReportMoney.fromMajor(500000, currencyCode),
      completedTaxAmount: ReportMoney.fromMajor(700000, currencyCode),
      completedServiceChargeAmount: ReportMoney.fromMajor(300000, currencyCode),
    ),
  );
}

List<RevenueSeriesPoint> testRevenueSeries({String currencyCode = 'VND'}) {
  return [
    RevenueSeriesPoint(
      bucketStartDate: const ReportDate(2026, 10, 1),
      collectedAmount: ReportMoney.fromMajor(2000000, currencyCode),
      completedOrderSalesAmount: ReportMoney.fromMajor(1900000, currencyCode),
      successfulPaymentCount: 10,
      completedOrderCount: 8,
    ),
    RevenueSeriesPoint(
      bucketStartDate: const ReportDate(2026, 10, 2),
      collectedAmount: ReportMoney.fromMajor(3500000, currencyCode),
      completedOrderSalesAmount: ReportMoney.fromMajor(3200000, currencyCode),
      successfulPaymentCount: 15,
      completedOrderCount: 14,
    ),
  ];
}

List<PaymentMethodReportRow> testPaymentMethods({String currencyCode = 'VND'}) {
  return [
    PaymentMethodReportRow(
      paymentMethod: ReportPaymentMethod.cash,
      collectedAmount: ReportMoney.fromMajor(6000000, currencyCode),
      successfulPaymentCount: 20,
      percentage: 40.0,
    ),
    PaymentMethodReportRow(
      paymentMethod: ReportPaymentMethod.transfer,
      collectedAmount: ReportMoney.fromMajor(9000000, currencyCode),
      successfulPaymentCount: 25,
      percentage: 60.0,
    ),
  ];
}

ReportPage<TopItemReportRow> testTopItemsPage({String currencyCode = 'VND'}) {
  return ReportPage<TopItemReportRow>(
    content: [
      TopItemReportRow(
        itemId: 'item-1',
        itemName: 'Phở bò đặc biệt',
        unit: 'Tô',
        quantity: 120.0,
        itemSalesAmount: ReportMoney.fromMajor(7200000, currencyCode),
        completedOrderCount: 80,
      ),
      TopItemReportRow(
        itemId: 'item-2',
        itemName: 'Cà phê sữa đá',
        unit: 'Ly',
        quantity: 200.5,
        itemSalesAmount: ReportMoney.fromMajor(5012500, currencyCode),
        completedOrderCount: 95,
      ),
    ],
    page: 0,
    size: 20,
    totalElements: 2,
    totalPages: 1,
  );
}

ReportPage<ReportOrderRow> testReportOrdersPage({String currencyCode = 'VND'}) {
  return ReportPage<ReportOrderRow>(
    content: [
      ReportOrderRow(
        id: 'ord-101',
        orderCode: 'ORD-20261015-001',
        serviceType: ServiceType.dineIn,
        sourceChannel: ReportSourceChannel.waiter,
        status: OrderStatus.completed,
        paymentStatus: OrderPaymentStatus.paid,
        currencyCode: currencyCode,
        totalAmount: ReportMoney.fromMajor(350000, currencyCode),
        collectedAmountInRange: ReportMoney.fromMajor(350000, currencyCode),
        createdAt: DateTime(2026, 10, 15, 11, 30, 0),
        reportEventAt: DateTime(2026, 10, 15, 11, 45, 0),
      ),
      ReportOrderRow(
        id: 'ord-102',
        orderCode: 'ORD-20261015-002',
        serviceType: ServiceType.takeaway,
        sourceChannel: ReportSourceChannel.cashier,
        status: OrderStatus.completed,
        paymentStatus: OrderPaymentStatus.paid,
        currencyCode: currencyCode,
        totalAmount: ReportMoney.fromMajor(120000, currencyCode),
        collectedAmountInRange: ReportMoney.fromMajor(120000, currencyCode),
        createdAt: DateTime(2026, 10, 15, 12, 0, 0),
        reportEventAt: DateTime(2026, 10, 15, 12, 10, 0),
      ),
    ],
    page: 0,
    size: 20,
    totalElements: 2,
    totalPages: 1,
  );
}

class FakeReportRepository implements ReportRepository {
  Result<ReportEnvelope<ReportOverview>>? dailyReportResult;
  Result<ReportEnvelope<ReportOverview>>? reportSummaryResult;
  Result<ReportEnvelope<List<RevenueSeriesPoint>>>? revenueSeriesResult;
  Result<ReportEnvelope<List<PaymentMethodReportRow>>>? paymentMethodsResult;
  Result<ReportEnvelope<ReportPage<TopItemReportRow>>>? topItemsResult;
  Result<ReportEnvelope<ReportPage<ReportOrderRow>>>? reportOrdersResult;

  DailyReportFilter? lastDailyFilter;
  ReportRangeFilter? lastSummaryFilter;
  ReportRangeFilter? lastSeriesFilter;
  ReportGranularity? lastSeriesGranularity;
  ReportRangeFilter? lastPaymentsFilter;
  TopItemsFilter? lastTopItemsFilter;
  ReportOrdersFilter? lastOrdersFilter;

  int dailyCalls = 0;
  int summaryCalls = 0;
  int seriesCalls = 0;
  int paymentsCalls = 0;
  int topItemsCalls = 0;
  int ordersCalls = 0;

  @override
  Future<Result<ReportEnvelope<ReportOverview>>> getDailyReport(
    DailyReportFilter filter,
  ) async {
    dailyCalls++;
    lastDailyFilter = filter;
    return dailyReportResult ??
        Success(
          ReportEnvelope(meta: testReportMeta(), data: testReportOverview()),
        );
  }

  @override
  Future<Result<ReportEnvelope<ReportOverview>>> getReportSummary(
    ReportRangeFilter filter,
  ) async {
    summaryCalls++;
    lastSummaryFilter = filter;
    return reportSummaryResult ??
        Success(
          ReportEnvelope(
            meta: testReportMeta(
              fromDate: filter.range.fromDate,
              toDate: filter.range.toDate,
            ),
            data: testReportOverview(),
          ),
        );
  }

  @override
  Future<Result<ReportEnvelope<List<RevenueSeriesPoint>>>> getRevenueSeries(
    ReportRangeFilter filter, {
    ReportGranularity granularity = ReportGranularity.day,
  }) async {
    seriesCalls++;
    lastSeriesFilter = filter;
    lastSeriesGranularity = granularity;
    return revenueSeriesResult ??
        Success(
          ReportEnvelope(
            meta: testReportMeta(
              fromDate: filter.range.fromDate,
              toDate: filter.range.toDate,
              granularity: granularity,
            ),
            data: testRevenueSeries(),
          ),
        );
  }

  @override
  Future<Result<ReportEnvelope<List<PaymentMethodReportRow>>>>
  getPaymentMethods(ReportRangeFilter filter) async {
    paymentsCalls++;
    lastPaymentsFilter = filter;
    return paymentMethodsResult ??
        Success(
          ReportEnvelope(
            meta: testReportMeta(
              fromDate: filter.range.fromDate,
              toDate: filter.range.toDate,
            ),
            data: testPaymentMethods(),
          ),
        );
  }

  @override
  Future<Result<ReportEnvelope<ReportPage<TopItemReportRow>>>> getTopItems(
    TopItemsFilter filter,
  ) async {
    topItemsCalls++;
    lastTopItemsFilter = filter;
    return topItemsResult ??
        Success(
          ReportEnvelope(
            meta: testReportMeta(
              fromDate: filter.range.fromDate,
              toDate: filter.range.toDate,
            ),
            data: testTopItemsPage(),
          ),
        );
  }

  @override
  Future<Result<ReportEnvelope<ReportPage<ReportOrderRow>>>> getReportOrders(
    ReportOrdersFilter filter,
  ) async {
    ordersCalls++;
    lastOrdersFilter = filter;
    return reportOrdersResult ??
        Success(
          ReportEnvelope(
            meta: testReportMeta(
              fromDate: filter.range.fromDate,
              toDate: filter.range.toDate,
              dateBasis: filter.dateBasis,
            ),
            data: testReportOrdersPage(),
          ),
        );
  }
}
