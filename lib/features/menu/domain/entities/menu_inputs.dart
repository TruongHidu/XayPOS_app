import 'menu_group.dart';
import 'menu_item.dart';
import 'menu_price.dart';

class CreateMenuGroupInput {
  const CreateMenuGroupInput({
    required this.name,
    required this.displayOrder,
    this.active = true,
  });
  final String name;
  final int displayOrder;
  final bool active;
}

class UpdateMenuGroupInput {
  const UpdateMenuGroupInput({
    required this.expectedVersion,
    this.name,
    this.displayOrder,
  });
  final int expectedVersion;
  final String? name;
  final int? displayOrder;
  bool get isEmpty => name == null && displayOrder == null;

  factory UpdateMenuGroupInput.changes(
    MenuGroup baseline, {
    required String name,
    required int displayOrder,
  }) => UpdateMenuGroupInput(
    expectedVersion: baseline.version,
    name: name.trim() == baseline.name ? null : name.trim(),
    displayOrder: displayOrder == baseline.displayOrder ? null : displayOrder,
  );
}

class CreateMenuItemInput {
  const CreateMenuItemInput({
    required this.name,
    required this.baseUnit,
    required this.salePrice,
    this.costPrice,
    this.costConfigured,
    this.recipeEnabled = false,
    this.groupId,
    this.sku,
    this.description,
    this.imageUrl,
    this.active = true,
  });
  final String name;
  final String baseUnit;
  final MenuPrice salePrice;
  final MenuPrice? costPrice;
  final bool? costConfigured;
  final bool recipeEnabled;
  final String? groupId;
  final String? sku;
  final String? description;
  final String? imageUrl;
  final bool active;
}

class UpdateMenuItemInput {
  const UpdateMenuItemInput({
    required this.expectedVersion,
    this.name,
    this.baseUnit,
    this.salePrice,
    this.costPrice,
    this.costConfigured,
    this.recipeEnabled,
    this.sku,
    this.description,
    this.imageUrl,
  });
  final int expectedVersion;
  final String? name;
  final String? baseUnit;
  final MenuPrice? salePrice;

  /// Null omits this PATCH field; any supplied value explicitly configures it.
  final MenuPrice? costPrice;
  final bool? costConfigured;
  final bool? recipeEnabled;
  final String? sku;
  final String? description;
  final String? imageUrl;
  bool get isEmpty =>
      name == null &&
      baseUnit == null &&
      salePrice == null &&
      costPrice == null &&
      costConfigured == null &&
      recipeEnabled == null &&
      sku == null &&
      description == null &&
      imageUrl == null;

  factory UpdateMenuItemInput.changes(
    MenuItem baseline, {
    required String name,
    required String baseUnit,
    required MenuPrice salePrice,
    MenuPrice? costPrice,
    bool? costConfigured,
    bool? recipeEnabled,
    required String sku,
    required String description,
    required String imageUrl,
  }) => UpdateMenuItemInput(
    expectedVersion: baseline.version,
    name: name.trim() == baseline.name ? null : name.trim(),
    baseUnit: baseUnit.trim() == baseline.baseUnit ? null : baseUnit.trim(),
    salePrice: salePrice == baseline.salePrice ? null : salePrice,
    // Presence carries user intent even if a stored, unconfirmed zero is equal.
    costPrice: costPrice,
    costConfigured: costConfigured,
    recipeEnabled: recipeEnabled,
    sku: sku.trim() == (baseline.sku ?? '') ? null : sku.trim(),
    description: description.trim() == (baseline.description ?? '')
        ? null
        : description.trim(),
    imageUrl: imageUrl.trim() == (baseline.imageUrl ?? '')
        ? null
        : imageUrl.trim(),
  );
}
