import '../../domain/entities/inventory_queries.dart';
import '../../domain/entities/inventory_inputs.dart';

abstract final class InventoryRequests {
  static Map<String, dynamic> warehouseQuery(WarehouseQuery q) => {
    if (q.q.trim().isNotEmpty) 'q': q.q.trim(),
    if (q.active != null) 'active': q.active,
    'page': q.page,
    'size': q.size,
    'sortBy': q.sortBy,
    'direction': q.direction,
  };
  static Map<String, dynamic> balanceQuery(InventoryBalanceQuery q) => {
    if (q.q.trim().isNotEmpty) 'q': q.q.trim(),
    if (q.ingredientActive != null) 'ingredientActive': q.ingredientActive,
    'page': q.page,
    'size': q.size,
    'sortBy': q.sortBy,
    'direction': q.direction,
  };
  static Map<String, dynamic> create(CreateWarehouseInput i) => {
    'code': i.normalizedCode,
    'name': i.name.trim(),
  };
  static Map<String, dynamic> update(UpdateWarehouseInput i) => {
    'expectedVersion': i.expectedVersion,
    if (i.code != null) 'code': i.code!.trim().toUpperCase(),
    if (i.name != null) 'name': i.name!.trim(),
  };
}
