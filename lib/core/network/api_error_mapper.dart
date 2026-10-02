import 'package:dio/dio.dart';

import '../errors/failure.dart';
import 'api_error_dto.dart';

abstract final class ApiErrorMapper {
  static Failure fromException(Object error) {
    if (error is! DioException) {
      return const Failure(
        type: FailureType.internal,
        message: 'Đã xảy ra lỗi. Vui lòng thử lại.',
      );
    }

    if (_isNetworkError(error)) {
      return const Failure(
        type: FailureType.network,
        message: 'Không thể kết nối đến máy chủ. Vui lòng thử lại.',
      );
    }

    final data = error.response?.data;
    final apiError = data is Map<String, dynamic>
        ? ApiErrorDto.fromJson(data)
        : const ApiErrorDto(code: 'INTERNAL_ERROR', message: 'Đã xảy ra lỗi.');

    final mapped = switch (apiError.code) {
      'UNAUTHORIZED' || 'ACCOUNT_INACTIVE' => FailureType.unauthorized,
      'TENANT_ACCESS_DENIED' ||
      'STAFF_TARGET_FORBIDDEN' => FailureType.forbidden,
      'ROLE_NOT_FOUND' => FailureType.notFound,
      'INVALID_STAFF_LIMIT_CONFIG' ||
      'CONCURRENT_STAFF_UPDATE' => FailureType.conflict,
      'EMPTY_UPDATE_REQUEST' ||
      'PERMISSION_NOT_FOUND' ||
      'PERMISSION_NOT_ASSIGNABLE' => FailureType.validation,
      _ => null,
    };
    if (mapped != null) {
      return Failure(
        type: mapped,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: apiError.message.isNotEmpty
            ? apiError.message
            : 'Không thể thực hiện thao tác (${apiError.code}).',
      );
    }
    return switch (apiError.code) {
      'INVALID_CREDENTIALS' => Failure(
        type: FailureType.invalidCredentials,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: 'Email hoặc mật khẩu không đúng',
      ),
      'RESTAURANT_INACTIVE' => Failure(
        type: FailureType.restaurantInactive,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message:
            'Nhà hàng đang bị khóa hoặc tạm ngừng hoạt động. Vui lòng liên hệ quản trị viên.',
      ),
      'INVALID_REFRESH_TOKEN' => Failure(
        type: FailureType.invalidRefreshToken,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: 'Phiên đăng nhập đã hết hạn',
      ),
      'SUBSCRIPTION_NOT_ACTIVE' => Failure(
        type: FailureType.subscriptionNotActive,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: 'Nhà hàng chưa có gói hoạt động.',
      ),
      'FEATURE_NOT_ENTITLED' => Failure(
        type: FailureType.featureNotEntitled,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: 'Gói hiện tại không hỗ trợ chức năng này',
      ),
      'FORBIDDEN' => Failure(
        type: FailureType.forbidden,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: 'Bạn không có quyền thực hiện chức năng này',
      ),
      'EMAIL_EXISTS' => Failure(
        type: FailureType.conflict,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: apiError.message.isNotEmpty
            ? apiError.message
            : 'Email này đã được sử dụng bởi tài khoản khác.',
      ),
      'STAFF_LIMIT_REACHED' => Failure(
        type: FailureType.conflict,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: apiError.message.isNotEmpty
            ? apiError.message
            : 'Đã đạt giới hạn số lượng nhân viên của gói dịch vụ.',
      ),
      'OWNER_ACCOUNT_PROTECTED' => Failure(
        type: FailureType.forbidden,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: apiError.message.isNotEmpty
            ? apiError.message
            : 'Tài khoản Chủ nhà hàng (OWNER) được bảo vệ, không thể sửa/vô hiệu hóa.',
      ),
      'STAFF_SELF_MANAGEMENT_NOT_ALLOWED' => Failure(
        type: FailureType.forbidden,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: apiError.message.isNotEmpty
            ? apiError.message
            : 'Bạn không được tự chỉnh sửa hoặc vô hiệu hóa tài khoản của chính mình.',
      ),
      'PERMISSION_ESCALATION_NOT_ALLOWED' => Failure(
        type: FailureType.forbidden,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: apiError.message.isNotEmpty
            ? apiError.message
            : 'Bạn không thể phân quyền mà tài khoản của bạn chưa có.',
      ),
      'STAFF_ROLE_NOT_ALLOWED' => Failure(
        type: FailureType.validation,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: apiError.message.isNotEmpty
            ? apiError.message
            : 'Bạn không có quyền gán vai trò này.',
      ),
      'PERMISSION_EFFECT_CONFLICT' => Failure(
        type: FailureType.validation,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: apiError.message.isNotEmpty
            ? apiError.message
            : 'Xung đột phân quyền: Cùng một quyền không thể vừa gán vừa chặn.',
      ),
      'USER_NOT_FOUND' => Failure(
        type: FailureType.notFound,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: apiError.message.isNotEmpty
            ? apiError.message
            : 'Không tìm thấy thông tin nhân viên.',
      ),
      'VALIDATION_ERROR' => Failure(
        type: FailureType.validation,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: apiError.message.isNotEmpty
            ? apiError.message
            : 'Thông tin nhập chưa hợp lệ.',
      ),
      _ => Failure(
        type: FailureType.internal,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
        message: apiError.message.isNotEmpty
            ? apiError.message
            : 'Đã xảy ra lỗi. Vui lòng thử lại.',
      ),
    };
  }

  static bool _isNetworkError(DioException error) {
    return error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout;
  }
}
