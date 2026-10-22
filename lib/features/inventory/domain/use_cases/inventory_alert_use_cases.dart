import '../../../../core/result/result.dart';
import '../entities/inventory_alert.dart';
import '../entities/inventory_alert_query.dart';
import '../entities/inventory_entities.dart';
import '../repositories/inventory_alert_repository.dart';

class GetInventoryAlerts {
  const GetInventoryAlerts(this.repository);
  final InventoryAlertRepository repository;
  Future<Result<InventoryPage<InventoryAlert>>> call(
    InventoryAlertQuery query,
  ) => repository.list(query);
}

class GetInventoryAlert {
  const GetInventoryAlert(this.repository);
  final InventoryAlertRepository repository;
  Future<Result<InventoryAlert>> call(String id) => repository.detail(id);
}

class AcknowledgeInventoryAlert {
  const AcknowledgeInventoryAlert(this.repository);
  final InventoryAlertRepository repository;
  Future<Result<InventoryAlert>> call(
    String id,
    AcknowledgeInventoryAlertInput input,
  ) => repository.acknowledge(id, input);
}
