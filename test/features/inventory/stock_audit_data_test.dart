import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/inventory/data/data_sources/stock_audit_remote_data_source.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_audit_dto.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_audit_requests.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_json.dart';
import 'package:pos_saas_app/features/inventory/data/repositories/stock_audit_repository_impl.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_instant_range.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_quantity.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_audit.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_audit_inputs.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_audit_queries.dart';
import 'package:pos_saas_app/features/inventory/domain/policies/stock_audit_validation.dart';
import 'stock_audit_fakes.dart';

Map<String, dynamic> _page(
  List<Object?> values, {
  int page = 0,
  int size = 20,
}) => {
  'content': values,
  'page': page,
  'size': size,
  'totalElements': values.length,
  'totalPages': values.isEmpty ? 0 : 1,
};

void main() {
  test(
    'nine endpoints use audit versions, precise paths, key only for create',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://inventory.invalid',
          headers: {'Authorization': 'Bearer session'},
        ),
      );
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests.add(r);
            Object? value;
            var status = 200;
            if (r.method == 'GET' && r.path.endsWith('/audits')) {
              value = _page([stockAuditJson(detail: false)]);
            } else if (r.method == 'GET' && r.path.endsWith('/items')) {
              value = _page([stockAuditItemJson(counted: 0, system: 10)]);
            } else {
              value = stockAuditJson(
                status: r.path.endsWith('/confirm')
                    ? 'CONFIRMED'
                    : r.path.endsWith('/cancel')
                    ? 'CANCELLED'
                    : 'COUNTING',
              );
              if (r.method == 'POST' && r.path.endsWith('/audits')) {
                status = 201;
              }
            }
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: status,
                data: jsonEncode(value),
              ),
            );
          },
        ),
      );
      final repo = StockAuditRepositoryImpl(StockAuditRemoteDataSource(dio));
      final dates = InventoryInstantRange(
        from: DateTime.utc(2026, 10, 21),
        to: DateTime.utc(2026, 10, 22),
      );
      expect(
        await repo.list(
          StockAuditQuery(
            q: ' %_ ',
            warehouseId: 'w1',
            status: StockAuditStatus.counting,
            dates: dates,
          ),
        ),
        isA<Success>(),
      );
      expect(await repo.get('a1'), isA<Success>());
      expect(
        await repo.items(
          'a1',
          const StockAuditItemQuery(
            q: ' %_ ',
            counted: true,
            differenceOnly: true,
            sortBy: 'differenceQuantity',
            direction: 'desc',
          ),
        ),
        isA<Success>(),
      );
      expect(
        await repo.create(
          ' frozen-create ',
          const CreateStockAuditInput(warehouseId: 'w1', note: ' Cuối ca '),
        ),
        isA<Success>(),
      );
      expect(
        await repo.updateNote(
          'a1',
          const UpdateStockAuditNoteInput(expectedVersion: 2),
        ),
        isA<Success>(),
      );
      expect(
        await repo.start(
          'a1',
          const StockAuditTransitionInput(expectedVersion: 2),
        ),
        isA<Success>(),
      );
      expect(
        await repo.updateCounts(
          'a1',
          StockAuditCountsInput(
            expectedVersion: 2,
            items: [
              StockAuditCountInput(
                auditItemId: 'ai1',
                countedQuantity: InventoryQuantity.zero,
                note: '',
              ),
            ],
          ),
        ),
        isA<Success>(),
      );
      expect(
        await repo.confirm(
          'a1',
          const StockAuditTransitionInput(expectedVersion: 2),
        ),
        isA<Success>(),
      );
      expect(
        await repo.cancel(
          'a1',
          const CancelStockAuditInput(expectedVersion: 2),
        ),
        isA<Success>(),
      );
      expect(requests.map((r) => '${r.method} ${r.path}'), [
        'GET /api/v1/inventory/audits',
        'GET /api/v1/inventory/audits/a1',
        'GET /api/v1/inventory/audits/a1/items',
        'POST /api/v1/inventory/audits',
        'PATCH /api/v1/inventory/audits/a1',
        'POST /api/v1/inventory/audits/a1/start',
        'PATCH /api/v1/inventory/audits/a1/items',
        'POST /api/v1/inventory/audits/a1/confirm',
        'POST /api/v1/inventory/audits/a1/cancel',
      ]);
      expect(requests[0].queryParameters, {
        'q': '%_',
        'warehouseId': 'w1',
        'status': 'COUNTING',
        'createdFrom': '2026-10-21T00:00:00.000Z',
        'createdTo': '2026-10-22T00:00:00.000Z',
        'page': 0,
        'size': 20,
        'sortBy': 'createdAt',
        'direction': 'desc',
      });
      expect(requests[2].queryParameters, {
        'q': '%_',
        'counted': true,
        'differenceOnly': true,
        'page': 0,
        'size': 20,
        'sortBy': 'differenceQuantity',
        'direction': 'desc',
      });
      for (final r in requests) {
        expect(r.headers['Authorization'], 'Bearer session');
        expect(r.headers['Accept'], 'application/json');
        expect(
          r.headers.containsKey('Idempotency-Key'),
          identical(r, requests[3]),
        );
        if (r.method == 'GET') expect(r.data, isNull);
        expect('${r.data}', isNot(contains('restaurantId')));
      }
      expect(requests[3].headers['Idempotency-Key'], 'frozen-create');
      expect(requests[3].data, {'warehouseId': 'w1', 'note': 'Cuối ca'});
      expect(requests[4].data, {'expectedVersion': 2, 'note': null});
      expect(requests[5].data, {'expectedVersion': 2});
      expect(requests[6].data, {
        'expectedVersion': 2,
        'items': [
          {'auditItemId': 'ai1', 'countedQuantity': 0, 'note': ''},
        ],
      });
      expect(requests[8].data, {'expectedVersion': 2});
    },
  );

  test(
    'header, item and cancel notes have deliberately different semantics',
    () {
      expect(
        StockAuditRequests.note(
          const UpdateStockAuditNoteInput(expectedVersion: 4, note: '  '),
        ),
        {'expectedVersion': 4, 'note': null},
      );
      for (final note in [null, '  ']) {
        expect(
          StockAuditRequests.cancel(
            CancelStockAuditInput(expectedVersion: 4, note: note),
          ),
          {'expectedVersion': 4},
        );
      }
      expect(
        StockAuditRequests.cancel(
          const CancelStockAuditInput(expectedVersion: 4, note: ' Đếm lại '),
        ),
        {'expectedVersion': 4, 'note': 'Đếm lại'},
      );
      final payload = StockAuditRequests.counts(
        StockAuditCountsInput(
          expectedVersion: 4,
          items: [
            StockAuditCountInput(
              auditItemId: 'ai1',
              countedQuantity: InventoryQuantity.zero,
            ),
            StockAuditCountInput(
              auditItemId: 'ai2',
              countedQuantity: InventoryQuantity.zero,
              note: '  ',
            ),
          ],
        ),
      );
      final rows = payload['items'] as List;
      expect(rows[0], {'auditItemId': 'ai1', 'countedQuantity': 0});
      expect(rows[1], {'auditItemId': 'ai2', 'countedQuantity': 0, 'note': ''});
    },
  );

  test(
    'summary is distinct from detail and all lifecycle snapshots remain readable',
    () {
      final summary = stockAuditJson(detail: false);
      expect(StockAuditDto.summary(summary).startedAt, isNotNull);
      expect(() => StockAuditDto.detail(summary), throwsFormatException);
      for (final status in StockAuditStatus.values) {
        final value = StockAuditDto.detail(stockAuditJson(status: status.code));
        expect(value.status, status);
        if (status == StockAuditStatus.draft) expect(value.itemCount, 0);
      }
      final noChanges = StockAuditDto.detail(
        stockAuditJson(status: 'CONFIRMED', changed: 0),
      );
      expect(noChanges.adjustmentDocumentId, isNull);
      expect(noChanges.countedItemCount, noChanges.itemCount);
      expect(
        () => StockAuditDto.detail(
          stockAuditJson(status: 'COUNTING')..['confirmedBy'] = 'actor',
        ),
        throwsFormatException,
      );
      expect(
        () => StockAuditDto.summary(stockAuditJson()..['countedItemCount'] = 3),
        throwsFormatException,
      );
      expect(
        () => StockAuditDto.summary(
          stockAuditJson(status: 'CONFIRMED')..['adjustmentDocumentId'] = null,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'null count differs from zero and signed differences include exact zero',
    () {
      final empty = StockAuditDto.item(
        stockAuditItemJson(system: 0, counted: null),
      );
      expect(empty.countedQuantity, isNull);
      expect(empty.differenceQuantity, isNull);
      final zero = StockAuditDto.item(
        stockAuditItemJson(system: 0, counted: 0, cost: 0),
      );
      expect(zero.countedQuantity, InventoryQuantity.zero);
      expect(zero.differenceQuantity!.scaled, BigInt.zero);
      expect(zero.referenceUnitCostSnapshot.cents, BigInt.zero);
      expect(
        StockAuditDto.item(
          stockAuditItemJson(counted: 8),
        ).differenceQuantity.toString(),
        '-2',
      );
      expect(
        StockAuditDto.item(
          stockAuditItemJson(counted: 12),
        ).differenceQuantity.toString(),
        '2',
      );
      expect(
        () => StockAuditDto.item(
          stockAuditItemJson(counted: null)..['differenceQuantity'] = 0,
        ),
        throwsFormatException,
      );
      expect(
        () => StockAuditDto.item(
          stockAuditItemJson()..['differenceQuantity'] = -1,
        ),
        throwsFormatException,
      );
      expect(StockAuditDifference.parse('-0'), StockAuditDifference.parse('0'));
    },
  );

  test(
    'lossless HTTP handles max quantity, thousandths, and cost snapshot',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://inventory.invalid'));
      addTearDown(dio.close);
      var source = jsonEncode(
        _page([stockAuditItemJson(system: 0, counted: 0)]),
      );
      source = source
          .replaceFirst(
            '"systemQuantity":0',
            '"systemQuantity":99999999999.999',
          )
          .replaceFirst('"countedQuantity":0', '"countedQuantity":0.001')
          .replaceFirst(
            '"differenceQuantity":0',
            '"differenceQuantity":-99999999999.998',
          )
          .replaceFirst(
            '"referenceUnitCostSnapshot":10000',
            '"referenceUnitCostSnapshot":999999999999.99',
          );
      dio.httpClientAdapter = _AuditAdapter(source);
      final result = await StockAuditRepositoryImpl(
        StockAuditRemoteDataSource(dio),
      ).items('a1', const StockAuditItemQuery());
      final row = (result as Success).value.content.single as StockAuditItem;
      expect(row.systemQuantity.scaled, 99999999999999);
      expect(row.countedQuantity!.scaled, 1);
      expect(row.differenceQuantity!.scaled, BigInt.parse('-99999999999998'));
      expect(
        row.referenceUnitCostSnapshot.cents,
        BigInt.parse('99999999999999'),
      );
      final body = StockAuditRequests.counts(
        StockAuditCountsInput(
          expectedVersion: 0,
          items: [
            StockAuditCountInput(
              auditItemId: 'ai1',
              countedQuantity: row.systemQuantity,
            ),
          ],
        ),
      );
      expect(jsonEncode(body), contains('"countedQuantity":99999999999.999'));
    },
  );

  test(
    'invalid precision, missing nullable data, duplicate rows and page metadata are rejected',
    () {
      for (final number in ['-1', '100000000000', '0.0001', 'NaN']) {
        expect(() => InventoryQuantity.parse(number), throwsFormatException);
      }
      for (final number in ['-100000000000', '0.0001', '+1']) {
        expect(() => StockAuditDifference.parse(number), throwsFormatException);
      }
      expect(
        () =>
            StockAuditDto.item(stockAuditItemJson()..remove('countedQuantity')),
        throwsFormatException,
      );
      expect(
        () =>
            StockAuditDto.item(stockAuditItemJson()..['systemQuantity'] = '10'),
        throwsFormatException,
      );
      expect(
        () => StockAuditDto.item(
          decodeStockJson(
            jsonEncode(
              stockAuditItemJson(),
            ).replaceFirst('"systemQuantity":10', '"systemQuantity":10.0001'),
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => StockAuditDto.page(
          _page([stockAuditJson()])..['totalPages'] = 3,
          StockAuditDto.summary,
          0,
          20,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'query uses exclusive calendar end, literal text, and tri-state count',
    () {
      final dates = InventoryInstantRange.days(
        DateTime(2026, 10, 21, 23),
        DateTime(2026, 10, 21, 23),
      );
      expect(dates.from, DateTime(2026, 10, 21).toUtc());
      expect(dates.to, DateTime(2026, 10, 22).toUtc());
      expect(dates.valid, isTrue);
      final same = InventoryInstantRange(
        from: DateTime.utc(2026),
        to: DateTime.utc(2026),
      );
      expect(same.valid, isFalse);
      expect(const StockAuditQuery(q: 'foo_%').valid, isTrue);
      expect(StockAuditQuery(q: 'x' * 101).valid, isFalse);
      expect(StockAuditQuery(dates: same).valid, isFalse);
      for (final query in [
        const StockAuditQuery(size: 101),
        const StockAuditQuery(page: -1),
        const StockAuditQuery(sortBy: 'totalCost'),
        const StockAuditQuery(direction: 'sideways'),
      ]) {
        expect(query.valid, isFalse);
      }
      expect(
        StockAuditRequests.items(
          const StockAuditItemQuery(),
        ).containsKey('counted'),
        isFalse,
      );
      expect(
        StockAuditRequests.items(
          const StockAuditItemQuery(counted: false),
        )['counted'],
        false,
      );
      expect(
        StockAuditRequests.items(
          const StockAuditItemQuery(counted: true),
        )['counted'],
        true,
      );
      final q = StockAuditQuery(
        status: StockAuditStatus.counting,
        warehouseId: 'w1',
        dates: dates,
      );
      expect(
        q
            .copyWith(
              status: () => null,
              warehouseId: () => null,
              dates: () => null,
            )
            .status,
        isNull,
      );
      expect(
        const StockAuditItemQuery(
          counted: false,
        ).copyWith(counted: () => null).counted,
        isNull,
      );
    },
  );

  test(
    'invalid batch and note fail before HTTP without coercing quantities',
    () async {
      var requests = 0;
      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests++;
            h.reject(DioException(requestOptions: r));
          },
        ),
      );
      final repo = StockAuditRepositoryImpl(StockAuditRemoteDataSource(dio));
      final row = StockAuditCountInput(
        auditItemId: 'ai1',
        countedQuantity: InventoryQuantity.zero,
      );
      for (final rows in [
        <StockAuditCountInput>[],
        [row, row],
        List.filled(101, row),
      ]) {
        final input = StockAuditCountsInput(expectedVersion: 0, items: rows);
        expect(StockAuditValidation.counts(input), isNotEmpty);
        expect(
          (await repo.updateCounts('a1', input) as Error).failure.type,
          FailureType.validation,
        );
      }
      expect(
        await repo.updateNote(
          'a1',
          UpdateStockAuditNoteInput(expectedVersion: 0, note: 'x' * 2001),
        ),
        isA<Error>(),
      );
      expect(
        await repo.start(
          'a1',
          const StockAuditTransitionInput(expectedVersion: -1),
        ),
        isA<Error>(),
      );
      expect(
        await repo.create('', const CreateStockAuditInput(warehouseId: 'w1')),
        isA<Error>(),
      );
      expect(await repo.list(const StockAuditQuery(size: 0)), isA<Error>());
      expect(requests, 0);
    },
  );

  test(
    'wrong response identity and server filter violations cannot enter state',
    () async {
      Object? response = stockAuditJson(id: 'other');
      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) => h.resolve(
            Response(
              requestOptions: r,
              statusCode: 200,
              data: jsonEncode(response),
            ),
          ),
        ),
      );
      final repo = StockAuditRepositoryImpl(StockAuditRemoteDataSource(dio));
      expect(
        (await repo.get('a1') as Error).failure.code,
        'INVALID_INVENTORY_RESPONSE',
      );
      response = _page([stockAuditJson(warehouse: 'other', detail: false)]);
      expect(
        await repo.list(const StockAuditQuery(warehouseId: 'w1')),
        isA<Error>(),
      );
      response = _page([stockAuditItemJson(counted: null)]);
      expect(
        await repo.items('a1', const StockAuditItemQuery(counted: true)),
        isA<Error>(),
      );
      response = _page([stockAuditItemJson(counted: 10)]);
      expect(
        await repo.items('a1', const StockAuditItemQuery(differenceOnly: true)),
        isA<Error>(),
      );
      response = _page([stockAuditItemJson(), stockAuditItemJson()]);
      expect(await repo.items('a1', const StockAuditItemQuery()), isA<Error>());
    },
  );

  test(
    'a successful HTTP response must reach the command desired state',
    () async {
      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) => h.resolve(
            Response(
              requestOptions: r,
              statusCode: 200,
              data: jsonEncode(stockAuditJson(status: 'DRAFT')),
            ),
          ),
        ),
      );
      final repo = StockAuditRepositoryImpl(StockAuditRemoteDataSource(dio));
      for (final call in [
        repo.start('a1', const StockAuditTransitionInput(expectedVersion: 0)),
        repo.confirm('a1', const StockAuditTransitionInput(expectedVersion: 0)),
        repo.cancel('a1', const CancelStockAuditInput(expectedVersion: 0)),
        repo.updateCounts(
          'a1',
          StockAuditCountsInput(
            expectedVersion: 0,
            items: [
              StockAuditCountInput(
                auditItemId: 'ai1',
                countedQuantity: InventoryQuantity.zero,
              ),
            ],
          ),
        ),
      ]) {
        expect(
          (await call as Error).failure.code,
          'INVALID_INVENTORY_RESPONSE',
        );
      }
    },
  );

  test(
    'no-op and desired-state replay use returned version without inventing increments',
    () async {
      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) => h.resolve(
            Response(
              requestOptions: r,
              statusCode: 200,
              data: jsonEncode(
                stockAuditJson(
                  status: r.path.endsWith('/confirm')
                      ? 'CONFIRMED'
                      : 'COUNTING',
                  version: 2,
                ),
              ),
            ),
          ),
        ),
      );
      final repo = StockAuditRepositoryImpl(StockAuditRemoteDataSource(dio));
      final unchanged = await repo.updateCounts(
        'a1',
        StockAuditCountsInput(
          expectedVersion: 2,
          items: [
            StockAuditCountInput(
              auditItemId: 'ai1',
              countedQuantity: InventoryQuantity.parse('8'),
            ),
          ],
        ),
      );
      expect((unchanged as Success).value.version, 2);
      final replay = await repo.confirm(
        'a1',
        const StockAuditTransitionInput(expectedVersion: 1),
      );
      expect((replay as Success).value.version, 2);
      expect((replay as Success).value.adjustmentDocumentId, 'adjustment-a1');
    },
  );

  test(
    'HTTP conflict and wrong-parent 404 keep envelope code and status',
    () async {
      final dio = Dio();
      addTearDown(dio.close);
      var status = 409, code = 'STOCK_AUDIT_SNAPSHOT_STALE';
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) => h.reject(
            DioException(
              requestOptions: r,
              type: DioExceptionType.badResponse,
              response: Response<String>(
                requestOptions: r,
                statusCode: status,
                data: jsonEncode({
                  'success': false,
                  'code': code,
                  'message': 'Backend message',
                  'fieldErrors': <String, String>{},
                }),
              ),
            ),
          ),
        ),
      );
      final repo = StockAuditRepositoryImpl(StockAuditRemoteDataSource(dio));
      final stale =
          await repo.confirm(
                'a1',
                const StockAuditTransitionInput(expectedVersion: 2),
              )
              as Error;
      expect(stale.failure.code, code);
      expect(stale.failure.type, FailureType.conflict);
      status = 404;
      code = 'STOCK_AUDIT_ITEM_NOT_FOUND';
      final wrongParent =
          await repo.updateCounts(
                'a1',
                StockAuditCountsInput(
                  expectedVersion: 2,
                  items: [
                    StockAuditCountInput(
                      auditItemId: 'foreign-item',
                      countedQuantity: InventoryQuantity.zero,
                    ),
                  ],
                ),
              )
              as Error;
      expect(wrongParent.failure.code, code);
      expect(wrongParent.failure.type, FailureType.notFound);
    },
  );
}

class _AuditAdapter implements HttpClientAdapter {
  _AuditAdapter(this.body);
  final String body;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  void close({bool force = false}) {}
}
