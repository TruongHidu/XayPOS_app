import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/ui/sidebar/app_sidebar_registry.dart';
import 'package:pos_saas_app/core/ui/sidebar/sidebar_filter.dart';
import 'package:pos_saas_app/features/order/data/data_sources/order_remote_data_source.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/data/dto/order_requests.dart';
import 'package:pos_saas_app/features/order/data/repositories/order_repository_impl.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_inputs.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_quantity.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_submission.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_table_workspace.dart';
import 'package:pos_saas_app/features/order/domain/policies/order_validation.dart';
import 'package:pos_saas_app/features/order/domain/use_cases/order_use_cases.dart';
import 'package:pos_saas_app/features/order/domain/use_cases/order_workspace_use_cases.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_events.dart';
import 'package:pos_saas_app/features/tables/data/dto/table_dto.dart';
import 'package:pos_saas_app/features/tables/domain/use_cases/restaurant_table_use_cases.dart';
import 'package:pos_saas_app/features/tables/domain/use_cases/table_area_use_cases.dart';
import '../../helpers/auth_fakes.dart';
import '../tables/table_fakes.dart';
import 'order_fakes.dart';
import 'order_controller_test.dart' show saleItem;

const tableId = '33333333-3333-4333-8333-333333333333';
const otherTableId = '44444444-4444-4444-8444-444444444444';
Map<String, dynamic> tableData({bool occupied = true, bool areaActive = true}) {
  final data = tableJson(id: tableId, occupied: occupied, canOpen: !occupied);
  (data['area'] as Map)['active'] = areaActive;
  if (occupied) (data['currentSession'] as Map)['id'] = sessionId;
  return data;
}

OrderDetail serving({
  String id = 'o1',
  String session = sessionId,
  int version = 5,
  String status = 'CONFIRMED',
  num total = 100000,
  String currency = 'VND',
}) => OrderDto.detail(
  orderJson(version: version, status: status, confirmed: true)
    ..['id'] = id
    ..['serviceType'] = 'DINE_IN'
    ..['tableSessionId'] = session
    ..['totalAmount'] = total
    ..['currencyCode'] = currency,
);
OrderPage orderPage(
  List<OrderSummary> rows, {
  int page = 0,
  int pages = 1,
  int? total,
}) => OrderPage(
  content: rows,
  page: page,
  size: 100,
  totalElements: total ?? rows.length,
  totalPages: pages,
);

