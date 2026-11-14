import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/network/binary_download.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_transfer_qr.dart';
import '../../domain/repositories/order_transfer_qr_repository.dart';
import '../data_sources/order_transfer_qr_remote_data_source.dart';

class OrderTransferQrRepositoryImpl implements OrderTransferQrRepository {
  const OrderTransferQrRepositoryImpl(this.remote);

  final OrderTransferQrRemoteDataSource remote;

  static const notConfigured = 'TRANSFER_ACCOUNT_NOT_CONFIGURED';

  @override
  Future<Result<OrderTransferQr?>> details(String orderId) async {
    try {
      return Success(await remote.details(orderId));
    } on Object catch (error) {
      final failure = ApiErrorMapper.fromException(error);
      return failure.code == notConfigured
          ? const Success(null)
          : Error(failure);
    }
  }

  @override
  Future<Result<DownloadedFile>> image(String orderId, {int size = 720}) =>
      remote.image(orderId, size: size);
}
