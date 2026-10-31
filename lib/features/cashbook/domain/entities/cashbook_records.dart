import '../../../reports/domain/entities/report_date.dart';
import '../../../reports/domain/entities/report_money.dart';
import 'cashbook_enums.dart';

class CashbookCategory {
  const CashbookCategory({
    required this.id,
    required this.code,
    required this.name,
    required this.type,
    required this.active,
  });

  final String id, code, name;
  final CashbookEntryType type;
  final bool active;
}

/// One effective cash movement: a successful payment or a posted voucher.
class CashbookEntry {
  const CashbookEntry({
    required this.sourceType,
    required this.sourceId,
    required this.code,
    required this.type,
    required this.categoryCode,
    required this.categoryName,
    required this.amount,
    required this.currencyCode,
    required this.occurredAt,
    required this.recordedAt,
    this.paymentMethod,
    this.createdBy,
    this.orderId,
    this.orderCode,
    this.stockDocumentId,
    this.sourceDocumentCode,
  });

  final CashbookSourceType sourceType;
  final String sourceId, code, categoryCode, categoryName, currencyCode;
  final CashbookEntryType type;
  final ReportMoney amount;
  final CashbookPaymentMethod? paymentMethod;
  final DateTime occurredAt, recordedAt;
  final String? createdBy, orderId, orderCode;
  final String? stockDocumentId, sourceDocumentCode;

  /// Payment and voucher ids live in different tables; only the pair is unique.
  String get rowKey => '${sourceType.apiCode}:$sourceId';
}

class CashbookSummary {
  const CashbookSummary({
    required this.totalIncomeAmount,
    required this.totalExpenseAmount,
    required this.netCashFlowAmount,
    required this.incomeEntryCount,
    required this.expenseEntryCount,
    required this.saleIncomeAmount,
    required this.receiptLinkedExpenseAmount,
    required this.otherExpenseAmount,
  });

  final ReportMoney totalIncomeAmount, totalExpenseAmount, netCashFlowAmount;
  final int incomeEntryCount, expenseEntryCount;
  final ReportMoney saleIncomeAmount;

  /// Both are parts of [totalExpenseAmount], never extra spending.
  final ReportMoney receiptLinkedExpenseAmount, otherExpenseAmount;
}

class CashbookSeriesPoint {
  const CashbookSeriesPoint({
    required this.bucketStartDate,
    required this.totalIncomeAmount,
    required this.totalExpenseAmount,
    required this.netCashFlowAmount,
    required this.incomeEntryCount,
    required this.expenseEntryCount,
  });

  final ReportDate bucketStartDate;
  final ReportMoney totalIncomeAmount, totalExpenseAmount, netCashFlowAmount;
  final int incomeEntryCount, expenseEntryCount;

  bool get isEmpty => incomeEntryCount == 0 && expenseEntryCount == 0;
}

class CashbookExpense {
  const CashbookExpense({
    required this.id,
    required this.expenseCode,
    required this.categoryCode,
    required this.categoryName,
    required this.amount,
    required this.currencyCode,
    required this.paymentMethod,
    required this.expenseAt,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
    this.stockDocumentId,
    this.sourceDocumentCode,
    this.sourceCurrencyStatus,
    this.referenceNo,
    this.payeeName,
    this.note,
    this.createdBy,
    this.voidedBy,
    this.voidedAt,
    this.voidReason,
  });

  final String id, expenseCode, categoryCode, categoryName, currencyCode;
  final ReportMoney amount;
  final CashbookPaymentMethod paymentMethod;
  final DateTime expenseAt, createdAt, updatedAt;
  final CashbookExpenseStatus status;
  final int version;
  final String? stockDocumentId, sourceDocumentCode;
  final CashbookCurrencyStatus? sourceCurrencyStatus;
  final String? referenceNo, payeeName, note, createdBy;
  final String? voidedBy, voidReason;
  final DateTime? voidedAt;

  bool get isVoided => status == CashbookExpenseStatus.voided;
}

/// A confirmed stock receipt with the vouchers recorded against it so far.
/// It is a reconciliation aid, not a payable balance.
class CashbookStockReceipt {
  const CashbookStockReceipt({
    required this.stockDocumentId,
    required this.documentCode,
    required this.warehouseId,
    required this.warehouseName,
    required this.confirmedAt,
    required this.totalCost,
    required this.currencyStatus,
    required this.linkedPostedExpenseCount,
    this.currencyCode,
    this.recordedExpenseAmountAllTime,
  });

  final String stockDocumentId, documentCode, warehouseId, warehouseName;
  final DateTime confirmedAt;
  final ReportMoney totalCost;
  final String? currencyCode;
  final CashbookCurrencyStatus currencyStatus;
  final int linkedPostedExpenseCount;

  /// Null for an UNKNOWN currency receipt: it cannot be summed in any unit.
  final ReportMoney? recordedExpenseAmountAllTime;

  bool get currencyUnknown => currencyStatus == CashbookCurrencyStatus.unknown;
}
