import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/tables/data/dto/table_dto.dart';
import 'package:pos_saas_app/features/tables/domain/entities/table_entities.dart';
import 'package:pos_saas_app/features/tables/domain/entities/table_inputs.dart';
import 'package:pos_saas_app/features/tables/domain/entities/table_query.dart';
import 'package:pos_saas_app/features/tables/domain/use_cases/table_area_use_cases.dart';
import 'package:pos_saas_app/features/tables/domain/use_cases/restaurant_table_use_cases.dart';
import 'package:pos_saas_app/features/tables/presentation/controllers/table_area_controller.dart';
import 'package:pos_saas_app/features/tables/presentation/controllers/table_detail_controller.dart';
import 'package:pos_saas_app/features/tables/presentation/controllers/table_events.dart';
import '../../helpers/auth_fakes.dart';
import 'table_fakes.dart';
import 'controller_factory.dart';

void main() {
  late TableServer s;
  late TableEvents events;
  AppSession? auth;
  setUp(() {
    s = TableServer();
    events = TableEvents();
    auth = makeAppSession(
      permissions: tablePermissions,
      features: {'TABLE_MANAGEMENT'},
    );
  });
  tearDown(() {
    s.close();
    events.dispose();
  });
  test('late QR read cannot replace token returned by rotation', () async {
    final q = TableQrController(
      session: () => auth,
      events: events,
      id: 't1',
      get: QrRestaurantTable(s.tables),
      rotate: RotateQrRestaurantTable(s.tables),
    );
    addTearDown(q.dispose);
    await q.load();
    final baseline = q.value!;
    final pending = Completer<Response>();
    RequestOptions? request;
    s.respond = (r) async {
      if (r.method == 'GET') {
        request = r;
        return pending.future;
      }
      return s.response(r);
    };
    final oldRead = q.load();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await q.rotateCurrent(baseline);
    expect(q.value!.version, 10);
    pending.complete(
      Response(requestOptions: request!, statusCode: 200, data: qrJson()),
    );
    await oldRead;
    expect(q.value!.version, 10);
    expect(q.loading, false);
  });
  test(
    'mismatched snapshot version, canOpen false and missing feature never write',
    () async {
      final t = tablesController(s, () => auth, events),
          sc = sessionsController(s, () => auth, events);
      addTearDown(t.dispose);
      addTearDown(sc.dispose);
      expect(
        await t.update(
          TableDto.restaurantTable(tableJson()),
          const UpdateRestaurantTableInput(name: 'New', expectedVersion: 3),
        ),
        isA<Error>(),
      );
      expect(
        await sc.open(
          TableDto.restaurantTable(tableJson()),
          const OpenTableSessionInput(expectedVersion: 3),
        ),
        isA<Error>(),
      );
      expect(
        await sc.open(
          TableDto.restaurantTable(tableJson(canOpen: false)),
          const OpenTableSessionInput(expectedVersion: 9),
        ),
        isA<Error>(),
      );
      auth = makeAppSession(permissions: tablePermissions, features: {});
      expect(
        await t.create(const CreateRestaurantTableInput(code: 'B', name: 'B')),
        isA<Error>(),
      );
      expect(s.requests, isEmpty);
    },
  );
  test(
    '404 detail refreshes list and disposed controller ignores delayed completion',
    () async {
      final c = tablesController(s, () => auth, events);
      s.respond = (r) async {
        if (r.path.endsWith('/t1')) {
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.badResponse,
            response: Response(
              requestOptions: r,
              statusCode: 404,
              data: {'code': 'TABLE_NOT_FOUND'},
            ),
          );
        }
        return s.response(r);
      };
      expect(await c.getDetail('t1'), isA<Error>());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(s.requests.where((r) => r.path == '/api/v1/tables').length, 1);
      final pending = Completer<Response>();
      RequestOptions? request;
      s.respond = (r) {
        request = r;
        return pending.future;
      };
      final load = c.load();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      c.dispose();
      pending.complete(
        Response(
          requestOptions: request!,
          statusCode: 200,
          data: pageJson([tableJson()]),
        ),
      );
      await load;
      expect(c.rows, isEmpty);
    },
  );
  test('debounce invalidates in-flight query before next request', () async {
    final c = tablesController(s, () => auth, events);
    addTearDown(c.dispose);
    final old = Completer<Response>();
    RequestOptions? oldRequest;
    s.respond = (r) async {
      if (r.queryParameters['q'] == 'old') {
        oldRequest = r;
        return old.future;
      }
      return s.response(r);
    };
    c.setQuery(const TableQuery(q: 'old'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    c.search('new');
    old.complete(
      Response(
        requestOptions: oldRequest!,
        statusCode: 200,
        data: pageJson([tableJson(id: 'old')]),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(c.rows, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 360));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(c.rows.single.id, 't1');
    expect(s.requests.length, 2);
    expect(c.query.q, 'new');
  });
  test(
    'scope change drops delayed data, stops mutations, token-only scope survives',
    () async {
      final c = tablesController(s, () => auth, events);
      addTearDown(c.dispose);
      await c.load();
      c.setQuery(const TableQuery(q: 'saved'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final original = auth!;
      auth = original.copyWithAuth(
        user: original.authenticatedUser,
        tokens: makeTokens(accessToken: 'rotated'),
      );
      expect(c.isCurrent, true);
      expect(c.query.q, 'saved');
      final pending = Completer<Response>();
      RequestOptions? request;
      s.respond = (r) {
        request = r;
        return pending.future;
      };
      final load = c.load();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      auth = null;
      pending.complete(
        Response(
          requestOptions: request!,
          statusCode: 200,
          data: pageJson([tableJson(id: 'late')]),
        ),
      );
      await load;
      expect(c.rows.any((r) => r.id == 'late'), false);
      final count = s.requests.length;
      expect(
        await c.delete(TableDto.restaurantTable(tableJson())),
        isA<Error>(),
      );
      expect(s.requests.length, count);
    },
  );
  test('one mutation per resource, no retry on conflict or timeout', () async {
    final c = tablesController(s, () => auth, events);
    addTearDown(c.dispose);
    final b = TableDto.restaurantTable(tableJson());
    final pending = Completer<Response>();
    RequestOptions? request;
    s.respond = (r) {
      request = r;
      return pending.future;
    };
    final first = c.update(
      b,
      const UpdateRestaurantTableInput(name: 'A', expectedVersion: 9),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(
      await c.update(
        b,
        const UpdateRestaurantTableInput(name: 'B', expectedVersion: 9),
      ),
      isA<Error>(),
    );
    expect(s.requests.length, 1);
    pending.completeError(
      DioException(
        requestOptions: request!,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: request!,
          statusCode: 409,
          data: {'code': 'CONCURRENT_TABLE_UPDATE'},
        ),
      ),
    );
    expect(await first, isA<Error>());
    expect(s.requests.length, 1);
    s.respond = (r) async => throw DioException(
      requestOptions: r,
      type: DioExceptionType.receiveTimeout,
    );
    final result = await c.update(
      b,
      const UpdateRestaurantTableInput(name: 'C', expectedVersion: 9),
    );
    expect((result as Error).failure.isNetwork, true);
    expect(s.requests.length, 2);
  });
  test(
    'occupied blocks config changes while name and order still allowed',
    () async {
      final c = tablesController(s, () => auth, events);
      addTearDown(c.dispose);
      final b = TableDto.restaurantTable(tableJson(occupied: true));
      for (final input in [
        const UpdateRestaurantTableInput(code: 'B02', expectedVersion: 9),
        const UpdateRestaurantTableInput(capacity: 8, expectedVersion: 9),
      ]) {
        expect(await c.update(b, input), isA<Error>());
      }
      expect(await c.assignArea(b, null), isA<Error>());
      expect(await c.setStatus(b, TableStatus.inactive), isA<Error>());
      expect(await c.delete(b), isA<Error>());
      expect(s.requests, isEmpty);
      expect(
        await c.update(
          b,
          const UpdateRestaurantTableInput(
            name: 'New',
            displayOrder: 3,
            expectedVersion: 9,
          ),
        ),
        isA<Success>(),
      );
      expect(s.requests.where((r) => r.method == 'PATCH').single.data, {
        'name': 'New',
        'displayOrder': 3,
        'expectedVersion': 9,
      });
    },
  );
  test(
    'open uses table version, larger guest count allowed; session mutation uses session version',
    () async {
      final c = sessionsController(s, () => auth, events);
      addTearDown(c.dispose);
      expect(
        await c.open(
          TableDto.restaurantTable(tableJson()),
          const OpenTableSessionInput(guestCount: 20, expectedVersion: 9),
        ),
        isA<Success>(),
      );
      expect(s.requests.last.data['expectedVersion'], 9);
      expect(s.requests.last.data['guestCount'], 20);
      final b = TableDto.tableSession(sessionJson());
      await c.update(
        b,
        const UpdateTableSessionInput(guestCount: 8, expectedVersion: 3),
      );
      expect(s.requests.last.data['expectedVersion'], 3);
      await c.cancel(b, 'mistake');
      await c.cancel(b, 'mistake');
      expect(
        s.requests.where((r) => r.path.endsWith('/cancel')).map((r) => r.path),
        everyElement('/api/v1/table-sessions/s1/cancel'),
      );
      for (final status in ['CANCELLED', 'CLOSED']) {
        final terminal = TableDto.tableSession(sessionJson(status: status));
        final count = s.requests.length;
        expect(await c.cancel(terminal, 'reason'), isA<Error>());
        expect(
          await c.update(
            terminal,
            const UpdateTableSessionInput(note: 'x', expectedVersion: 3),
          ),
          isA<Error>(),
        );
        expect(s.requests.length, count);
      }
    },
  );
  test('permission gates all controller mutations independently', () async {
    auth = makeAppSession(
      permissions: {'TABLE_VIEW'},
      features: {'TABLE_MANAGEMENT'},
    );
    final t = tablesController(s, () => auth, events),
        a = areasController(s, () => auth, events),
        sc = sessionsController(s, () => auth, events);
    addTearDown(t.dispose);
    addTearDown(a.dispose);
    addTearDown(sc.dispose);
    final b = TableDto.restaurantTable(tableJson());
    expect(
      await t.create(const CreateRestaurantTableInput(code: 'B', name: 'B')),
      isA<Error>(),
    );
    expect(await t.delete(b), isA<Error>());
    expect(await a.create(const CreateTableAreaInput(name: 'A')), isA<Error>());
    expect(
      await sc.open(b, const OpenTableSessionInput(expectedVersion: 9)),
      isA<Error>(),
    );
    expect(
      await sc.cancel(TableDto.tableSession(sessionJson()), 'wrong'),
      isA<Error>(),
    );
    expect(s.requests, isEmpty);
    final qr = TableQrController(
      session: () => auth,
      events: events,
      id: 't1',
      get: QrRestaurantTable(s.tables),
      rotate: RotateQrRestaurantTable(s.tables),
    );
    addTearDown(qr.dispose);
    await qr.load();
    expect(qr.value, isNull);
    expect(s.requests, isEmpty);
  });
  test('delete last row returns to valid page and keeps filters', () async {
    final c = tablesController(s, () => auth, events);
    addTearDown(c.dispose);
    c.query = const TableQuery(page: 2, q: 'B', occupied: false);
    s.respond = (r) async => r.method == 'GET'
        ? Response(
            requestOptions: r,
            statusCode: 200,
            data: pageJson(
              r.queryParameters['page'] == 2 ? [] : [tableJson()],
              page: r.queryParameters['page'],
              pages: 2,
              total: 21,
            ),
          )
        : s.response(r);
    await c.delete(TableDto.restaurantTable(tableJson()));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(c.query.page, 1);
    expect(c.query.q, 'B');
    expect(c.query.occupied, false);
  });
  test('selector pages beyond 20 and always enforces activeOnly', () async {
    final c = TableAreaSelectorController(
      session: () => auth,
      events: events,
      list: ListTableArea(s.areas),
      activeOnly: true,
    );
    addTearDown(c.dispose);
    s.respond = (r) async => Response(
      requestOptions: r,
      statusCode: 200,
      data: pageJson(
        [areaJson(id: r.queryParameters['page'] == 0 ? 'a1' : 'a21')],
        page: r.queryParameters['page'],
        pages: 2,
        total: 21,
      ),
    );
    await c.load();
    c.setPage(1);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(c.rows.single.id, 'a21');
    expect(s.requests.last.queryParameters['active'], true);
    c.setQuery(const TableQuery(active: false));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(s.requests.last.queryParameters['active'], true);
  });
  test('area, session and QR changes refresh dependent data once', () async {
    final t = tablesController(s, () => auth, events),
        a = areasController(s, () => auth, events),
        sc = sessionsController(s, () => auth, events);
    addTearDown(t.dispose);
    addTearDown(a.dispose);
    addTearDown(sc.dispose);
    await sc.load();
    await sc.loadCurrent();
    s.requests.clear();
    await sc.cancel(TableDto.tableSession(sessionJson()), 'wrong');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(s.requests.where((r) => r.path == '/api/v1/tables').length, 1);
    expect(
      s.requests.where((r) => r.path == '/api/v1/table-sessions').length,
      1,
    );
    expect(
      s.requests.where((r) => r.path.endsWith('current-session')).length,
      1,
    );
    s.requests.clear();
    await a.setStatus(TableDto.tableArea(areaJson()), false);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(s.requests.where((r) => r.path == '/api/v1/tables').length, 1);
    final q = TableQrController(
      session: () => auth,
      events: events,
      id: 't1',
      get: QrRestaurantTable(s.tables),
      rotate: RotateQrRestaurantTable(s.tables),
    );
    addTearDown(q.dispose);
    await q.load();
    await q.rotateCurrent(q.value!);
    expect(q.value!.version, 10);
    expect(
      s.requests
          .where((r) => r.path.endsWith('/qr/rotate'))
          .single
          .data['expectedVersion'],
      9,
    );
  });
}
