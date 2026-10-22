import '../../domain/entities/inventory_alert_query.dart';

abstract final class InventoryAlertRequests {
  static Map<String, dynamic> list(InventoryAlertQuery q) {
    if (!q.valid) throw const FormatException('Invalid alert query');
    return {
      if (q.warehouseId != null) 'warehouseId': q.warehouseId,
      if (q.ingredientId != null) 'ingredientId': q.ingredientId,
      if (q.status != null) 'status': q.status!.code,
      if (q.q.trim().isNotEmpty) 'q': q.q.trim(),
      if (q.dates?.from != null)
        'triggeredFrom': q.dates!.from!.toUtc().toIso8601String(),
      if (q.dates?.to != null)
        'triggeredTo': q.dates!.to!.toUtc().toIso8601String(),
      'page': q.page,
      'size': q.size,
      'sortBy': q.sortBy,
      'direction': q.direction,
    };
  }

  static Map<String, dynamic> acknowledge(
    AcknowledgeInventoryAlertInput input,
  ) {
    if (!input.valid) throw const FormatException('Invalid alert version');
    return {'expectedVersion': input.expectedVersion};
  }
}
