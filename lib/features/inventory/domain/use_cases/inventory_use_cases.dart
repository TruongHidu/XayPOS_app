import '../../../../core/result/result.dart';
import '../entities/inventory_entities.dart';
import '../entities/inventory_inputs.dart';
import '../entities/inventory_queries.dart';
import '../repositories/warehouse_repository.dart';
import '../repositories/inventory_balance_repository.dart';

class GetWarehouses {
  const GetWarehouses(this.repository);
  final WarehouseRepository repository;
  Future<Result<InventoryPage<Warehouse>>> call(WarehouseQuery query) =>
      repository.list(query);
}

class GetWarehouse {
  const GetWarehouse(this.repository);
  final WarehouseRepository repository;
  Future<Result<Warehouse>> call(String id) => repository.detail(id);
}

class CreateWarehouse {
  const CreateWarehouse(this.repository);
  final WarehouseRepository repository;
  Future<Result<Warehouse>> call(CreateWarehouseInput input) =>
      repository.create(input);
}

class UpdateWarehouse {
  const UpdateWarehouse(this.repository);
  final WarehouseRepository repository;
  Future<Result<Warehouse>> call(String id, UpdateWarehouseInput input) =>
      repository.update(id, input);
}

class SetWarehouseStatus {
  const SetWarehouseStatus(this.repository);
  final WarehouseRepository repository;
  Future<Result<Warehouse>> call(String id, SetWarehouseStatusInput input) =>
      repository.setStatus(id, input);
}

class MakeDefaultWarehouse {
  const MakeDefaultWarehouse(this.repository);
  final WarehouseRepository repository;
  Future<Result<Warehouse>> call(String id, WarehouseVersionInput input) =>
      repository.makeDefault(id, input);
}

class DeleteWarehouse {
  const DeleteWarehouse(this.repository);
  final WarehouseRepository repository;
  Future<Result<void>> call(String id, WarehouseVersionInput input) =>
      repository.delete(id, input);
}

class GetInventoryBalances {
  const GetInventoryBalances(this.repository);
  final InventoryBalanceRepository repository;
  Future<Result<InventoryPage<InventoryBalance>>> call(
    String id,
    InventoryBalanceQuery query,
  ) => repository.list(id, query);
}

class GetInventoryBalance {
  const GetInventoryBalance(this.repository);
  final InventoryBalanceRepository repository;
  Future<Result<InventoryBalance>> call(
    String warehouseId,
    String ingredientId,
  ) => repository.detail(warehouseId, ingredientId);
}

class UpdateInventoryThreshold {
  const UpdateInventoryThreshold(this.repository);
  final InventoryBalanceRepository repository;
  Future<Result<InventoryBalance>> call(
    String warehouseId,
    String ingredientId,
    UpdateInventoryThresholdInput input,
  ) => repository.threshold(warehouseId, ingredientId, input);
}

class GetLowStockBalances {
  const GetLowStockBalances(this.repository);
  final InventoryBalanceRepository repository;
  Future<Result<InventoryPage<InventoryBalance>>> call(LowStockQuery query) =>
      repository.lowStock(query);
}
