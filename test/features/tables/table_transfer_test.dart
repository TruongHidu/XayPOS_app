import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/tables/domain/entities/table_entities.dart';
import 'package:pos_saas_app/features/tables/domain/entities/table_inputs.dart';
import 'package:pos_saas_app/features/tables/domain/use_cases/restaurant_table_use_cases.dart';
import 'package:pos_saas_app/features/tables/domain/use_cases/table_session_use_cases.dart';
import 'package:pos_saas_app/features/tables/domain/validation/table_validation.dart';
import 'package:pos_saas_app/features/tables/presentation/controllers/table_events.dart';
import 'package:pos_saas_app/features/tables/presentation/controllers/table_transfer_controller.dart';

import '../../helpers/auth_fakes.dart';
import 'table_fakes.dart';

class _Keys implements TableTransferKeyGenerator {
  _Keys(this.value);
  final String value;
  @override
  String next() => value;
}

TableTransferController _controller(
  TableServer server,
  TableEvents events,
  AppSession? Function() session, {
  String key = 'transfer-key',
}) => TableTransferController(
  session: session,
  events: events,
  sessionId: 's1',
  getSession: DetailTableSession(server.sessions),
  listTables: ListRestaurantTable(server.tables),
  transferSession: TransferTableSession(server.sessions),
  keys: _Keys(key),
);

