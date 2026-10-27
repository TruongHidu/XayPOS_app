import '../entities/ingredient_inputs.dart';
import 'menu_validation.dart';

abstract final class IngredientValidation {
  static String? name(String? value) =>
      MenuValidation.text(value ?? '', max: 150, required: true);

  static String? sku(String? value) =>
      MenuValidation.text(value ?? '', max: 80);

  static String? baseUnit(String? value) =>
      MenuValidation.text(value ?? '', max: 30, required: true);

  static String? costPrice(String? value) =>
      MenuValidation.optionalPrice(value);

  static String? description(String? value) =>
      MenuValidation.text(value ?? '', max: 10000);

  static Map<String, String> create(CreateIngredientInput input) => _errors({
    'name': name(input.name),
    'baseUnit': baseUnit(input.baseUnit),
    'sku': sku(input.sku),
    'description': description(input.description),
    'costPrice': MenuValidation.referenceCost(
      input.costPrice,
      input.costConfigured,
      creating: true,
    ),
  });

  static Map<String, String> patch(UpdateIngredientInput input) => _errors({
    'name': input.name == null ? null : name(input.name),
    'baseUnit': input.baseUnit == null ? null : baseUnit(input.baseUnit),
    'sku': sku(input.sku),
    'description': description(input.description),
    'costPrice': MenuValidation.referenceCost(
      input.costPrice,
      input.costConfigured,
      creating: false,
    ),
    'expectedVersion': input.expectedVersion < 0
        ? 'Version không hợp lệ.'
        : null,
  });

  static Map<String, String> _errors(Map<String, String?> fields) => {
    for (final entry in fields.entries)
      if (entry.value != null) entry.key: entry.value!,
  };
}
