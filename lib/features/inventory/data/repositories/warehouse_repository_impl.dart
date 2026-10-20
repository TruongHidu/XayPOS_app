import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/inventory_inputs.dart';
import '../../domain/entities/inventory_queries.dart';
import '../../domain/repositories/warehouse_repository.dart';
import '../data_sources/inventory_remote_data_source.dart';
import 'inventory_result.dart';

class WarehouseRepositoryImpl implements WarehouseRepository {
  const WarehouseRepositoryImpl(this.remote);
  final InventoryRemoteDataSource remote;
  @override
  Future<Result<InventoryPage<Warehouse>>> list(WarehouseQuery q) =>
      inventoryResult(() => remote.warehouses(q));
  @override
  Future<Result<Warehouse>> detail(String id) =>
      inventoryResult(() => remote.warehouse(id));
  @override
  Future<Result<Warehouse>> create(CreateWarehouseInput input) =>
      inventoryResult(() => remote.create(input));
  @override
  Future<Result<Warehouse>> update(String id, UpdateWarehouseInput input) =>
      inventoryResult(() => remote.update(id, input));
  @override
  Future<Result<Warehouse>> setStatus(
    String id,
    SetWarehouseStatusInput input,
  ) => inventoryResult(() => remote.status(id, input));
  @override
  Future<Result<Warehouse>> makeDefault(
    String id,
    WarehouseVersionInput input,
  ) => inventoryResult(() => remote.makeDefault(id, input));
  @override
  Future<Result<void>> delete(String id, WarehouseVersionInput input) =>
      inventoryResult(() => remote.delete(id, input));
}
