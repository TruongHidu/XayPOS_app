import 'dart:convert';
import 'package:dio/dio.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/stock_audit.dart';
import '../../domain/entities/stock_audit_inputs.dart';
import '../../domain/entities/stock_audit_queries.dart';
import '../dto/stock_audit_dto.dart';
import '../dto/stock_audit_requests.dart';
import '../dto/stock_json.dart';

class StockAuditRemoteDataSource {
  const StockAuditRemoteDataSource(this.dio);
  final Dio dio;
  static const base = '/api/v1/inventory/audits';
  String _path(String id) {
    if (id.trim().isEmpty) {
      throw const FormatException('Missing audit identity');
    }
    return '/${Uri.encodeComponent(id)}';
  }

  Future<Object?> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? body,
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
        throw const FormatException('Invalid audit response status');
      }
      return response.data is String
          ? decodeStockJson(response.data as String)
          : response.data;
    } on DioException catch (error) {
      final response = error.response;
      if (response?.data is String) {
        try {
          final decoded = jsonDecode(response!.data as String);
          // A plain transformer can return Response<String>; never assign a
          // decoded map into its covariant data setter.
          throw error.copyWith(
            response: Response<dynamic>(
              data: decoded,
              requestOptions: response.requestOptions,
              statusCode: response.statusCode,
              statusMessage: response.statusMessage,
              headers: response.headers,
              extra: response.extra,
              isRedirect: response.isRedirect,
              redirects: response.redirects,
            ),
          );
        } on FormatException {
          /* Preserve unrecognized server errors. */
        }
      }
      rethrow;
    }
  }

  StockAuditDetail _detail(
    Object? raw,
    String id, {
    Set<StockAuditStatus>? statuses,
  }) {
    final value = StockAuditDto.detail(raw);
    if (value.id != id ||
        statuses != null && !statuses.contains(value.status)) {
      throw const FormatException('Wrong audit identity or desired state');
    }
    return value;
  }

  Future<InventoryPage<StockAuditSummary>> list(StockAuditQuery query) async {
    final value = StockAuditDto.page(
      await _request('GET', '', query: StockAuditRequests.audits(query)),
      StockAuditDto.summary,
      query.page,
      query.size,
    );
    if (value.content.map((r) => r.id).toSet().length != value.content.length ||
        value.content.any(
          (row) =>
              query.warehouseId != null &&
                  row.warehouseId != query.warehouseId ||
              query.status != null && row.status != query.status ||
              query.dates?.from != null &&
                  row.createdAt.isBefore(query.dates!.from!) ||
              query.dates?.to != null &&
                  !row.createdAt.isBefore(query.dates!.to!),
        )) {
      throw const FormatException('Wrong audit list filters');
    }
    return value;
  }

  Future<StockAuditDetail> get(String id) async =>
      _detail(await _request('GET', _path(id)), id);
  Future<InventoryPage<StockAuditItem>> items(
    String id,
    StockAuditItemQuery query,
  ) async {
    final value = StockAuditDto.page(
      await _request(
        'GET',
        '${_path(id)}/items',
        query: StockAuditRequests.items(query),
      ),
      StockAuditDto.item,
      query.page,
      query.size,
    );
    if (value.content.map((r) => r.id).toSet().length != value.content.length ||
        value.content.map((r) => r.ingredientId).toSet().length !=
            value.content.length ||
        value.content.any(
          (row) =>
              query.counted != null &&
                  (row.countedQuantity != null) != query.counted ||
              query.differenceOnly &&
                  (row.differenceQuantity == null ||
                      row.differenceQuantity!.isZero),
        )) {
      throw const FormatException('Wrong audit item filters');
    }
    return value;
  }

  Future<StockAuditDetail> create(
    String key,
    CreateStockAuditInput input,
  ) async {
    final value = StockAuditDto.detail(
      await _request(
        'POST',
        '',
        key: key.trim(),
        body: StockAuditRequests.create(input),
        status: 201,
      ),
    );
    if (value.warehouseId != input.warehouseId) {
      throw const FormatException('Wrong audit creation warehouse');
    }
    // A replay can return the audit after another desired-state operation.
    return value;
  }

  Future<StockAuditDetail> updateNote(
    String id,
    UpdateStockAuditNoteInput input,
  ) async => _detail(
    await _request('PATCH', _path(id), body: StockAuditRequests.note(input)),
    id,
    statuses: const {StockAuditStatus.draft, StockAuditStatus.counting},
  );
  Future<StockAuditDetail> start(
    String id,
    StockAuditTransitionInput input,
  ) async => _detail(
    await _request(
      'POST',
      '${_path(id)}/start',
      body: StockAuditRequests.transition(input),
    ),
    id,
    statuses: const {StockAuditStatus.counting},
  );
  Future<StockAuditDetail> updateCounts(
    String id,
    StockAuditCountsInput input,
  ) async => _detail(
    await _request(
      'PATCH',
      '${_path(id)}/items',
      body: StockAuditRequests.counts(input),
    ),
    id,
    statuses: const {StockAuditStatus.counting},
  );
  Future<StockAuditDetail> confirm(
    String id,
    StockAuditTransitionInput input,
  ) async => _detail(
    await _request(
      'POST',
      '${_path(id)}/confirm',
      body: StockAuditRequests.transition(input),
    ),
    id,
    statuses: const {StockAuditStatus.confirmed},
  );
  Future<StockAuditDetail> cancel(
    String id,
    CancelStockAuditInput input,
  ) async => _detail(
    await _request(
      'POST',
      '${_path(id)}/cancel',
      body: StockAuditRequests.cancel(input),
    ),
    id,
    statuses: const {StockAuditStatus.cancelled},
  );
}
