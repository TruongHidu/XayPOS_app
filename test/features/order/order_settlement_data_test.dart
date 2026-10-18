import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_price.dart';
import 'package:pos_saas_app/features/order/data/data_sources/order_remote_data_source.dart';
import 'package:pos_saas_app/features/order/data/dto/order_payment_dto.dart';
import 'package:pos_saas_app/features/order/data/dto/order_requests.dart';
import 'package:pos_saas_app/features/order/data/repositories/order_repository_impl.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_payment.dart';
import 'order_fakes.dart';

Map<String, dynamic> _paymentJson({
  String method = 'CASH',
  String? referenceNo,
}) => {
  'id': 'payment1',
  'orderId': 'o1',
  'paymentCode': 'PAY-TEST',
  'amount': 100000,
  'currencyCode': 'VND',
  'paymentMethod': method,
  'confirmationSource': 'STAFF_MANUAL',
  'provider': null,
  'status': 'SUCCESS',
  'referenceNo': referenceNo,
  'requestedAt': '2026-10-17T00:00:00Z',
  'paidAt': '2026-10-17T00:00:00Z',
  'createdBy': 'u1',
};

RecordOrderPaymentInput _input({
  OrderPaymentMethod method = OrderPaymentMethod.cash,
  String? referenceNo,
}) => RecordOrderPaymentInput(
  expectedOrderVersion: 5,
  paymentMethod: method,
  amount: MenuPrice.parse('100000.00'),
  referenceNo: referenceNo,
);

