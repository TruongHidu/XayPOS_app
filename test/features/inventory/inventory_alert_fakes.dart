import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/inventory/data/dto/inventory_alert_dto.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_alert.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_alert_query.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/inventory/domain/repositories/inventory_alert_repository.dart';
import 'inventory_fakes.dart';

const alertPermissions = {'INVENTORY_VIEW', 'INVENTORY_ALERT_ACKNOWLEDGE'};
const alertFeatures = {'INVENTORY_MANAGEMENT', 'LOW_STOCK_ALERT'};

Map<String, dynamic> inventoryAlertJson({
  String id = 'a1',
  String status = 'OPEN',
  int version = 0,
  String reason = 'STOCK_RECOVERED',
  bool comparable = true,
  String? name,
  num current = 150,
  num reserved = 50,
  num minimum = 200,
}) => {
  'id': id,
  'warehouseId': 'w1',
  'warehouseCode': 'KHO-CHINH',
  'warehouseName': 'Kho chính lịch sử',
  'ingredientId': 'i1',
  'ingredientSku': 'NL-THIT-BO',
  'ingredientName': name ?? 'Thịt bò lịch sử',
  'unit': 'g',
  'status': status,
  'quantityAtTrigger': 150,
  'thresholdQuantity': 200,
  'currentQuantity': comparable ? current : null,
  'reservedQuantity': comparable ? reserved : null,
  'availableQuantity': comparable ? current - reserved : null,
  'currentMinQuantity': comparable ? minimum : null,
  'triggeredAt': '2026-10-21T08:00:00Z',
  'acknowledgedBy': status == 'ACKNOWLEDGED' ? 'user-ack' : null,
  'acknowledgedAt': status == 'ACKNOWLEDGED' ? '2026-10-21T08:15:00Z' : null,
  'resolvedAt': status == 'RESOLVED' ? '2026-10-21T09:00:00Z' : null,
  'resolutionReason': status == 'RESOLVED' ? reason : null,
  'version': version,
  'createdAt': '2026-10-21T08:00:00Z',
  'updatedAt': '2026-10-21T08:15:00Z',
};

InventoryAlert inventoryAlert({
  String id = 'a1',
  String status = 'OPEN',
  int version = 0,
  String reason = 'STOCK_RECOVERED',
  bool comparable = true,
  String? name,
}) => InventoryAlertDto.parse(
  inventoryAlertJson(
    id: id,
    status: status,
    version: version,
    reason: reason,
    comparable: comparable,
    name: name,
  ),
);

class FakeInventoryAlerts implements InventoryAlertRepository {
  List<InventoryAlert> rows = [inventoryAlert()];
  final queries = <InventoryAlertQuery>[];
  final detailIds = <String>[];
  final acknowledgements =
      <({String id, AcknowledgeInventoryAlertInput input})>[];
  Future<Result<InventoryPage<InventoryAlert>>> Function(InventoryAlertQuery)?
  onList;
  Future<Result<InventoryAlert>> Function(String)? onDetail;
  Future<Result<InventoryAlert>> Function(
    String,
    AcknowledgeInventoryAlertInput,
  )?
  onAcknowledge;
  @override
  Future<Result<InventoryPage<InventoryAlert>>> list(
    InventoryAlertQuery query,
  ) async {
    queries.add(query);
    return onList != null
        ? onList!(query)
        : Success(
            inventoryPage(
              rows
                  .where(
                    (r) => query.status == null || r.status == query.status,
                  )
                  .toList(),
              page: query.page,
            ),
          );
  }

  @override
  Future<Result<InventoryAlert>> detail(String id) async {
    detailIds.add(id);
    return onDetail != null
        ? onDetail!(id)
        : Success(rows.firstWhere((r) => r.id == id));
  }

  @override
  Future<Result<InventoryAlert>> acknowledge(
    String id,
    AcknowledgeInventoryAlertInput input,
  ) async {
    acknowledgements.add((id: id, input: input));
    if (onAcknowledge != null) return onAcknowledge!(id, input);
    final value = inventoryAlert(
      id: id,
      status: 'ACKNOWLEDGED',
      version: input.expectedVersion + 1,
    );
    rows = [for (final row in rows) row.id == id ? value : row];
    return Success(value);
  }
}
