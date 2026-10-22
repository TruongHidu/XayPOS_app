import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_alert.dart';
import '../../domain/entities/inventory_alert_query.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/repositories/inventory_alert_repository.dart';
import '../data_sources/inventory_alert_remote_data_source.dart';
import 'inventory_result.dart';

class InventoryAlertRepositoryImpl implements InventoryAlertRepository {
  const InventoryAlertRepositoryImpl(this.remote);
  final InventoryAlertRemoteDataSource remote;
  @override
  Future<Result<InventoryPage<InventoryAlert>>> list(
    InventoryAlertQuery query,
  ) => inventoryResult(() => remote.list(query));
  @override
  Future<Result<InventoryAlert>> detail(String id) =>
      inventoryResult(() => remote.detail(id));
  @override
  Future<Result<InventoryAlert>> acknowledge(
    String id,
    AcknowledgeInventoryAlertInput input,
  ) => inventoryResult(() => remote.acknowledge(id, input));
}
