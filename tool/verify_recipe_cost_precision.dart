import 'package:pos_saas_app/core/network/exact_json.dart';
import 'package:pos_saas_app/features/menu/data/dto/recipe_cost_estimate_dto.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_cost_amount.dart';

void main() {
  final value = RecipeCostEstimateDto.fromJson(
    decodeExactJson(r'''{
    "menuItemId":"m1","recipeId":"r1","recipeVersion":2,"recipeActive":false,
    "yieldQuantity":10.000,"yieldUnit":"tô","currencyCode":"VND",
    "costSource":"INGREDIENT_COST_PRICE","totalBatchCost":999999999999999999.99,
    "costPerYieldUnit":99999999999999999.99,
    "ingredients":[{"ingredientId":"i1","sku":null,"name":"Snapshot 12 \" 34",
      "unit":"g","quantity":0.001,"wastePercent":0.01,"grossQuantity":0.0010001,
      "unitCost":0.01,"lineCost":0.00}],"warnings":[],"estimatedAt":"2026-10-19T08:00:00Z"
  }'''),
  );
  check(value.totalBatchCost.cents.toString() == '99999999999999999999');
  check(value.costPerYieldUnit.cents.toString() == '9999999999999999999');
  check(value.ingredients.single.grossQuantity.toString() == '0.0010001');
  check(RecipeCostAmount.parse('1.0001e-3').toString() == '0.0010001');
  check(
    RecipeCostAmount.parse('1e18', money: true).cents.toString() ==
        '100000000000000000000',
  );
}

void check(bool condition) {
  if (!condition) throw StateError('Recipe cost precision regression');
}
