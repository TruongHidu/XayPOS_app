import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/network/auth_interceptor.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/data/data_sources/order_remote_data_source.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/data/dto/order_requests.dart';
import 'package:pos_saas_app/features/order/data/order_key_generator.dart';
import 'package:pos_saas_app/features/order/data/repositories/order_repository_impl.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_inputs.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_quantity.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_submission.dart';
import '../../helpers/auth_fakes.dart';
import '../../core/network/auth_interceptor_test.dart' show RefreshAdapter;
import 'order_fakes.dart';

void main() {
  test(
    'summary/page/detail parse direct responses and snapshots including cancelled nullable item',
    () {
      final json = orderJson(lineStatus: 'CANCELLED');
      (json['items'] as List).first['itemId'] = null;
      final d = OrderDto.detail(json);
      expect(d.version, 5);
      expect(d.items.first.itemId, isNull);
      expect(d.items.first.lineTotal.minorUnits, 10000000);
      final p = OrderDto.page({
        'content': [json],
        'page': 0,
        'size': 20,
        'totalElements': 1,
        'totalPages': 1,
      });
      expect(p.content.single.orderCode, 'OD-TEST');
    },
  );
  for (final field in [
    'version',
    'items',
    'totalAmount',
    'customerPhone',
    'confirmedAt',
  ]) {
    test('missing $field is rejected, never defaults', () {
      final json = orderJson()..remove(field);
      expect(() => OrderDto.detail(json), throwsFormatException);
    });
  }
  test('invalid enum, money precision, guestCount and dates rejected', () {
    for (final entry in {
      'status': 'UNKNOWN',
      'totalAmount': 0.123,
      'guestCount': 0,
      'createdAt': '2026-02-30T00:00:00Z',
    }.entries) {
      expect(
        () => OrderDto.detail(orderJson()..[entry.key] = entry.value),
        throwsFormatException,
      );
    }
  });
  test(
    'all 9 endpoints use exact method/body/version and only create key',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://orders.invalid'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests.add(r);
            final list = r.method == 'GET' && r.path == '/api/v1/orders';
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: r.method == 'POST' && r.path == '/api/v1/orders'
                    ? 201
                    : 200,
                data: list
                    ? {
                        'content': [orderJson()],
                        'page': 0,
                        'size': 20,
                        'totalElements': 1,
                        'totalPages': 1,
                      }
                    : orderJson(),
              ),
            );
          },
        ),
      );
      final repo = OrderRepositoryImpl(OrderRemoteDataSource(dio));
      final line = CreateOrderLine(
        itemId: itemId,
        quantity: OrderQuantity.parse('1.125'),
        note: 'Ít cay',
      );
      final create = CreateOrderInput(
        context: const OrderCreationContext.takeaway(),
        items: [line],
      );
      final responses = [
        await repo.list(
          const OrderQuery(
            q: ' OD ',
            status: OrderStatus.open,
            serviceType: ServiceType.takeaway,
            tableSessionId: sessionId,
          ),
        ),
        await repo.detail('o1'),
        await repo.create(create, 'stable-key'),
        await repo.update(
          'o1',
          const UpdateOrderInput(expectedVersion: 5, note: ''),
        ),
        await repo.addItems('o1', 5, [line]),
        await repo.updateItem(
          'o1',
          'line1',
          const UpdateOrderLineInput(expectedVersion: 5, note: ''),
        ),
        await repo.confirm('o1', 5),
        await repo.cancelItem('o1', 'line1', 5, '  Đổi món  '),
        await repo.cancel('o1', 5, 'Không dùng'),
      ];
      expect(responses.every((r) => r is Success), isTrue);
      expect(requests.map((r) => (r.method, r.path)).toList(), [
        ('GET', '/api/v1/orders'),
        ('GET', '/api/v1/orders/o1'),
        ('POST', '/api/v1/orders'),
        ('PATCH', '/api/v1/orders/o1'),
        ('POST', '/api/v1/orders/o1/items'),
        ('PATCH', '/api/v1/orders/o1/items/line1'),
        ('POST', '/api/v1/orders/o1/confirm'),
        ('POST', '/api/v1/orders/o1/items/line1/cancel'),
        ('POST', '/api/v1/orders/o1/cancel'),
      ]);
      expect(requests.first.queryParameters['q'], 'OD');
      expect(requests[2].headers['Idempotency-Key'], 'stable-key');
      expect(
        requests.where((r) => r.headers.containsKey('Idempotency-Key')).length,
        1,
      );
      expect(requests[2].data['sourceChannel'], 'WAITER');
      expect(requests[2].data['tableSessionId'], isNull);
      expect(requests[3].data, {'expectedVersion': 5, 'note': ''});
      expect(requests[5].data, {'expectedVersion': 5, 'note': ''});
      expect(requests[7].data['reason'], 'Đổi món');
      expect(requests[2].data.keys, isNot(contains('restaurantId')));
      expect(requests[2].data['items'][0].keys, isNot(contains('unitPrice')));
      dio.close();
    },
  );
  test('create accepts 200 replay and current representation', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) => h.resolve(
            Response(
              requestOptions: r,
              statusCode: 200,
              data: orderJson(version: 9, status: 'CONFIRMED', confirmed: true),
            ),
          ),
        ),
      );
    final repo = OrderRepositoryImpl(OrderRemoteDataSource(dio));
    final result = await repo.create(
      CreateOrderInput(
        context: const OrderCreationContext.takeaway(),
        items: [],
      ),
      'key',
    );
    expect((result as Success<OrderSubmission>).value.order.version, 9);
    expect(result.value.order.summary.status, OrderStatus.confirmed);
    dio.close();
  });
  test('parse failure maps INVALID_ORDER_RESPONSE', () async {
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) => h.resolve(Response(requestOptions: r, data: {})),
        ),
      );
    final result = await OrderRepositoryImpl(
      OrderRemoteDataSource(dio),
    ).detail('o1');
    expect((result as Error).failure.code, 'INVALID_ORDER_RESPONSE');
    dio.close();
  });
  test('PATCH fields absent/null stay omitted, empty clears', () {
    expect(OrderRequests.update(const UpdateOrderInput(expectedVersion: 7)), {
      'expectedVersion': 7,
    });
    expect(
      OrderRequests.update(
        const UpdateOrderInput(expectedVersion: 7, customerName: ''),
      ),
      {'expectedVersion': 7, 'customerName': ''},
    );
  });
  for (final raw in ['0', '-1', '1.0001', '1000000000', 'NaN']) {
    test(
      'quantity rejects $raw',
      () => expect(() => OrderQuantity.parse(raw), throwsFormatException),
    );
  }
  test('quantity preserves 3 decimal digits at numeric boundary', () {
    expect(OrderQuantity.parse('2.000'), OrderQuantity.parse('2'));
    expect(OrderQuantity.parse('0.001').milliUnits, 1);
    expect(OrderQuantity.parse('999999999.999').toNumber(), 999999999.999);
  });
  test('keys are unique secure UUID v4 and within header limit', () {
    final keys = SecureOrderKeyGenerator();
    final ids = List.generate(20, (_) => keys.next());
    expect(ids.toSet().length, 20);
    for (final id in ids) {
      expect(
        id,
        matches(
          RegExp(
            r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
          ),
        ),
      );
    }
  });
  test(
    'order error codes keep code/fieldErrors and distinguish EMPTY_ORDER statuses',
    () {
      for (final code in [
        'CONCURRENT_ORDER_UPDATE',
        'IDEMPOTENCY_KEY_REUSED',
        'ITEM_OUT_OF_STOCK',
        'TABLE_SESSION_IN_USE',
        'ORDER_NOT_FOUND',
        'ORDER_CURRENCY_MISMATCH',
        'ORDER_HAS_FINANCIAL_OBLIGATIONS',
        'INVALID_IDEMPOTENCY_KEY',
      ]) {
        final r = RequestOptions(path: '/api/v1/orders');
        final f = ApiErrorMapper.fromException(
          DioException(
            requestOptions: r,
            response: Response(
              requestOptions: r,
              statusCode: 409,
              data: {
                'code': code,
                'message': 'raw',
                'fieldErrors': {'note': 'bad'},
              },
            ),
          ),
        );
        expect(f.code, code);
        expect(f.fieldErrors, {'note': 'bad'});
        expect(f.type, isNot(FailureType.internal));
      }
    },
  );
  test('401 refresh retry preserves create key and exact payload', () async {
    final client = Dio()..httpClientAdapter = CreateRetryAdapter();
    final refresh = Dio()..httpClientAdapter = RefreshAdapter();
    final adapter = client.httpClientAdapter as CreateRetryAdapter;
    client.interceptors.add(
      AuthInterceptor(
        client: client,
        refreshClient: refresh,
        tokenStorage: FakeTokenStorage(makeTokens(accessToken: 'old-access')),
        sessionEvents: SessionEvents(),
      ),
    );
    final result = await OrderRepositoryImpl(OrderRemoteDataSource(client))
        .create(
          CreateOrderInput(
            context: const OrderCreationContext.takeaway(),
            items: [
              CreateOrderLine(itemId: itemId, quantity: OrderQuantity.one),
            ],
          ),
          'same-key',
        );
    expect(result, isA<Success<OrderSubmission>>());
    expect(adapter.requests.length, 2);
    expect(adapter.requests[0], adapter.requests[1]);
    client.close();
    refresh.close();
  });
}

class CreateRetryAdapter implements HttpClientAdapter {
  final requests = <(String, Object?)>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add((
      options.headers['Idempotency-Key'] as String,
      jsonEncode(options.data),
    ));
    final ok = options.headers['Authorization'] == 'Bearer new-access';
    return ResponseBody.fromString(
      jsonEncode(ok ? orderJson() : {'code': 'UNAUTHORIZED'}),
      ok ? (options.path.endsWith('/items') ? 200 : 201) : 401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
