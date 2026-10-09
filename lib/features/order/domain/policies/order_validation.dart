import 'order_access_policy.dart';
import '../entities/order_inputs.dart';
import '../entities/order_entities.dart';
import '../entities/order_submission.dart';

abstract final class OrderValidation {
  static String? text(String? value, int max, {bool required = false}) =>
      required && (value == null || value.trim().isEmpty)
      ? 'Vui lòng nhập thông tin.'
      : (value?.length ?? 0) > max
      ? 'Tối đa $max ký tự.'
      : null;
  static Map<String, String> create(CreateOrderInput input) {
    final result = fields(
      guestCount: input.guestCount,
      customerName: input.customerName,
      customerPhone: input.customerPhone,
      note: input.note,
    );
    result.addAll(lines(input.items));
    if (input.context.serviceType == ServiceType.dineIn) {
      if (input.context.fromTable) {
        if (!OrderAccessPolicy.isUuid(input.context.tableId) ||
            input.context.tableSessionId != null) {
          result['tableId'] =
              'Cần mã bàn hợp lệ và một tham chiếu bàn duy nhất.';
        }
        if (input.submissionMode != OrderSubmissionMode.submit) {
          result['submissionMode'] =
              'Gửi từ bàn phải dùng SUBMIT, không tạo nháp.';
        }
      } else if (!OrderAccessPolicy.isUuid(input.context.tableSessionId) ||
          input.context.tableId != null) {
        result['tableSessionId'] = 'Cần phiên bàn đang mở.';
      }
    }
    if (input.context.serviceType == ServiceType.takeaway &&
        (input.context.tableSessionId != null ||
            input.context.tableId != null)) {
      result['tableSessionId'] = 'Đơn mang đi không có phiên bàn.';
    }
    return result;
  }

  static Map<String, String> fields({
    int? guestCount,
    String? customerName,
    String? customerPhone,
    String? note,
  }) {
    final result = <String, String>{};
    if (guestCount != null && (guestCount < 1 || guestCount > 32767)) {
      result['guestCount'] = 'Số khách phải từ 1 đến 32767.';
    }
    for (final entry in {
      'customerName': text(customerName, 100),
      'customerPhone': text(customerPhone, 30),
      'note': text(note, 2000),
    }.entries) {
      if (entry.value != null) result[entry.key] = entry.value!;
    }
    return result;
  }

  static Map<String, String> lines(List<CreateOrderLine> items) {
    final result = <String, String>{};
    if (items.isEmpty || items.length > 100) {
      result['items'] = 'Cần từ 1 đến 100 dòng món.';
    }
    for (var i = 0; i < items.length; i++) {
      if (!OrderAccessPolicy.isUuid(items[i].itemId)) {
        result['items[$i].itemId'] = 'Mã món không hợp lệ.';
      }
      final error = text(items[i].note, 2000);
      if (error != null) result['items[$i].note'] = error;
    }
    return result;
  }
}
