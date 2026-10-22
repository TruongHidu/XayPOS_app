import '../../domain/entities/stock_inputs.dart';
import '../../domain/entities/stock_queries.dart';

abstract final class StockDocumentRequests {
  static String? note(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
  static Map<String, dynamic> line(
    StockLineInput input, {
    bool includeIngredient = true,
  }) => {
    if (includeIngredient) 'ingredientId': input.ingredientId,
    'quantity': input.quantity.toNumber(),
    'unitCost': input.unitCost.toUnitCostNumber(),
    'adjustmentDirection': input.direction?.code,
    'note': note(input.note),
  };
  static Map<String, dynamic> create(CreateStockDocumentInput input) => {
    'documentType': input.type.code,
    'warehouseId': input.warehouseId,
    'note': note(input.note),
    'items': input.items.map((r) => line(r)).toList(),
  };
  static Map<String, dynamic> documents(StockDocumentQuery q) => {
    if (q.q.trim().isNotEmpty) 'q': q.q.trim(),
    if (q.type != null) 'type': q.type!.code,
    if (q.status != null) 'status': q.status!.code,
    if (q.warehouseId != null) 'warehouseId': q.warehouseId,
    ...dates(q.dates),
    'page': q.page,
    'size': q.size,
    'sortBy': q.sortBy,
    'direction': q.direction,
  };
  static Map<String, dynamic> transactions(InventoryTransactionQuery q) => {
    if (q.orderId != null) 'orderId': q.orderId,
    if (q.orderItemId != null) 'orderItemId': q.orderItemId,
    if (q.source != null) 'sourceType': q.source!.code,
    if (q.warehouseId != null) 'warehouseId': q.warehouseId,
    if (q.ingredientId != null) 'ingredientId': q.ingredientId,
    if (q.documentId != null) 'documentId': q.documentId,
    if (q.type != null) 'transactionType': q.type!.code,
    ...dates(q.dates),
    'page': q.page,
    'size': q.size,
    'sortBy': q.sortBy,
    'direction': q.direction,
  };
  static Map<String, dynamic> dates(StockDateRange? range) => {
    if (range?.from != null)
      'createdFrom': range!.from!.toUtc().toIso8601String(),
    if (range?.to != null) 'createdTo': range!.to!.toUtc().toIso8601String(),
  };
}
