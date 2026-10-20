import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/inventory/data/dto/inventory_dto.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_inputs.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_queries.dart';
import 'package:pos_saas_app/features/inventory/domain/repositories/warehouse_repository.dart';
import 'package:pos_saas_app/features/inventory/domain/repositories/inventory_balance_repository.dart';

const inventoryPermissions = {
  'INVENTORY_VIEW',
  'WAREHOUSE_CREATE',
  'WAREHOUSE_UPDATE',
  'WAREHOUSE_DELETE',
  'INVENTORY_THRESHOLD_UPDATE',
};
const inventoryFeatures = {'INVENTORY_MANAGEMENT', 'LOW_STOCK_ALERT'};

Map<String, dynamic> warehouseJson({
  String id = 'w1',
  bool active = true,
  bool isDefault = true,
  int version = 0,
  String? name,
}) => {
  'id': id,
  'code': 'KHO-${id.toUpperCase()}',
  'name': name ?? 'Kho chính $id',
  'active': active,
  'isDefault': isDefault,
  'version': version,
  'createdAt': '2026-10-18T01:00:00Z',
  'updatedAt': '2026-10-18T01:00:00Z',
};
Warehouse warehouse({
  String id = 'w1',
  bool active = true,
  bool isDefault = true,
  int version = 0,
  String? name,
}) => InventoryDto.warehouse(
  warehouseJson(
    id: id,
    active: active,
    isDefault: isDefault,
    version: version,
    name: name,
  ),
);
Map<String, dynamic> balanceJson({
  String w = 'w1',
  String i = 'i1',
  bool configured = true,
  num quantity = 1,
  num min = 2,
  int version = 0,
  bool active = true,
  String? name,
}) => {
  'balanceId': configured ? '$w-$i' : null,
  'configured': configured,
  'warehouseId': w,
  'warehouseCode': 'KHO-${w.toUpperCase()}',
  'ingredientId': i,
  'ingredientSku': null,
  'ingredientName': name ?? 'Bột mì $i',
  'baseUnit': 'g',
  'ingredientActive': active,
  'quantity': configured ? quantity : 0,
  'minQuantity': configured ? min : 0,
  'lowStock': configured && min > 0 && quantity <= min,
  'version': configured ? version : null,
  'createdAt': configured ? '2026-10-18T01:00:00Z' : null,
  'updatedAt': configured ? '2026-10-18T01:00:00Z' : null,
};
InventoryBalance balance({
  String w = 'w1',
  String i = 'i1',
  bool configured = true,
  num quantity = 1,
  num min = 2,
  int version = 0,
  bool active = true,
  String? name,
}) => InventoryDto.balance(
  balanceJson(
    w: w,
    i: i,
    configured: configured,
    quantity: quantity,
    min: min,
    version: version,
    active: active,
    name: name,
  ),
);
Map<String, dynamic> pageJson(
  List<Object> rows, {
  int page = 0,
  int size = 20,
  int? total,
  int? pages,
}) => {
  'content': rows,
  'page': page,
  'size': size,
  'totalElements': total ?? rows.length,
  'totalPages': pages ?? (rows.isEmpty ? 0 : 1),
};
InventoryPage<T> inventoryPage<T>(
  List<T> rows, {
  int page = 0,
  int size = 20,
  int? total,
  int? pages,
}) => InventoryPage(
  content: rows,
  page: page,
  size: size,
  totalElements: total ?? rows.length,
  totalPages: pages ?? (rows.isEmpty ? 0 : 1),
);

class FakeWarehouses implements WarehouseRepository {
  List<Warehouse> rows = [warehouse(), warehouse(id: 'w2', isDefault: false)];
  final queries = <WarehouseQuery>[];
  int details = 0,
      creates = 0,
      updates = 0,
      statuses = 0,
      defaults = 0,
      deletes = 0;
  Future<Result<InventoryPage<Warehouse>>> Function(WarehouseQuery)? onList;
  Future<Result<Warehouse>> Function(String)? onDetail;
  Future<Result<Warehouse>> Function(CreateWarehouseInput)? onCreate;
  Future<Result<Warehouse>> Function(String, UpdateWarehouseInput)? onUpdate;
  Result<Warehouse>? statusResult;
  CreateWarehouseInput? lastCreate;
  UpdateWarehouseInput? lastUpdate;
  @override
  Future<Result<InventoryPage<Warehouse>>> list(WarehouseQuery query) async {
    queries.add(query);
    return onList != null
        ? onList!(query)
        : Success(inventoryPage(rows, page: query.page));
  }

