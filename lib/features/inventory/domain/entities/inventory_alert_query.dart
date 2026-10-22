import 'inventory_alert.dart';
import 'inventory_instant_range.dart';

class InventoryAlertQuery {
  const InventoryAlertQuery({
    this.warehouseId,
    this.ingredientId,
    this.status = InventoryAlertStatus.open,
    this.q = '',
    this.dates,
    this.page = 0,
    this.size = 20,
    this.sortBy = 'triggeredAt',
    this.direction = 'desc',
  });
  final String? warehouseId, ingredientId;
  final InventoryAlertStatus? status;
  final String q, sortBy, direction;
  final InventoryInstantRange? dates;
  final int page, size;
  bool get valid =>
      q.trim().length <= 100 &&
      page >= 0 &&
      size >= 1 &&
      size <= 100 &&
      const {'triggeredAt', 'updatedAt'}.contains(sortBy) &&
      const {'asc', 'desc'}.contains(direction) &&
      (dates?.isValid ?? true) &&
      (warehouseId == null || warehouseId!.trim().isNotEmpty) &&
      (ingredientId == null || ingredientId!.trim().isNotEmpty);

  InventoryAlertQuery copyWith({
    String? Function()? warehouseId,
    String? Function()? ingredientId,
    InventoryAlertStatus? Function()? status,
    InventoryInstantRange? Function()? dates,
    String? q,
    int? page,
    int? size,
    String? sortBy,
    String? direction,
  }) => InventoryAlertQuery(
    warehouseId: warehouseId == null ? this.warehouseId : warehouseId(),
    ingredientId: ingredientId == null ? this.ingredientId : ingredientId(),
    status: status == null ? this.status : status(),
    dates: dates == null ? this.dates : dates(),
    q: q ?? this.q,
    page: page ?? this.page,
    size: size ?? this.size,
    sortBy: sortBy ?? this.sortBy,
    direction: direction ?? this.direction,
  );
}

class AcknowledgeInventoryAlertInput {
  const AcknowledgeInventoryAlertInput(this.expectedVersion);
  final int expectedVersion;
  bool get valid => expectedVersion >= 0;
}
