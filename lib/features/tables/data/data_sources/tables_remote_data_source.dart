import 'package:dio/dio.dart';
import '../../domain/entities/table_entities.dart';
import '../../domain/entities/table_inputs.dart';
import '../../domain/entities/table_query.dart';
import '../dto/table_dto.dart';
import '../dto/table_requests.dart';

class TablesRemoteDataSource {
  TablesRemoteDataSource(this._dio);
  final Dio _dio;
  Future<TablePage<TableArea>> tableAreaList(TableQuery query) async {
    final response = await _dio.get<dynamic>(
      '/api/v1/table-areas',
      queryParameters: _query(query, TableQueryKind.areas),
    );
    return TableDto.page(response.data, TableDto.tableArea);
  }

  Future<TableArea> tableAreaDetail(String id) async {
    final key = Uri.encodeComponent(id);
    final response = await _dio.get<dynamic>('/api/v1/table-areas/$key');
    return TableDto.tableArea(response.data);
  }

  Future<TableArea> tableAreaCreate(CreateTableAreaInput input) async {
    final response = await _dio.post<dynamic>(
      '/api/v1/table-areas',
      data: TableRequests.createTableArea(input),
    );
    return TableDto.tableArea(response.data);
  }

  Future<TableArea> tableAreaUpdate(
    String id,
    UpdateTableAreaInput input,
  ) async {
    final key = Uri.encodeComponent(id);
    final response = await _dio.patch<dynamic>(
      '/api/v1/table-areas/$key',
      data: TableRequests.updateTableArea(input),
    );
    return TableDto.tableArea(response.data);
  }

  Future<TableArea> tableAreaSetStatus(
    String id,
    bool active,
    int version,
  ) async {
    final key = Uri.encodeComponent(id);
    final response = await _dio.patch<dynamic>(
      '/api/v1/table-areas/$key/status',
      data: {'active': active, 'expectedVersion': version},
    );
    return TableDto.tableArea(response.data);
  }

  Future<void> tableAreaDelete(String id, int version) async {
    final key = Uri.encodeComponent(id);
    await _dio.delete<dynamic>(
      '/api/v1/table-areas/$key',
      queryParameters: {'expectedVersion': version},
    );
  }

  Future<TablePage<RestaurantTable>> restaurantTableList(
    TableQuery query,
  ) async {
    final response = await _dio.get<dynamic>(
      '/api/v1/tables',
      queryParameters: _query(query, TableQueryKind.tables),
    );
    return TableDto.page(response.data, TableDto.restaurantTable);
  }

  Future<RestaurantTable> restaurantTableDetail(String id) async {
    final key = Uri.encodeComponent(id);
    final response = await _dio.get<dynamic>('/api/v1/tables/$key');
    return TableDto.restaurantTable(response.data);
  }

  Future<RestaurantTable> restaurantTableCreate(
    CreateRestaurantTableInput input,
  ) async {
    final response = await _dio.post<dynamic>(
      '/api/v1/tables',
      data: TableRequests.createRestaurantTable(input),
    );
    return TableDto.restaurantTable(response.data);
  }

  Future<RestaurantTable> restaurantTableUpdate(
    String id,
    UpdateRestaurantTableInput input,
  ) async {
    final key = Uri.encodeComponent(id);
    final response = await _dio.patch<dynamic>(
      '/api/v1/tables/$key',
      data: TableRequests.updateRestaurantTable(input),
    );
    return TableDto.restaurantTable(response.data);
  }

  Future<RestaurantTable> restaurantTableSetStatus(
    String id,
    TableStatus status,
    int version,
  ) async {
    final key = Uri.encodeComponent(id);
    final response = await _dio.patch<dynamic>(
      '/api/v1/tables/$key/status',
      data: {'status': status.code, 'expectedVersion': version},
    );
    return TableDto.restaurantTable(response.data);
  }

  Future<RestaurantTable> restaurantTableAssignArea(
    String id,
    String? areaId,
    int version,
  ) async {
    final key = Uri.encodeComponent(id);
    final response = await _dio.patch<dynamic>(
      '/api/v1/tables/$key/area',
      data: TableRequests.assignment(areaId, version),
    );
    return TableDto.restaurantTable(response.data);
  }

