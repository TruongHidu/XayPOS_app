import '../../../../core/result/result.dart';
import '../entities/inventory_entities.dart';
import '../entities/inventory_inputs.dart';
import '../entities/inventory_queries.dart';

abstract interface class WarehouseRepository {
  Future<Result<InventoryPage<Warehouse>>> list(WarehouseQuery query);
  Future<Result<Warehouse>> detail(String id);
  Future<Result<Warehouse>> create(CreateWarehouseInput input);
  Future<Result<Warehouse>> update(String id, UpdateWarehouseInput input);
  Future<Result<Warehouse>> setStatus(String id, SetWarehouseStatusInput input);
  Future<Result<Warehouse>> makeDefault(String id, WarehouseVersionInput input);
  Future<Result<void>> delete(String id, WarehouseVersionInput input);
}
