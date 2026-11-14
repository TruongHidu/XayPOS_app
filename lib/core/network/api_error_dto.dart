import '../errors/stock_shortage.dart';

class ApiErrorDto {
  const ApiErrorDto({
    required this.code,
    required this.message,
    this.fieldErrors = const {},
    this.stockShortage,
    this.subscriptionExpired = false,
  });

  final String code;
  final String message;
  final Map<String, String> fieldErrors;
  final StockShortage? stockShortage;

  /// SUBSCRIPTION_NOT_ACTIVE because the last package ran out (renew), not
  /// because there never was one (subscribe).
  final bool subscriptionExpired;

  factory ApiErrorDto.fromJson(Map<String, dynamic> json) {
    final rawFieldErrors = json['fieldErrors'];
    final code = json['code'] as String? ?? 'INTERNAL_ERROR';
    return ApiErrorDto(
      code: code,
      stockShortage: code == 'INSUFFICIENT_AVAILABLE_STOCK'
          ? StockShortage.tryParse(json['details'])
          : null,
      subscriptionExpired:
          code == 'SUBSCRIPTION_NOT_ACTIVE' &&
          json['details'] is Map &&
          (json['details'] as Map)['reason'] == 'EXPIRED',
      message: json['message'] as String? ?? 'Đã xảy ra lỗi.',
      fieldErrors: rawFieldErrors is Map
          ? rawFieldErrors.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
    );
  }
}
