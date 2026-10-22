import '../../../../core/result/result.dart';
import '../entities/inventory_alert.dart';
import '../entities/inventory_alert_query.dart';
import '../entities/inventory_entities.dart';

abstract interface class InventoryAlertRepository {
  Future<Result<InventoryPage<InventoryAlert>>> list(InventoryAlertQuery query);
  Future<Result<InventoryAlert>> detail(String id);
  Future<Result<InventoryAlert>> acknowledge(
    String id,
    AcknowledgeInventoryAlertInput input,
  );
}
