import 'recipe.dart';
import 'recipe_amount.dart';

class RecipeIngredientInput {
  const RecipeIngredientInput({
    required this.ingredientId,
    required this.quantity,
    this.wastePercent = RecipeWastePercent.zero,
  });

  final String ingredientId;
  final RecipeQuantity quantity;
  final RecipeWastePercent wastePercent;
}

class RecipeInput {
  RecipeInput({
    required this.yieldQuantity,
    required List<RecipeIngredientInput> ingredients,
  }) : ingredients = List.unmodifiable(ingredients);

  final RecipeQuantity yieldQuantity;
  final List<RecipeIngredientInput> ingredients;

  /// Compare normalized content; row order and snapshot labels do not matter.
  bool sameAs(Recipe baseline) {
    if (yieldQuantity != baseline.yieldQuantity ||
        ingredients.length != baseline.ingredients.length) {
      return false;
    }
    final current = {
      for (final line in ingredients) line.ingredientId.trim(): line,
    };
    final previous = {
      for (final line in baseline.ingredients) line.ingredientId: line,
    };
    // Duplicates are invalid and must never be treated as unchanged content.
    if (current.length != ingredients.length ||
        previous.length != baseline.ingredients.length) {
      return false;
    }
    for (final entry in current.entries) {
      final line = previous[entry.key];
      if (line == null ||
          line.quantity != entry.value.quantity ||
          line.wastePercent != entry.value.wastePercent) {
        return false;
      }
    }
    return true;
  }
}

class CreateRecipeVersionInput extends RecipeInput {
  CreateRecipeVersionInput({
    required this.expectedVersion,
    required super.yieldQuantity,
    required super.ingredients,
  });

  final int expectedVersion;
}