  Future<void> restaurantTableDelete(String id, int version) async {
    final key = Uri.encodeComponent(id);
    await _dio.delete<dynamic>(
      '/api/v1/tables/$key',
      queryParameters: {'expectedVersion': version},
    );
  }

  Future<TableQrPayload> restaurantTableQr(String id) async {
    final key = Uri.encodeComponent(id);
    final response = await _dio.get<dynamic>('/api/v1/tables/$key/qr');
    return TableDto.tableQrPayload(response.data);
  }

  Future<TableQrPayload> restaurantTableRotateQr(String id, int version) async {
    final key = Uri.encodeComponent(id);
    final response = await _dio.post<dynamic>(
      '/api/v1/tables/$key/qr/rotate',
      data: {'expectedVersion': version},
    );
    return TableDto.tableQrPayload(response.data);
  }

  Future<TablePage<TableSession>> tableSessionList(TableQuery query) async {
    final response = await _dio.get<dynamic>(
      '/api/v1/table-sessions',
      queryParameters: _query(query, TableQueryKind.sessions),
    );
    return TableDto.page(response.data, TableDto.tableSession);
  }

  Future<TableSession> tableSessionDetail(String id) async {
    final key = Uri.encodeComponent(id);
    final response = await _dio.get<dynamic>('/api/v1/table-sessions/$key');
    return TableDto.tableSession(response.data);
  }

  Future<TableSession?> tableSessionCurrent(String id) async {
    final key = Uri.encodeComponent(id);
    final response = await _dio.get<dynamic>(
      '/api/v1/tables/$key/current-session',
    );
    if (response.statusCode == 204) return null;
    return TableDto.tableSession(response.data);
  }

  Future<TableSession> tableSessionOpen(
    String id,
    OpenTableSessionInput input,
  ) async {
    final key = Uri.encodeComponent(id);
    final response = await _dio.post<dynamic>(
      '/api/v1/tables/$key/sessions',
      data: TableRequests.openTableSession(input),
    );
    return TableDto.tableSession(response.data);
  }

  Future<TableSession> tableSessionUpdate(
    String id,
    UpdateTableSessionInput input,
  ) async {
    final key = Uri.encodeComponent(id);
    final response = await _dio.patch<dynamic>(
      '/api/v1/table-sessions/$key',
      data: TableRequests.updateTableSession(input),
    );
    return TableDto.tableSession(response.data);
  }

  Future<TableSession> tableSessionCancel(
    String id,
    String reason,
    int version,
  ) async {
    final key = Uri.encodeComponent(id);
    final response = await _dio.post<dynamic>(
      '/api/v1/table-sessions/$key/cancel',
      data: {'reason': reason, 'expectedVersion': version},
    );
    return TableDto.tableSession(response.data);
  }
}

Map<String, dynamic> _query(TableQuery q, TableQueryKind kind) {
  if (!q.valid(kind)) throw const FormatException('Invalid query');
  return {
    'page': q.page,
    'size': q.size,
    'sortBy': q.sortBy,
    'direction': q.direction,
    if (kind != TableQueryKind.sessions && q.q.trim().isNotEmpty)
      'q': q.q.trim(),
    if (kind == TableQueryKind.areas && q.active != null) 'active': q.active,
    if (kind == TableQueryKind.tables) ...{
      if (q.areaId != null) 'areaId': q.areaId,
      if (q.status != null) 'status': q.status!.code,
      if (q.occupied != null) 'occupied': q.occupied,
    },
    if (kind == TableQueryKind.sessions) ...{
      if (q.tableId != null) 'tableId': q.tableId,
      if (q.sessionStatus != null) 'status': q.sessionStatus!.code,
      if (q.openedFrom != null)
        'openedFrom': q.openedFrom!.toUtc().toIso8601String(),
      if (q.openedTo != null) 'openedTo': q.openedTo!.toUtc().toIso8601String(),
    },
  };
}
