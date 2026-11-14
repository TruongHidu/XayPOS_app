import 'dart:typed_data';

import '../../../menu/domain/entities/menu_price.dart';

/// What the server encoded in the VietQR for one order version: who receives
/// the money, how much, and the content the customer's bank app pre-fills.
/// Display only; it never records a payment.
class OrderTransferQr {
  const OrderTransferQr({
    required this.orderId,
    required this.orderVersion,
    required this.amount,
    required this.currencyCode,
    required this.bankBin,
    required this.accountNumber,
    required this.accountName,
    required this.transferContent,
    required this.qrPayload,
  });

  final String orderId;
  final int orderVersion;
  final MenuPrice amount;
  final String currencyCode;
  final String bankBin;
  final String accountNumber;
  final String accountName;

  /// `TT ` + the last 10 letters/digits of the order code. Also what the app
  /// pre-fills as the payment reference.
  final String transferContent;

  /// The EMVCo string inside the QR picture.
  final String qrPayload;
}

/// [details] plus the server-rendered PNG of the code.
class OrderTransferQrCode {
  const OrderTransferQrCode({required this.details, required this.png});

  final OrderTransferQr details;
  final Uint8List png;
}
