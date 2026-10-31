import '../../../../core/network/exact_json.dart';
import '../../../reports/domain/entities/report_date.dart';
import '../../../reports/domain/entities/report_money.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../../domain/entities/cashbook_enums.dart';
import '../../domain/entities/cashbook_meta.dart';
import '../../domain/entities/cashbook_records.dart';

/// Money ledgers are parsed strictly: a malformed or rounded amount is a
/// failed read, never a silent zero. Decimals are decoded before doubles.
abstract final class CashbookDto {
  static List<CashbookCategory> categories(Object? raw) {
    if (raw is! List) throw const FormatException('Expected category list');
    return List.unmodifiable(
      raw.map((value) {
        final j = _object(value);
        if (j['active'] is! bool) throw const FormatException('Invalid active');
        return CashbookCategory(
          id: _text(j, 'id'),
          code: _text(j, 'code'),
          name: _text(j, 'name'),
          type: _enum(j['type'], CashbookEntryType.values, (e) => e.apiCode),
          active: j['active'] as bool,
        );
      }),
    );
  }

  static CashbookEnvelope<ReportPage<CashbookEntry>> entries(Object? raw) =>
      _envelope(raw, 'CASH_OCCURRED_AT', (data) => _page(data, entry));

  static CashbookEnvelope<CashbookSummary> summary(Object? raw) =>
      _envelope(raw, 'CASH_OCCURRED_AT', (data) {
        final j = _object(data);
        return CashbookSummary(
          totalIncomeAmount: _money(j, 'totalIncomeAmount'),
          totalExpenseAmount: _money(j, 'totalExpenseAmount'),
          netCashFlowAmount: _money(j, 'netCashFlowAmount'),
          incomeEntryCount: _integer(j, 'incomeEntryCount'),
          expenseEntryCount: _integer(j, 'expenseEntryCount'),
          saleIncomeAmount: _money(j, 'saleIncomeAmount'),
          receiptLinkedExpenseAmount: _money(j, 'receiptLinkedExpenseAmount'),
          otherExpenseAmount: _money(j, 'otherExpenseAmount'),
        );
      });

  static CashbookEnvelope<List<CashbookSeriesPoint>> series(
    Object? raw,
    CashbookGranularity granularity,
  ) {
    final result = _envelope(raw, 'CASH_OCCURRED_AT', (data) {
      if (data is! List) throw const FormatException('Expected series');
      ReportDate? previous;
      return List<CashbookSeriesPoint>.unmodifiable(
        data.map((value) {
          final j = _object(value);
          final date = ReportDate.parse(_text(j, 'bucketStartDate'));
          if (previous != null && date <= previous! ||
              granularity == CashbookGranularity.month && date.day != 1) {
            throw const FormatException('Invalid cashbook bucket');
          }
          previous = date;
          return CashbookSeriesPoint(
            bucketStartDate: date,
            totalIncomeAmount: _money(j, 'totalIncomeAmount'),
            totalExpenseAmount: _money(j, 'totalExpenseAmount'),
            netCashFlowAmount: _money(j, 'netCashFlowAmount'),
            incomeEntryCount: _integer(j, 'incomeEntryCount'),
            expenseEntryCount: _integer(j, 'expenseEntryCount'),
          );
        }),
      );
    });
    if (result.meta.granularity != granularity) {
      throw const FormatException('Wrong cashbook granularity');
    }
    return result;
  }

  static CashbookEnvelope<ReportPage<CashbookExpense>> expenses(Object? raw) =>
      _envelope(raw, 'EXPENSE_AT', (data) => _page(data, expense));

  static CashbookEnvelope<ReportPage<CashbookStockReceipt>> receipts(
    Object? raw,
  ) => _envelope(raw, 'CONFIRMED_AT', (data) => _page(data, receipt));

  static CashbookEntry entry(Object? raw) {
    final j = _object(raw);
    return CashbookEntry(
      sourceType: _enum(
        j['sourceType'],
        CashbookSourceType.values,
        (e) => e.apiCode,
      ),
      sourceId: _text(j, 'sourceId'),
      code: _text(j, 'code'),
      type: _enum(j['type'], CashbookEntryType.values, (e) => e.apiCode),
      categoryCode: _text(j, 'categoryCode'),
      categoryName: _text(j, 'categoryName'),
      amount: _money(j, 'amount'),
      currencyCode: _currency(j, 'currencyCode'),
      paymentMethod: _optionalEnum(
        j['paymentMethod'],
        CashbookPaymentMethod.values,
        (e) => e.apiCode,
      ),
      occurredAt: _instant(j, 'occurredAt'),
      recordedAt: _instant(j, 'recordedAt'),
      createdBy: _optionalText(j, 'createdBy'),
      orderId: _optionalText(j, 'orderId'),
      orderCode: _optionalText(j, 'orderCode'),
      stockDocumentId: _optionalText(j, 'stockDocumentId'),
      sourceDocumentCode: _optionalText(j, 'sourceDocumentCode'),
    );
  }

