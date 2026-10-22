import 'inventory_quantity.dart';
import 'stock_numbers.dart';

enum StockDocumentType {
  receipt('RECEIPT', 'Nhập kho', 'INVENTORY_RECEIVE'),
  issue('ISSUE', 'Xuất kho', 'INVENTORY_ISSUE'),
  adjustment('ADJUSTMENT', 'Điều chỉnh', 'INVENTORY_ADJUST');

  const StockDocumentType(this.code, this.label, this.permission);
  final String code, label, permission;
}

enum StockDocumentStatus {
  draft('DRAFT', 'Nháp'),
  confirmed('CONFIRMED', 'Đã xác nhận'),
  cancelled('CANCELLED', 'Đã hủy');

  const StockDocumentStatus(this.code, this.label);
  final String code, label;
}

enum AdjustmentDirection {
  increase('INCREASE', 'Tăng'),
  decrease('DECREASE', 'Giảm');

  const AdjustmentDirection(this.code, this.label);
  final String code, label;
}

enum InventoryTransactionType {
  recipeUse('RECIPE_USE', 'Tiêu thụ theo món'),
  receipt('RECEIPT', 'Nhập kho'),
  issue('ISSUE', 'Xuất kho'),
  adjustmentIncrease('ADJUSTMENT_INCREASE', 'Điều chỉnh tăng'),
  adjustmentDecrease('ADJUSTMENT_DECREASE', 'Điều chỉnh giảm');

  const InventoryTransactionType(this.code, this.label);
  final String code, label;
}

enum InventoryTransactionSource {
  stockDocument('STOCK_DOCUMENT', 'Chứng từ kho'),
  orderItem('ORDER_ITEM', 'Dòng món');

  const InventoryTransactionSource(this.code, this.label);
  final String code, label;
}

class StockDocumentSummary {
  const StockDocumentSummary({
    required this.id,
    required this.documentCode,
    required this.type,
    required this.status,
    required this.warehouseId,
    required this.warehouseCode,
    required this.warehouseName,
    required this.note,
    required this.lineCount,
    required this.totalQuantity,
    required this.totalCost,
    required this.createdBy,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.stockAuditId,
  });
  final String id,
      documentCode,
      warehouseId,
      warehouseCode,
      warehouseName,
      createdBy;
  final String? note;
  final String? stockAuditId;
  final StockDocumentType type;
  final StockDocumentStatus status;
  final int lineCount, version;
  final StockQuantityTotal totalQuantity;
  final StockMoney totalCost;
  final DateTime createdAt, updatedAt;
}

class StockDocumentDetail extends StockDocumentSummary {
  StockDocumentDetail({
    required super.id,
    required super.documentCode,
    required super.type,
    required super.status,
    required super.warehouseId,
    required super.warehouseCode,
    required super.warehouseName,
    required super.note,
    required super.lineCount,
    required super.totalQuantity,
    required super.totalCost,
    required super.createdBy,
    required super.version,
    required super.createdAt,
    required super.updatedAt,
    super.stockAuditId,
    required List<StockDocumentItem> items,
    required this.confirmedBy,
    required this.cancelledBy,
    required this.confirmedAt,
    required this.cancelledAt,
  }) : items = List.unmodifiable(items);
  final List<StockDocumentItem> items;
  final String? confirmedBy, cancelledBy;
  final DateTime? confirmedAt, cancelledAt;
}

class StockDocumentItem {
  const StockDocumentItem({
    required this.id,
    required this.ingredientId,
    required this.ingredientSku,
    required this.ingredientName,
    required this.unit,
    required this.quantity,
    required this.direction,
    required this.unitCost,
    required this.totalCost,
    required this.note,
  });
  final String id, ingredientId, ingredientName, unit;
  final String? ingredientSku, note;
  final InventoryQuantity quantity;
  final AdjustmentDirection? direction;
  final StockMoney unitCost, totalCost;
}

class InventoryTransaction {
  const InventoryTransaction({
    required this.source,
    required this.orderId,
    required this.orderItemId,
    required this.reservationId,
    required this.recipeUsageId,
    required this.id,
    required this.warehouseId,
    required this.warehouseCode,
    required this.ingredientId,
    required this.ingredientSku,
    required this.ingredientName,
    required this.unit,
    required this.documentId,
    required this.documentCode,
    required this.documentType,
    required this.type,
    required this.change,
    required this.before,
    required this.after,
    required this.unitCost,
    required this.createdBy,
    required this.createdAt,
  });
  final String id,
      warehouseId,
      warehouseCode,
      ingredientId,
      ingredientName,
      unit,
      createdBy;
  final String? ingredientSku, documentId, documentCode;
  final String? orderId, orderItemId, reservationId, recipeUsageId;
  final InventoryTransactionSource source;
  final StockDocumentType? documentType;
  final InventoryTransactionType type;
  final StockQuantityChange change;
  final InventoryQuantity before, after;
  final StockMoney? unitCost;
  final DateTime createdAt;
}
