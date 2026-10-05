import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/result/result.dart';

Future<Result<T>> menuResult<T>(Future<T> Function() operation) async {
  try {
    return Success(await operation());
  } on FormatException {
    return const Error(
      Failure(
        type: FailureType.internal,
        code: 'INVALID_MENU_RESPONSE',
        message:
            'Dữ liệu thực đơn từ máy chủ không hợp lệ. Vui lòng tải lại hoặc liên hệ hỗ trợ.',
      ),
    );
  } catch (error) {
    final failure = ApiErrorMapper.fromException(error);
    return Error(
      failure.type == FailureType.internal
          ? Failure(
              type: failure.type,
              code: failure.code,
              fieldErrors: failure.fieldErrors,
              message: 'Không thể xử lý thực đơn. Vui lòng thử lại sau.',
            )
          : failure,
    );
  }
}
