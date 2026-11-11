import '../values/ingredient_quantity.dart';

/// `details` of a 409 INSUFFICIENT_AVAILABLE_STOCK from order submit, append,
/// confirm and QR approval: which new lines could not be reserved.
class StockShortage {
  StockShortage(List<StockShortageLine> lines)
    : lines = List.unmodifiable(lines);
  final List<StockShortageLine> lines;

  /// Null when the server sent no usable detail; callers then fall back to the
  /// plain message rather than showing a partial list.
  static StockShortage? tryParse(Object? details) {
    try {
      if (details is! Map) return null;
      final raw = details['lines'];
      if (raw is! List || raw.isEmpty) return null;
      return StockShortage([
        for (final line in raw) StockShortageLine._parse(line as Map),
      ]);
    } on Object {
      return null;
    }
  }
}

class StockShortageLine {
  const StockShortageLine({
    required this.orderItemId,
    required this.menuItemId,
    required this.itemName,
    required this.requestedQuantity,
    required this.maxAvailableQuantity,
    required this.unit,
    required this.sharesIngredientWithOtherLines,
    this.shortIngredients,
  });
  final String orderItemId, menuItemId, itemName, unit;
  final IngredientQuantity requestedQuantity, maxAvailableQuantity;
  final bool sharesIngredientWithOtherLines;

  /// Only sent to users with INVENTORY_VIEW; null (not empty) otherwise.
  final List<StockShortIngredient>? shortIngredients;

  bool get soldOut => maxAvailableQuantity.scaled == BigInt.zero;

  factory StockShortageLine._parse(Map json) {
    final ingredients = json['shortIngredients'];
    return StockShortageLine(
      orderItemId: json['orderItemId'] as String,
      menuItemId: json['menuItemId'] as String,
      itemName: json['itemName'] as String,
      requestedQuantity: stockQuantity(json['requestedQuantity']),
      maxAvailableQuantity: stockQuantity(json['maxAvailableQuantity']),
      unit: json['unit'] as String,
      sharesIngredientWithOtherLines:
          json['sharesIngredientWithOtherLines'] as bool,
      shortIngredients: ingredients is List
          ? [
              for (final row in ingredients)
                StockShortIngredient._parse(row as Map),
            ]
          : null,
    );
  }
}

class StockShortIngredient {
  const StockShortIngredient({
    required this.ingredientId,
    required this.name,
    required this.unit,
    required this.availableQuantity,
    required this.requiredQuantity,
  });
  final String ingredientId, name, unit;
  final IngredientQuantity availableQuantity;

  /// Demand of the whole command, not just this line.
  final IngredientQuantity requiredQuantity;

  factory StockShortIngredient._parse(Map json) => StockShortIngredient(
    ingredientId: json['ingredientId'] as String,
    name: json['name'] as String,
    unit: json['unit'] as String,
    availableQuantity: stockQuantity(json['availableQuantity']),
    requiredQuantity: stockQuantity(json['requiredQuantity']),
  );
}

/// NUMERIC(14,3) arrives as a JSON number or string; fixed 3 decimals keeps a
/// double like 0.33 from turning into 0.33000000000000002.
IngredientQuantity stockQuantity(Object? value) => switch (value) {
  final num n => IngredientQuantity.parse(n.toStringAsFixed(3)),
  final String s => IngredientQuantity.parse(s),
  _ => throw const FormatException('Invalid stock quantity'),
};
