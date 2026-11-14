import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/binary_download.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_price.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_transfer_qr.dart';
import 'package:pos_saas_app/features/order/domain/repositories/order_transfer_qr_repository.dart';

import '../../helpers/qr_fakes.dart';

OrderTransferQr transferQr({
  int version = 5,
  String amount = '100000.00',
  String content = 'TT ODTEST',
}) => OrderTransferQr(
  orderId: 'o1',
  orderVersion: version,
  amount: MenuPrice.parse(amount),
  currencyCode: 'VND',
  bankBin: '970436',
  accountNumber: '0123456789',
  accountName: 'NGUYEN VAN A',
  transferContent: content,
  qrPayload: '000201010212...6304ABCD',
);

const notConfiguredFailure = Failure(
  type: FailureType.conflict,
  code: 'TRANSFER_ACCOUNT_NOT_CONFIGURED',
  message: 'Nhà hàng chưa cài tài khoản nhận chuyển khoản.',
);

/// Records every read so tests can tell a reload from a cached value, and
/// proves nothing here ever writes.
class FakeTransferQrs implements OrderTransferQrRepository {
  FakeTransferQrs({this.configured = true});

  bool configured;

  /// Overrides the details answer when set.
  Future<Result<OrderTransferQr?>> Function()? onDetails;
  OrderTransferQr Function() current = transferQr;
  final detailCalls = <String>[];
  final imageCalls = <(String, int)>[];

  @override
  Future<Result<OrderTransferQr?>> details(String orderId) async {
    detailCalls.add(orderId);
    if (onDetails case final answer?) return answer();
    return Success(configured ? current() : null);
  }

  @override
  Future<Result<DownloadedFile>> image(String orderId, {int size = 720}) async {
    imageCalls.add((orderId, size));
    return Success(
      DownloadedFile(
        bytes: tinyPng,
        fileName: 'vietqr.png',
        mimeType: 'image/png',
      ),
    );
  }
}
