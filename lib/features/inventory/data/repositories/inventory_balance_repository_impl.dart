import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/inventory_inputs.dart';
import '../../domain/entities/inventory_queries.dart';
import '../../domain/repositories/inventory_balance_repository.dart';
import '../data_sources/inventory_remote_data_source.dart';
import 'inventory_result.dart';

class InventoryBalanceRepositoryImpl implements InventoryBalanceRepository {
  const InventoryBalanceRepositoryImpl(this.remote);
  final InventoryRemoteDataSource remote;
  @override
  Future<Result<InventoryPage<InventoryBalance>>> list(
    String id,
    InventoryBalanceQuery q,
  ) => inventoryResult(() => remote.balances(id, q));
  @override
  Future<Result<InventoryBalance>> detail(String w, String i) =>
      inventoryResult(() => remote.balance(w, i));
  @override
  Future<Result<InventoryBalance>> threshold(
    String w,
    String i,
    UpdateInventoryThresholdInput input,
  ) => inventoryResult(() => remote.threshold(w, i, input));
  @override
  Future<Result<InventoryPage<InventoryBalance>>> lowStock(LowStockQuery q) =>
      inventoryResult(() => remote.lowStock(q));
}
