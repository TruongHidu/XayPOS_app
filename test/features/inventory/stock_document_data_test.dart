import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/inventory/data/data_sources/stock_document_remote_data_source.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_json.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_document_dto.dart';
import 'package:pos_saas_app/features/inventory/data/repositories/stock_document_repository_impl.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_quantity.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_document.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_inputs.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_numbers.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_queries.dart';
import 'package:pos_saas_app/features/inventory/domain/policies/stock_document_validation.dart';
import 'stock_fakes.dart';
import 'inventory_fakes.dart';

void main() {
  test('real Dio transformer leaves large JSON decimals intact', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://stock.invalid'));
    addTearDown(dio.close);
    final summary = stockDetailJson()..remove('items');
    dio.httpClientAdapter = _StockAdapter(
      jsonEncode(
        pageJson([summary]),
      ).replaceFirst('"totalCost":200', '"totalCost":9999999999999999.99'),
    );
    final result =
        await StockDocumentRepositoryImpl(
              StockDocumentRemoteDataSource(dio),
            ).list(const StockDocumentQuery())
            as Success;
    expect(
      result.value.content.single.totalCost.cents,
      BigInt.parse('999999999999999999'),
    );
  });
  test(
    '10 stock endpoints preserve aggregate version, full line payload and exact statuses',
    () async {
      final requests = <RequestOptions>[],
          dio = Dio(
            BaseOptions(
              baseUrl: 'https://stock.invalid',
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
              data = 'NOT JSON';
            } else if (r.path.endsWith('/transactions')) {
              data = pageJson(
                [transactionJson()],
                page: 2,
                size: 50,
                total: 101,
                pages: 3,
              );
            } else if (r.method == 'GET' &&
                r.path.endsWith('/stock-documents')) {
              data = pageJson(
                [stockDetailJson()],
                page: 2,
                size: 50,
                total: 101,
                pages: 3,
              );
            } else {
              data = stockDetailJson(
                status: r.path.endsWith('/confirm')
                    ? 'CONFIRMED'
                    : r.path.endsWith('/cancel')
                    ? 'CANCELLED'
                    : 'DRAFT',
              );
              if (r.method == 'POST' && r.path.endsWith('/stock-documents')) {
                status = 201;
              }
            }
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: status,
                data: status == 204 ? data : jsonEncode(data),
              ),
            );
          },
        ),
      );
      final remote = StockDocumentRemoteDataSource(dio),
          repo = StockDocumentRepositoryImpl(remote),
          ledger = InventoryTransactionRepositoryImpl(remote);
      final dates = StockDateRange(
        from: DateTime.utc(2026, 10, 1),
        to: DateTime.utc(2026, 10, 18),
      );
      expect(
        await repo.list(
          StockDocumentQuery(
            q: ' nhập ',
            type: StockDocumentType.receipt,
            status: StockDocumentStatus.draft,
            warehouseId: 'w1',
            dates: dates,
            page: 2,
            size: 50,
            sortBy: 'totalCost',
            direction: 'asc',
          ),
        ),
        isA<Success>(),
      );
      expect(await repo.detail('d1'), isA<Success>());
      expect(
        await repo.create(
          'frozen-key',
          CreateStockDocumentInput(
            type: StockDocumentType.receipt,
            warehouseId: 'w1',
            note: ' ghi chú ',
            items: [stockLine(note: ' dòng ')],
          ),
        ),
        isA<Success>(),
      );
      expect(
        await repo.update('d1', const UpdateStockDocumentNote(3, null)),
        isA<Success>(),
      );
      expect(
        await repo.addItem('d1', StockDocumentLineInput(3, stockLine())),
        isA<Success>(),
      );
      expect(
        await repo.updateItem(
          'd1',
          'si1',
          StockDocumentLineInput(3, stockLine()),
        ),
        isA<Success>(),
      );
      expect(
        await repo.removeItem('d1', 'si1', const StockDocumentVersion(3)),
        isA<Success>(),
      );
      expect(
        await repo.confirm('d1', const StockDocumentVersion(3)),
        isA<Success>(),
      );
      expect(
        await repo.cancel('d1', const StockDocumentVersion(3)),
        isA<Success>(),
      );
      expect(
        await ledger.list(
          InventoryTransactionQuery(
            warehouseId: 'w1',
            ingredientId: 'i1',
            documentId: 'd1',
            type: InventoryTransactionType.issue,
            dates: dates,
            page: 2,
            size: 50,
            direction: 'asc',
          ),
        ),
        isA<Success>(),
      );
      expect(requests.map((r) => '${r.method} ${r.path}'), [
        'GET /api/v1/inventory/stock-documents',
        'GET /api/v1/inventory/stock-documents/d1',
        'POST /api/v1/inventory/stock-documents',
        'PATCH /api/v1/inventory/stock-documents/d1',
        'POST /api/v1/inventory/stock-documents/d1/items',
        'PATCH /api/v1/inventory/stock-documents/d1/items/si1',
        'DELETE /api/v1/inventory/stock-documents/d1/items/si1',
        'POST /api/v1/inventory/stock-documents/d1/confirm',
        'POST /api/v1/inventory/stock-documents/d1/cancel',
        'GET /api/v1/inventory/transactions',
      ]);
      expect(requests[0].queryParameters, {
        'q': 'nhập',
        'type': 'RECEIPT',
        'status': 'DRAFT',
        'warehouseId': 'w1',
        'createdFrom': '2026-10-01T00:00:00.000Z',
        'createdTo': '2026-10-18T00:00:00.000Z',
        'page': 2,
        'size': 50,
        'sortBy': 'totalCost',
        'direction': 'asc',
      });
      expect(requests[2].headers['Idempotency-Key'], 'frozen-key');
      expect(requests[2].data, {
        'documentType': 'RECEIPT',
        'warehouseId': 'w1',
        'note': 'ghi chú',
        'items': [
          {
            'ingredientId': 'i1',
            'quantity': 2,
            'unitCost': 100,
            'adjustmentDirection': null,
            'note': 'dòng',
          },
        ],
      });
      expect(requests[3].data, {'expectedVersion': 3, 'note': null});
      expect(requests[4].data, {
        'expectedVersion': 3,
        'ingredientId': 'i1',
        'quantity': 2,
        'unitCost': 100,
        'adjustmentDirection': null,
        'note': null,
      });
      expect(requests[5].data, {
        'expectedVersion': 3,
        'quantity': 2,
        'unitCost': 100,
        'adjustmentDirection': null,
        'note': null,
      });
      expect(requests[6].data, isNull);
      expect(requests[6].queryParameters, {'expectedVersion': 3});
      expect(requests[7].data, {'expectedVersion': 3});
      expect(requests[8].data, {'expectedVersion': 3});
      expect(requests.last.queryParameters['documentId'], 'd1');
      expect(requests.last.queryParameters['transactionType'], 'ISSUE');
      expect(requests.last.queryParameters.containsKey('q'), false);
      for (final r in requests) {
        expect(r.headers['Authorization'], 'Bearer existing');
        expect(r.queryParameters.containsKey('restaurantId'), false);
        if (r != requests[2]) {
          expect(r.headers.containsKey('Idempotency-Key'), false);
        }
        expect(r.responseType, ResponseType.plain);
      }
    },
  );
  test(
    'lossless decimal reader preserves huge totals and ignores numbers in escaped notes',
    () {
      final json = jsonEncode(stockDetailJson());
      final summary = (jsonDecode(json) as Map<String, dynamic>)
        ..['totalCost'] = 'RAW'
        ..['totalQuantity'] = 'QRAW'
        ..['note'] = '2026, \\ "123.99"';
      final raw = jsonEncode(summary)
          .replaceFirst('"RAW"', '9999999999999999.99')
          .replaceFirst('"QRAW"', '9999999999999.999');
      final value = StockDocumentDto.summary(decodeStockJson(raw));
      expect(value.totalCost.cents, BigInt.parse('999999999999999999'));
      expect(value.totalQuantity.scaled, BigInt.parse('9999999999999999'));
      expect(value.note, '2026, \\ "123.99"');
      expect(
        () => StockDocumentDto.summary({
          ...stockDetailJson(),
          'totalCost': 9999999999999999.99,
        }),
        throwsFormatException,
      );
      expect(StockMoney.unitCost('999999999999.99').validUnitCost, true);
      expect(() => StockMoney.unitCost('1000000000000'), throwsFormatException);
      expect(
        StockDocumentDto.summary(
          decodeStockJson(json.replaceFirst('200', '2e2')),
        ).totalCost.toString(),
        '200',
      );
    },
  );
  test(
    'positive input, signed deltas, exact preview and backend rounding limitation',
    () {
      expect(StockQuantityChange.parse('-0.001').scaled, -BigInt.one);
      for (final value in ['0', '-0', '1.0001', '--1', '1e2']) {
        expect(() => StockQuantityChange.parse(value), throwsFormatException);
      }
      for (final value in ['-1', '1.001', 'NaN', '1x2', '1.2x3']) {
        expect(() => StockMoney.unitCost(value), throwsFormatException);
      }
      expect(
        stockLineCost(
          InventoryQuantity.parse('1.125'),
          StockMoney.unitCost('1234.56'),
        ).toString(),
        '1388.88',
      );
      final bad = StockDocumentValidation.line(
        StockDocumentType.receipt,
        stockLine(quantity: '0.001', cost: '0.01'),
      );
      expect(bad['unitCost'], contains('chưa hỗ trợ làm tròn'));
      expect(
        StockDocumentValidation.line(
          StockDocumentType.issue,
          stockLine(quantity: '0'),
        ).containsKey('quantity'),
        true,
      );
      expect(
        StockDocumentValidation.line(
          StockDocumentType.adjustment,
          stockLine(),
        ).containsKey('adjustmentDirection'),
        true,
      );
      expect(
        StockDocumentValidation.create(
          CreateStockDocumentInput(
            type: StockDocumentType.receipt,
            warehouseId: 'w1',
            items: [],
          ),
        ),
        isEmpty,
      );
      expect(
        StockDocumentValidation.create(
          CreateStockDocumentInput(
            type: StockDocumentType.receipt,
            warehouseId: 'w1',
            items: [
              stockLine(),
              stockLine(direction: AdjustmentDirection.decrease),
            ],
          ),
        ),
        isNotEmpty,
      );
    },
  );
  test(
    'ledger sign and before/after validated; no artificial 100-line response limit',
    () {
      final row = StockDocumentDto.transaction(transactionJson());
      expect(row.change.negative, true);
      expect(row.documentId, 'd1');
      expect(
        () => StockDocumentDto.transaction({
          ...transactionJson(),
          'quantityChange': 2,
        }),
        throwsFormatException,
      );
      expect(
        () => StockDocumentDto.transaction({
          ...transactionJson(),
          'afterQuantity': 7,
        }),
        throwsFormatException,
      );
      final rows = [
        for (var i = 0; i < 101; i++)
          stockItemJson(id: 's$i', ingredient: 'i$i'),
      ];
      expect(
        StockDocumentDto.detail(stockDetailJson(items: rows)).lineCount,
        101,
      );
    },
  );
  test(
    'create replay can return terminal status, no-op versions retained, plain HTTP errors mapped',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://stock.invalid'));
      addTearDown(dio.close);
      var status = 201;
      Object data = stockDetailJson(status: 'CONFIRMED', version: 8);
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
                    data: jsonEncode(data),
                  ),
                ),
              );
            } else {
              h.resolve(
                Response(
                  requestOptions: r,
                  statusCode: status,
                  data: jsonEncode(data),
                ),
              );
            }
          },
        ),
      );
      final repo = StockDocumentRepositoryImpl(
        StockDocumentRemoteDataSource(dio),
      );
      final created =
          await repo.create(
                'same',
                CreateStockDocumentInput(
                  type: StockDocumentType.receipt,
                  warehouseId: 'w1',
                  items: [],
                ),
              )
              as Success;
      expect(created.value.status, StockDocumentStatus.confirmed);
      expect(created.value.version, 8);
      status = 200;
      expect(
        (await repo.confirm('d1', const StockDocumentVersion(8)) as Success)
            .value
            .version,
        8,
      );
      status = 409;
      data = {
        'code': 'INSUFFICIENT_STOCK',
        'message': 'No stock',
        'fieldErrors': {},
      };
      final failed =
          await repo.confirm('d1', const StockDocumentVersion(8)) as Error;
      expect(failed.failure.type, FailureType.conflict);
      expect(failed.failure.message, contains('Toàn bộ phiếu chưa'));
      data = {
        'code': 'CONCURRENT_STOCK_DOCUMENT_UPDATE',
        'message': 'Conflict',
        'fieldErrors': {},
      };
      expect(
        (await repo.update('d1', const UpdateStockDocumentNote(8, 'x'))
                as Error)
            .failure
            .code,
        'CONCURRENT_STOCK_DOCUMENT_UPDATE',
      );
    },
  );
}

class _StockAdapter implements HttpClientAdapter {
  _StockAdapter(this.raw);
  final String raw;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    raw,
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
  @override
  void close({bool force = false}) {}
}
