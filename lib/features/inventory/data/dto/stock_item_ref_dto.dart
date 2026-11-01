import '../../../../core/values/item_type.dart';

typedef StockItemRef = ({String stockItemId, ItemType itemType});

/// `itemId` identifies a stock row of either type. `ingredientId` is a legacy
/// alias that is null for menu items, so it must never be used as a key.
abstract final class StockItemRefDto {
  static String? _id(Map<String, dynamic> j, String key) {
    final value = j[key];
    if (value == null) return null;
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid $key');
    }
    return value;
  }

  static StockItemRef parse(Map<String, dynamic> j) {
    final id = _id(j, 'itemId'), legacy = _id(j, 'ingredientId');
    if (id == null) {
      // Payloads from before backend V40 only carry ingredientId.
      if (legacy == null) throw const FormatException('Invalid itemId');
      return (stockItemId: legacy, itemType: ItemType.ingredient);
    }
    final code = j['itemType'];
    if (code is! String) throw const FormatException('Invalid itemType');
    final type = ItemType.fromCode(code);
    if (type == ItemType.ingredient ? legacy != id : legacy != null) {
      throw const FormatException('Mismatched stock item identity');
    }
    return (stockItemId: id, itemType: type);
  }
}
