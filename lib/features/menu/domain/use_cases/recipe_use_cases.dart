import '../../../../core/result/result.dart';
import '../entities/menu_page.dart';
import '../entities/recipe.dart';
import '../entities/recipe_cost_estimate.dart';
import '../entities/recipe_inputs.dart';
import '../entities/recipe_query.dart';
import '../repositories/recipe_repository.dart';

class GetRecipeCostEstimate {
  const GetRecipeCostEstimate(this._repository);
  final RecipeRepository _repository;
  Future<Result<RecipeCostEstimate>> call(String menuItemId, String recipeId) =>
      _repository.costEstimate(menuItemId, recipeId);
}

class GetActiveRecipe {
  const GetActiveRecipe(this._repository);
  final RecipeRepository _repository;
  Future<Result<Recipe>> call(String menuItemId) =>
      _repository.active(menuItemId);
}

class GetRecipeHistory {
  const GetRecipeHistory(this._repository);
  final RecipeRepository _repository;
  Future<Result<MenuPage<RecipeSummary>>> call(
    String menuItemId,
    RecipeQuery query,
  ) => _repository.history(menuItemId, query);
}

class GetRecipeDetail {
  const GetRecipeDetail(this._repository);
  final RecipeRepository _repository;
  Future<Result<Recipe>> call(String menuItemId, String recipeId) =>
      _repository.detail(menuItemId, recipeId);
}

class CreateRecipe {
  const CreateRecipe(this._repository);
  final RecipeRepository _repository;
  Future<Result<Recipe>> call(String menuItemId, RecipeInput input) =>
      _repository.create(menuItemId, input);
}

class CreateRecipeVersion {
  const CreateRecipeVersion(this._repository);
  final RecipeRepository _repository;
  Future<Result<Recipe>> call(
    String menuItemId,
    String activeRecipeId,
    CreateRecipeVersionInput input,
  ) => _repository.createVersion(menuItemId, activeRecipeId, input);
}

class DeactivateRecipe {
  const DeactivateRecipe(this._repository);
  final RecipeRepository _repository;
  Future<Result<void>> call(
    String menuItemId,
    String recipeId,
    int expectedVersion,
  ) => _repository.deactivate(menuItemId, recipeId, expectedVersion);
}
