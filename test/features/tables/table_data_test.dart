import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/tables/data/dto/table_dto.dart';
import 'package:pos_saas_app/features/tables/data/dto/table_requests.dart';
import 'package:pos_saas_app/features/tables/domain/entities/table_entities.dart';
import 'package:pos_saas_app/features/tables/domain/entities/table_inputs.dart';
import 'package:pos_saas_app/features/tables/domain/entities/table_query.dart';
import 'package:pos_saas_app/features/tables/domain/validation/table_validation.dart';
import 'table_fakes.dart';

void main() {
  test('all 21 endpoint verbs, paths, versions and 204 contracts', () async {
    final s = TableServer();
    addTearDown(s.close);
    await s.areas.list(const TableQuery(q: ' floor ', active: false));
    await s.areas.create(const CreateTableAreaInput(name: 'A'));
    await s.areas.detail('a1');
    await s.areas.update(
      'a1',
      const UpdateTableAreaInput(description: '', expectedVersion: 7),
    );
    await s.areas.setStatus('a1', false, 7);
    expect(await s.areas.delete('a1', 7), isA<Success<void>>());
    await s.tables.list(
      const TableQuery(
        areaId: 'a1',
        occupied: true,
        status: TableStatus.available,
      ),
    );
    await s.tables.create(
      const CreateRestaurantTableInput(code: 'B01', name: 'B'),
    );
    await s.tables.detail('t1');
    await s.tables.update(
      't1',
      const UpdateRestaurantTableInput(name: 'New', expectedVersion: 9),
    );
    await s.tables.setStatus('t1', TableStatus.inactive, 9);
    await s.tables.assignArea('t1', null, 9);
    expect(await s.tables.delete('t1', 9), isA<Success<void>>());
    await s.tables.qr('t1');
    await s.tables.rotateQr('t1', 9);
    await s.sessions.open(
      't1',
      const OpenTableSessionInput(guestCount: 6, expectedVersion: 9),
    );
    expect(
      (await s.sessions.current('t1') as Success<TableSession?>).value,
      isNull,
    );
    await s.sessions.list(
      TableQuery(
        tableId: 't1',
        sortBy: 'openedAt',
        sessionStatus: TableSessionStatus.closed,
        openedFrom: DateTime.utc(2026, 1, 1),
      ),
    );
    await s.sessions.detail('s1');
    await s.sessions.update(
      's1',
      const UpdateTableSessionInput(note: '', expectedVersion: 3),
    );
    await s.sessions.cancel('s1', 'mistake', 3);
    expect(s.requests.map((r) => '${r.method} ${r.path}').toList(), [
      'GET /api/v1/table-areas',
      'POST /api/v1/table-areas',
      'GET /api/v1/table-areas/a1',
      'PATCH /api/v1/table-areas/a1',
      'PATCH /api/v1/table-areas/a1/status',
      'DELETE /api/v1/table-areas/a1',
      'GET /api/v1/tables',
      'POST /api/v1/tables',
      'GET /api/v1/tables/t1',
      'PATCH /api/v1/tables/t1',
      'PATCH /api/v1/tables/t1/status',
      'PATCH /api/v1/tables/t1/area',
      'DELETE /api/v1/tables/t1',
      'GET /api/v1/tables/t1/qr',
      'POST /api/v1/tables/t1/qr/rotate',
      'POST /api/v1/tables/t1/sessions',
      'GET /api/v1/tables/t1/current-session',
      'GET /api/v1/table-sessions',
      'GET /api/v1/table-sessions/s1',
      'PATCH /api/v1/table-sessions/s1',
      'POST /api/v1/table-sessions/s1/cancel',
    ]);
    expect(s.requests[0].queryParameters['q'], 'floor');
    expect(s.requests[3].data, {'description': '', 'expectedVersion': 7});
    expect(s.requests[5].queryParameters, {'expectedVersion': 7});
    expect(s.requests[5].data, isNull);
    expect(s.requests[9].data, {'name': 'New', 'expectedVersion': 9});
    expect(s.requests[11].data, {'areaId': null, 'expectedVersion': 9});
    expect(s.requests[15].data['expectedVersion'], 9);
    expect(s.requests[19].data, {'note': '', 'expectedVersion': 3});
    expect(s.requests[20].data, {'reason': 'mistake', 'expectedVersion': 3});
    for (final r in s.requests) {
      expect(r.queryParameters.containsKey('restaurantId'), false);
      expect(r.headers.containsKey('X-Restaurant-Id'), false);
    }
  });
  test(
    'strict entities, dates, nullable fields and occupancy independent of status',
    () {
      final a = TableDto.tableArea(areaJson()),
          t = TableDto.restaurantTable(tableJson(occupied: true)),
          s = TableDto.tableSession(sessionJson());
      expect(a.description, isNull);
      expect(a.createdAt, a.updatedAt);
      expect(t.status, TableStatus.available);
      expect(t.occupied, true);
      expect(t.currentSession!.guestCount, 6);
      expect(s.closedAt, isNull);
      expect(TableDto.tableQrPayload(qrJson()).version, 9);
      for (final key in ['id', 'version', 'createdAt', 'status', 'capacity']) {
        final j = tableJson()..remove(key);
        expect(() => TableDto.restaurantTable(j), throwsFormatException);
      }
      expect(
        () => TableDto.tableSession(sessionJson()..['status'] = 'PAID'),
        throwsFormatException,
      );
      expect(
        () => TableDto.tableArea(
          areaJson()..['createdAt'] = '2026-02-30T03:00:00Z',
        ),
        throwsFormatException,
      );
      expect(
        () => TableDto.page(pageJson([])..['size'] = 101, TableDto.tableArea),
        throwsFormatException,
      );
      expect(
        TableDto.tableQrPayload(qrJson()).toString(),
        isNot(contains('secret')),
      );
    },
  );
  test(
    'null update fields omitted, empty strings retained, requests allowlist',
    () {
      expect(
        TableRequests.updateTableArea(
          const UpdateTableAreaInput(expectedVersion: 7),
        ),
        {'expectedVersion': 7},
      );
      expect(
        TableRequests.updateTableSession(
          const UpdateTableSessionInput(note: '', expectedVersion: 3),
        ),
        {'note': '', 'expectedVersion': 3},
      );
      expect(
        TableRequests.createRestaurantTable(
          const CreateRestaurantTableInput(code: 'B', name: 'Name'),
        ).keys.toSet(),
        {'code', 'name', 'areaId', 'capacity', 'displayOrder', 'status'},
      );
      expect(
        TableValidation.input(
          const OpenTableSessionInput(guestCount: 32767, expectedVersion: 9),
        ),
        isEmpty,
      );
      expect(
        TableValidation.input(
          const OpenTableSessionInput(guestCount: 32768, expectedVersion: 9),
        ),
        contains('guestCount'),
      );
    },
  );
  test(
    'malformed response becomes controlled Failure and no request replay',
    () async {
      final s = TableServer();
      addTearDown(s.close);
      s.respond = (r) async => Response(
        requestOptions: r,
        statusCode: 200,
        data: tableJson()..remove('version'),
      );
      final result = await s.tables.detail('t1');
      expect((result as Error).failure.code, 'INVALID_TABLE_RESPONSE');
      expect(s.requests.length, 1);
    },
  );
  test('TABLE error codes mapped, field errors preserved', () {
    for (final code in [
      'TABLE_AREA_NAME_EXISTS',
      'TABLE_CODE_EXISTS',
      'TABLE_AREA_INACTIVE',
      'TABLE_AREA_NOT_EMPTY',
      'TABLE_AREA_HAS_OPEN_SESSIONS',
      'TABLE_INACTIVE',
      'TABLE_ALREADY_OCCUPIED',
      'TABLE_HAS_OPEN_SESSION',
      'INVALID_TABLE_SESSION_TRANSITION',
      'CONCURRENT_TABLE_UPDATE',
      'TABLE_AREA_NOT_FOUND',
      'TABLE_NOT_FOUND',
      'TABLE_SESSION_NOT_FOUND',
      'QR_TOKEN_CONFLICT',
      'EMPTY_UPDATE_REQUEST',
      'INVALID_REQUEST_BODY',
      'VALIDATION_ERROR',
    ]) {
      final r = RequestOptions(path: '/api/v1/tables');
      final f = ApiErrorMapper.fromException(
        DioException(
          requestOptions: r,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: r,
            statusCode: 409,
            data: {
              'code': code,
              'message': '',
              'fieldErrors': {'name': 'required'},
            },
          ),
        ),
      );
      expect(f.code, code);
      expect(f.type, isNot(FailureType.internal));
      expect(f.fieldErrors['name'], 'required');
      expect(f.message, isNotEmpty);
    }
  });
}
