import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/kitchen/data/data_sources/kitchen_remote_data_source.dart';
import 'package:pos_saas_app/features/kitchen/data/dto/kitchen_dto.dart';
import 'package:pos_saas_app/features/kitchen/data/repositories/kitchen_repository_impl.dart';
import 'package:pos_saas_app/features/kitchen/domain/entities/kitchen_queue.dart';
import 'package:pos_saas_app/features/kitchen/domain/use_cases/kitchen_use_cases.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import '../../helpers/auth_fakes.dart';
import '../order/order_fakes.dart';
import 'kitchen_fakes.dart';

class KitchenAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  Object data = {};
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'queue and mutation use exact HTTP contract without extra fields/keys',
    () async {
      final adapter = KitchenAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://kitchen.invalid'))
        ..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final repo = KitchenRepositoryImpl(KitchenRemoteDataSource(dio));
      adapter.data = {
        'content': [kitchenJson(quantity: 1.25)],
        'page': 2,
        'size': 20,
        'totalElements': 41,
        'totalPages': 3,
      };
      final page = await repo.queue(
        const KitchenQueueQuery(status: OrderItemStatus.pending, page: 2),
      );
      expect(
        (page as Success<KitchenQueuePage>).value.content.single.quantity
            .toString(),
        '1.25',
      );
      expect(adapter.requests.single.path, '/api/v1/kitchen/items');
      expect(adapter.requests.single.queryParameters, {
        'status': 'PENDING',
        'page': 2,
        'size': 20,
      });
      adapter.data = orderJson(
        status: 'PREPARING',
        lineStatus: 'COOKING',
        version: 4,
        confirmed: true,
      );
      final result = await repo.transition(
        const KitchenItemTransition(
          orderId: 'o1',
          orderItemId: 'line1',
          expectedOrderVersion: 3,
          action: KitchenAction.startCooking,
        ),
      );
      expect((result as Success<OrderDetail>).value.version, 4);
      final request = adapter.requests.last;
      expect(request.path, '/api/v1/orders/o1/items/line1/start-cooking');
      expect(request.data, {'expectedOrderVersion': 3});
      expect(request.headers['Accept'], 'application/json');
      expect(request.contentType, Headers.jsonContentType);
      expect(request.headers.containsKey('Idempotency-Key'), false);
    },
  );
  test(
    'malformed success and HTTP 5xx remain uncertain regardless of error code',
    () async {
      final adapter = KitchenAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://kitchen.invalid'))
        ..httpClientAdapter = adapter;
      addTearDown(dio.close);
      final repo = KitchenRepositoryImpl(KitchenRemoteDataSource(dio));
      const input = KitchenItemTransition(
        orderId: 'o1',
        orderItemId: 'i1',
        expectedOrderVersion: 3,
        action: KitchenAction.markReady,
      );
      expect(
        (await repo.transition(input) as Error<OrderDetail>).failure.code,
        'INVALID_KITCHEN_RESPONSE',
      );
      adapter.status = 503;
      adapter.data = {'code': 'CONCURRENT_ORDER_UPDATE', 'message': 'Conflict'};
      final error = await repo.transition(input) as Error<OrderDetail>;
      expect(error.failure.type, FailureType.internal);
      expect(error.failure.code, 'CONCURRENT_ORDER_UPDATE');
    },
  );
  test(
    'strict parsing preserves nullable seating/note and rejects invalid status/version',
    () {
      final json = kitchenJson(note: null, takeaway: true);
      final item = KitchenDto.item(json);
      expect(item.seating, 'Mang đi');
      expect(item.note, isNull);
      expect(item.queuedAt, item.createdAt);
      expect(
        () => KitchenDto.item({...json, 'itemStatus': 'SERVED'}),
        throwsFormatException,
      );
      expect(
        () => KitchenDto.item({...json, 'orderVersion': null}),
        throwsFormatException,
      );
      expect(
        () => KitchenDto.item({...json, 'quantity': 0}),
        throwsFormatException,
      );
    },
  );
  test(
    'validation rejects ALL-equivalent terminal query and missing version before HTTP',
    () async {
      final repo = FakeKitchen();
      final query = await GetKitchenQueue(repo)(
        const KitchenQueueQuery(status: OrderItemStatus.served),
      );
      final mutation = await TransitionKitchenItem(repo)(
        const KitchenItemTransition(
          orderId: 'o1',
          orderItemId: 'i1',
          expectedOrderVersion: -1,
          action: KitchenAction.markReady,
        ),
      );
      expect(query, isA<Error<KitchenQueuePage>>());
      expect(mutation, isA<Error<OrderDetail>>());
      expect(repo.queries, isEmpty);
      expect(repo.writes, isEmpty);
    },
  );
  test(
    'effective kitchen rights are independent of ORDER_VIEW and legacy KITCHEN_UPDATE',
    () {
      final session = makeAppSession(
        role: UserRole.kitchen,
        permissions: kitchenPermissions,
        features: {'KITCHEN_DISPLAY'},
      );
      expect(AccessPolicy.canOpenRoute(session, '/app/kitchen'), true);
      expect(AccessPolicy.canOrders(session, 'ORDER_VIEW'), false);
      expect(AccessPolicy.canKitchen(session, 'KITCHEN_MARK_READY'), true);
      expect(AccessPolicy.canKitchen(session, 'KITCHEN_UPDATE'), false);
      expect(
        AccessPolicy.canKitchen(
          makeAppSession(permissions: kitchenPermissions, features: {}),
          'KITCHEN_VIEW',
        ),
        false,
      );
      expect(
        AccessPolicy.canKitchen(
          makeAppSession(
            role: UserRole.cashier,
            permissions: kitchenPermissions,
            features: {'KITCHEN_DISPLAY'},
          ),
          'KITCHEN_VIEW',
        ),
        false,
      );
    },
  );
}
