import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_page.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_amount.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_query.dart';
import 'package:pos_saas_app/features/menu/domain/repositories/recipe_repository.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_cost_estimate.dart';
import 'recipe_cost_fakes.dart' show estimateForRecipe;

const recipePermissions = {
  'RECIPE_VIEW',
  'RECIPE_CREATE',
  'RECIPE_UPDATE',
  'RECIPE_DELETE',
};

Recipe stateRecipe({
  String id = 'recipe-7',
  String menuItemId = 'item-1',
  int recipeVersion = 7,
  int version = 2,
  bool active = true,
  List<RecipeIngredient>? ingredients,
}) => Recipe(
  id: id,
  menuItemId: menuItemId,
  recipeVersion: recipeVersion,
  yieldQuantity: RecipeQuantity.parse('10'),
  yieldUnit: 'tô',
  active: active,
  ingredients:
      ingredients ??
      [
        for (final id in ['ingredient-1', 'ingredient-2'])
          RecipeIngredient(
            id: 'line-$id',
            ingredientId: id,
            sku: 'NL-$id',
            name: 'Tên snapshot $id',
            unit: 'g',
            quantity: RecipeQuantity.parse('1200'),
            wastePercent: RecipeWastePercent.zero,
          ),
      ],
  version: version,
  createdAt: DateTime.utc(2026, 10, 16),
  updatedAt: DateTime.utc(2026, 10, 16),
);

RecipeInput stateInput({bool reversed = false, String yieldQuantity = '11'}) =>
    RecipeInput(
      yieldQuantity: RecipeQuantity.parse(yieldQuantity),
      ingredients: [
        for (final id
            in reversed
                ? ['ingredient-2', 'ingredient-1']
                : ['ingredient-1', 'ingredient-2'])
          RecipeIngredientInput(
            ingredientId: id,
            quantity: RecipeQuantity.parse('1200.000'),
          ),
      ],
    );

MenuPage<RecipeSummary> recipeStatePage({
  int page = 0,
  int totalPages = 1,
  String id = 'summary-1',
}) => MenuPage(
  content: [
    RecipeSummary(
      id: id,
      menuItemId: 'item-1',
      recipeVersion: 7,
      yieldQuantity: RecipeQuantity.parse('10'),
      yieldUnit: 'tô',
      active: true,
      ingredientCount: 2,
      version: 2,
      createdAt: DateTime.utc(2026, 10, 16),
      updatedAt: DateTime.utc(2026, 10, 16),
    ),
  ],
  page: page,
  size: 20,
  totalElements: totalPages,
  totalPages: totalPages,
);

class FakeRecipeStateRepository implements RecipeRepository {
  @override
  Future<Result<RecipeCostEstimate>> costEstimate(
    String menuItemId,
    String recipeId,
  ) async => Success(estimateForRecipe(current));
  Recipe current = stateRecipe();
  final activeIds = <String>[];
  final detailIds = <(String, String)>[];
  final historyQueries = <(String, RecipeQuery)>[];
  final creates = <(String, RecipeInput)>[];
  final versions = <(String, String, CreateRecipeVersionInput)>[];
  final deactivations = <(String, String, int)>[];
  Future<Result<Recipe>> Function()? onActive;
  Future<Result<MenuPage<RecipeSummary>>> Function(RecipeQuery)? onHistory;
  Future<Result<Recipe>> Function(String)? onDetail;
  Future<Result<Recipe>> Function()? onCreate;
  Future<Result<Recipe>> Function()? onVersion;
  Future<Result<void>> Function()? onDeactivate;

  @override
  Future<Result<Recipe>> active(String menuItemId) async {
    activeIds.add(menuItemId);
    return onActive != null ? onActive!() : Success(current);
  }

  @override
  Future<Result<MenuPage<RecipeSummary>>> history(
    String menuItemId,
    RecipeQuery query,
  ) async {
    historyQueries.add((menuItemId, query));
    return onHistory != null
        ? onHistory!(query)
        : Success(recipeStatePage(page: query.page));
  }

  @override
  Future<Result<Recipe>> detail(String menuItemId, String recipeId) async {
    detailIds.add((menuItemId, recipeId));
    return onDetail != null ? onDetail!(recipeId) : Success(current);
  }

  @override
  Future<Result<Recipe>> create(String menuItemId, RecipeInput input) async {
    creates.add((menuItemId, input));
    return onCreate != null ? onCreate!() : Success(current);
  }

  @override
  Future<Result<Recipe>> createVersion(
    String menuItemId,
    String activeRecipeId,
    CreateRecipeVersionInput input,
  ) async {
    versions.add((menuItemId, activeRecipeId, input));
    return onVersion != null ? onVersion!() : Success(current);
  }

  @override
  Future<Result<void>> deactivate(
    String menuItemId,
    String recipeId,
    int expectedVersion,
  ) async {
    deactivations.add((menuItemId, recipeId, expectedVersion));
    return onDeactivate != null ? onDeactivate!() : const Success(null);
  }
}
