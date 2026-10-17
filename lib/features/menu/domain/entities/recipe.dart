import 'recipe_amount.dart';

class Recipe {
  Recipe({
    required this.id,
    required this.menuItemId,
    required this.recipeVersion,
    required this.yieldQuantity,
    required this.yieldUnit,
    required this.active,
    required List<RecipeIngredient> ingredients,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  }) : ingredients = List.unmodifiable(ingredients);

  final String id;
  final String menuItemId;

  /// Business version displayed to the user.
  final int recipeVersion;
  final RecipeQuantity yieldQuantity;
  final String yieldUnit;
  final bool active;
  final List<RecipeIngredient> ingredients;

  /// Optimistic-lock version supplied as expectedVersion for mutations.
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class RecipeIngredient {
  const RecipeIngredient({
    required this.id,
    required this.ingredientId,
    required this.sku,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.wastePercent,
  });

  final String id;
  final String ingredientId;

  /// These fields are historical snapshots, not live catalog data.
  final String? sku;
  final String name;
  final String unit;
  final RecipeQuantity quantity;
  final RecipeWastePercent wastePercent;
}

class RecipeSummary {
  const RecipeSummary({
    required this.id,
    required this.menuItemId,
    required this.recipeVersion,
    required this.yieldQuantity,
    required this.yieldUnit,
    required this.active,
    required this.ingredientCount,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String menuItemId;
  final int recipeVersion;
  final RecipeQuantity yieldQuantity;
  final String yieldUnit;
  final bool active;
  final int ingredientCount;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
}
