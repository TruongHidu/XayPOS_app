import 'package:dio/dio.dart';

import '../../../../core/network/binary_download.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_transfer_qr.dart';
import '../dto/order_transfer_qr_dto.dart';

class OrderTransferQrRemoteDataSource {
  const OrderTransferQrRemoteDataSource(this.dio);

  final Dio dio;

  static String _path(String orderId) =>
      '/api/v1/orders/${Uri.encodeComponent(orderId)}/transfer-qr';

  Future<OrderTransferQr> details(String orderId) async {
    final response = await dio.get<Object?>(
      _path(orderId),
      options: Options(headers: {'Accept': 'application/json'}),
    );
    final qr = OrderTransferQrDto.parse(response.data);
    if (qr.orderId != orderId) {
      throw const FormatException('Transfer QR for another order');
    }
    return qr;
  }

  Future<Result<DownloadedFile>> image(String orderId, {int size = 720}) =>
      getBinary(
        dio,
        '${_path(orderId)}/image',
        query: {'format': 'png', 'size': size},
        fallbackName: 'vietqr.png',
      );
}
