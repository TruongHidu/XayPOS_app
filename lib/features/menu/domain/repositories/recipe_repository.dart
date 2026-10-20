import '../../../../core/result/result.dart';
import '../entities/menu_page.dart';
import '../entities/recipe.dart';
import '../entities/recipe_cost_estimate.dart';
import '../entities/recipe_inputs.dart';
import '../entities/recipe_query.dart';

abstract class RecipeRepository {
  Future<Result<RecipeCostEstimate>> costEstimate(
    String menuItemId,
    String recipeId,
  );
  Future<Result<Recipe>> active(String menuItemId);
  Future<Result<MenuPage<RecipeSummary>>> history(
    String menuItemId,
    RecipeQuery query,
  );
  Future<Result<Recipe>> detail(String menuItemId, String recipeId);
  Future<Result<Recipe>> create(String menuItemId, RecipeInput input);
  Future<Result<Recipe>> createVersion(
    String menuItemId,
    String activeRecipeId,
    CreateRecipeVersionInput input,
  );
  Future<Result<void>> deactivate(
    String menuItemId,
    String recipeId,
    int expectedVersion,
  );
}
