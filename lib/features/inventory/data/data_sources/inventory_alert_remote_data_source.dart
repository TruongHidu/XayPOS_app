import 'dart:convert';
import 'package:dio/dio.dart';
import '../../domain/entities/inventory_alert.dart';
import '../../domain/entities/inventory_alert_query.dart';
import '../../domain/entities/inventory_entities.dart';
import '../dto/inventory_alert_dto.dart';
import '../dto/inventory_alert_requests.dart';
import '../dto/stock_json.dart';

class InventoryAlertRemoteDataSource {
  const InventoryAlertRemoteDataSource(this.dio);
  final Dio dio;
  static const base = '/api/v1/inventory/alerts';
  Future<Object?> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    try {
      final response = await dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          responseType: ResponseType.plain,
          contentType: body == null ? null : Headers.jsonContentType,
          headers: {'Accept': 'application/json', 'Cache-Control': 'no-store'},
        ),
      );
      if (response.statusCode != 200) {
        throw const FormatException('Invalid alert response status');
      }
      return response.data is String
          ? decodeStockJson(response.data as String)
          : response.data;
    } on DioException catch (error) {
      final response = error.response;
      if (response?.data is String) {
        try {
          // Some adapters return Response<String>; do not assign a Map through
          // that response's runtime String setter when decoding an error.
          final data = jsonDecode(response!.data as String);
          throw error.copyWith(
            response: Response<dynamic>(
              data: data,
              requestOptions: response.requestOptions,
              statusCode: response.statusCode,
              statusMessage: response.statusMessage,
              headers: response.headers,
              extra: response.extra,
            ),
          );
        } on FormatException {
          /* Retain unknown error body. */
        }
      }
      rethrow;
    }
  }

  InventoryAlert _detail(Object? raw, String id) {
    final value = InventoryAlertDto.parse(raw);
    if (value.id != id) throw const FormatException('Wrong alert identity');
    return value;
  }

  Future<InventoryPage<InventoryAlert>> list(InventoryAlertQuery q) async {
    final value = InventoryAlertDto.page(
      await _request('GET', base, query: InventoryAlertRequests.list(q)),
      q.page,
    );
    if (value.content.any(
      (row) =>
          q.warehouseId != null && row.warehouseId != q.warehouseId ||
          q.ingredientId != null && row.ingredientId != q.ingredientId ||
          q.status != null && row.status != q.status,
    )) {
      throw const FormatException('Wrong alert query response');
    }
    return value;
  }

  Future<InventoryAlert> detail(String id) async =>
      _detail(await _request('GET', '$base/${Uri.encodeComponent(id)}'), id);
  Future<InventoryAlert> acknowledge(
    String id,
    AcknowledgeInventoryAlertInput input,
  ) async {
    final value = _detail(
      await _request(
        'POST',
        '$base/${Uri.encodeComponent(id)}/acknowledge',
        body: InventoryAlertRequests.acknowledge(input),
      ),
      id,
    );
    if (value.status != InventoryAlertStatus.acknowledged) {
      throw const FormatException('Wrong acknowledged status');
    }
    return value;
  }
}
