import 'package:dio/dio.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/result/result.dart';

Future<Result<T>> inventoryResult<T>(Future<T> Function() operation) async {
  try {
    return Success(await operation());
  } on FormatException {
    return const Error(
      Failure(
        type: FailureType.internal,
        code: 'INVALID_INVENTORY_RESPONSE',
        message:
            'Dữ liệu kho chưa xác minh được. Vui lòng tải lại để kiểm tra.',
      ),
    );
  } on Object catch (e) {
    final original = ApiErrorMapper.fromException(e);
    // The shared mapper does not yet know inventory business codes.
    // Preserve its auth/feature mapping, and classify new codes by HTTP status.
    final type = original.type == FailureType.internal && e is DioException
        ? switch (e.response?.statusCode) {
            400 => FailureType.validation,
            401 => FailureType.unauthorized,
            403 => FailureType.forbidden,
            404 => FailureType.notFound,
            409 => FailureType.conflict,
            _ => original.type,
          }
        : original.type;
    final message = switch (original.code) {
      'WAREHOUSE_NOT_FOUND' =>
        'Kho không còn tồn tại hoặc bạn không có quyền truy cập.',
      'WAREHOUSE_CODE_EXISTS' =>
        'Mã kho đã được sử dụng, kể cả bởi kho đã xóa.',
      'WAREHOUSE_INACTIVE' =>
        'Kho đã ngừng hoạt động. Hãy kiểm tra trạng thái kho.',
      'DEFAULT_WAREHOUSE_CANNOT_BE_DISABLED' =>
        'Không thể tắt kho mặc định. Hãy chọn kho mặc định khác trước.',
      'DEFAULT_WAREHOUSE_CANNOT_BE_DELETED' =>
        'Không thể xóa kho mặc định. Hãy chọn kho mặc định khác trước.',
      'WAREHOUSE_HAS_STOCK' =>
        'Kho vẫn còn nguyên liệu có tồn khác 0 nên không thể tắt hoặc xóa.',
      'CONCURRENT_WAREHOUSE_UPDATE' =>
        'Kho đã thay đổi. Hãy tải lại, đối chiếu rồi xác nhận lại.',
      'CONCURRENT_INVENTORY_UPDATE' =>
        'Số dư tồn đã thay đổi. Hãy tải lại trước khi sửa ngưỡng.',
      'CONCURRENT_STOCK_DOCUMENT_UPDATE' =>
        'Chứng từ đã thay đổi. Bản nháp đang nhập được giữ; hãy tải lại để đối chiếu.',
      'STOCK_DOCUMENT_NOT_FOUND' =>
        'Chứng từ không còn tồn tại hoặc bạn không có quyền truy cập.',
      'STOCK_DOCUMENT_ITEM_NOT_FOUND' =>
        'Dòng nguyên liệu không còn trong phiếu. Hãy tải lại để đối chiếu.',
      'TRACKED_INGREDIENT_NOT_FOUND' =>
        'Nguyên liệu không còn tồn tại hoặc không còn theo dõi tồn.',
      'STOCK_DOCUMENT_EMPTY' =>
        'Phiếu cần ít nhất một dòng trước khi xác nhận.',
      'DUPLICATE_STOCK_DOCUMENT_ITEM' =>
        'Nguyên liệu đã có trong phiếu; mỗi nguyên liệu chỉ được xuất hiện một lần.',
      'CONFIRMED_STOCK_DOCUMENT_IMMUTABLE' =>
        'Phiếu đã xác nhận nên không thể sửa hoặc hủy.',
      'STOCK_DOCUMENT_CANCELLED' =>
        'Phiếu đã hủy nên không thể sửa hoặc xác nhận.',
      'INVALID_DOCUMENT_QUANTITY' =>
        'Số lượng phải lớn hơn 0, tối đa 3 chữ số thập phân.',
      'INVALID_DOCUMENT_COST' => 'Đơn giá không âm, tối đa 2 chữ số thập phân.',
      'INVALID_ADJUSTMENT_DIRECTION' =>
        'Chọn hướng tăng/giảm đúng loại chứng từ.',
      'INGREDIENT_INACTIVE_FOR_RECEIPT' =>
        'Nguyên liệu đã ngừng hoạt động, không thể nhập kho.',
      'INGREDIENT_UNIT_CHANGED' =>
        'Đơn vị nguyên liệu đã thay đổi so với phiếu. Hãy đối chiếu; không tự quy đổi hoặc xác nhận lại.',
      'INSUFFICIENT_STOCK' =>
        'Tồn hiện tại không đủ. Toàn bộ phiếu chưa được ghi nhận; hãy kiểm tra tồn rồi đối chiếu lại.',
      'IDEMPOTENCY_KEY_REQUIRED' =>
        'Yêu cầu tạo dữ liệu kho thiếu mã đối chiếu. Hãy kiểm tra lại yêu cầu.',
      'IDEMPOTENCY_KEY_REUSED' =>
        'Mã đối chiếu đã dùng cho nội dung khác. Hãy đối chiếu danh sách trước khi tạo yêu cầu khác.',
      'STOCK_DOCUMENT_CODE_EXISTS' =>
        'Mã chứng từ xung đột. Hãy kiểm tra lại dữ liệu.',
      _ => original.message,
    };
    return Error(
      Failure(
        type: type,
        code: original.code,
        message: message,
        fieldErrors: original.code == 'WAREHOUSE_CODE_EXISTS'
            ? {'code': message}
            : original.fieldErrors,
      ),
    );
  }
}
