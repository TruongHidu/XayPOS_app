import '../../../reports/domain/entities/report_date.dart';
import 'cashbook_enums.dart';

/// Restaurant-local calendar range shared by every cashbook tab.
class CashbookRangeFilter {
  const CashbookRangeFilter({required this.range, this.currencyCode});

  factory CashbookRangeFilter.initial([ReportDate? today]) =>
      CashbookRangeFilter(range: ReportDateRange.thisMonth(today));

  final ReportDateRange range;

  /// Null asks the server for the restaurant's current currency.
  final String? currencyCode;

  String? validate() {
    final invalid = range.validate();
    if (invalid != null) return invalid;
    final code = currencyCode;
    if (code != null && !RegExp(r'^[A-Z]{3}$').hasMatch(code)) {
      return 'Mã tiền tệ gồm 3 chữ cái in hoa, ví dụ VND.';
    }
    return null;
  }

  CashbookRangeFilter copyWith({
    ReportDateRange? range,
    String? Function()? currencyCode,
  }) => CashbookRangeFilter(
    range: range ?? this.range,
    currencyCode: currencyCode == null ? this.currencyCode : currencyCode(),
  );

  @override
  bool operator ==(Object other) =>
      other is CashbookRangeFilter &&
      other.range == range &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode => Object.hash(range, currencyCode);
}

/// From the 1st to the last day of the month before [today].
ReportDateRange cashbookLastMonth([ReportDate? today]) {
  final t = today ?? ReportDate.today();
  final end = ReportDate(t.year, t.month, 1).subtractDays(1);
  return ReportDateRange(
    fromDate: ReportDate(end.year, end.month, 1),
    toDate: end,
  );
}

/// Filters of the effective cash flow. Summary and series reuse every field
/// except paging and sorting, so their totals always match the listed rows.
class CashbookEntryFilter {
  const CashbookEntryFilter({
    this.type,
    this.sourceType,
    this.categoryCode,
    this.paymentMethod,
    this.q,
    this.page = 0,
    this.size = 20,
    this.sortBy = CashbookEntrySort.occurredAt,
    this.direction = CashbookSortDirection.desc,
  });

  final CashbookEntryType? type;
  final CashbookSourceType? sourceType;
  final String? categoryCode, q;
  final CashbookPaymentMethod? paymentMethod;
  final int page, size;
  final CashbookEntrySort sortBy;
  final CashbookSortDirection direction;

  bool get hasCriteria =>
      type != null ||
      sourceType != null ||
      categoryCode != null ||
      paymentMethod != null ||
      q != null;

  CashbookEntryFilter copyWith({
    CashbookEntryType? Function()? type,
    CashbookSourceType? Function()? sourceType,
    String? Function()? categoryCode,
    CashbookPaymentMethod? Function()? paymentMethod,
    String? Function()? q,
    int? page,
    int? size,
    CashbookEntrySort? sortBy,
    CashbookSortDirection? direction,
  }) => CashbookEntryFilter(
    type: type == null ? this.type : type(),
    sourceType: sourceType == null ? this.sourceType : sourceType(),
    categoryCode: categoryCode == null ? this.categoryCode : categoryCode(),
    paymentMethod: paymentMethod == null ? this.paymentMethod : paymentMethod(),
    q: q == null ? this.q : q(),
    page: page ?? this.page,
    size: size ?? this.size,
    sortBy: sortBy ?? this.sortBy,
    direction: direction ?? this.direction,
  );

  @override
  bool operator ==(Object other) =>
      other is CashbookEntryFilter &&
      other.type == type &&
      other.sourceType == sourceType &&
      other.categoryCode == categoryCode &&
      other.paymentMethod == paymentMethod &&
      other.q == q &&
      other.page == page &&
      other.size == size &&
      other.sortBy == sortBy &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(
    type,
    sourceType,
    categoryCode,
    paymentMethod,
    q,
    page,
    size,
    sortBy,
    direction,
  );
}

class CashbookExpenseFilter {
  const CashbookExpenseFilter({
    this.status = CashbookExpenseStatus.posted,
    this.categoryCode,
    this.paymentMethod,
    this.stockDocumentId,
    this.stockDocumentCode,
    this.q,
    this.page = 0,
    this.size = 20,
    this.sortBy = CashbookExpenseSort.expenseAt,
    this.direction = CashbookSortDirection.desc,
  });

  /// Null lists both posted and voided vouchers.
  final CashbookExpenseStatus? status;
  final String? categoryCode, stockDocumentId, q;

  /// Display label for [stockDocumentId]; never sent to the server.
  final String? stockDocumentCode;
  final CashbookPaymentMethod? paymentMethod;
  final int page, size;
  final CashbookExpenseSort sortBy;
  final CashbookSortDirection direction;

  CashbookExpenseFilter copyWith({
    CashbookExpenseStatus? Function()? status,
    String? Function()? categoryCode,
    CashbookPaymentMethod? Function()? paymentMethod,
    ({String id, String code})? Function()? stockDocument,
    String? Function()? q,
    int? page,
    int? size,
    CashbookExpenseSort? sortBy,
    CashbookSortDirection? direction,
  }) {
    final document = stockDocument?.call();
    return CashbookExpenseFilter(
      status: status == null ? this.status : status(),
      categoryCode: categoryCode == null ? this.categoryCode : categoryCode(),
      paymentMethod: paymentMethod == null
          ? this.paymentMethod
          : paymentMethod(),
      stockDocumentId: stockDocument == null ? stockDocumentId : document?.id,
      stockDocumentCode: stockDocument == null
          ? stockDocumentCode
          : document?.code,
      q: q == null ? this.q : q(),
      page: page ?? this.page,
      size: size ?? this.size,
      sortBy: sortBy ?? this.sortBy,
      direction: direction ?? this.direction,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CashbookExpenseFilter &&
      other.status == status &&
      other.categoryCode == categoryCode &&
      other.paymentMethod == paymentMethod &&
      other.stockDocumentId == stockDocumentId &&
      other.q == q &&
      other.page == page &&
      other.size == size &&
      other.sortBy == sortBy &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(
    status,
    categoryCode,
    paymentMethod,
    stockDocumentId,
    q,
    page,
    size,
    sortBy,
    direction,
  );
}

class CashbookReceiptFilter {
  const CashbookReceiptFilter({
    this.includeUnknownCurrency = true,
    this.q,
    this.page = 0,
    this.size = 20,
    this.sortBy = CashbookReceiptSort.confirmedAt,
    this.direction = CashbookSortDirection.desc,
  });

  final bool includeUnknownCurrency;
  final String? q;
  final int page, size;
  final CashbookReceiptSort sortBy;
  final CashbookSortDirection direction;

  CashbookReceiptFilter copyWith({
    bool? includeUnknownCurrency,
    String? Function()? q,
    int? page,
    int? size,
    CashbookReceiptSort? sortBy,
    CashbookSortDirection? direction,
  }) => CashbookReceiptFilter(
    includeUnknownCurrency:
        includeUnknownCurrency ?? this.includeUnknownCurrency,
    q: q == null ? this.q : q(),
    page: page ?? this.page,
    size: size ?? this.size,
    sortBy: sortBy ?? this.sortBy,
    direction: direction ?? this.direction,
  );

  @override
  bool operator ==(Object other) =>
      other is CashbookReceiptFilter &&
      other.includeUnknownCurrency == includeUnknownCurrency &&
      other.q == q &&
      other.page == page &&
      other.size == size &&
      other.sortBy == sortBy &&
      other.direction == direction;

  @override
  int get hashCode =>
      Object.hash(includeUnknownCurrency, q, page, size, sortBy, direction);
}
