import '../../domain/entities/recipe_inputs.dart';
import '../../domain/entities/recipe_query.dart';

abstract final class RecipeRequests {
  static Map<String, dynamic> query(RecipeQuery query) => {
    'page': query.page,
    'size': query.size,
    'sortBy': query.sortBy,
    'direction': query.direction,
  };

  /// Only writable fields cross this boundary; snapshots belong to the server.
  static Map<String, dynamic> create(RecipeInput input) => {
    'yieldQuantity': input.yieldQuantity.toNumber(),
    'ingredients': [
      for (final line in input.ingredients)
        {
          'ingredientId': line.ingredientId.trim(),
          'quantity': line.quantity.toNumber(),
          'wastePercent': line.wastePercent.toNumber(),
        },
    ],
  };

  static Map<String, dynamic> createVersion(CreateRecipeVersionInput input) => {
    ...create(input),
    'expectedVersion': input.expectedVersion,
  };
}
