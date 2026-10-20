import 'inventory_quantity.dart';
import 'stock_numbers.dart';
import 'stock_document.dart';

class StockLineInput {
  const StockLineInput({
    required this.ingredientId,
    required this.quantity,
    required this.unitCost,
    this.direction,
    this.note,
  });
  final String ingredientId;
  final InventoryQuantity quantity;
  final StockMoney unitCost;
  final AdjustmentDirection? direction;
  final String? note;
}

class CreateStockDocumentInput {
  CreateStockDocumentInput({
    required this.type,
    required this.warehouseId,
    this.note,
    required List<StockLineInput> items,
  }) : items = List.unmodifiable(items);
  final StockDocumentType type;
  final String warehouseId;
  final String? note;
  final List<StockLineInput> items;
}

class UpdateStockDocumentNote {
  const UpdateStockDocumentNote(this.expectedVersion, this.note);
  final int expectedVersion;
  final String? note;
}

class StockDocumentLineInput {
  const StockDocumentLineInput(this.expectedVersion, this.line);
  final int expectedVersion;
  final StockLineInput line;
}

class StockDocumentVersion {
  const StockDocumentVersion(this.expectedVersion);
  final int expectedVersion;
}

abstract interface class StockKeyGenerator {
  String next();
}
