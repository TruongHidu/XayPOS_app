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
      'PAYMENT_NOT_FOUND' => (
        FailureType.notFound,
        'Không tìm thấy giao dịch thanh toán hoặc bạn không có quyền truy cập.',
      ),
      'ORDER_ALREADY_PAID' => (
        FailureType.conflict,
        'Đơn đã được thanh toán. Hãy tải lại đơn để đối chiếu.',
      ),
      'ORDER_NOT_PAYABLE' => (
        FailureType.conflict,
        'Đơn hiện không đủ điều kiện thanh toán. Hãy kiểm tra trạng thái và số tiền.',
      ),
      'PAYMENT_AMOUNT_MISMATCH' => (
        FailureType.conflict,
        'Số tiền thanh toán phải bằng tổng tiền mới nhất của đơn. Hãy tải lại và đối chiếu.',
      ),
      'CONCURRENT_PAYMENT_UPDATE' => (
        FailureType.conflict,
        'Thanh toán đã được cập nhật. Hãy kiểm tra lại trước khi tiếp tục.',
      ),
      'PAYMENT_IDEMPOTENCY_KEY_REUSED' => (
        FailureType.conflict,
        'Yêu cầu thanh toán có key xung đột. Giữ yêu cầu hiện tại và đối chiếu giao dịch trước khi tiếp tục.',
      ),
      'ORDER_NOT_PAID' => (
        FailureType.conflict,
        'Đơn chưa được thanh toán đủ tiền nên chưa thể hoàn tất.',
      ),
      'ORDER_NOT_READY_FOR_COMPLETION' => (
        FailureType.conflict,
        'Đơn chưa thể hoàn tất. Tất cả món chưa hủy phải được phục vụ.',
      ),
      'TABLE_SESSION_NOT_READY_TO_CLOSE' => (
        FailureType.conflict,
        'Phiên bàn còn đơn hoặc nghĩa vụ thanh toán chưa xử lý nên chưa thể đóng.',
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
        'SKU đã được sử dụng hoặc đang được giữ bởi món bán, nguyên liệu hoặc bản ghi đã xóa.',
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
      'INGREDIENT_NOT_FOUND' => (
        FailureType.notFound,
        'Nguyên liệu không còn tồn tại hoặc bạn không còn quyền truy cập.',
      ),
      'MENU_GROUP_NOT_FOUND' => (
        FailureType.notFound,
        'Nhóm không còn tồn tại hoặc bạn không còn quyền truy cập.',
      ),
      'INVALID_MENU_ITEM_TRANSITION' => (
        FailureType.conflict,
        'Trạng thái món không cho phép thao tác này. Vui lòng tải lại chi tiết.',
      ),
      'INVALID_INGREDIENT_TRANSITION' => (
        FailureType.conflict,
        'Trạng thái nguyên liệu không cho phép thao tác này. Vui lòng tải lại chi tiết.',
      ),
      'CONCURRENT_MENU_UPDATE' => (
        FailureType.conflict,
        'Dữ liệu đã được người khác cập nhật. Vui lòng tải lại để kiểm tra.',
      ),
      'CONCURRENT_INGREDIENT_UPDATE' => (
        FailureType.conflict,
        'Dữ liệu đã được người khác cập nhật. Vui lòng tải lại để kiểm tra.',
      ),
      'RECIPE_NOT_FOUND' => (
        FailureType.notFound,
        'Phiên bản công thức không còn tồn tại hoặc bạn không có quyền truy cập.',
      ),
      'ORDER_ITEM_RECIPE_SNAPSHOT_CONFLICT' => (
        FailureType.conflict,
        'Dữ liệu công thức của dòng món chưa nhất quán. Hãy tải lại đơn để kiểm tra.',
      ),
      'INVALID_RECIPE_SNAPSHOT_DATA' => (
        FailureType.conflict,
        'Công thức chưa đủ dữ liệu hợp lệ để gửi món. Giỏ món được giữ nguyên.',
      ),
      'RECIPE_YIELD_UNIT_MISMATCH' => (
        FailureType.conflict,
        'Đơn vị sản lượng công thức khác đơn vị món. Cần kiểm tra công thức trước khi gửi.',
      ),
      'RECIPE_INGREDIENT_UNIT_MISMATCH' => (
        FailureType.conflict,
        'Đơn vị nguyên liệu trong công thức không còn phù hợp. Không tự quy đổi; hãy kiểm tra lại.',
      ),
      'RECIPE_INGREDIENT_UNAVAILABLE' => (
        FailureType.conflict,
        'Nguyên liệu trong công thức không còn hợp lệ để gửi món. Hãy liên hệ quản lý.',
      ),
      'RECIPE_USAGE_QUANTITY_OUT_OF_RANGE' ||
      'INVENTORY_QUANTITY_OUT_OF_RANGE' => (
        FailureType.conflict,
        'Lượng nguyên liệu cần dùng vượt giới hạn hỗ trợ. Giỏ món được giữ nguyên.',
      ),
      'INVENTORY_DEFAULT_WAREHOUSE_REQUIRED' => (
        FailureType.conflict,
        'Chưa có kho mặc định hợp lệ để giữ nguyên liệu. Hãy liên hệ quản lý cấu hình kho rồi thử lại.',
      ),
      'INSUFFICIENT_AVAILABLE_STOCK' => (
        FailureType.conflict,
        'Không đủ tồn khả dụng để gửi/chấp nhận món. Toàn bộ yêu cầu chưa được ghi nhận; hãy kiểm tra và thử lại.',
      ),
      'INVENTORY_ALLOCATION_NOT_FOUND' => (
        FailureType.conflict,
        'Dòng món đã gửi chưa có quyết định kho hợp lệ. Hãy tải lại hoặc liên hệ quản lý kiểm tra dữ liệu.',
      ),
      'INVALID_INVENTORY_ALLOCATION_TRANSITION' ||
      'INVENTORY_ALLOCATION_CONFLICT' => (
        FailureType.conflict,
        'Trạng thái nguyên liệu của món đã thay đổi. Hãy tải lại để đối chiếu.',
      ),
      'INVENTORY_RESERVATION_INVARIANT_VIOLATION' => (
        FailureType.conflict,
        'Dữ liệu giữ nguyên liệu chưa nhất quán. Hãy kiểm tra; không tự trừ hoặc giữ bù.',
      ),
      'WAREHOUSE_HAS_RESERVATIONS' => (
        FailureType.conflict,
        'Kho còn nguyên liệu đang giữ cho món. Cần xử lý các món đang giữ chỗ trước khi thay đổi.',
      ),
      'INGREDIENT_HAS_RESERVATIONS' => (
        FailureType.conflict,
        'Nguyên liệu đang được giữ cho món. Cần xử lý phần giữ chỗ trước khi thay đổi.',
      ),
      'CONCURRENT_INVENTORY_UPDATE' => (
        FailureType.conflict,
        'Tồn hoặc lượng giữ chỗ đã thay đổi. Hãy tải lại để đối chiếu trước khi thử lại.',
      ),
      'INGREDIENT_COST_UNIT_MISMATCH' => (
        FailureType.conflict,
        'Đơn vị trong công thức khác đơn vị hiện tại của nguyên liệu. Không thể ước tính.',
      ),
      'INGREDIENT_COST_UNAVAILABLE' => (
        FailureType.conflict,
        'Thiếu nguồn giá tham chiếu của nguyên liệu.',
      ),
      'INVALID_INGREDIENT_REFERENCE_COST' => (
        FailureType.conflict,
        'Giá tham chiếu của nguyên liệu không hợp lệ.',
      ),
      'INVALID_RECIPE_COST_DATA' => (
        FailureType.conflict,
        'Dữ liệu công thức chưa đủ hợp lệ để ước tính.',
      ),
      'ACTIVE_RECIPE_NOT_FOUND' => (
        FailureType.notFound,
        'Món chưa có công thức đang áp dụng.',
      ),
      'ACTIVE_RECIPE_ALREADY_EXISTS' => (
        FailureType.conflict,
        'Món đã có công thức đang áp dụng. Bản đang sửa được giữ; hãy tải lại để đối chiếu.',
      ),
      'RECIPE_NOT_ACTIVE' => (
        FailureType.conflict,
        'Công thức này đã ngừng áp dụng. Hãy tải lại công thức hiện tại trước khi tiếp tục.',
      ),
      'DUPLICATE_RECIPE_INGREDIENT' => (
        FailureType.conflict,
        'Nguyên liệu đã có trong công thức. Mỗi nguyên liệu chỉ được xuất hiện một lần.',
      ),
      'INGREDIENT_INACTIVE' => (
        FailureType.conflict,
        'Nguyên liệu đã ngừng sử dụng. Hãy chọn nguyên liệu đang sử dụng để thay thế.',
      ),
      'SAME_RECIPE_VERSION_NOT_ALLOWED' => (
        FailureType.conflict,
        'Công thức chưa có thay đổi thực tế.',
      ),
      'CONCURRENT_RECIPE_UPDATE' => (
        FailureType.conflict,
        'Công thức đã được người khác cập nhật. Bản đang sửa được giữ; hãy tải lại để đối chiếu.',
      ),
      'MENU_ITEM_UNIT_IN_USE' => (
        FailureType.conflict,
        'Đơn vị món đang được công thức áp dụng sử dụng. Hãy kiểm tra công thức trước khi đổi đơn vị.',
      ),
      'MENU_ITEM_HAS_ACTIVE_RECIPE' => (
        FailureType.conflict,
        'Món đang có công thức áp dụng nên chưa thể xóa. Hãy kiểm tra công thức trước.',
      ),
      'INGREDIENT_USED_BY_ACTIVE_RECIPE' => (
        FailureType.conflict,
        'Nguyên liệu đang được công thức áp dụng sử dụng nên chưa thể ngừng sử dụng hoặc xóa.',
      ),
      'INGREDIENT_UNIT_IN_USE' => (
        FailureType.conflict,
        'Đơn vị nguyên liệu đang được công thức áp dụng sử dụng. Hãy kiểm tra công thức trước khi đổi đơn vị.',
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
        fieldErrors: {
          ...apiError.fieldErrors,
          if (const {
                'MENU_ITEM_UNIT_IN_USE',
                'INGREDIENT_UNIT_IN_USE',
              }.contains(apiError.code) &&
              !apiError.fieldErrors.containsKey('baseUnit'))
            'baseUnit': menuError.$2,
        },
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
