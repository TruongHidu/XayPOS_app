import '../../../reports/domain/entities/report_money.dart';
import 'cashbook_enums.dart';
import 'cashbook_records.dart';

/// A voucher for money that has already been paid outside the system.
class CreateExpenseInput {
  const CreateExpenseInput({
    required this.categoryCode,
    required this.amount,
    required this.paymentMethod,
    required this.expenseAt,
    this.currencyCode,
    this.stockDocumentId,
    this.referenceNo,
    this.payeeName,
    this.note,
  });

  final String categoryCode;
  final ReportMoney amount;
  final CashbookPaymentMethod paymentMethod;

  /// The instant the payment happened (UTC), which may be earlier than today.
  final DateTime expenseAt;
  final String? currencyCode, stockDocumentId;
  final String? referenceNo, payeeName, note;

  @override
  bool operator ==(Object other) =>
      other is CreateExpenseInput &&
      other.categoryCode == categoryCode &&
      other.amount == amount &&
      other.paymentMethod == paymentMethod &&
      other.expenseAt == expenseAt &&
      other.currencyCode == currencyCode &&
      other.stockDocumentId == stockDocumentId &&
      other.referenceNo == referenceNo &&
      other.payeeName == payeeName &&
      other.note == note;

  @override
  int get hashCode => Object.hash(
    categoryCode,
    amount,
    paymentMethod,
    expenseAt,
    currencyCode,
    stockDocumentId,
    referenceNo,
    payeeName,
    note,
  );
}

class VoidExpenseInput {
  const VoidExpenseInput({required this.expectedVersion, required this.reason});
  final int expectedVersion;
  final String reason;
}

class ExpenseCreateResult {
  const ExpenseCreateResult({required this.expense, required this.replayed});
  final CashbookExpense expense;

  /// The server answered an earlier submit with the same key and payload.
  final bool replayed;
}

abstract interface class CashbookKeyGenerator {
  String next();
}
