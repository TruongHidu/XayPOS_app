import 'inventory_quantity.dart';

class CreateStockAuditInput {
  const CreateStockAuditInput({required this.warehouseId, this.note});
  final String warehouseId;
  final String? note;
}

class UpdateStockAuditNoteInput {
  const UpdateStockAuditNoteInput({required this.expectedVersion, this.note});
  final int expectedVersion;
  final String? note;
}

class StockAuditTransitionInput {
  const StockAuditTransitionInput({required this.expectedVersion});
  final int expectedVersion;
}

class StockAuditCountInput {
  const StockAuditCountInput({
    required this.auditItemId,
    required this.countedQuantity,
    this.note,
  });
  final String auditItemId;
  final InventoryQuantity countedQuantity;

  /// Null means preserve the saved note; blank means clear it.
  final String? note;
}

class StockAuditCountsInput {
  StockAuditCountsInput({
    required this.expectedVersion,
    required List<StockAuditCountInput> items,
  }) : items = List.unmodifiable(items);
  final int expectedVersion;
  final List<StockAuditCountInput> items;
}

class CancelStockAuditInput {
  const CancelStockAuditInput({required this.expectedVersion, this.note});
  final int expectedVersion;

  /// Null or blank preserves the header note when cancelling.
  final String? note;
}
