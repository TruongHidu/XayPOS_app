import 'package:dio/dio.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/inventory_inputs.dart';
import '../../domain/entities/inventory_queries.dart';
import '../dto/inventory_dto.dart';
import '../dto/inventory_requests.dart';

class InventoryRemoteDataSource {
  const InventoryRemoteDataSource(this.dio);
  final Dio dio;
  static const path = '/api/v1/inventory';
  String warehousePath(String id) => '/warehouses/${Uri.encodeComponent(id)}';
  String balancePath(String warehouseId, String ingredientId) =>
      '${warehousePath(warehouseId)}/balances/${Uri.encodeComponent(ingredientId)}';
  Future<Object?> request(
    String method,
    String suffix, {
    Map<String, dynamic>? query,
    Object? body,
    int status = 200,
  }) async {
    final response = await dio.request<Object?>(
      '$path$suffix',
      data: body,
      queryParameters: query,
      options: Options(
        method: method,
        headers: {'Accept': 'application/json'},
        contentType: body == null ? null : Headers.jsonContentType,
      ),
    );
    if (response.statusCode != status) {
      throw const FormatException('Invalid inventory response status');
    }
    return status == 204 ? null : response.data;
  }

  Future<InventoryPage<Warehouse>> warehouses(WarehouseQuery q) async =>
      InventoryDto.page(
        await request(
          'GET',
          '/warehouses',
          query: InventoryRequests.warehouseQuery(q),
        ),
        InventoryDto.warehouse,
        q.page,
      );
  Future<Warehouse> warehouse(String id) async =>
      _warehouse(await request('GET', warehousePath(id)), id);
  Future<Warehouse> create(CreateWarehouseInput input) async =>
      InventoryDto.warehouse(
        await request(
          'POST',
          '/warehouses',
          body: InventoryRequests.create(input),
          status: 201,
        ),
      );
  Future<Warehouse> update(String id, UpdateWarehouseInput input) async =>
      _warehouse(
        await request(
          'PATCH',
          warehousePath(id),
          body: InventoryRequests.update(input),
        ),
        id,
        input.expectedVersion,
      );
  Future<Warehouse> status(String id, SetWarehouseStatusInput input) async {
    final value = _warehouse(
      await request(
        'PATCH',
        '${warehousePath(id)}/status',
        body: {
          'active': input.active,
          'expectedVersion': input.expectedVersion,
        },
      ),
      id,
      input.expectedVersion,
    );
    if (value.active != input.active) {
      throw const FormatException('Wrong warehouse status');
    }
    return value;
  }

  Future<Warehouse> makeDefault(String id, WarehouseVersionInput input) async {
    final value = _warehouse(
      await request(
        'POST',
        '${warehousePath(id)}/make-default',
        body: {'expectedVersion': input.expectedVersion},
      ),
      id,
      input.expectedVersion,
    );
    if (!value.isDefault || !value.active) {
      throw const FormatException('Invalid default warehouse');
    }
    return value;
  }

  Future<void> delete(String id, WarehouseVersionInput input) async {
    await request(
      'DELETE',
      warehousePath(id),
      query: {'expectedVersion': input.expectedVersion},
      status: 204,
    );
  }

  Warehouse _warehouse(Object? json, String id, [int? version]) {
    final value = InventoryDto.warehouse(json);
    if (value.id != id || version != null && value.version < version) {
      throw const FormatException('Wrong warehouse response');
    }
    return value;
  }

  Future<InventoryPage<InventoryBalance>> balances(
    String id,
    InventoryBalanceQuery q,
  ) async {
    final page = InventoryDto.page(
      await request(
        'GET',
        '${warehousePath(id)}/balances',
        query: InventoryRequests.balanceQuery(q),
      ),
      InventoryDto.balance,
      q.page,
    );
    if (page.content.any((r) => r.warehouseId != id)) {
      throw const FormatException('Wrong balance warehouse');
    }
    return page;
  }

  Future<InventoryBalance> balance(String w, String i) async =>
      _balance(await request('GET', balancePath(w, i)), w, i);
  Future<InventoryBalance> threshold(
    String w,
    String i,
    UpdateInventoryThresholdInput input,
  ) async {
    final value = _balance(
      await request(
        'PATCH',
        '${balancePath(w, i)}/threshold',
        body: {
          'expectedVersion': input.expectedVersion,
          'minQuantity': input.minQuantity.toNumber(),
        },
      ),
      w,
      i,
    );
    if (value.minQuantity != input.minQuantity ||
        input.expectedVersion != null &&
            (value.version == null ||
                value.version! < input.expectedVersion!)) {
      throw const FormatException('Wrong threshold response');
    }
    return value;
  }

  InventoryBalance _balance(Object? json, String w, String i) {
    final value = InventoryDto.balance(json);
    if (value.warehouseId != w || value.ingredientId != i) {
      throw const FormatException('Wrong balance identity');
    }
    return value;
  }

  Future<InventoryPage<InventoryBalance>> lowStock(LowStockQuery q) async {
    final page = InventoryDto.page(
      await request(
        'GET',
        '/low-stock',
        query: {
          ...InventoryRequests.balanceQuery(q.filters),
          if (q.warehouseId != null) 'warehouseId': q.warehouseId,
        },
      ),
      InventoryDto.balance,
      q.filters.page,
    );
    if (page.content.any(
      (r) =>
          !r.lowStock ||
          q.warehouseId != null && r.warehouseId != q.warehouseId,
    )) {
      throw const FormatException('Wrong low stock response');
    }
    return page;
  }
}
