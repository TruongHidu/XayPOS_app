import '../../../../core/network/binary_download.dart';
import '../../../../core/result/result.dart';
import '../entities/order_transfer_qr.dart';

/// Read-only VietQR for paying an order by bank transfer.
abstract interface class OrderTransferQrRepository {
  /// Null when the restaurant has no receiving account yet.
  Future<Result<OrderTransferQr?>> details(String orderId);

  Future<Result<DownloadedFile>> image(String orderId, {int size});
}
