import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/result/result.dart';

Future<Result<T>> tableResult<T>(Future<T> Function() operation) async {
  try {
    return Success(await operation());
  } on FormatException {
    return const Error(
      Failure(
        type: FailureType.internal,
        code: 'INVALID_TABLE_RESPONSE',
        message:
            'Dữ liệu bàn từ máy chủ không hợp lệ. Vui lòng tải lại hoặc liên hệ hỗ trợ.',
      ),
    );
  } catch (error) {
    return Error(ApiErrorMapper.fromException(error));
  }
}
