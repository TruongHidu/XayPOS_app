import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/menu/data/dto/recipe_cost_estimate_dto.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_cost_estimate.dart';
import 'recipe_ui_fakes.dart';

Map<String, dynamic> recipeCostJson({
  String menu = 'i1',
  String recipe = 'r7',
  bool active = true,
  String unit = 'tô',
  num cost = 36900,
  num total = 369000,
  String currency = 'VND',
  bool zero = false,
}) => {
  'menuItemId': menu,
  'recipeId': recipe,
  'recipeVersion': 2,
  'recipeActive': active,
  'yieldQuantity': 10.000,
  'yieldUnit': unit,
  'currencyCode': currency,
  'costSource': 'INGREDIENT_COST_PRICE',
  'totalBatchCost': zero ? 0 : total,
  'costPerYieldUnit': zero ? 0 : cost,
  'ingredients': [
    {
      'ingredientId': 'ingredient-1',
      'sku': 'NL-THIT-BO',
      'name': 'Thịt bò',
      'unit': 'g',
      'quantity': 1200.000,
      'wastePercent': 5.00,
      'grossQuantity': 1260.000,
      'unitCost': zero ? 0 : 250.00,
      'lineCost': zero ? 0 : 315000.00,
    },
    {
      'ingredientId': 'ingredient-2',
      'sku': 'NL-BANH-PHO',
      'name': 'Bánh phở',
      'unit': 'g',
      'quantity': 1800.000,
      'wastePercent': 0.00,
      'grossQuantity': 1800.000,
      'unitCost': zero ? 0 : 30.00,
      'lineCost': zero ? 0 : 54000.00,
    },
  ],
  'warnings': [
    if (zero)
      for (final id in ['ingredient-1', 'ingredient-2'])
        {
          'code': 'ZERO_INGREDIENT_REFERENCE_COST',
          'ingredientId': id,
          'message': 'Nguyên liệu đang có giá vốn tham chiếu bằng 0',
        },
  ],
  'estimatedAt': '2026-10-19T08:00:00Z',
};

RecipeCostEstimate estimateForRecipe(Recipe recipe) =>
    RecipeCostEstimateDto.fromJson(
      recipeCostJson(
        menu: recipe.menuItemId,
        recipe: recipe.id,
        active: recipe.active,
        unit: recipe.yieldUnit,
      )..['recipeVersion'] = recipe.recipeVersion,
    );

class CostRecipes extends UiRecipes {
  final costCalls = <(String, String)>[];
  Future<Result<RecipeCostEstimate>> Function(String, String)? onCost;
  @override
  Future<Result<RecipeCostEstimate>> costEstimate(
    String menuItemId,
    String recipeId,
  ) async {
    costCalls.add((menuItemId, recipeId));
    return onCost != null
        ? onCost!(menuItemId, recipeId)
        : Success(
            estimateForRecipe(
              recipeId == historical.id ? historical : current!,
            ),
          );
  }
}
