import '../../domain/entities/order_payment.dart';
import 'order_dto.dart';

abstract final class OrderPaymentDto {
  static OrderPayment parse(Object? value) {
    final j = OrderDto.object(value);
    final currency = OrderDto.string(j, 'currencyCode');
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const FormatException('Invalid payment currency');
    }
    final amount = OrderDto.money(j, 'amount');
    if (amount.minorUnits <= 0) {
      throw const FormatException('Invalid payment amount');
    }
    return OrderPayment(
      id: OrderDto.string(j, 'id'),
      orderId: OrderDto.string(j, 'orderId'),
      paymentCode: OrderDto.string(j, 'paymentCode'),
      amount: amount,
      currencyCode: currency,
      paymentMethod: OrderDto.parseEnum(
        OrderPaymentMethod.values,
        OrderDto.string(j, 'paymentMethod'),
        (v) => v.code,
      ),
      confirmationSource: OrderDto.parseEnum(
        PaymentConfirmationSource.values,
        OrderDto.string(j, 'confirmationSource'),
        (v) => v.code,
      ),
      provider: OrderDto.nullableString(j, 'provider'),
      status: OrderDto.parseEnum(
        PaymentRecordStatus.values,
        OrderDto.string(j, 'status'),
        (v) => v.code,
      ),
      referenceNo: OrderDto.nullableString(j, 'referenceNo'),
      requestedAt: OrderDto.date(j, 'requestedAt')!,
      paidAt: OrderDto.date(j, 'paidAt', nullable: true),
      createdBy: OrderDto.string(j, 'createdBy'),
    );
  }
}
