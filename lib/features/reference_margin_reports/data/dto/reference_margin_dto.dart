import '../../../../core/network/exact_json.dart';
import '../../../order/domain/entities/order_entities.dart' show ServiceType;
import '../../../reports/domain/entities/report_date.dart';
import '../../../reports/domain/entities/report_enums.dart';
import '../../../reports/domain/entities/report_meta.dart';
import '../../../reports/domain/entities/report_money.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../../domain/entities/reference_margin_enums.dart';
import '../../domain/entities/reference_margin_filters.dart';
import '../../domain/entities/reference_margin_report.dart';

/// Private report reads are strict: absent, malformed and excluded costs never
/// silently become a numeric zero. Decimal tokens are decoded before doubles.
abstract final class ReferenceMarginDto {
  static ReportEnvelope<ReferenceMarginSummary> summary(
    Object? raw,
    ReferenceMarginFilter filter,
  ) {
    final envelope = _object(raw);
    return ReportEnvelope(
      meta: _meta(envelope['meta'], filter),
      data: summaryValue(envelope['data']),
    );
  }

  static ReportEnvelope<List<ReferenceMarginSeriesPoint>> series(
    Object? raw,
    ReferenceMarginFilter filter,
    ReportGranularity granularity,
  ) {
    final envelope = _object(raw);
    final meta = _meta(envelope['meta'], filter, granularity: granularity);
    final rows = _list(envelope, 'data');
    final result = <ReferenceMarginSeriesPoint>[];
    ReportDate? previous;
    for (final raw in rows) {
      final row = _object(raw);
      final date = ReportDate.parse(_text(row, 'bucketStartDate'));
      final first = granularity == ReportGranularity.month
          ? ReportDate(
              filter.range.fromDate.year,
              filter.range.fromDate.month,
              1,
            )
          : filter.range.fromDate;
      if (date < first ||
          date > filter.range.toDate ||
          previous != null && date <= previous ||
          granularity == ReportGranularity.month && date.day != 1) {
        throw const FormatException('Invalid reference margin bucket');
      }
      previous = date;
      // JsonUnwrapped: summary metrics sit next to bucketStartDate on the wire.
      result.add(
        ReferenceMarginSeriesPoint(
          bucketStartDate: date,
          metrics: summaryValue(row),
        ),
      );
    }
    return ReportEnvelope(meta: meta, data: List.unmodifiable(result));
  }

  static ReportEnvelope<ReportPage<ReferenceMarginOrderRow>> orders(
    Object? raw,
    ReferenceMarginOrdersFilter filter,
  ) {
    final envelope = _object(raw);
    final meta = _meta(envelope['meta'], filter.filter);
    final page = _object(envelope['data']);
    final index = _integer(page, 'page'), size = _integer(page, 'size');
    final total = _integer(page, 'totalElements'),
        pages = _integer(page, 'totalPages');
    final content = _list(page, 'content').map(orderValue).toList();
    if (index != filter.page ||
        size != filter.size ||
        size < 1 ||
        size > 100 ||
        content.length > size ||
        pages != (total == 0 ? 0 : 1 + (total - 1) ~/ size) ||
        content.map((e) => e.orderId).toSet().length != content.length ||
        total == 0 && content.isNotEmpty ||
        index >= pages && content.isNotEmpty) {
      throw const FormatException('Invalid reference margin page');
    }
    if (filter.costCoverage == CostCoverageFilter.complete &&
            content.any(
              (e) => e.costCoverageStatus != CostCoverageStatus.complete,
            ) ||
        filter.costCoverage == CostCoverageFilter.excluded &&
            content.any(
              (e) => e.costCoverageStatus == CostCoverageStatus.complete,
            )) {
      throw const FormatException('Wrong cost coverage page');
    }
    return ReportEnvelope(
      meta: meta,
      data: ReportPage(
        content: List.unmodifiable(content),
        page: index,
        size: size,
        totalElements: total,
        totalPages: pages,
      ),
    );
  }