void main() {
  test('transfer POST uses exact contract and parses replay header', () async {
    final server = TableServer();
    addTearDown(server.close);
    server.respond = (request) async => Response(
      requestOptions: request,
      statusCode: 200,
      headers: Headers.fromMap({
        'idempotency-replayed': ['true'],
      }),
      data: sessionJson(
        version: 4,
        tableId: 't2',
        tableCode: 'B02',
        tableName: 'Garden table',
      ),
    );

    final result = await server.sessions.transfer(
      's1',
      const TransferTableSessionInput(
        targetTableId: 't2',
        expectedVersion: 3,
        reason: 'Quiet area',
      ),
      'stable-key',
    );

    final value = (result as Success<TableSessionTransferResult>).value;
    expect(value.replayed, true);
    expect(value.session.tableId, 't2');
    final request = server.requests.single;
    expect(request.method, 'POST');
    expect(request.path, '/api/v1/table-sessions/s1/transfer');
    expect(request.headers['Idempotency-Key'], 'stable-key');
    expect(request.data, {
      'targetTableId': 't2',
      'expectedVersion': 3,
      'reason': 'Quiet area',
    });
    expect((request.data as Map).keys, hasLength(3));
    expect(request.headers.containsKey('X-Restaurant-Id'), false);
  });

  test('history page keeps server order and nullable reason', () async {
    final server = TableServer();
    addTearDown(server.close);
    server.respond = (request) async => Response(
      requestOptions: request,
      statusCode: 200,
      data: pageJson([
        transferJson(reason: null),
        transferJson(reason: 'Second'),
      ], total: 2),
    );

    final result = await server.sessions.transfers('s1', page: 0, size: 20);
    final page =
        (result as Success<TablePage<TableSessionTransferHistoryEntry>>).value;
    expect(page.content.map((entry) => entry.reason), [null, 'Second']);
    expect(server.requests.single.path, '/api/v1/table-sessions/s1/transfers');
    expect(server.requests.single.queryParameters, {'page': 0, 'size': 20});
    expect(
      server.requests.single.headers.containsKey('Idempotency-Key'),
      false,
    );
  });

  test('input normalization, validation and permission stay independent', () {
    final input = const TransferTableSessionInput(
      targetTableId: ' t2 ',
      expectedVersion: 3,
      reason: '   ',
    ).normalized();
    expect(input.targetTableId, 't2');
    expect(input.reason, isNull);
    expect(TableValidation.input(input), isEmpty);
    expect(
      TableValidation.input(
        TransferTableSessionInput(
          targetTableId: '',
          expectedVersion: -1,
          reason: List.filled(1001, 'x').join(),
        ),
      ).keys,
      containsAll(['targetTableId', 'expectedVersion', 'reason']),
    );

    final onlyTransfer = makeAppSession(
      permissions: {'TABLE_TRANSFER'},
      features: {'TABLE_MANAGEMENT'},
    );
    expect(AccessPolicy.canTables(onlyTransfer, 'TABLE_TRANSFER'), true);
    expect(AccessPolicy.canTables(onlyTransfer, 'TABLE_VIEW'), false);
    expect(AccessPolicy.canTables(onlyTransfer, 'TABLE_OPEN'), false);
    expect(AccessPolicy.canTables(onlyTransfer, 'TABLE_CLOSE'), false);
    final noFeature = makeAppSession(
      permissions: {'TABLE_VIEW', 'TABLE_TRANSFER'},
      features: {},
    );
    expect(AccessPolicy.canTables(noFeature, 'TABLE_TRANSFER'), false);
  });

  test(
    'double confirm sends once and success uses returned current table',
    () async {
      final server = TableServer()..table = tableJson(id: 't2');
      final events = TableEvents();
      addTearDown(server.close);
      addTearDown(events.dispose);
      AppSession? auth = makeAppSession(
        permissions: tablePermissions,
        features: {'TABLE_MANAGEMENT'},
      );
      final controller = _controller(server, events, () => auth);
      addTearDown(controller.dispose);
      await controller.loadContext();
      controller.select(controller.targets.single);

      final pending = Completer<Response<dynamic>>();
      RequestOptions? transferRequest;
      server.respond = (request) {
        if (request.path.endsWith('/transfer')) {
          transferRequest = request;
          return pending.future;
        }
        return Future.value(server.response(request));
      };
      final first = controller.submit();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await controller.submit(), isA<Error>());
      expect(
        server.requests.where((r) => r.path.endsWith('/transfer')),
        hasLength(1),
      );
      pending.complete(
        Response(
          requestOptions: transferRequest!,
          statusCode: 200,
          data: sessionJson(
            version: 5,
            tableId: 't3',
            tableCode: 'B03',
            tableName: 'Actual table',
          ),
        ),
      );
      await first;
      expect(controller.currentSession!.tableId, 't3');
      expect(controller.currentSession!.version, 5);
      expect(controller.uncertain, false);
      expect(events.change!.relatedTableIds, {'t1', 't2', 't3'});
    },
  );

  test('timeout retry keeps exact key, payload and session version', () async {
    final server = TableServer()..table = tableJson(id: 't2');
    final events = TableEvents();
    addTearDown(server.close);
    addTearDown(events.dispose);
    AppSession? auth = makeAppSession(
      permissions: tablePermissions,
      features: {'TABLE_MANAGEMENT'},
    );
    final controller = _controller(server, events, () => auth);
    addTearDown(controller.dispose);
    await controller.loadContext();
    controller.select(controller.targets.single);
    controller.setReason('  Quiet  ');
    var attempts = 0;
    server.respond = (request) async {
      if (!request.path.endsWith('/transfer')) {
        return server.response(request);
      }
      attempts++;
      if (attempts == 1) {
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.receiveTimeout,
        );
      }
      return Response(
        requestOptions: request,
        statusCode: 200,
        headers: Headers.fromMap({
          'idempotency-replayed': ['true'],
        }),
        data: sessionJson(version: 4, tableId: 't2', tableCode: 'B02'),
      );
    };

    expect(await controller.submit(), isA<Error>());
    expect(controller.uncertain, true);
    final first = server.requests.last;
    final original = auth;
    auth = original.copyWithAuth(
      user: original.authenticatedUser,
      tokens: makeTokens(accessToken: 'rotated'),
    );
    expect(controller.isCurrent, true);
    expect(await controller.retry(), isA<Success>());
    final second = server.requests.last;
    expect(second.data, first.data);
    expect(second.headers['Idempotency-Key'], first.headers['Idempotency-Key']);
    expect(second.data, {
      'targetTableId': 't2',
      'expectedVersion': 3,
      'reason': 'Quiet',
    });
  });

  test('definite conflict never auto-retries with a new key', () async {
    final server = TableServer()..table = tableJson(id: 't2');
    final events = TableEvents();
    addTearDown(server.close);
    addTearDown(events.dispose);
    final auth = makeAppSession(
      permissions: tablePermissions,
      features: {'TABLE_MANAGEMENT'},
    );
    final controller = _controller(server, events, () => auth);
    addTearDown(controller.dispose);
    await controller.loadContext();
    controller.select(controller.targets.single);
    server.respond = (request) async {
      if (!request.path.endsWith('/transfer')) return server.response(request);
      throw DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: request,
          statusCode: 409,
          data: {'code': 'CONCURRENT_TABLE_UPDATE'},
        ),
      );
    };
    expect(await controller.submit(), isA<Error>());
    expect(controller.uncertain, false);
    expect(controller.canRetry, false);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(
      server.requests.where((r) => r.path.endsWith('/transfer')),
      hasLength(1),
    );
  });

  test(
    'server 5xx stays uncertain even when payload carries conflict code',
    () async {
      final server = TableServer()..table = tableJson(id: 't2');
      final events = TableEvents();
      addTearDown(server.close);
      addTearDown(events.dispose);
      final auth = makeAppSession(
        permissions: tablePermissions,
        features: {'TABLE_MANAGEMENT'},
      );
      final controller = _controller(server, events, () => auth);
      addTearDown(controller.dispose);
      await controller.loadContext();
      controller.select(controller.targets.single);
      server.respond = (request) async {
        if (!request.path.endsWith('/transfer')) {
          return server.response(request);
        }
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: request,
            statusCode: 503,
            data: {'code': 'CONCURRENT_TABLE_UPDATE'},
          ),
        );
      };
      expect(await controller.submit(), isA<Error>());
      expect(controller.uncertain, true);
      expect(controller.canRetry, true);
    },
  );

  test('related order mutation blocks only the same session', () async {
    final server = TableServer()..table = tableJson(id: 't2');
    final events = TableEvents();
    addTearDown(server.close);
    addTearDown(events.dispose);
    final auth = makeAppSession(
      permissions: tablePermissions,
      features: {'TABLE_MANAGEMENT'},
    );
    final controller = _controller(server, events, () => auth);
    addTearDown(controller.dispose);
    await controller.loadContext();
    controller.select(controller.targets.single);
    final source = Object();
    events.markExternalSessionBlocked(source, 'another-session', true);
    expect(controller.canSubmit, true);
    events.markExternalSessionBlocked(source, 's1', true);
    expect(controller.conflictingMutation, true);
    expect(controller.canSubmit, false);
    expect(await controller.submit(), isA<Error>());
    expect(server.requests.where((r) => r.path.endsWith('/transfer')), isEmpty);
    events.markExternalSessionBlocked(source, null, false);
    expect(controller.canSubmit, true);
  });

  test('late read and changed scope cannot overwrite transfer truth', () async {
    final server = TableServer()..table = tableJson(id: 't2');
    final events = TableEvents();
    addTearDown(server.close);
    addTearDown(events.dispose);
    AppSession? auth = makeAppSession(
      permissions: tablePermissions,
      features: {'TABLE_MANAGEMENT'},
    );
    final controller = _controller(server, events, () => auth);
    addTearDown(controller.dispose);
    await controller.loadContext();
    controller.select(controller.targets.single);
    final oldRead = Completer<Response<dynamic>>();
    RequestOptions? oldRequest;
    var detailReads = 0;
    server.respond = (request) async {
      if (request.method == 'GET' &&
          request.path == '/api/v1/table-sessions/s1') {
        detailReads++;
        oldRequest = request;
        return oldRead.future;
      }
      if (request.path.endsWith('/transfer')) {
        return Response(
          requestOptions: request,
          statusCode: 200,
          data: sessionJson(
            version: 4,
            status: 'CLOSED',
            tableId: 't3',
            tableCode: 'B03',
            tableName: 'Closed elsewhere',
          ),
        );
      }
      return server.response(request);
    };
    final read = controller.loadSession();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(detailReads, 1);
    await controller.submit();
    expect(controller.currentSession!.tableId, 't3');
    expect(controller.currentSession!.status, TableSessionStatus.closed);
    oldRead.complete(
      Response(
        requestOptions: oldRequest!,
        statusCode: 200,
        data: sessionJson(),
      ),
    );
    await read;
    expect(controller.currentSession!.tableId, 't3');

    final pending = Completer<Response<dynamic>>();
    RequestOptions? request;
    server.respond = (value) {
      request = value;
      return pending.future;
    };
    final nextRead = controller.loadSession();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    auth = makeAppSession(
      restaurantId: 'other',
      permissions: tablePermissions,
      features: {'TABLE_MANAGEMENT'},
    );
    pending.complete(
      Response(
        requestOptions: request!,
        statusCode: 200,
        data: sessionJson(tableId: 'late'),
      ),
    );
    await nextRead;
    expect(controller.currentSession!.tableId, 't3');
  });

  test('target pagination never calls current-session per card', () async {
    final server = TableServer();
    final events = TableEvents();
    addTearDown(server.close);
    addTearDown(events.dispose);
    final auth = makeAppSession(
      permissions: tablePermissions,
      features: {'TABLE_MANAGEMENT'},
    );
    final controller = _controller(server, events, () => auth);
    addTearDown(controller.dispose);
    server.respond = (request) async {
      if (request.path == '/api/v1/tables') {
        final page = request.queryParameters['page'] as int;
        return Response(
          requestOptions: request,
          statusCode: 200,
          data: pageJson(
            page == 0 ? [tableJson(id: 't1')] : [tableJson(id: 't2')],
            page: page,
            pages: 2,
            total: 2,
          ),
        );
      }
      return server.response(request);
    };
    await controller.loadContext();
    expect(controller.targets, isEmpty);
    expect(controller.totalPages, 2);
    controller.setPage(1);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.targets.single.id, 't2');
    expect(
      server.requests.where((r) => r.path.endsWith('/current-session')),
      isEmpty,
    );
  });
}
