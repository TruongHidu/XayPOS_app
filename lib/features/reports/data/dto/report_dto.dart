import '../../../order/domain/entities/order_entities.dart'
    show OrderPaymentStatus, OrderStatus, ServiceType;
import '../../domain/entities/payment_method_report_row.dart';
import '../../domain/entities/report_date.dart';
import '../../domain/entities/report_enums.dart';
import '../../domain/entities/report_meta.dart';
import '../../domain/entities/report_money.dart';
import '../../domain/entities/report_order_row.dart';
import '../../domain/entities/report_overview.dart';
import '../../domain/entities/report_page.dart';
import '../../domain/entities/revenue_series_point.dart';
import '../../domain/entities/top_item_report_row.dart';

abstract final class ReportDto {
  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    throw const FormatException('Expected JSON object in report response');
  }

  static ReportMeta parseMeta(Object? value) {
    final json = _asMap(value);

    final fromDateStr = json['fromDate'] as String?;
    final toDateStr = json['toDate'] as String?;
    final timezone = json['timezone'] as String?;
    final currencyCode = json['currencyCode'] as String?;
    final generatedAtStr = json['generatedAt'] as String?;

    if (fromDateStr == null ||
        toDateStr == null ||
        timezone == null ||
        currencyCode == null) {
      throw const FormatException('Missing required fields in report meta');
    }

    final fromDate = ReportDate.parse(fromDateStr);
    final toDate = ReportDate.parse(toDateStr);
    final generatedAt = generatedAtStr != null
        ? (DateTime.tryParse(generatedAtStr) ?? DateTime.now())
        : DateTime.now();

    ServiceType? serviceType;
    final st = json['serviceType'] as String?;
    if (st != null && st.isNotEmpty) {
      serviceType = ServiceType.values.where((v) => v.code == st).firstOrNull;
    }

    final sourceChannel = ReportSourceChannel.fromCode(
      json['sourceChannel'] as String?,
    );

    ReportGranularity? granularity;
    final gran = json['granularity'] as String?;
    if (gran != null && gran.isNotEmpty) {
      granularity = ReportGranularity.fromCode(gran);
    }

    ReportDateBasis? dateBasis;
    final db = json['dateBasis'] as String?;
    if (db != null && db.isNotEmpty) {
      dateBasis = ReportDateBasis.fromCode(db);
    }

    return ReportMeta(
      fromDate: fromDate,
      toDate: toDate,
      timezone: timezone,
      currencyCode: currencyCode,
      generatedAt: generatedAt,
      serviceType: serviceType,
      sourceChannel: sourceChannel,
      granularity: granularity,
      dateBasis: dateBasis,
    );
  }

  static ReportEnvelope<ReportOverview> parseOverviewEnvelope(Object? json) {
    final root = _asMap(json);
    final meta = parseMeta(root['meta']);
    final data = _asMap(root['data']);

    final c = _asMap(data['collections']);
    final o = _asMap(data['orders']);

    final collections = ReportCollectionsSummary(
      collectedAmount: ReportMoney.parse(c['collectedAmount']),
      successfulPaymentCount:
          (c['successfulPaymentCount'] as num?)?.toInt() ?? 0,
      paidOrderCount: (c['paidOrderCount'] as num?)?.toInt() ?? 0,
    );

    final orders = ReportOrdersSummary(
      createdOrderCount: (o['createdOrderCount'] as num?)?.toInt() ?? 0,
      completedOrderCount: (o['completedOrderCount'] as num?)?.toInt() ?? 0,
      cancelledOrderCount: (o['cancelledOrderCount'] as num?)?.toInt() ?? 0,
      completedSubtotalAmount: ReportMoney.parse(o['completedSubtotalAmount']),
      completedDiscountAmount: ReportMoney.parse(o['completedDiscountAmount']),
      completedTaxAmount: ReportMoney.parse(o['completedTaxAmount']),
      completedServiceChargeAmount: ReportMoney.parse(
        o['completedServiceChargeAmount'],
      ),
      completedOrderSalesAmount: ReportMoney.parse(
        o['completedOrderSalesAmount'],
      ),
      averageCompletedOrderValue: ReportMoney.parse(
        o['averageCompletedOrderValue'],
      ),
    );

    return ReportEnvelope(
      meta: meta,
      data: ReportOverview(collections: collections, orders: orders),
    );
  }

  static ReportEnvelope<List<RevenueSeriesPoint>> parseRevenueSeriesEnvelope(
    Object? json,
  ) {
    final root = _asMap(json);
    final meta = parseMeta(root['meta']);
    final dataRaw = root['data'];

    if (dataRaw is! List) {
      throw const FormatException('Expected list in revenue series data');
    }

    final points = <RevenueSeriesPoint>[];
    for (final itemRaw in dataRaw) {
      final item = _asMap(itemRaw);
      points.add(
        RevenueSeriesPoint(
          bucketStartDate: ReportDate.parse(item['bucketStartDate'] as String),
          collectedAmount: ReportMoney.parse(item['collectedAmount']),
          completedOrderSalesAmount: ReportMoney.parse(
            item['completedOrderSalesAmount'],
          ),
          successfulPaymentCount:
              (item['successfulPaymentCount'] as num?)?.toInt() ?? 0,
          completedOrderCount:
              (item['completedOrderCount'] as num?)?.toInt() ?? 0,
        ),
      );
    }

    return ReportEnvelope(meta: meta, data: points);
  }

  static ReportEnvelope<List<PaymentMethodReportRow>>
  parsePaymentMethodsEnvelope(Object? json) {
    final root = _asMap(json);
    final meta = parseMeta(root['meta']);
    final dataRaw = root['data'];

    if (dataRaw is! List) {
      throw const FormatException('Expected list in payment methods data');
    }

    final rows = <PaymentMethodReportRow>[];
    for (final itemRaw in dataRaw) {
      final item = _asMap(itemRaw);
      rows.add(
        PaymentMethodReportRow(
          paymentMethod: ReportPaymentMethod.fromCode(
            item['paymentMethod'] as String?,
          ),
          collectedAmount: ReportMoney.parse(item['collectedAmount']),
          successfulPaymentCount:
              (item['successfulPaymentCount'] as num?)?.toInt() ?? 0,
          percentage: (item['percentage'] as num?)?.toDouble() ?? 0.0,
        ),
      );
    }

    return ReportEnvelope(meta: meta, data: rows);
  }

  static ReportEnvelope<ReportPage<TopItemReportRow>> parseTopItemsEnvelope(
    Object? json,
  ) {
    final root = _asMap(json);
    final meta = parseMeta(root['meta']);
    final data = _asMap(root['data']);

    final contentRaw = data['content'];
    final items = <TopItemReportRow>[];
    if (contentRaw is List) {
      for (final itemRaw in contentRaw) {
        final item = _asMap(itemRaw);
        items.add(
          TopItemReportRow(
            itemId: item['itemId'] as String?,
            itemName:
                (item['itemName'] ?? item['snapshotItemName']) as String? ?? '',
            unit: item['unit'] as String? ?? '',
            quantity: (item['quantity'] as num?)?.toDouble() ?? 0.0,
            itemSalesAmount: ReportMoney.parse(item['itemSalesAmount']),
            completedOrderCount:
                (item['completedOrderCount'] as num?)?.toInt() ?? 0,
          ),
        );
      }
    }

    final page = ReportPage<TopItemReportRow>(
      content: items,
      page: (data['page'] as num?)?.toInt() ?? 0,
      size: (data['size'] as num?)?.toInt() ?? 20,
      totalElements: (data['totalElements'] as num?)?.toInt() ?? 0,
      totalPages: (data['totalPages'] as num?)?.toInt() ?? 0,
    );

    return ReportEnvelope(meta: meta, data: page);
  }

  static ReportEnvelope<ReportPage<ReportOrderRow>> parseOrdersEnvelope(
    Object? json,
  ) {
    final root = _asMap(json);
    final meta = parseMeta(root['meta']);
    final data = _asMap(root['data']);

    final contentRaw = data['content'];
    final items = <ReportOrderRow>[];
    if (contentRaw is List) {
      for (final itemRaw in contentRaw) {
        final item = _asMap(itemRaw);

        final stCode = item['serviceType'] as String?;
        final serviceType =
            ServiceType.values.where((v) => v.code == stCode).firstOrNull ??
            ServiceType.dineIn;

        final sourceChannel =
            ReportSourceChannel.fromCode(item['sourceChannel'] as String?) ??
            ReportSourceChannel.cashier;

        final statusCode = item['status'] as String?;
        final status =
            OrderStatus.values.where((v) => v.code == statusCode).firstOrNull ??
            OrderStatus.open;

        final payCode = item['paymentStatus'] as String?;
        final paymentStatus =
            OrderPaymentStatus.values
                .where((v) => v.code == payCode)
                .firstOrNull ??
            OrderPaymentStatus.unpaid;

        final createdAtStr = item['createdAt'] as String?;
        final reportEventAtStr = item['reportEventAt'] as String?;

        items.add(
          ReportOrderRow(
            id: (item['id'] ?? item['orderId']) as String? ?? '',
            orderCode: item['orderCode'] as String? ?? '',
            serviceType: serviceType,
            sourceChannel: sourceChannel,
            status: status,
            paymentStatus: paymentStatus,
            currencyCode: item['currencyCode'] as String? ?? meta.currencyCode,
            totalAmount: ReportMoney.parse(item['totalAmount']),
            collectedAmountInRange: ReportMoney.parse(
              item['collectedAmountInRange'],
            ),
            createdAt: createdAtStr != null
                ? DateTime.parse(createdAtStr)
                : (reportEventAtStr != null
                      ? DateTime.parse(reportEventAtStr)
                      : DateTime.now()),
            completedAt: item['completedAt'] != null
                ? DateTime.parse(item['completedAt'] as String)
                : null,
            cancelledAt: item['cancelledAt'] != null
                ? DateTime.parse(item['cancelledAt'] as String)
                : null,
            reportEventAt: reportEventAtStr != null
                ? DateTime.parse(reportEventAtStr)
                : (createdAtStr != null
                      ? DateTime.parse(createdAtStr)
                      : DateTime.now()),
          ),
        );
      }
    }

    final page = ReportPage<ReportOrderRow>(
      content: items,
      page: (data['page'] as num?)?.toInt() ?? 0,
      size: (data['size'] as num?)?.toInt() ?? 20,
      totalElements: (data['totalElements'] as num?)?.toInt() ?? 0,
      totalPages: (data['totalPages'] as num?)?.toInt() ?? 0,
    );

    return ReportEnvelope(meta: meta, data: page);
  }
}
