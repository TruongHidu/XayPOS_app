enum CashbookEntryType {
  income('INCOME', 'Thu'),
  expense('EXPENSE', 'Chi');

  const CashbookEntryType(this.apiCode, this.label);
  final String apiCode, label;
}

enum CashbookSourceType {
  orderPayment('ORDER_PAYMENT', 'Thanh toán đơn'),
  expenseVoucher('EXPENSE_VOUCHER', 'Phiếu chi');

  const CashbookSourceType(this.apiCode, this.label);
  final String apiCode, label;
}

enum CashbookPaymentMethod {
  cash('CASH', 'Tiền mặt'),
  transfer('TRANSFER', 'Chuyển khoản');

  const CashbookPaymentMethod(this.apiCode, this.label);
  final String apiCode, label;
}

enum CashbookExpenseStatus {
  posted('POSTED', 'Hiệu lực'),
  voided('VOIDED', 'Đã hủy');

  const CashbookExpenseStatus(this.apiCode, this.label);
  final String apiCode, label;
}

/// Legacy receipts may predate currency tracking: their totals carry no unit.
enum CashbookCurrencyStatus {
  known('KNOWN'),
  unknown('UNKNOWN');

  const CashbookCurrencyStatus(this.apiCode);
  final String apiCode;
}

enum CashbookGranularity {
  day('DAY', 'Ngày'),
  month('MONTH', 'Tháng');

  const CashbookGranularity(this.apiCode, this.label);
  final String apiCode, label;
}

enum CashbookSortDirection {
  asc('asc'),
  desc('desc');

  const CashbookSortDirection(this.apiCode);
  final String apiCode;
}

enum CashbookEntrySort {
  occurredAt('occurredAt', 'Thời điểm'),
  amount('amount', 'Số tiền'),
  code('code', 'Mã');

  const CashbookEntrySort(this.apiCode, this.label);
  final String apiCode, label;
}

enum CashbookExpenseSort {
  expenseAt('expenseAt', 'Ngày chi'),
  amount('amount', 'Số tiền'),
  expenseCode('expenseCode', 'Mã phiếu'),
  createdAt('createdAt', 'Ngày ghi sổ');

  const CashbookExpenseSort(this.apiCode, this.label);
  final String apiCode, label;
}

enum CashbookReceiptSort {
  confirmedAt('confirmedAt', 'Ngày xác nhận'),
  documentCode('documentCode', 'Mã phiếu'),
  totalCost('totalCost', 'Giá trị phiếu');

  const CashbookReceiptSort(this.apiCode, this.label);
  final String apiCode, label;
}

/// Seeded category codes the client gives special meaning to.
abstract final class CashbookCategoryCodes {
  static const salesCollection = 'SALES_COLLECTION';
  static const ingredientPurchase = 'INGREDIENT_PURCHASE';
}
