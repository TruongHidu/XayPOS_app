import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/inventory/data/data_sources/inventory_remote_data_source.dart';
import 'package:pos_saas_app/features/inventory/data/dto/inventory_dto.dart';
import 'package:pos_saas_app/features/inventory/data/repositories/warehouse_repository_impl.dart';
import 'package:pos_saas_app/features/inventory/data/repositories/inventory_balance_repository_impl.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_inputs.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_quantity.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_queries.dart';
import 'inventory_fakes.dart';

void main() {
  test(
    'all 11 API contracts, null/zero version, no-op and DELETE 204',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://inventory.invalid',
          headers: {'Authorization': 'Bearer existing'},
        ),
      );
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests.add(r);
            Object? data;
            var status = 200;
            if (r.method == 'DELETE') {
              status = 204;
              data = 'not-json-and-must-not-be-parsed';
            } else if (r.path.endsWith('/threshold')) {
              final body = r.data as Map;
              data = balanceJson(
                configured:
                    body['minQuantity'] != 0 || body['expectedVersion'] != null,
                quantity: 0,
                min: body['minQuantity'],
                version: body['expectedVersion'] ?? 0,
              );
            } else if (r.path.endsWith('/balances')) {
              data = pageJson(
                [balanceJson(configured: false)],
                page: 2,
                size: 50,
                total: 101,
                pages: 3,
              );
            } else if (r.path.endsWith('/balances/i1')) {
              data = balanceJson(configured: false);
            } else if (r.path.endsWith('/low-stock')) {
              data = pageJson([balanceJson(quantity: 2, min: 2)]);
            } else if (r.method == 'GET' && r.path.endsWith('/warehouses')) {
              data = pageJson(
                [warehouseJson()],
                page: 2,
                size: 50,
                total: 101,
                pages: 3,
              );
            } else {
              data = warehouseJson(
                active: !r.path.endsWith('/status'),
                isDefault: !r.path.endsWith('/status'),
              );
              if (r.method == 'POST' && r.path.endsWith('/warehouses')) {
                status = 201;
              }
            }
            h.resolve(
              Response(requestOptions: r, statusCode: status, data: data),
            );
          },
        ),
      );
      final remote = InventoryRemoteDataSource(dio),
          wh = WarehouseRepositoryImpl(InventoryRemoteDataSource(dio));
      final balances = InventoryBalanceRepositoryImpl(remote);
      expect(
        await wh.list(
          const WarehouseQuery(
            q: ' chính ',
            active: false,
            page: 2,
            size: 50,
            sortBy: 'code',
            direction: 'asc',
          ),
        ),
        isA<Success>(),
      );
      expect(await wh.detail('w1'), isA<Success>());
      expect(
        await wh.create(
          const CreateWarehouseInput(code: ' kho-main ', name: ' Kho chính '),
        ),
        isA<Success>(),
      );
      expect(
        await wh.update(
          'w1',
          const UpdateWarehouseInput(expectedVersion: 0, name: 'Tên mới'),
        ),
        isA<Success>(),
      );
      expect(
        await wh.setStatus('w1', const SetWarehouseStatusInput(0, false)),
        isA<Success>(),
      );
      expect(
        await wh.makeDefault('w1', const WarehouseVersionInput(0)),
        isA<Success>(),
      );
      expect(
        await wh.delete('w1', const WarehouseVersionInput(0)),
        isA<Success>(),
      );
      final list = await balances.list(
        'w1',
        const InventoryBalanceQuery(
          q: ' bột ',
          ingredientActive: false,
          page: 2,
          size: 50,
          sortBy: 'updatedAt',
          direction: 'desc',
        ),
      );
      expect((list as Success).value.content.single.configured, false);
      final logical = await balances.detail('w1', 'i1') as Success;
      expect(logical.value.version, isNull);
      expect(
        await balances.threshold(
          'w1',
          'i1',
          UpdateInventoryThresholdInput(
            null,
            InventoryQuantity.parse('10.125'),
          ),
        ),
        isA<Success>(),
      );
      expect(
        await balances.threshold(
          'w1',
          'i1',
          const UpdateInventoryThresholdInput(0, InventoryQuantity.zero),
        ),
        isA<Success>(),
      );
      final zero =
          await balances.threshold(
                'w1',
                'i1',
                const UpdateInventoryThresholdInput(
                  null,
                  InventoryQuantity.zero,
                ),
              )
              as Success;
      expect(zero.value.configured, false);
      expect(zero.value.version, isNull);
      expect(
        await balances.lowStock(const LowStockQuery(warehouseId: 'w1')),
        isA<Success>(),
      );
      expect(requests.map((r) => '${r.method} ${r.path}'), [
        'GET /api/v1/inventory/warehouses',
        'GET /api/v1/inventory/warehouses/w1',
        'POST /api/v1/inventory/warehouses',
        'PATCH /api/v1/inventory/warehouses/w1',
        'PATCH /api/v1/inventory/warehouses/w1/status',
        'POST /api/v1/inventory/warehouses/w1/make-default',
        'DELETE /api/v1/inventory/warehouses/w1',
        'GET /api/v1/inventory/warehouses/w1/balances',
        'GET /api/v1/inventory/warehouses/w1/balances/i1',
        ...List.filled(
          3,
          'PATCH /api/v1/inventory/warehouses/w1/balances/i1/threshold',
        ),
        'GET /api/v1/inventory/low-stock',
      ]);
      expect(requests[0].queryParameters, {
        'q': 'chính',
        'active': false,
        'page': 2,
        'size': 50,
        'sortBy': 'code',
        'direction': 'asc',
      });
      expect(requests[2].data, {'code': 'KHO-MAIN', 'name': 'Kho chính'});
      expect(requests[3].data, {'expectedVersion': 0, 'name': 'Tên mới'});
      expect(requests[4].data, {'active': false, 'expectedVersion': 0});
      expect(requests[5].data, {'expectedVersion': 0});
      expect(requests[6].queryParameters, {'expectedVersion': 0});
      expect(requests[6].data, isNull);
      expect(requests[7].queryParameters, {
        'q': 'bột',
        'ingredientActive': false,
        'page': 2,
        'size': 50,
        'sortBy': 'updatedAt',
        'direction': 'desc',
      });
      expect(requests[9].data, {
        'expectedVersion': null,
        'minQuantity': 10.125,
      });
      expect(requests[10].data, {'expectedVersion': 0, 'minQuantity': 0});
      expect(requests.last.queryParameters, {
        'warehouseId': 'w1',
        'page': 0,
        'size': 20,
        'sortBy': 'quantity',
        'direction': 'asc',
      });
      for (final r in requests) {
        expect(r.headers['Authorization'], 'Bearer existing');
        expect(r.headers.containsKey('Idempotency-Key'), false);
        expect(r.queryParameters.containsKey('restaurantId'), false);
      }
    },
  );

  test(
    'exact thousandths, zero, web-safe upper bound and invalid precision',
    () {
      expect(InventoryQuantity.parse('0.000'), InventoryQuantity.zero);
      expect(InventoryQuantity.parse('0001.001').scaled, 1001);
      final max = InventoryQuantity.parse('99999999999.999');
      expect(max.scaled, 99999999999999);
      expect(max.scaled, lessThan(9007199254740991));
      expect(InventoryQuantity.fromNumber(max.toNumber()), max);
      for (final input in [
        '',
        '-1',
        '1.0001',
        '100000000000',
        '1e2',
        'NaN',
        'Infinity',
        '1,5',
      ]) {
        expect(
          () => InventoryQuantity.parse(input),
          throwsFormatException,
          reason: input,
        );
      }
      expect(
        () => InventoryQuantity.fromNumber(double.nan),
        throwsFormatException,
      );
    },
  );

  test('logical balances, null SKU and inactive ingredients are valid', () {
    final row = InventoryDto.balance(
      balanceJson(configured: false, active: false),
    );
    expect(row.key, 'w1:i1');
    expect([
      row.balanceId,
      row.version,
      row.createdAt,
      row.updatedAt,
      row.ingredientSku,
    ], everyElement(isNull));
    expect(row.lowStock, false);
    expect(
      InventoryDto.balance(balanceJson(quantity: 2, min: 2)).lowStock,
      true,
    );
    expect(
      InventoryDto.balance(balanceJson(quantity: 0, min: 0)).lowStock,
      false,
    );
    expect(
      () => InventoryDto.balance({
        ...balanceJson(configured: false),
        'version': 0,
      }),
      throwsFormatException,
    );
    expect(
      () => InventoryDto.balance({...balanceJson(), 'lowStock': false}),
      throwsFormatException,
    );
  });

  test(
    'wrong status/identity/version/schema is not applied; conflict keeps server code',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://inventory.invalid'));
      addTearDown(dio.close);
      var status = 200;
      Object? data = warehouseJson(id: 'other');
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            if (status >= 400) {
              h.reject(
                DioException(
                  requestOptions: r,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: r,
                    statusCode: status,
                    data: data,
                  ),
                ),
              );
            } else {
              h.resolve(
                Response(requestOptions: r, statusCode: status, data: data),
              );
            }
          },
        ),
      );
      final repo = WarehouseRepositoryImpl(InventoryRemoteDataSource(dio));
      expect(await repo.detail('w1'), isA<Error>());
      data = warehouseJson();
      expect(
        await repo.create(const CreateWarehouseInput(code: 'A', name: 'A')),
        isA<Error>(),
      ); // requires 201
      expect(
        await repo.update(
          'w1',
          const UpdateWarehouseInput(expectedVersion: 2, name: 'X'),
        ),
        isA<Error>(),
      );
      status = 409;
      data = {
        'success': false,
        'code': 'WAREHOUSE_CODE_EXISTS',
        'message': 'Duplicate',
        'fieldErrors': {},
      };
      final result =
          await repo.create(const CreateWarehouseInput(code: 'A', name: 'A'))
              as Error;
      expect(result.failure.type, FailureType.conflict);
      expect(result.failure.fieldErrors['code'], contains('đã xóa'));
      data = {
        'success': false,
        'code': 'WAREHOUSE_HAS_STOCK',
        'message': 'Stock',
        'fieldErrors': {},
      };
      final stock =
          await repo.delete('w1', const WarehouseVersionInput(0)) as Error;
      expect(stock.failure.message, contains('tồn khác 0'));
    },
  );
}
