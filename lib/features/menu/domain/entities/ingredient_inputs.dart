import 'ingredient.dart';
import 'menu_price.dart';

class CreateIngredientInput {
  const CreateIngredientInput({
    required this.name,
    required this.baseUnit,
    this.sku,
    this.description,
    this.costPrice,
    this.costConfigured,
    this.trackInventory = false,
    this.active = true,
  });

  final String name;
  final String baseUnit;
  final String? sku;
  final String? description;
  final MenuPrice? costPrice;
  final bool? costConfigured;
  final bool trackInventory;
  final bool active;
}

class UpdateIngredientInput {
  const UpdateIngredientInput({
    required this.expectedVersion,
    this.name,
    this.baseUnit,
    this.sku,
    this.description,
    this.costPrice,
    this.costConfigured,
    this.trackInventory,
  });

  final int expectedVersion;
  final String? name;
  final String? baseUnit;
  final String? sku;
  final String? description;
  final MenuPrice? costPrice;
  final bool? costConfigured;
  final bool? trackInventory;

  bool get isEmpty =>
      name == null &&
      baseUnit == null &&
      sku == null &&
      description == null &&
      costPrice == null &&
      costConfigured == null &&
      trackInventory == null;

  factory UpdateIngredientInput.changes(
    Ingredient baseline, {
    required String name,
    required String baseUnit,
    required String sku,
    required String description,
    MenuPrice? costPrice,
    bool? costConfigured,
    required bool trackInventory,
  }) {
    final trimmedName = name.trim();
    final trimmedUnit = baseUnit.trim();
    final trimmedSku = sku.trim().toUpperCase();
    final trimmedDesc = description.trim();

    final nameChange = trimmedName == baseline.name ? null : trimmedName;
    final unitChange = trimmedUnit == baseline.baseUnit ? null : trimmedUnit;

    // SKU: if empty and baseline had SKU -> send "" to clear. If different -> send new.
    final String? skuChange;
    final baselineSku = baseline.sku?.trim().toUpperCase() ?? '';
    if (trimmedSku != baselineSku) {
      skuChange =
          trimmedSku; // Note: if trimmedSku is empty, it sends "" which tells backend to clear SKU
    } else {
      skuChange = null;
    }

    // Description: if empty and baseline had description -> send "" to clear.
    final String? descChange;
    final baselineDesc = baseline.description?.trim() ?? '';
    if (trimmedDesc != baselineDesc) {
      descChange = trimmedDesc; // "" means clear
    } else {
      descChange = null;
    }

    final trackChange = trackInventory == baseline.trackInventory
        ? null
        : trackInventory;

    return UpdateIngredientInput(
      expectedVersion: baseline.version,
      name: nameChange,
      baseUnit: unitChange,
      sku: skuChange,
      description: descChange,
      // An explicit equal value still confirms a formerly unknown reference cost.
      costPrice: costPrice,
      costConfigured: costConfigured,
      trackInventory: trackChange,
    );
  }
}
