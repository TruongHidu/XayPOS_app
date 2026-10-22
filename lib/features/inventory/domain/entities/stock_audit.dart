import 'inventory_quantity.dart';
import 'stock_numbers.dart';

enum StockAuditStatus {
  draft('DRAFT', 'Nháp'),
  counting('COUNTING', 'Đang kiểm kê'),
  confirmed('CONFIRMED', 'Đã chốt kiểm kê'),
  cancelled('CANCELLED', 'Đã hủy');

  const StockAuditStatus(this.code, this.label);
  final String code, label;
}

class StockAuditSummary {
  const StockAuditSummary({
    required this.id,
    required this.auditCode,
    required this.warehouseId,
    required this.warehouseCode,
    required this.warehouseName,
    required this.status,
    required this.note,
    required this.itemCount,
    required this.countedItemCount,
    required this.changedItemCount,
    required this.adjustmentDocumentId,
    required this.adjustmentDocumentCode,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.startedAt,
  });
  final String id, auditCode, warehouseId, warehouseCode, warehouseName;
  final String? note, adjustmentDocumentId, adjustmentDocumentCode;
  final StockAuditStatus status;
  final int itemCount, countedItemCount, changedItemCount, version;
  final DateTime createdAt, updatedAt;
  final DateTime? startedAt;
}

class StockAuditDetail extends StockAuditSummary {
  const StockAuditDetail({
    required super.id,
    required super.auditCode,
    required super.warehouseId,
    required super.warehouseCode,
    required super.warehouseName,
    required super.status,
    required super.note,
    required super.itemCount,
    required super.countedItemCount,
    required super.changedItemCount,
    required super.adjustmentDocumentId,
    required super.adjustmentDocumentCode,
    required super.version,
    required super.createdAt,
    required super.updatedAt,
    required super.startedAt,
    required this.createdBy,
    required this.startedBy,
    required this.confirmedBy,
    required this.cancelledBy,
    required this.confirmedAt,
    required this.cancelledAt,
  });
  final String createdBy;
  final String? startedBy, confirmedBy, cancelledBy;
  final DateTime? confirmedAt, cancelledAt;
}

class StockAuditItem {
  const StockAuditItem({
    required this.id,
    required this.ingredientId,
    required this.sku,
    required this.name,
    required this.unit,
    required this.systemQuantity,
    required this.countedQuantity,
    required this.differenceQuantity,
    required this.referenceUnitCostSnapshot,
    required this.note,
  });
  final String id, ingredientId, name, unit;
  final String? sku, note;
  final InventoryQuantity systemQuantity;
  final InventoryQuantity? countedQuantity;
  final StockAuditDifference? differenceQuantity;
  final StockMoney referenceUnitCostSnapshot;
}

/// Exact signed thousandths. Unlike a ledger movement, zero is valid here.
class StockAuditDifference {
  const StockAuditDifference._(this.scaled);
  final BigInt scaled;
  factory StockAuditDifference.parse(String input) {
    final value = input.trim();
    final negative = value.startsWith('-');
    final magnitude = InventoryQuantity.parse(
      negative ? value.substring(1) : value,
    );
    final scaled = BigInt.from(magnitude.scaled);
    return StockAuditDifference._(negative ? -scaled : scaled);
  }
  factory StockAuditDifference.between(
    InventoryQuantity counted,
    InventoryQuantity system,
  ) => StockAuditDifference._(
    BigInt.from(counted.scaled) - BigInt.from(system.scaled),
  );
  bool get negative => scaled.isNegative;
  bool get isZero => scaled == BigInt.zero;
  @override
  String toString() => stockDecimal(scaled, 3);
  @override
  bool operator ==(Object other) =>
      other is StockAuditDifference && other.scaled == scaled;
  @override
  int get hashCode => scaled.hashCode;
}
