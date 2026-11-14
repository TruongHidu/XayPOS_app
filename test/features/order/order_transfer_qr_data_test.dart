import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/data/data_sources/order_transfer_qr_remote_data_source.dart';
import 'package:pos_saas_app/features/order/data/repositories/order_transfer_qr_repository_impl.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_transfer_qr.dart';
import 'package:pos_saas_app/features/order/domain/use_cases/order_use_cases.dart';

import '../../helpers/qr_fakes.dart';
import 'order_transfer_qr_fakes.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, Object?> _qrJson({Object amount = '100000.00'}) => {
  'orderId': 'o1',
  'orderVersion': 5,
  'amount': amount,
  'currencyCode': 'VND',
  'bankBin': '970436',
  'accountNumber': '0123456789',
  'accountName': 'NGUYEN VAN A',
  'transferContent': 'TT ODTEST',
  'qrPayload': '00020101021238...6304ABCD',
};

(OrderTransferQrRepositoryImpl, _Adapter) _repository(
  ResponseBody Function(RequestOptions options) respond,
) {
  final adapter = _Adapter(respond);
  final dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
    ..httpClientAdapter = adapter;
  return (
    OrderTransferQrRepositoryImpl(OrderTransferQrRemoteDataSource(dio)),
    adapter,
  );
}

void main() {
  test('reads QR details with a decimal-string or number amount', () async {
    Object amount = '125000.00';
    final (repository, adapter) = _repository(
      (_) => _json(_qrJson(amount: amount)),
    );
    final first = await repository.details('o1');
    final qr = (first as Success<OrderTransferQr?>).value!;
    expect(qr.amount.minorUnits, 12500000);
    expect(qr.orderVersion, 5);
    expect(qr.bankBin, '970436');
    expect(qr.transferContent, 'TT ODTEST');
    expect(adapter.requests.single.path, '/api/v1/orders/o1/transfer-qr');

    amount = 99000;
    final second = await repository.details('o1');
    expect(
      (second as Success<OrderTransferQr?>).value!.amount.minorUnits,
      9900000,
    );
  });

  test(
    'a missing receiving account reads as null, other errors stay',
    () async {
      var code = 'TRANSFER_ACCOUNT_NOT_CONFIGURED';
      final (repository, _) = _repository(
        (_) => _json({'code': code, 'message': 'x'}, 409),
      );
      expect(
        (await repository.details('o1') as Success<OrderTransferQr?>).value,
        isNull,
      );
      code = 'TRANSFER_QR_CURRENCY_UNSUPPORTED';
      final failure = (await repository.details('o1') as Error).failure;
      expect(failure.code, 'TRANSFER_QR_CURRENCY_UNSUPPORTED');
      expect(failure.message, contains('VND'));
    },
  );

  test('rejects a QR for another order or with a bad amount', () async {
    var body = {..._qrJson(), 'orderId': 'o2'};
    final (repository, _) = _repository((_) => _json(body));
    expect(await repository.details('o1'), isA<Error<OrderTransferQr?>>());
    body = _qrJson(amount: '0');
    expect(await repository.details('o1'), isA<Error<OrderTransferQr?>>());
  });

  test('image reads the PNG with format and size', () async {
    final (repository, adapter) = _repository(
      (_) => ResponseBody.fromBytes(
        tinyPng,
        200,
        headers: {
          Headers.contentTypeHeader: ['image/png'],
        },
      ),
    );
    final image = await repository.image('o1');
    expect(image, isA<Success>());
    final request = adapter.requests.single;
    expect(request.path, '/api/v1/orders/o1/transfer-qr/image');
    expect(request.queryParameters, {'format': 'png', 'size': 720});
  });

  test('GetOrderTransferQr skips the picture when not configured', () async {
    final qrs = FakeTransferQrs(configured: false);
    final get = GetOrderTransferQr(qrs);
    expect((await get('o1') as Success<OrderTransferQrCode?>).value, isNull);
    expect(qrs.imageCalls, isEmpty);

    qrs.configured = true;
    final code = (await get('o1') as Success<OrderTransferQrCode?>).value!;
    expect(code.details.transferContent, 'TT ODTEST');
    expect(code.png, tinyPng);
    expect(qrs.imageCalls, [('o1', 720)]);

    qrs.onDetails = () async =>
        const Error(Failure(type: FailureType.network, message: 'offline'));
    expect(await get('o1'), isA<Error<OrderTransferQrCode?>>());
    expect(qrs.imageCalls.length, 1);
  });
}
