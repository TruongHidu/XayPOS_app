import 'dart:convert';
import 'package:dio/dio.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/stock_document.dart';
import '../../domain/entities/stock_inputs.dart';
import '../../domain/entities/stock_queries.dart';
import '../dto/stock_document_dto.dart';
import '../dto/stock_document_requests.dart';
import '../dto/stock_json.dart';

class StockDocumentRemoteDataSource {
  const StockDocumentRemoteDataSource(this.dio);
  final Dio dio;
  static const base = '/api/v1/inventory';
  String documentPath(String id) =>
      '/stock-documents/${Uri.encodeComponent(id)}';
  Future<Object?> request(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    String? key,
    int status = 200,
  }) async {
    try {
      final response = await dio.request<dynamic>(
        '$base$path',
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          responseType: ResponseType.plain,
          contentType: body == null ? null : Headers.jsonContentType,
          headers: {
            'Accept': 'application/json',
            if (key != null) 'Idempotency-Key': key,
          },
        ),
      );
      if (response.statusCode != status) {
        throw const FormatException('Invalid stock response status');
      }
      if (status == 204) return null;
      return response.data is String
          ? decodeStockJson(response.data as String)
          : response.data;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is String) {
        try {
          e.response!.data = jsonDecode(data);
        } on FormatException {
          /* Keep unrecognized server errors. */
        }
      }
      rethrow;
    }
  }

  Future<InventoryPage<StockDocumentSummary>> list(
    StockDocumentQuery q,
  ) async => StockDocumentDto.page(
    await request(
      'GET',
      '/stock-documents',
      query: StockDocumentRequests.documents(q),
    ),
    StockDocumentDto.summary,
    q.page,
  );
  StockDocumentDetail _detail(Object? raw, String id) {
    final value = StockDocumentDto.detail(raw);
    if (value.id != id) throw const FormatException('Wrong document identity');
    return value;
  }

  Future<StockDocumentDetail> detail(String id) async =>
      _detail(await request('GET', documentPath(id)), id);
  Future<StockDocumentDetail> create(
    String key,
    CreateStockDocumentInput input,
  ) async {
    final value = StockDocumentDto.detail(
      await request(
        'POST',
        '/stock-documents',
        key: key,
        body: StockDocumentRequests.create(input),
        status: 201,
      ),
    );
    if (value.warehouseId != input.warehouseId || value.type != input.type) {
      throw const FormatException('Wrong creation identity');
    }
    return value;
  }

  Future<StockDocumentDetail> update(
    String id,
    UpdateStockDocumentNote input,
  ) async => _detail(
    await request(
      'PATCH',
      documentPath(id),
      body: {
        'expectedVersion': input.expectedVersion,
        'note': StockDocumentRequests.note(input.note),
      },
    ),
    id,
  );
  Future<StockDocumentDetail> addItem(
    String id,
    StockDocumentLineInput input,
  ) async => _detail(
    await request(
      'POST',
      '${documentPath(id)}/items',
      body: {
        'expectedVersion': input.expectedVersion,
        ...StockDocumentRequests.line(input.line),
      },
    ),
    id,
  );
  Future<StockDocumentDetail> updateItem(
    String id,
    String item,
    StockDocumentLineInput input,
  ) async => _detail(
    await request(
      'PATCH',
      '${documentPath(id)}/items/${Uri.encodeComponent(item)}',
      body: {
        'expectedVersion': input.expectedVersion,
        ...StockDocumentRequests.line(input.line, includeIngredient: false),
      },
    ),
    id,
  );
  Future<void> removeItem(
    String id,
    String item,
    StockDocumentVersion version,
  ) async {
    await request(
      'DELETE',
      '${documentPath(id)}/items/${Uri.encodeComponent(item)}',
      query: {'expectedVersion': version.expectedVersion},
      status: 204,
    );
  }

  Future<StockDocumentDetail> transition(
    String id,
    StockDocumentVersion version,
    bool confirm,
  ) async {
    final value = _detail(
      await request(
        'POST',
        '${documentPath(id)}/${confirm ? 'confirm' : 'cancel'}',
        body: {'expectedVersion': version.expectedVersion},
      ),
      id,
    );
    if (value.status !=
        (confirm
            ? StockDocumentStatus.confirmed
            : StockDocumentStatus.cancelled)) {
      throw const FormatException('Wrong document status');
    }
    return value;
  }

  Future<InventoryPage<InventoryTransaction>> transactions(
    InventoryTransactionQuery q,
  ) async {
    final page = StockDocumentDto.page(
      await request(
        'GET',
        '/transactions',
        query: StockDocumentRequests.transactions(q),
      ),
      StockDocumentDto.transaction,
      q.page,
    );
    if (page.content.any(
      (r) =>
          q.warehouseId != null && r.warehouseId != q.warehouseId ||
          q.ingredientId != null && r.ingredientId != q.ingredientId ||
          q.documentId != null && r.documentId != q.documentId ||
          q.orderId != null && r.orderId != q.orderId ||
          q.orderItemId != null && r.orderItemId != q.orderItemId ||
          q.source != null && r.source != q.source ||
          q.type != null && r.type != q.type,
    )) {
      throw const FormatException('Wrong ledger query response');
    }
    return page;
  }
}
