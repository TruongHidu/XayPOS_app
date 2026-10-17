import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_amount.dart';

/// Recipe labels and units are server snapshots, preserved without catalog reads.
class RecipeDto {
  const RecipeDto._(this._entity);
  final Recipe _entity;

  factory RecipeDto.fromJson(Object? value) {
    final json = _object(value);
    final rawIngredients = json['ingredients'];
    if (rawIngredients is! List ||
        rawIngredients.isEmpty ||
        rawIngredients.length > 100) {
      throw const FormatException('Invalid recipe ingredients');
    }
    final ingredients = rawIngredients
        .map((line) => RecipeIngredientDto.fromJson(line).toEntity())
        .toList();
    if (ingredients.map((line) => line.ingredientId).toSet().length !=
        ingredients.length) {
      throw const FormatException('Duplicate recipe ingredient');
    }
    return RecipeDto._(
      Recipe(
        id: _string(json, 'id'),
        menuItemId: _string(json, 'menuItemId'),
        recipeVersion: _integer(json, 'recipeVersion', minimum: 1),
        yieldQuantity: _quantity(json, 'yieldQuantity'),
        yieldUnit: _string(json, 'yieldUnit'),
        active: _boolean(json, 'active'),
        ingredients: ingredients,
        version: _integer(json, 'version'),
        createdAt: _date(json, 'createdAt'),
        updatedAt: _date(json, 'updatedAt'),
      ),
    );
  }

  Recipe toEntity() => _entity;
}

class RecipeIngredientDto {
  const RecipeIngredientDto._(this._entity);
  final RecipeIngredient _entity;

  factory RecipeIngredientDto.fromJson(Object? value) {
    final json = _object(value);
    final waste = json['wastePercent'];
    if (waste is! num) {
      throw const FormatException('Invalid recipe wastePercent');
    }
    return RecipeIngredientDto._(
      RecipeIngredient(
        id: _string(json, 'id'),
        ingredientId: _string(json, 'ingredientId'),
        sku: _nullableString(json, 'sku'),
        name: _string(json, 'name'),
        unit: _string(json, 'unit'),
        quantity: _quantity(json, 'quantity'),
        wastePercent: RecipeWastePercent.fromNumber(waste),
      ),
    );
  }

  RecipeIngredient toEntity() => _entity;
}

/// History lists contain summaries and never require ingredient detail payloads.
class RecipeSummaryDto {
  const RecipeSummaryDto._(this._entity);
  final RecipeSummary _entity;

  factory RecipeSummaryDto.fromJson(Object? value) {
    final json = _object(value);
    final count = _integer(json, 'ingredientCount', minimum: 1);
    if (count > 100) throw const FormatException('Invalid ingredientCount');
    return RecipeSummaryDto._(
      RecipeSummary(
        id: _string(json, 'id'),
        menuItemId: _string(json, 'menuItemId'),
        recipeVersion: _integer(json, 'recipeVersion', minimum: 1),
        yieldQuantity: _quantity(json, 'yieldQuantity'),
        yieldUnit: _string(json, 'yieldUnit'),
        active: _boolean(json, 'active'),
        ingredientCount: count,
        version: _integer(json, 'version'),
        createdAt: _date(json, 'createdAt'),
        updatedAt: _date(json, 'updatedAt'),
      ),
    );
  }

  RecipeSummary toEntity() => _entity;
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected recipe JSON object');
  }
  return value;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $key');
  }
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value != null && value is! String) throw FormatException('Invalid $key');
  return value as String?;
}

int _integer(Map<String, dynamic> json, String key, {int minimum = 0}) {
  final value = json[key];
  if (value is! int || value < minimum) throw FormatException('Invalid $key');
  return value;
}

bool _boolean(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Invalid $key');
  return value;
}

RecipeQuantity _quantity(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) throw FormatException('Invalid $key');
  return RecipeQuantity.fromNumber(value);
}

DateTime _date(Map<String, dynamic> json, String key) {
  final text = _string(json, key);
  final date = DateTime.tryParse(text);
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-](\d{2}):(\d{2}))$',
  ).firstMatch(text);
  if (date == null || match == null) throw FormatException('Invalid $key');
  int part(int index) => int.parse(match.group(index) ?? '0');
  final days = DateTime.utc(part(1), part(2) + 1, 0).day;
  if (part(2) < 1 ||
      part(2) > 12 ||
      part(3) < 1 ||
      part(3) > days ||
      part(4) > 23 ||
      part(5) > 59 ||
      part(6) > 59 ||
      part(7) > 23 ||
      part(8) > 59) {
    throw FormatException('Invalid $key');
  }
  return date;
}
