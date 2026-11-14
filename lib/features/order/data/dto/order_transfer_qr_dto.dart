import '../../../menu/domain/entities/menu_price.dart';
import '../../domain/entities/order_transfer_qr.dart';
import 'order_dto.dart';

abstract final class OrderTransferQrDto {
  static OrderTransferQr parse(Object? value) {
    final j = OrderDto.object(value);
    final currency = OrderDto.string(j, 'currencyCode');
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const FormatException('Invalid transfer QR currency');
    }
    final amount = _amount(j['amount']);
    if (amount.minorUnits <= 0) {
      throw const FormatException('Invalid transfer QR amount');
    }
    final bin = OrderDto.string(j, 'bankBin');
    if (!RegExp(r'^\d{6}$').hasMatch(bin)) {
      throw const FormatException('Invalid transfer QR bank');
    }
    return OrderTransferQr(
      orderId: OrderDto.string(j, 'orderId'),
      orderVersion: OrderDto.integer(j, 'orderVersion'),
      amount: amount,
      currencyCode: currency,
      bankBin: bin,
      accountNumber: OrderDto.string(j, 'accountNumber'),
      accountName: OrderDto.string(j, 'accountName'),
      transferContent: OrderDto.string(j, 'transferContent').trim(),
      qrPayload: OrderDto.string(j, 'qrPayload'),
    );
  }

  /// A decimal string (`"125000.00"`) or a JSON number.
  static MenuPrice _amount(Object? value) => switch (value) {
    final String text => MenuPrice.parse(text),
    final num number => MenuPrice.fromNumber(number),
    _ => throw const FormatException('Invalid transfer QR amount'),
  };
}