  static CashbookExpense expense(Object? raw) {
    final j = _object(raw);
    final amount = _money(j, 'amount');
    if (!amount.isPositive) throw const FormatException('Invalid amount');
    return CashbookExpense(
      id: _text(j, 'id'),
      expenseCode: _text(j, 'expenseCode'),
      categoryCode: _text(j, 'categoryCode'),
      categoryName: _text(j, 'categoryName'),
      amount: amount,
      currencyCode: _currency(j, 'currencyCode'),
      paymentMethod: _enum(
        j['paymentMethod'],
        CashbookPaymentMethod.values,
        (e) => e.apiCode,
      ),
      expenseAt: _instant(j, 'expenseAt'),
      status: _enum(
        j['status'],
        CashbookExpenseStatus.values,
        (e) => e.apiCode,
      ),
      createdAt: _instant(j, 'createdAt'),
      updatedAt: _instant(j, 'updatedAt'),
      version: _integer(j, 'version'),
      stockDocumentId: _optionalText(j, 'stockDocumentId'),
      sourceDocumentCode: _optionalText(j, 'sourceDocumentCode'),
      sourceCurrencyStatus: _optionalEnum(
        j['sourceCurrencyStatus'],
        CashbookCurrencyStatus.values,
        (e) => e.apiCode,
      ),
      referenceNo: _optionalText(j, 'referenceNo'),
      payeeName: _optionalText(j, 'payeeName'),
      note: _optionalText(j, 'note'),
      createdBy: _optionalText(j, 'createdBy'),
      voidedBy: _optionalText(j, 'voidedBy'),
      voidedAt: j['voidedAt'] == null ? null : _instant(j, 'voidedAt'),
      voidReason: _optionalText(j, 'voidReason'),
    );
  }

  static CashbookStockReceipt receipt(Object? raw) {
    final j = _object(raw);
    final status = _enum(
      j['currencyStatus'],
      CashbookCurrencyStatus.values,
      (e) => e.apiCode,
    );
    final currency = j['currencyCode'] == null
        ? null
        : _currency(j, 'currencyCode');
    final recorded = j['recordedExpenseAmountAllTime'] == null
        ? null
        : _money(j, 'recordedExpenseAmountAllTime');
    if (status == CashbookCurrencyStatus.unknown &&
            (currency != null || recorded != null) ||
        status == CashbookCurrencyStatus.known &&
            (currency == null || recorded == null)) {
      throw const FormatException('Inconsistent receipt currency');
    }
    return CashbookStockReceipt(
      stockDocumentId: _text(j, 'stockDocumentId'),
      documentCode: _text(j, 'documentCode'),
      warehouseId: _text(j, 'warehouseId'),
      warehouseName: _text(j, 'warehouseName'),
      confirmedAt: _instant(j, 'confirmedAt'),
      totalCost: _money(j, 'totalCost'),
      currencyCode: currency,
      currencyStatus: status,
      linkedPostedExpenseCount: _integer(j, 'linkedPostedExpenseCount'),
      recordedExpenseAmountAllTime: recorded,
    );
  }

  static CashbookEnvelope<T> _envelope<T>(
    Object? raw,
    String dateBasis,
    T Function(Object? data) read,
  ) {
    final envelope = _object(raw);
    final j = _object(envelope['meta']);
    final from = ReportDate.parse(_text(j, 'fromDate'));
    final to = ReportDate.parse(_text(j, 'toDate'));
    if (from > to || j['dateBasis'] != dateBasis) {
      throw const FormatException('Wrong cashbook metadata');
    }
    final meta = CashbookMeta(
      fromDate: from,
      toDate: to,
      timezone: _text(j, 'timezone'),
      currencyCode: _currency(j, 'currencyCode'),
      dateBasis: dateBasis,
      generatedAt: _instant(j, 'generatedAt'),
      granularity: _optionalEnum(
        j['granularity'],
        CashbookGranularity.values,
        (e) => e.apiCode,
      ),
    );
    return CashbookEnvelope(meta: meta, data: read(envelope['data']));
  }

  static ReportPage<T> _page<T>(Object? raw, T Function(Object?) read) {
    final j = _object(raw);
    final page = _integer(j, 'page'), size = _integer(j, 'size');
    final total = _integer(j, 'totalElements');
    final pages = _integer(j, 'totalPages');
    final content = _list(j, 'content').map(read).toList();
    if (size < 1 || content.length > size) {
      throw const FormatException('Invalid cashbook page');
    }
    return ReportPage(
      content: List.unmodifiable(content),
      page: page,
      size: size,
      totalElements: total,
      totalPages: pages,
    );
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected cashbook object');
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

  static String? _optionalText(Map<String, dynamic> j, String key) {
    final raw = j[key];
    if (raw == null) return null;
    if (raw is! String) throw FormatException('Invalid $key');
    return raw.trim().isEmpty ? null : raw;
  }

  static String _currency(Map<String, dynamic> j, String key) {
    final value = _text(j, key);
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(value)) {
      throw FormatException('Invalid $key');
    }
    return value;
  }

  static List<dynamic> _list(Map<String, dynamic> j, String key) {
    final raw = j[key];
    if (raw is! List) throw FormatException('Invalid $key');
    return raw;
  }

  static T _enum<T>(Object? raw, Iterable<T> values, String Function(T) code) =>
      values.where((e) => code(e) == raw).firstOrNull ??
      (throw const FormatException('Unsupported cashbook enum'));

  static T? _optionalEnum<T>(
    Object? raw,
    Iterable<T> values,
    String Function(T) code,
  ) => raw == null ? null : _enum<T>(raw, values, code);

  static DateTime _instant(Map<String, dynamic> j, String key) {
    final raw = _text(j, key);
    if (!RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$',
    ).hasMatch(raw)) {
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
      throw const FormatException('Invalid cashbook decimal');
    }
    final fraction = match[3] ?? '';
    final exponent = int.tryParse(match[4] ?? '0');
    if (exponent == null || exponent.abs() > 200) {
      throw const FormatException('Invalid cashbook exponent');
    }
    var magnitude = BigInt.parse('${match[2]}$fraction');
    final shift = exponent + scale - fraction.length;
    if (shift >= 0) {
      magnitude *= BigInt.from(10).pow(shift);
    } else {
      final divisor = BigInt.from(10).pow(-shift);
      if (magnitude % divisor != BigInt.zero) {
        throw const FormatException('Unexpected cashbook precision');
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
}
