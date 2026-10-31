import 'package:dio/dio.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/result/result.dart';

const _messages = {
  'INVALID_CASHBOOK_DATE_RANGE': 'Khoảng ngày không hợp lệ.',
  'CASHBOOK_RANGE_TOO_LARGE': 'Chỉ xem tối đa 366 ngày trong một lần.',
  'INVALID_CASHBOOK_CURRENCY': 'Mã tiền tệ không hợp lệ.',
  'INVALID_CASHBOOK_FILTER': 'Bộ lọc sổ thu chi không hợp lệ.',
  'INVALID_CASHBOOK_SORT': 'Lựa chọn sắp xếp không hợp lệ.',
  'INVALID_EXPENSE_AMOUNT':
      'Số tiền phải lớn hơn 0 và tối đa 2 chữ số thập phân.',
  'EXPENSE_DATE_IN_FUTURE': 'Thời điểm chi không được ở tương lai.',
  'INVALID_IDEMPOTENCY_KEY': 'Mã chống trùng không hợp lệ. Hãy gửi lại.',
  'CASHBOOK_EXPENSE_NOT_FOUND':
      'Phiếu chi không tồn tại hoặc thuộc nhà hàng khác.',
  'CASHBOOK_CATEGORY_NOT_FOUND':
      'Danh mục chi không còn hiệu lực. Hãy chọn danh mục khác.',
  'CASHBOOK_IDEMPOTENCY_KEY_REUSED':
      'Lần gửi trước đã dùng nội dung khác. Hãy kiểm tra danh sách phiếu chi rồi gửi lại.',
  'CONCURRENT_CASHBOOK_UPDATE':
      'Phiếu chi vừa được thay đổi. Đã tải lại trạng thái mới nhất, hãy kiểm tra trước khi thao tác tiếp.',
  'INVALID_STOCK_RECEIPT_LINK':
      'Chỉ liên kết được phiếu nhập đã xác nhận của nhà hàng với danh mục mua nguyên liệu.',
  'STOCK_RECEIPT_CURRENCY_MISMATCH':
      'Tiền tệ của khoản chi khác tiền tệ của phiếu nhập.',
  'INVALID_CASHBOOK_TIMEZONE':
      'Múi giờ nhà hàng chưa hợp lệ. Hãy kiểm tra cấu hình nhà hàng.',
};

/// Keeps the shared auth/feature mapping and classifies cashbook business
/// codes, which the shared mapper does not know, by their HTTP status.
Future<Result<T>> cashbookResult<T>(
  Future<T> Function() operation, {
  String? validation,
}) async {
  if (validation != null) {
    return Error(
      Failure(
        type: FailureType.validation,
        code: 'INVALID_CASHBOOK_FILTER',
        message: validation,
      ),
    );
  }
  try {
    return Success(await operation());
  } on FormatException {
    return const Error(
      Failure(
        type: FailureType.internal,
        code: 'INVALID_CASHBOOK_RESPONSE',
        message: 'Dữ liệu sổ thu chi chưa hợp lệ. Hãy tải lại để đối soát.',
      ),
    );
  } on Object catch (error) {
    final Failure original;
    try {
      original = ApiErrorMapper.fromException(error);
    } on Object {
      return const Error(
        Failure(
          type: FailureType.internal,
          code: 'INVALID_CASHBOOK_ERROR',
          message: 'Chưa đọc được lỗi từ máy chủ. Hãy thử lại.',
        ),
      );
    }
    final status = error is DioException ? error.response?.statusCode : null;
    final type = original.type == FailureType.internal
        ? switch (status) {
            400 => FailureType.validation,
            401 => FailureType.unauthorized,
            403 => FailureType.forbidden,
            404 => FailureType.notFound,
            409 => FailureType.conflict,
            _ => original.type,
          }
        : original.type;
    final message =
        _messages[original.code] ??
        (status != null && status >= 500
            ? 'Máy chủ đang bận. Hãy thử lại sau ít phút.'
            : original.message);
    return Error(
      Failure(
        type: type,
        code: original.code,
        message: message,
        fieldErrors: original.fieldErrors,
      ),
    );
  }
}