  @override
  Future<Result<Warehouse>> detail(String id) async {
    details++;
    return onDetail != null
        ? onDetail!(id)
        : Success(rows.firstWhere((r) => r.id == id));
  }

  @override
  Future<Result<Warehouse>> create(CreateWarehouseInput input) async {
    creates++;
    lastCreate = input;
    return onCreate != null
        ? onCreate!(input)
        : Success(warehouse(id: 'new', isDefault: false));
  }

  @override
  Future<Result<Warehouse>> update(
    String id,
    UpdateWarehouseInput input,
  ) async {
    updates++;
    lastUpdate = input;
    return onUpdate != null
        ? onUpdate!(id, input)
        : Success(
            warehouse(
              id: id,
              isDefault: false,
              version: input.expectedVersion + 1,
              name: input.name,
            ),
          );
  }

  @override
  Future<Result<Warehouse>> setStatus(
    String id,
    SetWarehouseStatusInput input,
  ) async {
    statuses++;
    return statusResult ??
        Success(
          warehouse(
            id: id,
            isDefault: false,
            active: input.active,
            version: input.expectedVersion,
          ),
        );
  }

  @override
  Future<Result<Warehouse>> makeDefault(
    String id,
    WarehouseVersionInput input,
  ) async {
    defaults++;
    rows = [
      for (final r in rows)
        warehouse(
          id: r.id,
          isDefault: r.id == id,
          active: r.active,
          version: r.version + 1,
        ),
    ];
    return Success(rows.firstWhere((r) => r.id == id));
  }

  @override
  Future<Result<void>> delete(String id, WarehouseVersionInput input) async {
    deletes++;
    rows.removeWhere((r) => r.id == id);
    return const Success(null);
  }
}

class FakeBalances implements InventoryBalanceRepository {
  List<InventoryBalance> rows = [
    balance(),
    balance(i: 'i2', configured: false),
    balance(i: 'i3', active: false, quantity: 20, min: 0),
  ];
  final queries = <({String w, InventoryBalanceQuery q})>[];
  int lowCalls = 0, details = 0, saves = 0;
  UpdateInventoryThresholdInput? lastInput;
  Future<Result<InventoryPage<InventoryBalance>>> Function(
    String,
    InventoryBalanceQuery,
  )?
  onList;
  Future<Result<InventoryBalance>> Function(String, String)? onDetail;
  Future<Result<InventoryBalance>> Function(
    String,
    String,
    UpdateInventoryThresholdInput,
  )?
  onSave;
  @override
  Future<Result<InventoryPage<InventoryBalance>>> list(
    String w,
    InventoryBalanceQuery q,
  ) async {
    queries.add((w: w, q: q));
    return onList != null
        ? onList!(w, q)
        : Success(
            inventoryPage(
              rows.where((r) => r.warehouseId == w).toList(),
              page: q.page,
            ),
          );
  }

  @override
  Future<Result<InventoryBalance>> detail(String w, String i) async {
    details++;
    return onDetail != null
        ? onDetail!(w, i)
        : Success(
            rows.firstWhere((r) => r.warehouseId == w && r.ingredientId == i),
          );
  }

  @override
  Future<Result<InventoryBalance>> threshold(
    String w,
    String i,
    UpdateInventoryThresholdInput input,
  ) async {
    saves++;
    lastInput = input;
    if (onSave != null) return onSave!(w, i, input);
    final old = rows.firstWhere(
      (r) => r.warehouseId == w && r.ingredientId == i,
    );
    final updated = balance(
      w: w,
      i: i,
      configured: old.configured || input.minQuantity.scaled > 0,
      quantity: old.quantity.toNumber(),
      min: input.minQuantity.toNumber(),
      version: old.version ?? 0,
    );
    rows = [for (final r in rows) r.key == updated.key ? updated : r];
    return Success(updated);
  }

  @override
  Future<Result<InventoryPage<InventoryBalance>>> lowStock(
    LowStockQuery q,
  ) async {
    lowCalls++;
    return Success(
      inventoryPage(
        rows
            .where(
              (r) =>
                  r.lowStock &&
                  (q.warehouseId == null || r.warehouseId == q.warehouseId),
            )
            .toList(),
      ),
    );
  }
}
