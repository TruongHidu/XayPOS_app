import '../../../../core/network/read_json.dart';
import '../../domain/entities/order_recipe_snapshot.dart';

abstract final class OrderRecipeSnapshotDto {
  static OrderRecipeSnapshot parse(Object? raw) {
    final j = ReadJson.object(raw);
    final status = ReadJson.enumeration(
      j['snapshotStatus'],
      RecipeSnapshotStatus.values,
      (e) => e.code,
    );
    final captured = status == RecipeSnapshotStatus.captured;
    final application = j['recipeEnabledSnapshot'];
    if (application != null && application is! bool) {
      throw const FormatException('Invalid snapshot application flag');
    }
    final ingredients = ReadJson.list(j, 'ingredients').map((raw) {
      final row = ReadJson.object(raw);
      if (row['trackInventory'] is! bool) {
        throw const FormatException('Invalid tracking flag');
      }
      final waste = ReadJson.quantity(row, 'wastePercent').scaled;
      if (waste > BigInt.from(100000) ||
          waste % BigInt.from(10) != BigInt.zero) {
        throw const FormatException('Invalid waste');
      }
      return OrderRecipeIngredient(
        ingredientId: ReadJson.text(row, 'ingredientId'),
        sku: ReadJson.optionalText(row, 'sku'),
        name: ReadJson.text(row, 'name'),
        unit: ReadJson.text(row, 'unit'),
        recipeQuantity: ReadJson.quantity(
          row,
          'recipeQuantity',
          positive: true,
        ),
        wastePercent: (waste ~/ BigInt.from(10)).toInt(),
        trackInventory: row['trackInventory'] as bool,
        requiredQuantity: ReadJson.quantity(
          row,
          'requiredQuantity',
          positive: true,
        ),
      );
    }).toList();
    final value = OrderRecipeSnapshot(
      orderId: ReadJson.text(j, 'orderId'),
      orderItemId: ReadJson.text(j, 'orderItemId'),
      status: status,
      recipeId: ReadJson.optionalText(j, 'recipeId'),
      recipeVersion: j['recipeVersion'] == null
          ? null
          : ReadJson.integer(j, 'recipeVersion'),
      yieldQuantity: j['yieldQuantity'] == null
          ? null
          : ReadJson.quantity(j, 'yieldQuantity', positive: true),
      yieldUnit: ReadJson.optionalText(j, 'yieldUnit'),
      orderQuantity: ReadJson.quantity(j, 'orderQuantity', positive: true),
      orderUnit: ReadJson.text(j, 'orderUnit'),
      capturedAt: ReadJson.date(j, 'capturedAt'),
      ingredients: ingredients,
      recipeEnabledSnapshot: application as bool?,
      costSourceSnapshot: j['costSourceSnapshot'] == null
          ? null
          : ReadJson.enumeration<RecipeCostSourceSnapshot>(
              j['costSourceSnapshot'],
              RecipeCostSourceSnapshot.values,
              (e) => e.code,
            ),
    );
    if (captured
        ? value.recipeId == null ||
              value.recipeVersion == null ||
              value.recipeVersion! < 1 ||
              value.yieldQuantity == null ||
              value.yieldUnit == null ||
              value.capturedAt == null ||
              ingredients.isEmpty
        : value.recipeId != null ||
              value.recipeVersion != null ||
              value.yieldQuantity != null ||
              value.yieldUnit != null ||
              ingredients.isNotEmpty) {
      throw const FormatException('Invalid recipe snapshot state');
    }
    if (ingredients.map((e) => e.ingredientId).toSet().length !=
            ingredients.length ||
        const {
              RecipeSnapshotStatus.legacyUnavailable,
              RecipeSnapshotStatus.notSubmitted,
            }.contains(status) &&
            value.capturedAt != null ||
        const {
              RecipeSnapshotStatus.noRecipe,
              RecipeSnapshotStatus.featureDisabled,
              RecipeSnapshotStatus.recipeDisabled,
            }.contains(status) &&
            value.capturedAt == null) {
      throw const FormatException('Invalid snapshot history');
    }
    // Nullable metadata belongs to old rows; never invent a source from today's menu.
    final source = value.costSourceSnapshot;
    if (const {
              RecipeSnapshotStatus.legacyUnavailable,
              RecipeSnapshotStatus.notSubmitted,
              RecipeSnapshotStatus.noRecipe,
            }.contains(status) &&
            (application != null || source != null) ||
        status == RecipeSnapshotStatus.recipeDisabled &&
            (application == true ||
                source == RecipeCostSourceSnapshot.recipe) ||
        const {
              RecipeSnapshotStatus.captured,
              RecipeSnapshotStatus.featureDisabled,
            }.contains(status) &&
            (application == false ||
                source == RecipeCostSourceSnapshot.manual)) {
      throw const FormatException('Invalid snapshot source decision');
    }
    return value;
  }
}
