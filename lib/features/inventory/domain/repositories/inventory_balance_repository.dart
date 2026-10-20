import '../../../../core/result/result.dart';
import '../entities/inventory_entities.dart';
import '../entities/inventory_inputs.dart';
import '../entities/inventory_queries.dart';

abstract interface class InventoryBalanceRepository {
  Future<Result<InventoryPage<InventoryBalance>>> list(
    String warehouseId,
    InventoryBalanceQuery query,
  );
  Future<Result<InventoryBalance>> detail(
    String warehouseId,
    String ingredientId,
  );
  Future<Result<InventoryBalance>> threshold(
    String warehouseId,
    String ingredientId,
    UpdateInventoryThresholdInput input,
  );
  Future<Result<InventoryPage<InventoryBalance>>> lowStock(LowStockQuery query);
}
