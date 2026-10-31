import '../../domain/entities/cashbook_enums.dart';
import '../../domain/entities/cashbook_filters.dart';
import '../../domain/entities/cashbook_inputs.dart';

/// Query and body builders. Optional criteria are omitted, never sent empty.
abstract final class CashbookRequests {
  static Map<String, Object> range(CashbookRangeFilter range) => {
    'fromDate': range.range.fromDate.toIso8601Date(),
    'toDate': range.range.toDate.toIso8601Date(),
    if (range.currencyCode != null) 'currencyCode': range.currencyCode!,
  };

  /// The criteria shared by entries, summary and series.
  static Map<String, Object> flow(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
  ) => {
    ...CashbookRequests.range(range),
    if (filter.type != null) 'type': filter.type!.apiCode,
    if (filter.sourceType != null) 'sourceType': filter.sourceType!.apiCode,
    if (filter.categoryCode != null) 'categoryCode': filter.categoryCode!,
    if (filter.paymentMethod != null)
      'paymentMethod': filter.paymentMethod!.apiCode,
    if (_text(filter.q) != null) 'q': _text(filter.q)!,
  };

  static Map<String, Object> entries(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
  ) => {
    ...flow(range, filter),
    'page': filter.page,
    'size': filter.size,
    'sortBy': filter.sortBy.apiCode,
    'direction': filter.direction.apiCode,
  };

  static Map<String, Object> series(
    CashbookRangeFilter range,
    CashbookEntryFilter filter,
    CashbookGranularity granularity,
  ) => {...flow(range, filter), 'granularity': granularity.apiCode};

  static Map<String, Object> expenses(
    CashbookRangeFilter range,
    CashbookExpenseFilter filter,
  ) => {
    ...CashbookRequests.range(range),
    if (filter.status != null) 'status': filter.status!.apiCode,
    if (filter.categoryCode != null) 'categoryCode': filter.categoryCode!,
    if (filter.paymentMethod != null)
      'paymentMethod': filter.paymentMethod!.apiCode,
    if (filter.stockDocumentId != null)
      'stockDocumentId': filter.stockDocumentId!,
    if (_text(filter.q) != null) 'q': _text(filter.q)!,
    'page': filter.page,
    'size': filter.size,
    'sortBy': filter.sortBy.apiCode,
    'direction': filter.direction.apiCode,
  };

  static Map<String, Object> receipts(
    CashbookRangeFilter range,
    CashbookReceiptFilter filter,
  ) => {
    ...CashbookRequests.range(range),
    'includeUnknownCurrency': filter.includeUnknownCurrency,
    if (_text(filter.q) != null) 'q': _text(filter.q)!,
    'page': filter.page,
    'size': filter.size,
    'sortBy': filter.sortBy.apiCode,
    'direction': filter.direction.apiCode,
  };

  static Map<String, Object?> create(CreateExpenseInput input) => {
    'categoryCode': input.categoryCode,
    // A decimal string keeps cents exact; Jackson binds it to BigDecimal.
    'amount': input.amount.toString(),
    if (input.currencyCode != null) 'currencyCode': input.currencyCode,
    'paymentMethod': input.paymentMethod.apiCode,
    'expenseAt': input.expenseAt.toUtc().toIso8601String(),
    if (input.stockDocumentId != null) 'stockDocumentId': input.stockDocumentId,
    if (_text(input.referenceNo) != null)
      'referenceNo': _text(input.referenceNo),
    if (_text(input.payeeName) != null) 'payeeName': _text(input.payeeName),
    if (_text(input.note) != null) 'note': _text(input.note),
  };

  static Map<String, Object> voidBody(VoidExpenseInput input) => {
    'expectedVersion': input.expectedVersion,
    'reason': input.reason.trim(),
  };

  static String? _text(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