void main() {
  test(
    'pagination stops starting new pages when request scope/generation is obsolete',
    () async {
      final server = TableServer();
      addTearDown(server.close);
      var current = true;
      server.respond = (r) async {
        current = false;
        return Response(
          requestOptions: r,
          statusCode: 200,
          data: {
            'content': [tableData()],
            'page': 0,
            'size': 100,
            'totalElements': 200,
            'totalPages': 2,
          },
        );
      };
      final result = await GetAvailableOrderTables(
        ListRestaurantTable(server.tables),
      )(isCurrent: () => current);
      expect(result, isA<Error<List<dynamic>>>());
      expect(server.requests.length, 1);
    },
  );
  test(
    'table context identity includes target kind/id but ignores display and open hints',
    () {
      const a = OrderCreationContext.fromTable(
        tableId: tableId,
        tableName: 'A',
      );
      const equivalent = OrderCreationContext.fromTable(
        tableId: tableId,
        tableName: 'New',
        guestCount: 9,
        sessionAlreadyOpen: true,
      );
      expect(a, equivalent);
      expect(a.hashCode, equivalent.hashCode);
      expect(
        a,
        isNot(const OrderCreationContext.fromTable(tableId: otherTableId)),
      );
      expect(a, isNot(const OrderCreationContext.dineIn(sessionId: tableId)));
      expect(a, isNot(const OrderCreationContext.takeaway()));
    },
  );
  test(
    'table serializer sends only tableId/SUBMIT, no guessed guests or amounts',
    () {
      final input = CreateOrderInput(
        context: const OrderCreationContext.fromTable(
          tableId: tableId,
          guestCount: 6,
        ),
        items: [CreateOrderLine(itemId: itemId, quantity: OrderQuantity.one)],
        submissionMode: OrderSubmissionMode.submit,
      );
      final body = OrderRequests.create(input);
      expect(body['tableId'], tableId);
      expect(body['submissionMode'], 'SUBMIT');
      expect(body['sourceChannel'], 'WAITER');
      for (final field in [
        'tableSessionId',
        'expectedVersion',
        'guestCount',
        'restaurantId',
        'createdBy',
        'totalAmount',
        'unitPrice',
      ]) {
        expect(body.containsKey(field), false);
      }
      expect(OrderValidation.create(input), isEmpty);
      final draftInput = CreateOrderInput(
        context: input.context,
        items: input.items,
      );
      expect(OrderValidation.create(draftInput), contains('submissionMode'));
      final bad = CreateOrderInput(
        context: const OrderCreationContext.fromTable(tableId: 'bad'),
        items: input.items,
        submissionMode: OrderSubmissionMode.submit,
      );
      expect(OrderValidation.create(bad), contains('tableId'));
    },
  );
  for (final code in [200, 204]) {
    test(
      'active-order $code uses exact session route and distinguishes no body',
      () async {
        final requests = <RequestOptions>[];
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (r, h) {
                requests.add(r);
                h.resolve(
                  Response(
                    requestOptions: r,
                    statusCode: code,
                    data: code == 204
                        ? null
                        : (orderJson()
                            ..['serviceType'] = 'DINE_IN'
                            ..['tableSessionId'] = sessionId),
                  ),
                );
              },
            ),
          );
        addTearDown(dio.close);
        final result = await OrderRepositoryImpl(
          OrderRemoteDataSource(dio),
        ).activeForSession(sessionId);
        expect(result, isA<Success<OrderDetail?>>());
        expect(
          (result as Success<OrderDetail?>).value,
          code == 204 ? isNull : isNotNull,
        );
        expect(requests.single.method, 'GET');
        expect(
          requests.single.path,
          '/api/v1/table-sessions/$sessionId/active-order',
        );
        expect(requests.single.headers['Accept'], 'application/json');
        expect(requests.single.headers.containsKey('Idempotency-Key'), false);
      },
    );
  }
  for (final status in [403, 404, 409]) {
    test('active-order $status is a failure, never no-order', () async {
      final code = status == 403
          ? 'FORBIDDEN'
          : status == 404
          ? 'TABLE_SESSION_NOT_FOUND'
          : 'INCONSISTENT_SERVING_ORDER_STATE';
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) => h.reject(
              DioException(
                requestOptions: r,
                response: Response(
                  requestOptions: r,
                  statusCode: status,
                  data: {'code': code, 'message': 'refused'},
                ),
                type: DioExceptionType.badResponse,
              ),
            ),
          ),
        );
      addTearDown(dio.close);
      final result = await OrderRepositoryImpl(
        OrderRemoteDataSource(dio),
      ).activeForSession(sessionId);
      expect(result, isA<Error<OrderDetail?>>());
      expect((result as Error).failure.code, code);
    });
  }
  test(
    'active-order malformed/wrong session/terminal response fails closed',
    () async {
      for (final data in [
        <String, dynamic>{},
        orderJson(),
        orderJson(status: 'CANCELLED')
          ..['serviceType'] = 'DINE_IN'
          ..['tableSessionId'] = sessionId,
      ]) {
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (r, h) => h.resolve(
                Response(requestOptions: r, statusCode: 200, data: data),
              ),
            ),
          );
        final result = await OrderRepositoryImpl(
          OrderRemoteDataSource(dio),
        ).activeForSession(sessionId);
        expect((result as Error).failure.code, 'INVALID_ORDER_RESPONSE');
        dio.close();
      }
    },
  );
  test(
    'all available tables and areas load every page, dedup and keep available occupied rows',
    () async {
      final server = TableServer();
      addTearDown(server.close);
      server.respond = (r) async {
        final index = r.queryParameters['page'] as int;
        final areas = r.path.endsWith('table-areas');
        final rows = List.generate(
          index == 0 ? 100 : 21,
          (i) => areas
              ? areaJson(id: 'a-${index * 100 + i}')
              : tableJson(
                  id: 't-${index * 100 + i}',
                  occupied: i == 0,
                  canOpen: i != 0,
                ),
        );
        if (index == 1) {
          rows[0] = areas ? areaJson(id: 'a-99') : tableJson(id: 't-99');
        }
        return Response(
          requestOptions: r,
          statusCode: 200,
          data: {
            'content': rows,
            'page': index,
            'size': 100,
            'totalElements': 121,
            'totalPages': 2,
          },
        );
      };
      final tables = await GetAvailableOrderTables(
        ListRestaurantTable(server.tables),
      )();
      final areas = await GetActiveOrderAreas(ListTableArea(server.areas))();
      expect((tables as Success).value.length, 120);
      expect((areas as Success).value.length, 120);
      expect(server.requests.length, 4);
      expect(
        server.requests.every((r) => r.queryParameters['size'] == 100),
        true,
      );
      expect(server.requests.first.queryParameters['status'], 'AVAILABLE');
      expect(
        server.requests.first.queryParameters.containsKey('occupied'),
        false,
      );
      expect(
        server.requests.any((r) => r.path.endsWith('current-session')),
        false,
      );
    },
  );
  test(
    'serving batches load all pages across five statuses with bounded concurrency',
    () async {
      final repo = FakeOrders();
      var inFlight = 0, maximum = 0;
      repo.onList = (q) async {
        inFlight++;
        if (inFlight > maximum) maximum = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        inFlight--;
        final rows = q.status == OrderStatus.confirmed
            ? List.generate(
                q.page == 0 ? 100 : 2,
                (i) => serving(
                  id: 'o-${q.page * 100 + i}',
                  session: 's-${q.page * 100 + i}',
                ).summary,
              )
            : <OrderSummary>[];
        return Success(
          orderPage(
            rows,
            page: q.page,
            pages: q.status == OrderStatus.confirmed ? 2 : 0,
            total: q.status == OrderStatus.confirmed ? 102 : 0,
          ),
        );
      };
      final result = await GetServingOrderSummaries(GetOrders(repo))();
      expect(
        (result as Success<ServingOrderSnapshot>).value.bySession.length,
        102,
      );
      expect(repo.queries.length, 6);
      expect(maximum, lessThanOrEqualTo(3));
      expect(
        repo.queries.every(
          (q) =>
              q.serviceType == ServiceType.dineIn &&
              q.size == 100 &&
              q.status != null,
        ),
        true,
      );
      expect(repo.activeCalls, isEmpty);
      expect(repo.detailCalls, 0);
    },
  );
  test(
    'duplicate same id chooses newer version, history excluded, conflicting ids remain ambiguous',
    () {
      final old = serving(version: 2, total: 90000).summary;
      final newer = serving(version: 3, total: 0, currency: 'USD').summary;
      final history = serving(id: 'history', status: 'CANCELLED').summary;
      final snapshot = ServingOrderSnapshot.fromOrders([old, newer, history]);
      expect(snapshot.bySession[sessionId]!.version, 3);
      expect(snapshot.bySession[sessionId]!.totalAmount.minorUnits, 0);
      expect(snapshot.bySession[sessionId]!.currencyCode, 'USD');
      expect(snapshot.ambiguousSessions, isEmpty);
      final conflict = ServingOrderSnapshot.fromOrders([
        old,
        serving(id: 'other').summary,
      ]);
      expect(conflict.bySession.containsKey(sessionId), false);
      expect(conflict.ambiguousSessions, contains(sessionId));
      expect(() => snapshot.bySession.clear(), throwsUnsupportedError);
    },
  );
  test(
    'one failed status/page never becomes an empty successful snapshot',
    () async {
      final repo = FakeOrders()
        ..onList = (q) async => q.status == OrderStatus.ready
            ? const Error(networkFailure)
            : Success(orderPage([]));
      expect(
        await GetServingOrderSummaries(GetOrders(repo))(),
        isA<Error<ServingOrderSnapshot>>(),
      );
    },
  );
  test(
    'bill model distinguishes empty seating, unknown/forbidden/error and legitimate zero',
    () {
      final table = TableDto.restaurantTable(tableData());
      expect(
        OrderTableTile.from(
          table,
          canView: true,
          loading: false,
          snapshot: ServingOrderSnapshot.fromOrders([]),
        ).billState,
        TableBillState.noOrder,
      );
      expect(
        OrderTableTile.from(table, canView: false, loading: false).billState,
        TableBillState.forbidden,
      );
      expect(
        OrderTableTile.from(table, canView: true, loading: false).billState,
        TableBillState.unknown,
      );
      expect(
        OrderTableTile.from(table, canView: true, loading: true).billState,
        TableBillState.loading,
      );
      final zero = OrderTableTile.from(
        table,
        canView: true,
        loading: false,
        snapshot: ServingOrderSnapshot.fromOrders([serving(total: 0).summary]),
      );
      expect(zero.billState, TableBillState.ready);
      expect(zero.order!.totalAmount.minorUnits, 0);
      expect(zero.table.occupied, true);
      final inconsistent = TableDto.restaurantTable(
        tableData()..['occupied'] = false,
      );
      expect(
        OrderTableTile.from(
          inconsistent,
          canView: true,
          loading: false,
        ).billState,
        TableBillState.inconsistent,
      );
    },
  );
  test(
    'view-only hub shows money and selects bill without CREATE/MENU/OPEN',
    () async {
      final server = TableServer()..table = tableData();
      addTearDown(server.close);
      final repo = FakeOrders()..current = serving();
      final c = hub(
        server,
        () => orderSession(
          permissions: {'ORDER_VIEW', 'TABLE_VIEW'},
          features: {'ORDER_MANAGEMENT', 'TABLE_MANAGEMENT'},
        ),
        orders: repo,
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.tile(c.tables.single).billState, TableBillState.ready);
      expect(c.canSelect(c.tables.single), true);
      final result = await c.selectTable(tableId);
      expect(
        (result as Success<OrderTableSelection>).value,
        isA<ViewTableOrder>(),
      );
      expect(repo.activeCalls, [sessionId]);
      expect(server.requests.any((r) => r.method == 'POST'), false);
    },
  );
  test(
    'no VIEW skips private requests and cannot fallback create into occupied table',
    () async {
      final server = TableServer()..table = tableData();
      addTearDown(server.close);
      final repo = FakeOrders();
      final c = hub(
        server,
        () => orderSession(
          permissions: {
            'ORDER_CREATE',
            'ORDER_UPDATE',
            'TABLE_VIEW',
            'TABLE_OPEN',
            'MENU_VIEW',
          },
        ),
        orders: repo,
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.tile(c.tables.single).billState, TableBillState.forbidden);
      expect(repo.queries, isEmpty);
      expect(await c.selectTable(tableId), isA<Error<OrderTableSelection>>());
      expect(repo.activeCalls, isEmpty);
      expect(repo.creates, isEmpty);
    },
  );
  test(
    '204 seating reuses table target without TABLE_OPEN, failures never create',
    () async {
      final server = TableServer()..table = tableData();
      addTearDown(server.close);
      final repo = FakeOrders()..onActive = (_) async => const Success(null);
      final c = hub(
        server,
        () => orderSession(
          permissions: orderPermissions.difference({'TABLE_OPEN'}),
        ),
        orders: repo,
      );
      addTearDown(c.dispose);
      final result = await c.selectTable(tableId);
      final target =
          ((result as Success<OrderTableSelection>).value as ComposeTableOrder)
              .context;
      expect(target.tableId, tableId);
      expect(target.tableSessionId, isNull);
      expect(target.sessionAlreadyOpen, true);
      for (final type in [
        FailureType.forbidden,
        FailureType.notFound,
        FailureType.conflict,
        FailureType.network,
      ]) {
        repo.onActive = (_) async =>
            Error(Failure(type: type, message: 'failed'));
        expect(await c.selectTable(tableId), isA<Error<OrderTableSelection>>());
      }
      expect(repo.creates, isEmpty);
      expect(server.requests.any((r) => r.method == 'POST'), false);
    },
  );
  test(
    'money failure remains unknown and readonly inactive area does not hide existing bill',
    () async {
      final server = TableServer()..table = tableData(areaActive: false);
      addTearDown(server.close);
      final repo = FakeOrders()
        ..current = serving()
        ..onList = (_) async => const Error(networkFailure);
      final c = hub(server, () => orderSession(), orders: repo);
      addTearDown(c.dispose);
      await c.load();
      expect(c.tables.length, 1);
      expect(c.tile(c.tables.single).billState, TableBillState.unknown);
      expect(c.canCreateAt(c.tables.single), false);
      expect(
        (await c.selectTable(tableId) as Success).value,
        isA<ViewTableOrder>(),
      );
    },
  );
  test(
    'inconsistent occupancy fails closed without querying or creating order',
    () async {
      final server = TableServer()
        ..table = tableData()
        ..table['occupied'] = false;
      addTearDown(server.close);
      final repo = FakeOrders();
      final c = hub(server, () => orderSession(), orders: repo);
      addTearDown(c.dispose);
      expect(
        (await c.selectTable(tableId) as Error).failure.code,
        'INCONSISTENT_TABLE_SESSION_STATE',
      );
      expect(repo.activeCalls, isEmpty);
      expect(repo.creates, isEmpty);
    },
  );
  test(
    'ORDER event refreshes amounts but cancelling bill never changes occupancy locally',
    () async {
      final events = OrderEvents();
      addTearDown(events.dispose);
      final server = TableServer()..table = tableData();
      addTearDown(server.close);
      final repo = FakeOrders()..current = serving();
      final c = hub(server, () => orderSession(), orders: repo, events: events);
      addTearDown(c.dispose);
      await c.load();
      final calls = repo.queries.length;
      repo.current = serving(status: 'CANCELLED');
      events.emit('o1', sessionId);
      events.emit('o1', sessionId);
      await Future<void>.delayed(const Duration(milliseconds: 180));
      expect(repo.queries.length, calls + 5);
      expect(c.tables.single.occupied, true);
      expect(c.tile(c.tables.single).billState, TableBillState.noOrder);
    },
  );
  test(
    'older snapshot and late scope responses cannot overwrite current data',
    () async {
      final server = TableServer()..table = tableData();
      addTearDown(server.close);
      final repo = FakeOrders();
      AppSession? session = orderSession();
      final c = hub(server, () => session, orders: repo);
      addTearDown(c.dispose);
      final pending = Completer<Result<OrderPage>>();
      repo.onList = (_) => pending.future;
      final old = c.load();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      repo.onList = (q) async => Success(
        orderPage(
          q.status == OrderStatus.confirmed
              ? [serving(total: 200000).summary]
              : [],
        ),
      );
      await c.load();
      pending.complete(Success(orderPage([serving(total: 100000).summary])));
      await old;
      expect(c.tile(c.tables.single).order!.totalAmount.minorUnits, 20000000);
      final late = Completer<Result<OrderPage>>();
      repo.onList = (_) => late.future;
      final request = c.load();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      session = null;
      late.complete(Success(orderPage([serving().summary])));
      await request;
      expect(c.tables, isEmpty);
      expect(c.canView, false);
    },
  );
  test(
    'table submit freezes target/key/optional guests through timeout and remount hints',
    () async {
      final repo = FakeOrders()
        ..onCreate = () async => const Error(networkFailure);
      final c = draft(
        repo,
        () => orderSession(),
        context: const OrderCreationContext.fromTable(
          tableId: tableId,
          guestCount: 6,
        ),
      );
      addTearDown(c.dispose);
      c.add(saleItem);
      await c.submit(mode: OrderSubmissionMode.submit);
      final original = repo.creates.single;
      expect(original.$1.guestCount, isNull);
      expect(c.canRetry, true);
      expect(c.canDraft, false);
      c.adoptSeatingHint(
        const OrderCreationContext.fromTable(
          tableId: tableId,
          sessionAlreadyOpen: true,
        ),
      );
      c.setFields(guestCount: 9);
      repo.onCreate = () async => Success(serving());
      await c.retry();
      expect(identical(repo.creates.last.$1, original.$1), true);
      expect(repo.creates.last.$2, original.$2);
      expect(repo.creates.last.$1.context.tableId, tableId);
      expect(repo.creates.last.$1.context.tableSessionId, isNull);
      expect(repo.writes, isEmpty);
    },
  );
  test(
    'table submit requires explicit mode and only fresh opening requires TABLE_OPEN',
    () async {
      final who = orderSession(
        permissions: orderPermissions.difference({'TABLE_OPEN'}),
      );
      final repo = FakeOrders();
      final empty = draft(
        repo,
        () => who,
        context: const OrderCreationContext.fromTable(tableId: tableId),
      );
      addTearDown(empty.dispose);
      empty.add(saleItem);
      expect(empty.canSubmit, false);
      await empty.submit(mode: OrderSubmissionMode.submit);
      expect(repo.creates, isEmpty);
      final seated = draft(
        repo,
        () => who,
        context: const OrderCreationContext.fromTable(
          tableId: tableId,
          sessionAlreadyOpen: true,
        ),
      );
      addTearDown(seated.dispose);
      seated.add(saleItem);
      expect(seated.canSubmit, true);
      await seated.submit();
      expect(repo.creates, isEmpty);
      await seated.submit(mode: OrderSubmissionMode.submit);
      expect(repo.creates.length, 1);
    },
  );
  test(
    'table conflict keeps cart, blocks blind create and needs explicit unchanged-target acknowledgement',
    () async {
      final repo = FakeOrders()
        ..onCreate = () async => const Error(
          Failure(
            type: FailureType.conflict,
            code: 'TABLE_SESSION_HAS_SERVING_ORDER',
            message: 'busy',
          ),
        );
      final c = draft(
        repo,
        () => orderSession(),
        context: const OrderCreationContext.fromTable(tableId: tableId),
      );
      addTearDown(c.dispose);
      c.add(saleItem);
      await c.submit(mode: OrderSubmissionMode.submit);
      expect(c.needsTableReview, true);
      expect(c.lines.length, 1);
      await c.submit(mode: OrderSubmissionMode.submit);
      expect(repo.creates.length, 1);
      expect(repo.submissions, isEmpty);
      expect(
        c.acknowledgeTableContext(
          const OrderCreationContext.fromTable(tableId: otherTableId),
        ),
        false,
      );
      expect(
        c.acknowledgeTableContext(
          const OrderCreationContext.fromTable(
            tableId: tableId,
            sessionAlreadyOpen: true,
          ),
        ),
        true,
      );
      repo.onCreate = null;
      await c.submit(mode: OrderSubmissionMode.submit);
      expect(repo.creates.length, 2);
      expect(repo.creates.first.$2, isNot(repo.creates.last.$2));
    },
  );
  test(
    'create key conflict cannot be retried or replaced by a fresh key',
    () async {
      final repo = FakeOrders()
        ..onCreate = () async => const Error(
          Failure(
            type: FailureType.conflict,
            code: 'IDEMPOTENCY_KEY_REUSED',
            message: 'conflict',
          ),
        );
      final c = draft(
        repo,
        () => orderSession(),
        context: const OrderCreationContext.fromTable(tableId: tableId),
      );
      addTearDown(c.dispose);
      c.add(saleItem);
      await c.submit(mode: OrderSubmissionMode.submit);
      expect(c.uncertain, true);
      expect(c.canRetry, false);
      await c.retry();
      await c.submit();
      expect(repo.creates.length, 1);
    },
  );
  test(
    'VIEW hub sidebar/route does not grant composer or mutation permissions',
    () {
      final view = orderSession(
        permissions: {'ORDER_VIEW', 'TABLE_VIEW'},
        features: {'ORDER_MANAGEMENT', 'TABLE_MANAGEMENT'},
      );
      expect(AccessPolicy.canOpenRoute(view, '/app/order-create'), true);
      expect(
        AccessPolicy.canOpenRoute(view, '/app/order-create?tableId=$tableId'),
        false,
      );
      expect(
        AccessPolicy.canOpenRoute(
          view,
          '/app/order-create?serviceType=TAKEAWAY',
        ),
        false,
      );
      final items = filterMenuItems(
        view,
        AppSidebarRegistry.categories.expand((c) => c.items).toList(),
      );
      expect(items.any((i) => i.id == 'order-create'), true);
      expect(AccessPolicy.canOrders(view, 'ORDER_UPDATE'), false);
    },
  );
}