  static ReferenceMarginSummary summaryValue(Object? raw) {
    final j = _object(raw);
    final total = _integer(j, 'completedOrderCount');
    final covered = _integer(j, 'fullyCostedOrderCount');
    final excluded = _integer(j, 'excludedOrderCount');
    final coverage = _enum(
      j['costCoverageStatus'],
      CostCoverageStatus.values,
      (e) => e.code,
    );
    final basis = _text(j, 'costBasis'), scope = _text(j, 'marginScope');
    if (basis != 'CATALOG_REFERENCE_AT_ACCEPTANCE' ||
        scope != 'FULLY_COSTED_COMPLETED_ORDERS' ||
        covered > total ||
        excluded != total - covered ||
        coverage !=
            (total == 0
                ? CostCoverageStatus.noData
                : covered == total
                ? CostCoverageStatus.complete
                : covered == 0
                ? CostCoverageStatus.unavailable
                : CostCoverageStatus.partial)) {
      throw const FormatException('Invalid reference margin coverage');
    }
    return ReferenceMarginSummary(
      costBasis: basis,
      marginScope: scope,
      costCoverageStatus: coverage,
      completedOrderCount: total,
      fullyCostedOrderCount: covered,
      excludedOrderCount: excluded,
      orderCoveragePercent: _percent(j, 'orderCoveragePercent'),
      subtotalAmount: _money(j, 'subtotalAmount'),
      discountAmount: _money(j, 'discountAmount'),
      taxAmount: _money(j, 'taxAmount'),
      serviceChargeAmount: _money(j, 'serviceChargeAmount'),
      salesAmount: _money(j, 'salesAmount'),
      netSalesAmount: _money(j, 'netSalesAmount'),
      coveredNetSalesAmount: _money(j, 'coveredNetSalesAmount'),
      coveredReferenceCostAmount: _money(j, 'coveredReferenceCostAmount'),
      coveredReferenceMarginAmount: _money(j, 'coveredReferenceMarginAmount'),
      coveredReferenceMarginPercent: _percent(
        j,
        'coveredReferenceMarginPercent',
      ),
      costIssues: _issues(j),
    );
  }

  static ReferenceMarginOrderRow orderValue(Object? raw) {
    final j = _object(raw);
    final cost = _nullableMoney(j, 'referenceCostAmount');
    final margin = _nullableMoney(j, 'referenceMarginAmount');
    final percent = _percent(j, 'referenceMarginPercent');
    final coverage = _enum(
      j['costCoverageStatus'],
      CostCoverageStatus.values,
      (e) => e.code,
    );
    final eligible = _integer(j, 'eligibleItemCount'),
        covered = _integer(j, 'fullyCostedItemCount');
    if (covered > eligible ||
        coverage == CostCoverageStatus.noData ||
        (coverage == CostCoverageStatus.complete
            ? cost == null ||
                  margin == null ||
                  eligible == 0 ||
                  eligible != covered
            : cost != null || margin != null || percent != null)) {
      throw const FormatException('Invalid order cost coverage');
    }
    return ReferenceMarginOrderRow(
      orderId: _text(j, 'orderId'),
      orderCode: _text(j, 'orderCode'),
      completedAt: _instant(j, 'completedAt'),
      serviceType: _enum(j['serviceType'], ServiceType.values, (e) => e.code),
      sourceChannel: _enum(
        j['sourceChannel'],
        ReportSourceChannel.values,
        (e) => e.apiCode,
      ),
      subtotalAmount: _money(j, 'subtotalAmount'),
      discountAmount: _money(j, 'discountAmount'),
      taxAmount: _money(j, 'taxAmount'),
      serviceChargeAmount: _money(j, 'serviceChargeAmount'),
      salesAmount: _money(j, 'salesAmount'),
      netSalesAmount: _money(j, 'netSalesAmount'),
      eligibleItemCount: eligible,
      fullyCostedItemCount: covered,
      costCoverageStatus: coverage,
      costIssues: _issues(j),
      referenceCostAmount: cost,
      referenceMarginAmount: margin,
      referenceMarginPercent: percent,
    );
  }

