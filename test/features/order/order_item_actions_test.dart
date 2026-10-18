import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/data/data_sources/order_remote_data_source.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/data/repositories/order_repository_impl.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_item_action.dart';
import 'package:pos_saas_app/features/order/domain/policies/order_access_policy.dart';
import 'package:pos_saas_app/features/order/domain/use_cases/order_use_cases.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_events.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_detail_controller.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_settlement_controller.dart';
import '../../helpers/auth_fakes.dart';
import 'order_fakes.dart';

const _rights = {
  'ORDER_VIEW',
  'ORDER_CANCEL',
  'ORDER_COMPLETE',
  'ORDER_MARK_SERVED',
  'TABLE_CLOSE',
  'KITCHEN_START_COOKING',
  'KITCHEN_MARK_READY',
};
const _features = {'ORDER_MANAGEMENT', 'TABLE_MANAGEMENT', 'KITCHEN_DISPLAY'};
const _network = Failure(type: FailureType.network, message: 'Mất mạng');
const _conflict = Failure(
  type: FailureType.conflict,
  code: 'CONCURRENT_ORDER_UPDATE',
  message: 'Đơn đã thay đổi',
);

Map<String, dynamic> _json({
  String line = 'PENDING',
  int version = 5,
  bool paid = false,
  String? status,
}) =>
    orderJson(
        version: version,
        confirmed: true,
        lineStatus: line,
        status: status ?? (line == 'SERVED' ? 'SERVED' : 'PREPARING'),
      )
      ..['paymentStatus'] = paid ? 'PAID' : 'UNPAID'
      ..['paidAmount'] = paid ? 100000 : 0
      ..['completedAt'] = status == 'COMPLETED' ? '2026-10-18T10:00:00Z' : null;
OrderDetail _order({
  String line = 'PENDING',
  int version = 5,
  bool paid = false,
  String? status,
}) => OrderDto.detail(
  _json(line: line, version: version, paid: paid, status: status),
);

class _Harness {
  _Harness({OrderDetail? initial, Set<String> rights = _rights}) {
    who = makeAppSession(permissions: rights, features: _features);
    repo.current = initial ?? _order();
    read = detail(repo, () => who, events: events);
    settlement = OrderSettlementController(
      id: 'o1',
      session: () => who,
      events: events,
      getOrder: GetOrderDetail(repo),
      recordPayment: RecordOrderPayment(repo),
      completeOrder: CompleteOrder(repo),
      markAllServed: MarkAllOrderItemsServed(repo),
      keys: TestKeys(),
      root: () => read.order,
      beforeSend: read.beginSubmission,
      onApplied: read.applySubmission,
      appliedSource: () => read,
    );
  }
  final repo = FakeOrders();
  final events = OrderEvents();
  late AppSession? who;
  late final OrderDetailController read;
  late final OrderSettlementController settlement;
  void dispose() {
    settlement.dispose();
    read.dispose();
    events.dispose();
  }
}

