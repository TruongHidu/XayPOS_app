class ApiErrorDto {
  const ApiErrorDto({
    required this.code,
    required this.message,
    this.fieldErrors = const {},
  });

  final String code;
  final String message;
  final Map<String, String> fieldErrors;

  factory ApiErrorDto.fromJson(Map<String, dynamic> json) {
    final rawFieldErrors = json['fieldErrors'];
    return ApiErrorDto(
      code: json['code'] as String? ?? 'INTERNAL_ERROR',
      message: json['message'] as String? ?? 'Đã xảy ra lỗi.',
      fieldErrors: rawFieldErrors is Map
          ? rawFieldErrors.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
    );
  }
}
