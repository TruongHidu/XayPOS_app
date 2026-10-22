import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/inventory/data/data_sources/inventory_alert_remote_data_source.dart';
import 'package:pos_saas_app/features/inventory/data/dto/inventory_alert_dto.dart';
import 'package:pos_saas_app/features/inventory/data/dto/inventory_alert_requests.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_json.dart';
import 'package:pos_saas_app/features/inventory/data/repositories/inventory_alert_repository_impl.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_alert.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_alert_query.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_instant_range.dart';
import 'inventory_alert_fakes.dart';
import 'inventory_fakes.dart';

void main() {
  test(
    'three alert APIs use exact auth, read query, version and no key/body extras',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://alerts.invalid',
          headers: {'Authorization': 'Bearer inherited'},
        ),
      );
      addTearDown(dio.close);
      var acknowledged = false;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests.add(r);
            if (r.method == 'POST') acknowledged = true;
            final row = inventoryAlertJson(
              status: acknowledged ? 'ACKNOWLEDGED' : 'OPEN',
              version: acknowledged ? 1 : 0,
            );
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: 200,
                data: jsonEncode(
                  r.path.endsWith('/alerts') ? pageJson([row]) : row,
                ),
              ),
            );
          },
        ),
      );
      final repo = InventoryAlertRepositoryImpl(
        InventoryAlertRemoteDataSource(dio),
      );
      expect(
        await repo.list(
          InventoryAlertQuery(
            q: ' %_ ',
            warehouseId: 'w1',
            ingredientId: 'i1',
            dates: InventoryInstantRange(
              from: DateTime.utc(2026, 10, 20),
              to: DateTime.utc(2026, 10, 22),
            ),
          ),
        ),
        isA<Success>(),
      );
      expect(await repo.detail('a1'), isA<Success>());
      final ack =
          await repo.acknowledge('a1', const AcknowledgeInventoryAlertInput(0))
              as Success;
      final replay =
          await repo.acknowledge('a1', const AcknowledgeInventoryAlertInput(0))
              as Success;
      expect(replay.value.version, ack.value.version);
      expect(replay.value.acknowledgedAt, ack.value.acknowledgedAt);
      expect(requests.map((r) => '${r.method} ${r.path}'), [
        'GET /api/v1/inventory/alerts',
        'GET /api/v1/inventory/alerts/a1',
        'POST /api/v1/inventory/alerts/a1/acknowledge',
        'POST /api/v1/inventory/alerts/a1/acknowledge',
      ]);
      expect(requests.first.queryParameters, {
        'warehouseId': 'w1',
        'ingredientId': 'i1',
        'status': 'OPEN',
        'q': '%_',
        'triggeredFrom': '2026-10-20T00:00:00.000Z',
        'triggeredTo': '2026-10-22T00:00:00.000Z',
        'page': 0,
        'size': 20,
        'sortBy': 'triggeredAt',
        'direction': 'desc',
      });
      expect(requests[1].queryParameters, isEmpty);
      for (final r in requests) {
        expect(r.headers['Authorization'], 'Bearer inherited');
        expect(r.headers['Accept'], 'application/json');
        expect(r.headers['Cache-Control'], 'no-store');
        expect(r.headers.containsKey('Idempotency-Key'), false);
        expect(r.queryParameters.containsKey('restaurantId'), false);
        expect(r.responseType, ResponseType.plain);
        if (r.method == 'GET') {
          expect(r.data, null);
        } else {
          expect(r.data, {'expectedVersion': 0});
        }
      }
    },
  );
  test(
    'history metadata and all reasons survive null comparison and same-version stock changes',
    () {
      for (final reason in InventoryAlertResolution.values) {
        final value = InventoryAlertDto.parse(
          inventoryAlertJson(
            status: 'RESOLVED',
            reason: reason.code,
            comparable: false,
          ),
        );
        expect(value.resolutionReason, reason);
        expect(value.currentQuantity, null);
        expect(value.ingredientName, 'Thịt bò lịch sử');
        expect(value.thresholdQuantity.toString(), '200');
      }
      final before = InventoryAlertDto.parse(inventoryAlertJson()),
          after = InventoryAlertDto.parse(
            inventoryAlertJson(current: 1000, reserved: 900),
          );
      expect(before.version, after.version);
      expect(after.availableQuantity.toString(), '100');
      expect(
        after.currentQuantity!.scaled > after.currentMinQuantity!.scaled,
        true,
      );
      expect(after.quantityAtTrigger, before.quantityAtTrigger);
      final noSku = InventoryAlertDto.parse({
        ...inventoryAlertJson(),
        'ingredientSku': null,
      });
      expect(noSku.ingredientSku, null);
    },
  );
  test(
    'lossless 14,3, malformed lifecycle, partial comparison and negative stock rejected',
    () {
      final raw = jsonEncode(inventoryAlertJson())
          .replaceFirst(
            '"quantityAtTrigger":150',
            '"quantityAtTrigger":99999999999.998',
          )
          .replaceFirst(
            '"thresholdQuantity":200',
            '"thresholdQuantity":99999999999.999',
          );
      final value = InventoryAlertDto.parse(decodeStockJson(raw));
      expect(value.thresholdQuantity.toString(), '99999999999.999');
      expect(value.quantityAtTrigger.toString(), '99999999999.998');
      for (final row in [
        {...inventoryAlertJson(), 'currentQuantity': -1},
        {...inventoryAlertJson(), 'reservedQuantity': 151},
        {...inventoryAlertJson(), 'currentMinQuantity': null},
        {...inventoryAlertJson(), 'availableQuantity': 50},
        {...inventoryAlertJson(), 'status': 'ACKNOWLEDGED'},
        {...inventoryAlertJson(), 'resolutionReason': 'STOCK_RECOVERED'},
        {...inventoryAlertJson(), 'status': 'OTHER'},
      ]) {
        expect(() => InventoryAlertDto.parse(row), throwsFormatException);
      }
    },
  );
  test(
    'queries use exclusive next-day, literal search and independent nullable status',
    () {
      final range = InventoryInstantRange.days(
        DateTime(2026, 10, 21),
        DateTime(2026, 10, 21),
      );
      expect(range.to!.toLocal(), DateTime(2026, 10, 22));
      final q = InventoryAlertRequests.list(
        InventoryAlertQuery(status: null, dates: range, q: '%_'),
      );
      expect(q['q'], '%_');
      expect(q.containsKey('status'), false);
      expect(
        q['triggeredTo'],
        DateTime(2026, 10, 22).toUtc().toIso8601String(),
      );
      for (final q in [
        InventoryAlertQuery(q: 'x' * 101),
        const InventoryAlertQuery(size: 101),
        const InventoryAlertQuery(page: -1),
        const InventoryAlertQuery(sortBy: 'quantity'),
        const InventoryAlertQuery(direction: 'bad'),
        InventoryAlertQuery(
          dates: InventoryInstantRange(from: range.to, to: range.from),
        ),
      ]) {
        expect(q.valid, false);
      }
      expect(const AcknowledgeInventoryAlertInput(-1).valid, false);
    },
  );
  test(
    'wrong identity/status and plain 409 are preserved as safe failures',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://alerts.invalid'));
      addTearDown(dio.close);
      var response = inventoryAlertJson(id: 'wrong');
      var status = 200;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            final result = Response(
              requestOptions: r,
              statusCode: status,
              data: jsonEncode(response),
            );
            if (status >= 400) {
              h.reject(
                DioException(
                  requestOptions: r,
                  type: DioExceptionType.badResponse,
                  response: result,
                ),
              );
            } else {
              h.resolve(result);
            }
          },
        ),
      );
      final repo = InventoryAlertRepositoryImpl(
        InventoryAlertRemoteDataSource(dio),
      );
      expect(
        (await repo.detail('a1') as Error).failure.code,
        'INVALID_INVENTORY_RESPONSE',
      );
      response = inventoryAlertJson(status: 'RESOLVED');
      expect(
        await repo.acknowledge('a1', const AcknowledgeInventoryAlertInput(0)),
        isA<Error>(),
      );
      status = 409;
      response = {
        'code': 'CONCURRENT_LOW_STOCK_ALERT_UPDATE',
        'message': 'stale',
        'fieldErrors': {},
      };
      final error =
          (await repo.acknowledge('a1', const AcknowledgeInventoryAlertInput(0))
                  as Error)
              .failure;
      expect(error.type, FailureType.conflict);
      expect(error.code, 'CONCURRENT_LOW_STOCK_ALERT_UPDATE');
    },
  );
}
