import 'inventory_quantity.dart';

enum InventoryAlertStatus {
  open('OPEN', 'Chưa xem'),
  acknowledged('ACKNOWLEDGED', 'Đã xem'),
  resolved('RESOLVED', 'Đã kết thúc');

  const InventoryAlertStatus(this.code, this.label);
  final String code, label;
}

enum InventoryAlertResolution {
  stockRecovered('STOCK_RECOVERED', 'Tồn đã vượt ngưỡng'),
  thresholdDisabled('THRESHOLD_DISABLED', 'Đã tắt ngưỡng cảnh báo'),
  warehouseInactive('WAREHOUSE_INACTIVE', 'Kho ngừng hoạt động'),
  warehouseDeleted('WAREHOUSE_DELETED', 'Kho đã xóa'),
  ingredientUntracked('INGREDIENT_UNTRACKED', 'Nguyên liệu ngừng theo dõi tồn'),
  ingredientDeleted('INGREDIENT_DELETED', 'Nguyên liệu đã xóa'),
  ingredientUnitChanged(
    'INGREDIENT_UNIT_CHANGED',
    'Đơn vị nguyên liệu đã thay đổi',
  );

  const InventoryAlertResolution(this.code, this.label);
  final String code, label;
}

/// An alert episode. Snapshot metadata and trigger quantities are historical;
/// current quantities are a separate, nullable comparison from the same read.
class InventoryAlert {
  const InventoryAlert({
    required this.id,
    required this.warehouseId,
    required this.warehouseCode,
    required this.warehouseName,
    required this.ingredientId,
    required this.ingredientSku,
    required this.ingredientName,
    required this.unit,
    required this.status,
    required this.quantityAtTrigger,
    required this.thresholdQuantity,
    required this.currentQuantity,
    required this.reservedQuantity,
    required this.availableQuantity,
    required this.currentMinQuantity,
    required this.triggeredAt,
    required this.acknowledgedBy,
    required this.acknowledgedAt,
    required this.resolvedAt,
    required this.resolutionReason,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id, warehouseId, warehouseCode, warehouseName;
  final String ingredientId, ingredientName, unit;
  final String? ingredientSku, acknowledgedBy;
  final InventoryAlertStatus status;
  final InventoryQuantity quantityAtTrigger, thresholdQuantity;
  final InventoryQuantity? currentQuantity,
      reservedQuantity,
      availableQuantity,
      currentMinQuantity;
  final DateTime triggeredAt, createdAt, updatedAt;
  final DateTime? acknowledgedAt, resolvedAt;
  final InventoryAlertResolution? resolutionReason;
  final int version;
}