  static ReportMeta _meta(
    Object? raw,
    ReferenceMarginFilter filter, {
    ReportGranularity? granularity,
  }) {
    final j = _object(raw);
    final from = ReportDate.parse(_text(j, 'fromDate')),
        to = ReportDate.parse(_text(j, 'toDate'));
    final currency = _text(j, 'currencyCode');
    final type = j['serviceType'] == null
        ? null
        : _enum(j['serviceType'], ServiceType.values, (e) => e.code);
    final channel = j['sourceChannel'] == null
        ? null
        : _enum(
            j['sourceChannel'],
            ReportSourceChannel.values,
            (e) => e.apiCode,
          );
    final grain = j['granularity'] == null
        ? null
        : _enum(j['granularity'], ReportGranularity.values, (e) => e.apiCode);
    if (from != filter.range.fromDate ||
        to != filter.range.toDate ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        filter.currencyCode != null &&
            currency != filter.currencyCode!.trim().toUpperCase() ||
        type != filter.serviceType ||
        channel != filter.sourceChannel ||
        grain != granularity ||
        j['dateBasis'] != 'COMPLETED') {
      throw const FormatException('Wrong reference margin query metadata');
    }
    return ReportMeta(
      fromDate: from,
      toDate: to,
      timezone: _text(j, 'timezone'),
      currencyCode: currency,
      generatedAt: _instant(j, 'generatedAt'),
      serviceType: type,
      sourceChannel: channel,
      granularity: grain,
      dateBasis: ReportDateBasis.completed,
    );
  }

  static List<ReferenceMarginIssue> _issues(Map<String, dynamic> j) =>
      List.unmodifiable(
        _list(j, 'costIssues').map((raw) {
          final row = _object(raw);
          return ReferenceMarginIssue(
            code: _text(row, 'code'),
            orderCount: _integer(row, 'orderCount'),
            itemCount: _integer(row, 'itemCount'),
          );
        }),
      );

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected reference margin object');
    }
    return value;
  }

  static String _text(Map<String, dynamic> j, String key) {
    final raw = j[key];
    if (raw is! String || raw.trim().isEmpty) {
      throw FormatException('Invalid $key');
    }
    return raw;
  }

  static List<dynamic> _list(Map<String, dynamic> j, String key) {
    final raw = j[key];
    if (raw is! List) {
      throw FormatException('Invalid $key');
    }
    return raw;
  }

  static T _enum<T>(Object? raw, Iterable<T> values, String Function(T) code) =>
      values.where((e) => code(e) == raw).firstOrNull ??
      (throw const FormatException('Unsupported report enum'));

  static DateTime _instant(Map<String, dynamic> j, String key) {
    final raw = _text(j, key);
    if (!RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$',
    ).hasMatch(raw)) {
      throw FormatException('Invalid $key');
    }
    ReportDate.parse(raw.substring(0, 10));
    if (int.parse(raw.substring(11, 13)) > 23 ||
        int.parse(raw.substring(14, 16)) > 59 ||
        int.parse(raw.substring(17, 19)) > 59) {
      throw FormatException('Invalid $key');
    }
    return DateTime.parse(raw);
  }

  static BigInt _scaled(Object? raw, int scale) {
    final text = exactJsonNumberText(raw);
    final match = RegExp(
      r'^(-?)(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$',
    ).firstMatch(text);
    if (match == null || text.length > 300) {
      throw const FormatException('Invalid report decimal');
    }
    final fraction = match[3] ?? '';
    final exponent = int.tryParse(match[4] ?? '0');
    if (exponent == null || exponent.abs() > 200) {
      throw const FormatException('Invalid report exponent');
    }
    var magnitude = BigInt.parse('${match[2]}$fraction');
    final shift = exponent + scale - fraction.length;
    if (shift >= 0) {
      magnitude *= BigInt.from(10).pow(shift);
    } else {
      final divisor = BigInt.from(10).pow(-shift);
      if (magnitude % divisor != BigInt.zero) {
        throw const FormatException('Unexpected report precision');
      }
      magnitude ~/= divisor;
    }
    return match[1] == '-' ? -magnitude : magnitude;
  }

  static int _integer(Map<String, dynamic> j, String key) {
    final value = _scaled(j[key], 0);
    if (value < BigInt.zero || value > BigInt.parse('9007199254740991')) {
      throw FormatException('Invalid $key');
    }
    return value.toInt();
  }

  static ReportMoney _money(Map<String, dynamic> j, String key) =>
      ReportMoney(_scaled(j[key], 2));
  static ReportMoney? _nullableMoney(Map<String, dynamic> j, String key) {
    if (!j.containsKey(key)) {
      throw FormatException('Missing $key');
    }
    return j[key] == null ? null : _money(j, key);
  }

  static ReferenceMarginPercent? _percent(Map<String, dynamic> j, String key) {
    if (!j.containsKey(key)) {
      throw FormatException('Missing $key');
    }
    return j[key] == null ? null : ReferenceMarginPercent(_scaled(j[key], 2));
  }
}
