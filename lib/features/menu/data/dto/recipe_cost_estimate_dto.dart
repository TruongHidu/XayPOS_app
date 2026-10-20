import '../../../../core/network/exact_json.dart';
import '../../domain/entities/recipe_cost_amount.dart';
import '../../domain/entities/recipe_cost_estimate.dart';

abstract final class RecipeCostEstimateDto {
  static RecipeCostEstimate fromJson(Object? raw) {
    final json = object(raw);
    final ingredients = list(json, 'ingredients').map((raw) {
      final row = object(raw);
      final sku = row['sku'];
      if (!row.containsKey('sku') || sku != null && sku is! String) {
        throw const FormatException('Invalid sku');
      }
      return RecipeIngredientCost(
        ingredientId: string(row, 'ingredientId'),
        sku: sku as String?,
        name: string(row, 'name'),
        unit: string(row, 'unit'),
        quantity: amount(row, 'quantity', positive: true),
        wastePercent: amount(row, 'wastePercent'),
        grossQuantity: amount(row, 'grossQuantity', positive: true),
        unitCost: amount(row, 'unitCost', money: true),
        lineCost: amount(row, 'lineCost', money: true),
      );
    }).toList();
    final ids = ingredients.map((e) => e.ingredientId).toSet();
    if (ingredients.isEmpty || ids.length != ingredients.length) {
      throw const FormatException('Invalid cost ingredients');
    }
    final warningKeys = <(String, String)>{};
    final warnings = <RecipeCostWarning>[];
    for (final raw in list(json, 'warnings')) {
      final row = object(raw);
      final code = string(row, 'code'), id = string(row, 'ingredientId');
      if (!ids.contains(id)) {
        throw const FormatException('Warning for unknown ingredient');
      }
      final message = string(row, 'message');
      if (warningKeys.add((code, id))) {
        warnings.add(
          RecipeCostWarning(code: code, ingredientId: id, message: message),
        );
      }
    }
    final version = amount(json, 'recipeVersion', positive: true);
    if (version.scale != 0 ||
        version.coefficient > BigInt.from(9007199254740991)) {
      throw const FormatException('Invalid recipeVersion');
    }
    final currency = string(json, 'currencyCode'),
        source = string(json, 'costSource');
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency) ||
        source != 'INGREDIENT_COST_PRICE' ||
        json['recipeActive'] is! bool) {
      throw const FormatException('Invalid estimate metadata');
    }
    final estimatedAt = string(json, 'estimatedAt');
    if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(estimatedAt)) {
      throw const FormatException('Missing estimate timezone');
    }
    return RecipeCostEstimate(
      menuItemId: string(json, 'menuItemId'),
      recipeId: string(json, 'recipeId'),
      recipeVersion: version.coefficient.toInt(),
      recipeActive: json['recipeActive'] as bool,
      yieldQuantity: amount(json, 'yieldQuantity', positive: true),
      yieldUnit: string(json, 'yieldUnit'),
      currencyCode: currency,
      costSource: source,
      totalBatchCost: amount(json, 'totalBatchCost', money: true),
      costPerYieldUnit: amount(json, 'costPerYieldUnit', money: true),
      ingredients: ingredients,
      warnings: warnings,
      estimatedAt: DateTime.parse(estimatedAt),
    );
  }

  static Map<String, dynamic> object(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Expected estimate object');
    }
    return raw;
  }

  static String string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid $key');
    }
    return value;
  }

  static List<dynamic> list(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! List) throw FormatException('Invalid $key');
    return value;
  }

  static RecipeCostAmount amount(
    Map<String, dynamic> json,
    String key, {
    bool money = false,
    bool positive = false,
  }) {
    final value = RecipeCostAmount.parse(
      exactJsonNumberText(json[key]),
      money: money,
    );
    if (positive && value.isZero) throw FormatException('Invalid $key');
    return value;
  }
}
