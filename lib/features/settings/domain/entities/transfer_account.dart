import '../../../../core/values/vietnamese_text.dart';

/// The bank account customers transfer to. One per restaurant; the server
/// builds the VietQR for each order from it.
class TransferAccount {
  const TransferAccount({
    required this.bankBin,
    required this.accountNumber,
    required this.accountName,
    this.updatedAt,
  });

  final String bankBin;
  final String accountNumber;

  /// Account holder as the bank prints it: uppercase ASCII.
  final String accountName;
  final DateTime? updatedAt;
}

/// What the owner types in the form. Normalizes on the way out so the
/// server always receives the shape VietQR needs.
class TransferAccountDraft {
  const TransferAccountDraft({
    required this.bankBin,
    required this.accountNumber,
    required this.accountName,
  });

  final String bankBin;
  final String accountNumber;
  final String accountName;

  static const accountNumberMaxLength = 19;
  static const accountNameMaxLength = 50;

  /// Digits and letters only; spaces people type between groups are dropped.
  static String normalizeAccountNumber(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  /// `Nguyễn  Văn Đức` → `NGUYEN VAN DUC`.
  static String normalizeAccountName(String value) =>
      removeVietnameseDiacritics(
        value,
      ).toUpperCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  static String? validateBankBin(String? value) =>
      RegExp(r'^\d{6}$').hasMatch((value ?? '').trim())
      ? null
      : 'Hãy chọn ngân hàng.';

  static String? validateAccountNumber(String? value) {
    final number = normalizeAccountNumber(value ?? '');
    if (number.isEmpty) return 'Nhập số tài khoản.';
    if (number.length > accountNumberMaxLength) {
      return 'Số tài khoản tối đa $accountNumberMaxLength ký tự.';
    }
    if (!RegExp(r'^[A-Z0-9]+$').hasMatch(number)) {
      return 'Số tài khoản chỉ gồm chữ số và chữ cái.';
    }
    return null;
  }

  static String? validateAccountName(String? value) {
    final name = normalizeAccountName(value ?? '');
    if (name.isEmpty) return 'Nhập tên chủ tài khoản.';
    if (name.length > accountNameMaxLength) {
      return 'Tên chủ tài khoản tối đa $accountNameMaxLength ký tự.';
    }
    if (!RegExp(r'^[A-Z0-9 ]+$').hasMatch(name)) {
      return 'Tên chủ tài khoản chỉ gồm chữ cái, chữ số và khoảng trắng.';
    }
    return null;
  }

  /// Field name → message for every invalid field; empty when valid.
  Map<String, String> get errors => {
    if (validateBankBin(bankBin) case final error?) 'bankBin': error,
    if (validateAccountNumber(accountNumber) case final error?)
      'accountNumber': error,
    if (validateAccountName(accountName) case final error?)
      'accountName': error,
  };

  bool get isValid => errors.isEmpty;

  Map<String, dynamic> toJson() => {
    'bankBin': bankBin.trim(),
    'accountNumber': normalizeAccountNumber(accountNumber),
    'accountName': normalizeAccountName(accountName),
  };
}