void main() {
  test(
    'bulk preserves cancelled lines and rejects a response that revives one',
    () async {
      OrderDetail snapshot(String line, int version, {bool revive = false}) {
        final json = _json(line: line, version: version, paid: true);
        final first = (json['items'] as List).single as Map<String, dynamic>;
        json['items'] = [
          first,
          {
            ...first,
            'id': 'cancelled-1',
            'status': revive ? 'SERVED' : 'CANCELLED',
          },
        ];
        return OrderDto.detail(json);
      }

      for (final invalid in [false, true]) {
        final h = _Harness(initial: snapshot('PENDING', 5));
        addTearDown(h.dispose);
        h.repo.onMarkAllServed = () async =>
            Success(snapshot('SERVED', 8, revive: invalid));
        h.repo.onComplete = () async {
          final json = _json(
            line: 'SERVED',
            version: 10,
            paid: true,
            status: 'COMPLETED',
          );
          final first = (json['items'] as List).single as Map<String, dynamic>;
          json['items'] = [
            first,
            {...first, 'id': 'cancelled-1', 'status': 'CANCELLED'},
          ];
          return Success(OrderDto.detail(json));
        };
        final result = await h.settlement.serveAllAndComplete(h.read.order!);
        if (invalid) {
          expect(result, isA<Error<OrderDetail>>());
          expect(h.repo.completes, isEmpty);
        } else {
          expect(result, isA<Success<OrderDetail>>());
          expect(h.read.order!.items.last.status, OrderItemStatus.cancelled);
        }
      }
    },
  );
  for (final action in OrderItemAction.values) {
    test(
      '${action.endpoint} uses order version and the correct line endpoint',
      () async {
        final dio = Dio();
        RequestOptions? request;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              request = options;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: _json(line: action.target.code, version: 8),
                ),
              );
            },
          ),
        );
        final repository = OrderRepositoryImpl(OrderRemoteDataSource(dio));
        final result = await repository.transitionItem(
          'o1',
          'line1',
          5,
          action,
        );
        expect(result, isA<Success<OrderDetail>>());
        expect(
          request!.path,
          '/api/v1/orders/o1/items/line1/${action.endpoint}',
        );
        expect(request!.method, 'POST');
        expect(request!.data, {'expectedOrderVersion': 5});
        expect(request!.headers.containsKey('Idempotency-Key'), false);
        dio.close();
      },
    );
  }
  test(
    'bulk served uses a single request; response must contain served live items',
    () async {
      final dio = Dio();
      var valid = true;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.path, '/api/v1/orders/o1/mark-served');
            expect(options.data, {'expectedOrderVersion': 5});
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _json(
                  line: valid ? 'SERVED' : 'COOKING',
                  version: 8,
                  paid: true,
                ),
              ),
            );
          },
        ),
      );
      final repo = OrderRepositoryImpl(OrderRemoteDataSource(dio));
      expect(await repo.markAllServed('o1', 5), isA<Success<OrderDetail>>());
      valid = false;
      final invalid = await repo.markAllServed('o1', 5);
      expect(invalid, isA<Error<OrderDetail>>());
      expect((invalid as Error).failure.code, 'INVALID_ORDER_RESPONSE');
      dio.close();
    },
  );
  test(
    'transition rejects an unrelated line or a response at the wrong target',
    () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: _json(line: 'PENDING', version: 8),
              ),
            );
          },
        ),
      );
      final repo = OrderRepositoryImpl(OrderRemoteDataSource(dio));
      expect(
        await repo.transitionItem(
          'o1',
          'line1',
          5,
          OrderItemAction.startCooking,
        ),
        isA<Error<OrderDetail>>(),
      );
      expect(
        await repo.transitionItem(
          'o1',
          'other-line',
          5,
          OrderItemAction.startCooking,
        ),
        isA<Error<OrderDetail>>(),
      );
      dio.close();
    },
  );
  test(
    'pending lines on preparing orders can cancel but cooking and paid lines cannot',
    () {
      final pending = _order();
      expect(
        OrderAccessPolicy.canCancelLine(pending, pending.items.single, true),
        true,
      );
      final cooking = _order(line: 'COOKING');
      expect(
        OrderAccessPolicy.canCancelLine(cooking, cooking.items.single, true),
        false,
      );
      final paid = _order(paid: true);
      expect(
        OrderAccessPolicy.canCancelLine(paid, paid.items.single, true),
        false,
      );
    },
  );
  test(
    'detail advances a paid item with kitchen action permission without KITCHEN_VIEW',
    () async {
      final h = _Harness(initial: _order(paid: true));
      addTearDown(h.dispose);
      h.repo.onTransition = () async =>
          Success(_order(line: 'COOKING', version: 7, paid: true));
      expect(
        h.read.lineTransitionable(
          h.read.order!.items.single,
          OrderItemAction.startCooking,
        ),
        true,
      );
      final result = await h.read.transitionLine(
        h.read.order!.items.single,
        OrderItemAction.startCooking,
        5,
      );
      expect(result, isA<Success<OrderDetail>>());
      expect(h.repo.itemTransitions.single, (
        'o1',
        'line1',
        5,
        OrderItemAction.startCooking,
      ));
      expect(h.read.order!.items.single.status, OrderItemStatus.cooking);
    },
  );
  test(
    'OPEN, missing action permission and stale versions never send transitions',
    () async {
      final h = _Harness(
        initial: _order(status: 'OPEN'),
        rights: {'ORDER_VIEW', 'ORDER_UPDATE'},
      );
      addTearDown(h.dispose);
      expect(
        h.read.lineTransitionable(
          h.read.order!.items.single,
          OrderItemAction.startCooking,
        ),
        false,
      );
      h.read.applySubmission(_order(line: 'READY'));
      expect(
        await h.read.transitionLine(
          h.read.order!.items.single,
          OrderItemAction.markServed,
          5,
        ),
        isA<Error<OrderDetail>>(),
      );
      expect(h.repo.itemTransitions, isEmpty);
      h.who = makeAppSession(permissions: _rights, features: _features);
      final fresh = _Harness(initial: _order(line: 'READY', version: 7));
      addTearDown(fresh.dispose);
      expect(
        await fresh.read.transitionLine(
          fresh.read.order!.items.single,
          OrderItemAction.markServed,
          5,
        ),
        isA<Error<OrderDetail>>(),
      );
      expect(fresh.repo.itemTransitions, isEmpty);
    },
  );
  test(
    'shared order lock prevents duplicate line transitions and completion',
    () async {
      final h = _Harness(initial: _order(line: 'READY', paid: true));
      addTearDown(h.dispose);
      final deferred = Completer<Result<OrderDetail>>();
      h.repo.onTransition = () => deferred.future;
      final first = h.read.transitionLine(
        h.read.order!.items.single,
        OrderItemAction.markServed,
        5,
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        await h.read.transitionLine(
          h.read.order!.items.single,
          OrderItemAction.markServed,
          5,
        ),
        isA<Error<OrderDetail>>(),
      );
      expect(h.settlement.canBeginCompletion, false);
      deferred.complete(
        Success(_order(line: 'SERVED', version: 6, paid: true)),
      );
      await first;
      expect(h.repo.itemTransitions, hasLength(1));
    },
  );
  test(
    'confirmation flow serves once then completes using the returned version',
    () async {
      final h = _Harness(initial: _order(paid: true));
      addTearDown(h.dispose);
      h.repo.onMarkAllServed = () async => Success(
        h.repo.current = _order(line: 'SERVED', paid: true, version: 8),
      );
      h.repo.onComplete = () async => Success(
        h.repo.current = _order(
          line: 'SERVED',
          paid: true,
          version: 10,
          status: 'COMPLETED',
        ),
      );
      expect(h.settlement.canComplete, false);
      expect(h.settlement.canBeginCompletion, true);
      expect(
        await h.settlement.serveAllAndComplete(h.read.order!),
        isA<Success<OrderDetail>>(),
      );
      expect(h.repo.servedBatches.single, ('o1', 5));
      expect(h.repo.completes.single, ('o1', 8));
      expect(h.read.order!.summary.status, OrderStatus.completed);
    },
  );
  test(
    'unpaid and missing serve permission block the chain; served orders skip bulk',
    () async {
      final unpaid = _Harness();
      addTearDown(unpaid.dispose);
      expect(
        await unpaid.settlement.serveAllAndComplete(unpaid.read.order!),
        isA<Error<OrderDetail>>(),
      );
      expect(unpaid.repo.servedBatches, isEmpty);
      final h = _Harness(
        initial: _order(paid: true),
        rights: {'ORDER_VIEW', 'ORDER_COMPLETE'},
      );
      addTearDown(h.dispose);
      expect(h.settlement.canBeginCompletion, false);
      h.read.applySubmission(_order(line: 'SERVED', paid: true, version: 6));
      h.repo.onComplete = () async => Success(
        _order(line: 'SERVED', paid: true, version: 7, status: 'COMPLETED'),
      );
      expect(
        await h.settlement.serveAllAndComplete(h.read.order!),
        isA<Success<OrderDetail>>(),
      );
      expect(h.repo.servedBatches, isEmpty);
      expect(h.repo.completes.single.$2, 6);
    },
  );
  test(
    'bulk refusal never calls complete and requires explicit review',
    () async {
      final h = _Harness(initial: _order(paid: true));
      addTearDown(h.dispose);
      h.repo.onMarkAllServed = () async => const Error(_conflict);
      expect(
        await h.settlement.serveAllAndComplete(h.read.order!),
        isA<Error<OrderDetail>>(),
      );
      expect(h.repo.completes, isEmpty);
      expect(h.settlement.needsReview, true);
      expect(h.settlement.canBeginCompletion, false);
    },
  );
  test(
    'complete failure retains already-served response and only completes after review',
    () async {
      final h = _Harness(initial: _order(paid: true));
      addTearDown(h.dispose);
      h.repo.onMarkAllServed = () async => Success(
        h.repo.current = _order(line: 'SERVED', paid: true, version: 8),
      );
      h.repo.onComplete = () async => const Error(_conflict);
      expect(
        await h.settlement.serveAllAndComplete(h.read.order!),
        isA<Error<OrderDetail>>(),
      );
      expect(h.read.order!.items.single.status, OrderItemStatus.served);
      expect(h.read.order!.version, 8);
      expect(h.settlement.servedBeforeCompletion, true);
      h.repo.current = _order(line: 'SERVED', paid: true, version: 9);
      await h.settlement.refresh();
      expect(h.settlement.reviewCurrent(), true);
      h.repo.onComplete = () async => Success(
        _order(line: 'SERVED', paid: true, version: 10, status: 'COMPLETED'),
      );
      expect(
        await h.settlement.serveAllAndComplete(h.read.order!),
        isA<Success<OrderDetail>>(),
      );
      expect(h.repo.servedBatches, hasLength(1));
      expect(h.repo.completes.last.$2, 9);
    },
  );
  test(
    'bulk timeout verifies state without auto-completion or blind retry',
    () async {
      final h = _Harness(initial: _order(paid: true));
      addTearDown(h.dispose);
      h.repo.onMarkAllServed = () async => const Error(_network);
      await h.settlement.serveAllAndComplete(h.read.order!);
      expect(h.settlement.servingOutcomeUnknown, true);
      expect(h.repo.completes, isEmpty);
      h.repo.current = _order(line: 'SERVED', paid: true, version: 8);
      await h.settlement.refresh();
      expect(h.settlement.uncertain, false);
      expect(h.settlement.needsReview, true);
      expect(h.repo.completes, isEmpty);
      expect(h.repo.servedBatches, hasLength(1));
    },
  );
  test(
    'scope change during serving ignores the old response and does not complete',
    () async {
      final h = _Harness(initial: _order(paid: true));
      addTearDown(h.dispose);
      final deferred = Completer<Result<OrderDetail>>();
      h.repo.onMarkAllServed = () => deferred.future;
      final request = h.settlement.serveAllAndComplete(h.read.order!);
      h.who = null;
      deferred.complete(
        Success(_order(line: 'SERVED', paid: true, version: 8)),
      );
      expect(await request, isA<Error<OrderDetail>>());
      expect(h.repo.completes, isEmpty);
      expect(h.read.order!.version, 5);
    },
  );
}
