import '../../domain/entities/ingredient.dart';
import '../../domain/entities/menu_price.dart';

class IngredientDto {
  const IngredientDto._(this._entity);
  final Ingredient _entity;

  factory IngredientDto.fromJson(Object? value) {
    final json = _object(value);
    final costPriceRaw = json['costPrice'];
    if (costPriceRaw is! num) {
      throw const FormatException('Invalid costPrice in ingredient');
    }
    final price = MenuPrice.fromNumber(costPriceRaw);

    return IngredientDto._(
      Ingredient(
        id: _string(json, 'id'),
        sku: _nullableString(json, 'sku'),
        name: _string(json, 'name'),
        baseUnit: _string(json, 'baseUnit'),
        description: _nullableString(json, 'description'),
        costPrice: price,
        costConfigured: _boolean(json, 'costConfigured'),
        trackInventory: _boolean(json, 'trackInventory'),
        active: _boolean(json, 'active'),
        version: _integer(json, 'version'),
        createdAt: _date(json, 'createdAt'),
        updatedAt: _date(json, 'updatedAt'),
      ),
    );
  }

  Ingredient toEntity() => _entity;
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected ingredient JSON object');
  }
  return value;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing or empty string for $key');
  }
  return value.trim();
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid string for $key');
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _boolean(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Invalid boolean for $key');
  return value;
}

int _integer(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw FormatException('Invalid integer for $key');
  }
  return value;
}

DateTime _date(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('Invalid date for $key');
  return DateTime.parse(value);
}
