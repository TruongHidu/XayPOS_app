import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_page.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_amount.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_query.dart';
import 'package:pos_saas_app/features/menu/domain/repositories/recipe_repository.dart';
import 'menu_fakes.dart' show page;
import 'recipe_cost_fakes.dart' show estimateForRecipe;
import 'package:pos_saas_app/features/menu/domain/entities/recipe_cost_estimate.dart';

const recipeUiPermissions = {
  'RECIPE_VIEW',
  'RECIPE_CREATE',
  'RECIPE_UPDATE',
  'RECIPE_DELETE',
};

Recipe uiRecipe({
  String id = 'r7',
  int business = 7,
  int lock = 42,
  bool active = true,
  String unit = 'tô',
  int count = 1,
}) => Recipe(
  id: id,
  menuItemId: 'i1',
  recipeVersion: business,
  yieldQuantity: RecipeQuantity.parse('10'),
  yieldUnit: unit,
  active: active,
  ingredients: [
    for (var i = 0; i < count; i++)
      RecipeIngredient(
        id: 'line-$i',
        ingredientId: i == 0 ? 'ingredient-1' : 'ingredient-${i + 1}',
        sku: 'OLD-$i',
        name: 'Snapshot nguyên liệu $i',
        unit: 'g',
        quantity: RecipeQuantity.parse('1200'),
        wastePercent: RecipeWastePercent.parse('5'),
      ),
  ],
  version: lock,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 10, 16),
);

RecipeSummary uiSummary(Recipe recipe) => RecipeSummary(
  id: recipe.id,
  menuItemId: recipe.menuItemId,
  recipeVersion: recipe.recipeVersion,
  yieldQuantity: recipe.yieldQuantity,
  yieldUnit: recipe.yieldUnit,
  active: recipe.active,
  ingredientCount: recipe.ingredients.length,
  version: recipe.version,
  createdAt: recipe.createdAt,
  updatedAt: recipe.updatedAt,
);

class UiRecipes implements RecipeRepository {
  @override
  Future<Result<RecipeCostEstimate>> costEstimate(
    String menuItemId,
    String recipeId,
  ) async => Success(
    estimateForRecipe(recipeId == historical.id ? historical : current!),
  );
  Recipe? current = uiRecipe();
  Recipe historical = uiRecipe(id: 'r2', business: 2, lock: 90, active: false);
  final historyQueries = <RecipeQuery>[];
  int activeCalls = 0;
  int detailCalls = 0;
  final creates = <RecipeInput>[];
  final versions = <(String, CreateRecipeVersionInput)>[];
  final deletes = <(String, int)>[];
  Future<Result<Recipe>> Function()? onWrite;

  @override
  Future<Result<Recipe>> active(String menuItemId) async {
    activeCalls++;
    return current == null
        ? const Error(
            Failure(
              type: FailureType.notFound,
              code: 'ACTIVE_RECIPE_NOT_FOUND',
              message: 'Không có công thức active',
            ),
          )
        : Success(current!);
  }

  @override
  Future<Result<MenuPage<RecipeSummary>>> history(
    String menuItemId,
    RecipeQuery query,
  ) async {
    historyQueries.add(query);
    return Success(page([uiSummary(historical)], index: query.page));
  }

  @override
  Future<Result<Recipe>> detail(String menuItemId, String recipeId) async {
    detailCalls++;
    return Success(historical);
  }

  @override
  Future<Result<Recipe>> create(String menuItemId, RecipeInput input) async {
    creates.add(input);
    return onWrite != null ? onWrite!() : Success(current ?? uiRecipe());
  }

  @override
  Future<Result<Recipe>> createVersion(
    String menuItemId,
    String activeRecipeId,
    CreateRecipeVersionInput input,
  ) async {
    versions.add((activeRecipeId, input));
    return onWrite != null ? onWrite!() : Success(current ?? uiRecipe());
  }

  @override
  Future<Result<void>> deactivate(
    String menuItemId,
    String recipeId,
    int expectedVersion,
  ) async {
    deletes.add((recipeId, expectedVersion));
    current = null;
    return const Success(null);
  }
}
