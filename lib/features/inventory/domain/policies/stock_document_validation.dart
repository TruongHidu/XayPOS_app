import '../entities/stock_document.dart';
import '../entities/stock_inputs.dart';
import '../entities/stock_numbers.dart';

abstract final class StockDocumentValidation {
  static Map<String, String> revisedTotals(
    StockDocumentDetail document,
    StockLineInput replacement, {
    String? itemId,
  }) {
    var quantity = BigInt.zero, cost = BigInt.zero;
    for (final row in document.items) {
      if (row.id == itemId) continue;
      quantity += BigInt.from(row.quantity.scaled);
      cost += row.totalCost.cents;
    }
    quantity += BigInt.from(replacement.quantity.scaled);
    cost += stockLineCost(replacement.quantity, replacement.unitCost).cents;
    return {
      if (quantity > BigInt.parse('9999999999999999'))
        'quantity': 'Tổng số lượng vượt giới hạn lưu trữ của chứng từ.',
      if (cost > BigInt.parse('999999999999999999'))
        'unitCost': 'Tổng giá trị vượt giới hạn lưu trữ của chứng từ.',
    };
  }

  static Map<String, String> line(StockDocumentType type, StockLineInput line) {
    final errors = <String, String>{};
    if (line.ingredientId.trim().isEmpty) {
      errors['ingredientId'] = 'Chọn nguyên liệu.';
    }
    if (line.quantity.scaled <= 0) {
      errors['quantity'] = 'Số lượng phải lớn hơn 0.';
    }
    if (!line.unitCost.validUnitCost) {
      errors['unitCost'] = 'Đơn giá tối đa 999999999999.99.';
    }
    if ((type == StockDocumentType.adjustment) != (line.direction != null)) {
      errors['adjustmentDirection'] =
          'Chọn hướng tăng/giảm đúng loại chứng từ.';
    }
    if ((line.note?.length ?? 0) > 1000) {
      errors['note'] = 'Ghi chú dòng tối đa 1000 ký tự.';
    }
    if (errors.isEmpty) {
      try {
        stockLineCost(line.quantity, line.unitCost);
      } on FormatException catch (e) {
        errors['unitCost'] = e.message;
      }
    }
    return errors;
  }

  static Map<String, String> create(CreateStockDocumentInput input) {
    final errors = <String, String>{};
    if (input.warehouseId.trim().isEmpty) errors['warehouseId'] = 'Chọn kho.';
    if ((input.note?.length ?? 0) > 2000) {
      errors['note'] = 'Ghi chú tối đa 2000 ký tự.';
    }
    if (input.items.length > 100) errors['items'] = 'Tạo mới tối đa 100 dòng.';
    if (input.items.map((r) => r.ingredientId).toSet().length !=
        input.items.length) {
      errors['items'] = 'Mỗi nguyên liệu chỉ xuất hiện một lần.';
    }
    var total = BigInt.zero;
    for (var i = 0; i < input.items.length; i++) {
      final row = input.items[i], failures = line(input.type, input.items[i]);
      for (final e in failures.entries) {
        errors['items[$i].${e.key}'] = e.value;
      }
      if (failures.isEmpty) {
        total += stockLineCost(row.quantity, row.unitCost).cents;
      }
    }
    if (total > BigInt.parse('999999999999999999')) {
      errors['items'] = 'Tổng giá trị vượt giới hạn chứng từ.';
    }
    return errors;
  }
}
