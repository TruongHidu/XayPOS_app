import 'recipe_cost_amount.dart';

class RecipeCostEstimate {
  RecipeCostEstimate({
    required this.menuItemId,
    required this.recipeId,
    required this.recipeVersion,
    required this.recipeActive,
    required this.yieldQuantity,
    required this.yieldUnit,
    required this.currencyCode,
    required this.costSource,
    required this.totalBatchCost,
    required this.costPerYieldUnit,
    required List<RecipeIngredientCost> ingredients,
    required List<RecipeCostWarning> warnings,
    required this.estimatedAt,
  }) : ingredients = List.unmodifiable(ingredients),
       warnings = List.unmodifiable(warnings);
  final String menuItemId, recipeId, yieldUnit, currencyCode, costSource;
  final int recipeVersion;
  final bool recipeActive;
  final RecipeCostAmount yieldQuantity, totalBatchCost, costPerYieldUnit;
  final List<RecipeIngredientCost> ingredients;
  final List<RecipeCostWarning> warnings;
  final DateTime estimatedAt;
}

class RecipeIngredientCost {
  const RecipeIngredientCost({
    required this.ingredientId,
    required this.sku,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.wastePercent,
    required this.grossQuantity,
    required this.unitCost,
    required this.lineCost,
  });
  final String ingredientId, name, unit;
  final String? sku;
  final RecipeCostAmount quantity,
      wastePercent,
      grossQuantity,
      unitCost,
      lineCost;
}

class RecipeCostWarning {
  const RecipeCostWarning({
    required this.code,
    required this.ingredientId,
    required this.message,
  });
  final String code, ingredientId, message;
}
