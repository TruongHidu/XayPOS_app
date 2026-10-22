import '../../../../core/values/ingredient_quantity.dart';

enum RecipeSnapshotStatus {
  captured('CAPTURED', 'Đã chốt công thức'),
  noRecipe('NO_RECIPE', 'Khi gửi món chưa có công thức áp dụng'),
  featureDisabled(
    'FEATURE_DISABLED',
    'Khi gửi món chưa bật tính năng công thức',
  ),
  legacyUnavailable(
    'LEGACY_UNAVAILABLE',
    'Không có dữ liệu công thức lịch sử cho dòng món cũ',
  ),
  notSubmitted('NOT_SUBMITTED', 'Món chưa gửi, chưa chốt công thức');

  const RecipeSnapshotStatus(this.code, this.label);
  final String code, label;
}

class OrderRecipeSnapshot {
  OrderRecipeSnapshot({
    required this.orderId,
    required this.orderItemId,
    required this.status,
    required this.recipeId,
    required this.recipeVersion,
    required this.yieldQuantity,
    required this.yieldUnit,
    required this.orderQuantity,
    required this.orderUnit,
    required this.capturedAt,
    required List<OrderRecipeIngredient> ingredients,
  }) : ingredients = List.unmodifiable(ingredients);
  final String orderId, orderItemId, orderUnit;
  final RecipeSnapshotStatus status;
  final String? recipeId, yieldUnit;
  final int? recipeVersion;
  final IngredientQuantity? yieldQuantity;
  final IngredientQuantity orderQuantity;
  final DateTime? capturedAt;
  final List<OrderRecipeIngredient> ingredients;
}

class OrderRecipeIngredient {
  const OrderRecipeIngredient({
    required this.ingredientId,
    required this.sku,
    required this.name,
    required this.unit,
    required this.recipeQuantity,
    required this.wastePercent,
    required this.trackInventory,
    required this.requiredQuantity,
  });
  final String ingredientId, name, unit;
  final String? sku;
  final IngredientQuantity recipeQuantity, requiredQuantity;

  /// Hundredths of one percent, from 0 to 10000.
  final int wastePercent;
  final bool trackInventory;
}
