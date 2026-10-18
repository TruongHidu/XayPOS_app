import '../../../menu/domain/entities/menu_price.dart';

enum OrderPaymentMethod {
  cash('CASH', 'Tiền mặt'),
  transfer('TRANSFER', 'Chuyển khoản');

  const OrderPaymentMethod(this.code, this.label);
  final String code;
  final String label;
}

enum PaymentRecordStatus {
  pending('PENDING'),
  success('SUCCESS'),
  failed('FAILED'),
  cancelled('CANCELLED');

  const PaymentRecordStatus(this.code);
  final String code;
}

enum PaymentConfirmationSource {
  staffManual('STAFF_MANUAL'),
  providerWebhook('PROVIDER_WEBHOOK');

  const PaymentConfirmationSource(this.code);
  final String code;
}

/// A recorded payment is separate from the refreshed order representation.
class OrderPayment {
  const OrderPayment({
    required this.id,
    required this.orderId,
    required this.paymentCode,
    required this.amount,
    required this.currencyCode,
    required this.paymentMethod,
    required this.confirmationSource,
    required this.provider,
    required this.status,
    required this.referenceNo,
    required this.requestedAt,
    required this.paidAt,
    required this.createdBy,
  });

  final String id;
  final String orderId;
  final String paymentCode;
  final MenuPrice amount;
  final String currencyCode;
  final OrderPaymentMethod paymentMethod;
  final PaymentConfirmationSource confirmationSource;
  final String? provider;
  final PaymentRecordStatus status;
  final String? referenceNo;
  final DateTime requestedAt;
  final DateTime? paidAt;
  final String createdBy;

  bool get successful =>
      status == PaymentRecordStatus.success && paidAt != null;
}

class RecordOrderPaymentInput {
  const RecordOrderPaymentInput({
    required this.expectedOrderVersion,
    required this.paymentMethod,
    required this.amount,
    this.referenceNo,
  });

  final int expectedOrderVersion;
  final OrderPaymentMethod paymentMethod;
  final MenuPrice amount;
  final String? referenceNo;

  String? get normalizedReferenceNo {
    final value = referenceNo?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Map<String, String> get validationErrors => {
    if (expectedOrderVersion < 0)
      'expectedOrderVersion': 'Phiên bản đơn không hợp lệ. Hãy tải lại đơn.',
    if (amount.minorUnits <= 0) 'amount': 'Số tiền thanh toán phải lớn hơn 0.',
    if ((normalizedReferenceNo?.length ?? 0) > 100)
      'referenceNo': 'Mã tham chiếu tối đa 100 ký tự.',
    if (paymentMethod == OrderPaymentMethod.transfer &&
        normalizedReferenceNo == null)
      'referenceNo': 'Nhập mã tham chiếu giao dịch đã nhận tiền.',
  };
}
