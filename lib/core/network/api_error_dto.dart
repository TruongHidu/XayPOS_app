import '../errors/stock_shortage.dart';

class ApiErrorDto {
  const ApiErrorDto({
    required this.code,
    required this.message,
    this.fieldErrors = const {},
    this.stockShortage,
  });

  final String code;
  final String message;
  final Map<String, String> fieldErrors;
  final StockShortage? stockShortage;

  factory ApiErrorDto.fromJson(Map<String, dynamic> json) {
    final rawFieldErrors = json['fieldErrors'];
    final code = json['code'] as String? ?? 'INTERNAL_ERROR';
    return ApiErrorDto(
      code: code,
      stockShortage: code == 'INSUFFICIENT_AVAILABLE_STOCK'
          ? StockShortage.tryParse(json['details'])
          : null,
      message: json['message'] as String? ?? 'Đã xảy ra lỗi.',
      fieldErrors: rawFieldErrors is Map
          ? rawFieldErrors.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
    );
  }
}
