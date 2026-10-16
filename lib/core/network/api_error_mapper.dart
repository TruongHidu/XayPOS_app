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

    final orderError = switch (apiError.code) {
      'ORDER_NOT_FOUND' || 'ORDER_ITEM_NOT_FOUND' => (
        FailureType.notFound,
        'Đơn hoặc dòng món không còn tồn tại hoặc bạn không có quyền truy cập.',
      ),
      'CONCURRENT_ORDER_UPDATE' => (
        FailureType.conflict,
        'Đơn đã được cập nhật. Bản đang sửa được giữ; hãy tải lại để đối chiếu.',
      ),
      'IDEMPOTENCY_KEY_REUSED' => (
        FailureType.conflict,
        'Yêu cầu có key xung đột. Không tự tạo key mới; hãy đối chiếu trước khi gửi lại.',
      ),
      'ORDER_CODE_CONFLICT' => (
        FailureType.conflict,
        'Mã đơn xung đột. Yêu cầu chưa được lưu.',
      ),
      'ORDER_NOT_EDITABLE' || 'ORDER_ITEM_NOT_EDITABLE' => (
        FailureType.conflict,
        'Đơn hoặc dòng món không còn cho phép sửa.',
      ),
      'INVALID_ORDER_TRANSITION' => (
        FailureType.conflict,
        'Trạng thái đơn không cho phép thao tác này.',
      ),
      'INVALID_ORDER_ITEM_TRANSITION' => (
        FailureType.conflict,
        'Món đã đổi trạng thái. Hãy tải lại để kiểm tra trước khi thao tác tiếp.',
      ),
      'EMPTY_ORDER' => (
        error.response?.statusCode == 409
            ? FailureType.conflict
            : FailureType.validation,
        'Đơn cần ít nhất một món còn hiệu lực.',
      ),
      'TABLE_SESSION_NOT_OPEN' => (
        FailureType.conflict,
        'Phiên bàn không còn mở. Hãy kiểm tra lại bàn.',
      ),
      'TABLE_SESSION_HAS_SERVING_ORDER' => (
        FailureType.conflict,
        'Bàn đã có đơn đang phục vụ. Giữ giỏ và kiểm tra đơn hiện tại để gọi thêm.',
      ),
      'INCONSISTENT_SERVING_ORDER_STATE' ||
      'INCONSISTENT_TABLE_SESSION_STATE' => (
        FailureType.conflict,
        'Dữ liệu phiên/đơn chưa nhất quán. Không tự chọn đơn; hãy tải lại hoặc liên hệ quản lý.',
      ),
      'TABLE_SESSION_IN_USE' => (
        FailureType.conflict,
        'Phiên đang có đơn hoặc nghĩa vụ thanh toán, không thể hủy phiên.',
      ),
      'ITEM_NOT_SELLABLE' || 'ITEM_OUT_OF_STOCK' => (
        FailureType.conflict,
        'Món vừa hết hàng hoặc không còn được bán. Hãy kiểm tra giỏ món.',
      ),
      'ORDER_CURRENCY_MISMATCH' => (
        FailureType.conflict,
        'Tiền tệ hiện tại khác đơn cũ. Không thể thêm dòng vào đơn này.',
      ),
      'ORDER_HAS_FINANCIAL_OBLIGATIONS' => (
        FailureType.conflict,
        'Đơn có nghĩa vụ thanh toán, không thể gọi thêm hoặc hủy trong luồng hiện tại.',
      ),
      'INVALID_IDEMPOTENCY_KEY' => (
        FailureType.validation,
        'Idempotency-Key phải không trống và tối đa 100 ký tự.',
      ),
      'DINE_IN_SESSION_REQUIRED' => (
        FailureType.validation,
        'Đơn tại bàn cần mã bàn hoặc phiên đang mở.',
      ),
      'AMBIGUOUS_ORDER_SEATING' => (
        FailureType.validation,
        'Chỉ dùng mã bàn hoặc mã phiên, không gửi đồng thời cả hai.',
      ),
      'TABLE_ORDER_REQUIRES_SUBMIT' => (
        FailureType.validation,
        'Tạo từ bàn phải gửi SUBMIT, không được tạo nháp.',
      ),
      'TAKEAWAY_TABLE_NOT_ALLOWED' => (
        FailureType.validation,
        'Đơn mang đi không được gắn bàn.',
      ),
      'TAKEAWAY_SESSION_NOT_ALLOWED' => (
        FailureType.validation,
        'Đơn mang đi không được có phiên bàn.',
      ),
      'UNSUPPORTED_ORDER_SOURCE' => (
        FailureType.validation,
        'Kênh gọi món không được hỗ trợ trên API nhân viên.',
      ),
      'ORDER_AMOUNT_LIMIT_EXCEEDED' => (
        FailureType.validation,
        'Tổng tiền vượt giới hạn cho phép.',
      ),
      _ => null,
    };
    if (orderError != null) {
      return Failure(
        type: orderError.$1,
        message: orderError.$2,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
      );
    }
    final menuError = switch (apiError.code) {
      'TABLE_AREA_NAME_EXISTS' => (
        FailureType.conflict,
        'Tên khu vực đã được sử dụng.',
      ),
      'TABLE_CODE_EXISTS' => (
        FailureType.conflict,
        'Mã bàn đã được sử dụng hoặc đang được giữ bởi bàn đã xóa.',
      ),
      'TABLE_AREA_INACTIVE' => (
        FailureType.conflict,
        'Khu vực đang ngừng hoạt động.',
      ),
      'TABLE_AREA_NOT_EMPTY' => (
        FailureType.conflict,
        'Khu vực còn bàn. Hãy chuyển hoặc xóa các bàn trước.',
      ),
      'TABLE_AREA_HAS_OPEN_SESSIONS' => (
        FailureType.conflict,
        'Khu vực có bàn đang phục vụ, chưa thể tắt.',
      ),
      'TABLE_INACTIVE' => (FailureType.conflict, 'Bàn đang ngừng hoạt động.'),
      'TABLE_ALREADY_OCCUPIED' => (
        FailureType.conflict,
        'Bàn đã có phiên phục vụ. Vui lòng tải lại.',
      ),
      'SAME_TABLE_TRANSFER_NOT_ALLOWED' => (
        FailureType.conflict,
        'Bàn đích đang là bàn hiện tại của phiên.',
      ),
      'INCONSISTENT_TABLE_SESSION_STATE' => (
        FailureType.conflict,
        'Dữ liệu bàn và phiên chưa nhất quán. Hãy tải lại hoặc liên hệ quản lý.',
      ),
      'TABLE_HAS_OPEN_SESSION' => (
        FailureType.conflict,
        'Bàn đang có khách, không thể thực hiện thao tác này.',
      ),
      'INVALID_TABLE_SESSION_TRANSITION' => (
        FailureType.conflict,
        'Trạng thái phiên không cho phép thao tác này.',
      ),
      'CONCURRENT_TABLE_UPDATE' => (
        FailureType.conflict,
        'Dữ liệu đã được người khác cập nhật. Vui lòng tải lại để kiểm tra.',
      ),
      'TABLE_AREA_NOT_FOUND' ||
      'TABLE_NOT_FOUND' ||
      'TABLE_SESSION_NOT_FOUND' => (
        FailureType.notFound,
        'Tài nguyên không còn tồn tại hoặc bạn không còn quyền truy cập.',
      ),
      'QR_TOKEN_CONFLICT' => (
        FailureType.conflict,
        'Chưa thể tạo mã QR mới. Vui lòng thử lại.',
      ),
      'EMPTY_UPDATE_REQUEST' => (
        FailureType.validation,
        'Chưa có thay đổi để lưu.',
      ),
      'INVALID_REQUEST_BODY' => (
        FailureType.validation,
        'Nội dung yêu cầu không hợp lệ. Vui lòng kiểm tra dữ liệu.',
      ),
      'MENU_GROUP_NAME_EXISTS' => (
        FailureType.conflict,
        'Tên nhóm đã được sử dụng.',
      ),
      'SKU_EXISTS' => (
        FailureType.conflict,
        'SKU đã được sử dụng hoặc đang được giữ bởi món đã xóa.',
      ),
      'MENU_GROUP_INACTIVE' => (
        FailureType.conflict,
        'Nhóm đã ngừng hoạt động. Vui lòng tải lại lựa chọn nhóm.',
      ),
      'MENU_GROUP_NOT_EMPTY' => (
        FailureType.conflict,
        'Nhóm còn món chưa xóa, kể cả món ngừng bán. Hãy chuyển, bỏ nhóm hoặc xóa các món trước.',
      ),
      'MENU_ITEM_NOT_FOUND' => (
        FailureType.notFound,
        'Món không còn tồn tại hoặc bạn không còn quyền truy cập.',
      ),
      'MENU_GROUP_NOT_FOUND' => (
        FailureType.notFound,
        'Nhóm không còn tồn tại hoặc bạn không còn quyền truy cập.',
      ),
      'INVALID_MENU_ITEM_TRANSITION' => (
        FailureType.conflict,
        'Trạng thái món không cho phép thao tác này. Vui lòng tải lại chi tiết.',
      ),
      'CONCURRENT_MENU_UPDATE' => (
        FailureType.conflict,
        'Dữ liệu đã được người khác cập nhật. Vui lòng tải lại để kiểm tra.',
      ),
      'INTERNAL_ERROR' => (
        FailureType.internal,
        'Đã xảy ra lỗi trên máy chủ. Vui lòng thử lại sau.',
      ),
      _ => null,
    };
    if (menuError != null) {
      return Failure(
        type: menuError.$1,
        message: menuError.$2,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
      );
    }
    final reportError = switch (apiError.code) {
      'INVALID_REPORT_DATE_RANGE' => (
        FailureType.validation,
        'Khoảng ngày báo cáo không hợp lệ.',
      ),
      'REPORT_RANGE_TOO_LARGE' => (
        FailureType.validation,
        'Khoảng ngày báo cáo vượt quá giới hạn cho phép (tối đa 366 ngày).',
      ),
      'INVALID_REPORT_CURRENCY' => (
        FailureType.validation,
        'Mã tiền tệ báo cáo không hợp lệ.',
      ),
      'INVALID_REPORT_SORT' => (
        FailureType.validation,
        'Tiêu chí sắp xếp báo cáo không hợp lệ.',
      ),
      'INVALID_REPORT_TIMEZONE' => (
        FailureType.conflict,
        'Cấu hình múi giờ của nhà hàng không hợp lệ. Vui lòng liên hệ quản lý.',
      ),
      _ => null,
    };
    if (reportError != null) {
      return Failure(
        type: reportError.$1,
        message: reportError.$2,
        code: apiError.code,
        fieldErrors: apiError.fieldErrors,
      );
    }
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
