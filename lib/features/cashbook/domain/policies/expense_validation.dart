import '../../../reports/domain/entities/report_money.dart';
import '../entities/cashbook_enums.dart';

/// Field limits mirrored from the backend so most mistakes never leave the form.
abstract final class ExpenseLimits {
  static const integerDigits = 16;
  static const referenceNo = 100;
  static const payeeName = 150;
  static const note = 10000;
  static const voidReason = 1000;
}

/// Parses a typed amount in Vietnamese notation: `.` groups thousands and `,`
/// starts the fraction ("1.250.000,5"). A lone `.` followed by one or two
/// digits ("12.5") is read as a decimal point for keyboards without a comma.
({ReportMoney? value, String? error}) parseExpenseAmount(String raw) {
  var text = raw.replaceAll(RegExp(r'\s'), '');
  if (text.isEmpty) return (value: null, error: 'Nhập số tiền đã chi.');
  if (text.startsWith('-')) {
    return (value: null, error: 'Số tiền phải lớn hơn 0.');
  }
  if (!text.contains(',') && RegExp(r'^\d+\.\d{1,2}$').hasMatch(text)) {
    text = text.replaceFirst('.', ',');
  }
  final match = RegExp(
    r'^(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d*))?$',
  ).firstMatch(text);
  if (match == null) {
    return (value: null, error: 'Số tiền chỉ gồm chữ số, ví dụ 1.250.000.');
  }
  final whole = match[1]!.replaceAll('.', '').replaceFirst(RegExp(r'^0+'), '');
  final fraction = match[2] ?? '';
  if (fraction.length > 2) {
    return (value: null, error: 'Số tiền tối đa 2 chữ số thập phân.');
  }
  if (whole.length > ExpenseLimits.integerDigits) {
    return (value: null, error: 'Số tiền vượt quá giới hạn cho phép.');
  }
  final minor =
      BigInt.parse(whole.isEmpty ? '0' : whole) * BigInt.from(100) +
      BigInt.parse(fraction.padRight(2, '0'));
  if (minor <= BigInt.zero) {
    return (value: null, error: 'Số tiền phải lớn hơn 0.');
  }
  return (value: ReportMoney(minor), error: null);
}

/// Returns field errors keyed like the backend's `fieldErrors`.
Map<String, String> validateExpenseDraft({
  required String? categoryCode,
  required String amountText,
  required DateTime? expenseAt,
  required DateTime now,
  String? stockDocumentId,
  String referenceNo = '',
  String payeeName = '',
  String note = '',
}) {
  final errors = <String, String>{};
  if (categoryCode == null || categoryCode.isEmpty) {
    errors['categoryCode'] = 'Chọn danh mục chi.';
  }
  final amount = parseExpenseAmount(amountText);
  if (amount.error != null) errors['amount'] = amount.error!;
  if (expenseAt == null) {
    errors['expenseAt'] = 'Chọn thời điểm đã chi tiền.';
  } else if (expenseAt.isAfter(now)) {
    errors['expenseAt'] = 'Thời điểm chi không được ở tương lai.';
  }
  if (stockDocumentId != null &&
      categoryCode != CashbookCategoryCodes.ingredientPurchase) {
    errors['stockDocumentId'] =
        'Chỉ khoản chi mua nguyên liệu mới liên kết được phiếu nhập.';
  }
  if (referenceNo.trim().length > ExpenseLimits.referenceNo) {
    errors['referenceNo'] =
        'Mã tham chiếu tối đa ${ExpenseLimits.referenceNo} ký tự.';
  }
  if (payeeName.trim().length > ExpenseLimits.payeeName) {
    errors['payeeName'] =
        'Tên người nhận tối đa ${ExpenseLimits.payeeName} ký tự.';
  }
  if (note.trim().length > ExpenseLimits.note) {
    errors['note'] = 'Ghi chú tối đa ${ExpenseLimits.note} ký tự.';
  }
  return errors;
}

String? validateVoidReason(String reason) {
  final text = reason.trim();
  if (text.isEmpty) return 'Nhập lý do hủy phiếu.';
  if (text.length > ExpenseLimits.voidReason) {
    return 'Lý do tối đa ${ExpenseLimits.voidReason} ký tự.';
  }
  return null;
}