void main() {
  test(
    'payment input validates exact money and trimmed transfer reference',
    () {
      expect(_input().validationErrors, isEmpty);
      expect(
        _input(
          method: OrderPaymentMethod.transfer,
          referenceNo: '  ',
        ).validationErrors,
        contains('referenceNo'),
      );
      expect(
        _input(referenceNo: List.filled(101, 'x').join()).validationErrors,
        contains('referenceNo'),
      );
      final invalid = RecordOrderPaymentInput(
        expectedOrderVersion: -1,
        paymentMethod: OrderPaymentMethod.cash,
        amount: MenuPrice.zero,
      );
      expect(
        invalid.validationErrors.keys,
        containsAll(['expectedOrderVersion', 'amount']),
      );
      expect(
        OrderRequests.payment(
          _input(
            method: OrderPaymentMethod.transfer,
            referenceNo: '  BANK-123  ',
          ),
        ),
        {
          'expectedOrderVersion': 5,
          'paymentMethod': 'TRANSFER',
          'amount': 100000,
          'referenceNo': 'BANK-123',
        },
      );
      expect(
        OrderRequests.payment(_input(referenceNo: '  ')),
        isNot(contains('referenceNo')),
      );
    },
  );

  test(
    'PaymentResponse parses exact hundredths independently of OrderResponse',
    () {
      final json = _paymentJson()..['amount'] = 123.45;
      final payment = OrderPaymentDto.parse(json);
      expect(payment.amount.minorUnits, 12345);
      expect(payment.paymentMethod, OrderPaymentMethod.cash);
      expect(payment.status, PaymentRecordStatus.success);
      expect(payment.confirmationSource, PaymentConfirmationSource.staffManual);
      expect(payment.successful, isTrue);
      expect(payment.provider, isNull);
      expect(payment.referenceNo, isNull);
      expect(payment.paidAt, DateTime.utc(2026, 10, 17));
    },
  );

  test('PaymentResponse rejects missing fields without defaults', () {
    for (final field in _paymentJson().keys) {
      expect(
        () => OrderPaymentDto.parse(_paymentJson()..remove(field)),
        throwsFormatException,
        reason: field,
      );
    }
  });

  test(
    'PaymentResponse rejects unknown enums, precision and invalid dates',
    () {
      for (final entry in {
        'amount': 0.001,
        'currencyCode': 'vnd',
        'paymentMethod': 'CARD',
        'status': 'UNKNOWN',
        'confirmationSource': 'UNKNOWN',
        'paidAt': '2026-02-30T00:00:00Z',
        'requestedAt': 'today',
      }.entries) {
        expect(
          () =>
              OrderPaymentDto.parse(_paymentJson()..[entry.key] = entry.value),
          throwsFormatException,
          reason: entry.key,
        );
      }
    },
  );

  for (final status in [201, 200]) {
    test(
      'payment POST accepts $status, exact body, headers and PaymentResponse',
      () async {
        RequestOptions? request;
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (r, h) {
                request = r;
                h.resolve(
                  Response(
                    requestOptions: r,
                    statusCode: status,
                    headers: Headers.fromMap({
                      'Idempotency-Replayed': ['${status == 200}'],
                    }),
                    data: _paymentJson(
                      method: 'TRANSFER',
                      referenceNo: 'BANK-123',
                    ),
                  ),
                );
              },
            ),
          );
        addTearDown(dio.close);
        final result = await OrderRepositoryImpl(OrderRemoteDataSource(dio))
            .recordPayment(
              'o1',
              _input(
                method: OrderPaymentMethod.transfer,
                referenceNo: '  BANK-123  ',
              ),
              'same-key',
            );
        expect((result as Success<OrderPayment>).value.orderId, 'o1');
        expect(request!.method, 'POST');
        expect(request!.path, '/api/v1/orders/o1/payments');
        expect(request!.headers['Idempotency-Key'], 'same-key');
        expect(request!.headers['Accept'], 'application/json');
        expect(request!.contentType, Headers.jsonContentType);
        expect(request!.data, {
          'expectedOrderVersion': 5,
          'paymentMethod': 'TRANSFER',
          'amount': 100000,
          'referenceNo': 'BANK-123',
        });
        expect(request!.data.keys, isNot(contains('restaurantId')));
        expect(request!.data.keys, isNot(contains('paymentStatus')));
        expect(request!.data.keys, isNot(contains('currencyCode')));
      },
    );
  }

  test(
    'cash request omits optional blank reference; replay header may be absent',
    () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) {
              expect(r.data, {
                'expectedOrderVersion': 5,
                'paymentMethod': 'CASH',
                'amount': 100000,
              });
              h.resolve(
                Response(
                  requestOptions: r,
                  statusCode: 200,
                  data: _paymentJson(),
                ),
              );
            },
          ),
        );
      addTearDown(dio.close);
      expect(
        await OrderRepositoryImpl(
          OrderRemoteDataSource(dio),
        ).recordPayment('o1', _input(referenceNo: ' '), 'stable'),
        isA<Success<OrderPayment>>(),
      );
    },
  );

  test(
    'invalid payment representation maps INVALID_PAYMENT_RESPONSE',
    () async {
      final invalid = <Object?>[
        orderJson(),
        {},
        _paymentJson()..['orderId'] = 'another-order',
        _paymentJson()..['amount'] = 1,
        _paymentJson()..['status'] = 'PENDING',
        _paymentJson()..['paidAt'] = null,
        _paymentJson()..['paymentMethod'] = 'TRANSFER',
        _paymentJson()..['confirmationSource'] = 'PROVIDER_WEBHOOK',
        _paymentJson()..['referenceNo'] = 'another-ref',
        _paymentJson()..remove('amount'),
      ];
      for (final json in invalid) {
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (r, h) {
                h.resolve(
                  Response(requestOptions: r, statusCode: 201, data: json),
                );
              },
            ),
          );
        final result = await OrderRepositoryImpl(
          OrderRemoteDataSource(dio),
        ).recordPayment('o1', _input(), 'stable');
        expect((result as Error).failure.code, 'INVALID_PAYMENT_RESPONSE');
        dio.close();
      }
    },
  );

  test('payment unexpected success status remains unresolved', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: 202,
                data: _paymentJson(),
              ),
            );
          },
        ),
      );
    addTearDown(dio.close);
    final result = await OrderRepositoryImpl(
      OrderRemoteDataSource(dio),
    ).recordPayment('o1', _input(), 'stable');
    expect((result as Error).failure.code, 'INVALID_PAYMENT_RESPONSE');
  });

  test(
    'payment conflict retains conflict type, code and field errors',
    () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) {
              h.reject(
                DioException(
                  requestOptions: r,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: r,
                    statusCode: 409,
                    data: {
                      'code': 'PAYMENT_AMOUNT_MISMATCH',
                      'message': 'changed total',
                      'fieldErrors': {'amount': 'changed'},
                    },
                  ),
                ),
              );
            },
          ),
        );
      addTearDown(dio.close);
      final result = await OrderRepositoryImpl(
        OrderRemoteDataSource(dio),
      ).recordPayment('o1', _input(), 'stable');
      final failure = (result as Error).failure;
      expect(failure.code, 'PAYMENT_AMOUNT_MISMATCH');
      expect(failure.type, FailureType.conflict);
      expect(failure.fieldErrors, {'amount': 'changed'});
    },
  );

  test(
    'completion posts only expectedVersion and parses completed OrderResponse',
    () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) {
              expect(r.path, '/api/v1/orders/o1/complete');
              expect(r.method, 'POST');
              expect(r.data, {'expectedVersion': 6});
              expect(r.headers, isNot(contains('Idempotency-Key')));
              final json =
                  orderJson(
                      version: 7,
                      status: 'COMPLETED',
                      lineStatus: 'SERVED',
                    )
                    ..['paymentStatus'] = 'PAID'
                    ..['paidAmount'] = 100000
                    ..['completedAt'] = '2026-10-17T00:00:00Z';
              h.resolve(
                Response(requestOptions: r, statusCode: 200, data: json),
              );
            },
          ),
        );
      addTearDown(dio.close);
      final result = await OrderRepositoryImpl(
        OrderRemoteDataSource(dio),
      ).complete('o1', 6);
      final order = (result as Success<OrderDetail>).value;
      expect(order.version, 7);
      expect(order.summary.status, OrderStatus.completed);
      expect(order.summary.paymentStatus, OrderPaymentStatus.paid);
      expect(order.completedAt, isNotNull);
    },
  );

  test(
    'completion rejects another order, invalid status and incomplete response',
    () async {
      for (final json in [
        orderJson(),
        orderJson(status: 'COMPLETED'),
        orderJson(status: 'COMPLETED')..['id'] = 'other',
        _paymentJson(),
      ]) {
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (r, h) {
                h.resolve(
                  Response(requestOptions: r, statusCode: 200, data: json),
                );
              },
            ),
          );
        final result = await OrderRepositoryImpl(
          OrderRemoteDataSource(dio),
        ).complete('o1', 6);
        expect((result as Error).failure.code, 'INVALID_ORDER_RESPONSE');
        dio.close();
      }
    },
  );
}
