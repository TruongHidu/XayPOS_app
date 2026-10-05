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
    this.sku,
    this.description,
    this.imageUrl,
  });
  final int expectedVersion;
  final String? name;
  final String? baseUnit;
  final MenuPrice? salePrice;

  /// Null omits this PATCH field; an explicit zero resets the stored cost.
  final MenuPrice? costPrice;
  final String? sku;
  final String? description;
  final String? imageUrl;
  bool get isEmpty =>
      name == null &&
      baseUnit == null &&
      salePrice == null &&
      costPrice == null &&
      sku == null &&
      description == null &&
      imageUrl == null;

  factory UpdateMenuItemInput.changes(
    MenuItem baseline, {
    required String name,
    required String baseUnit,
    required MenuPrice salePrice,
    MenuPrice? costPrice,
    required String sku,
    required String description,
    required String imageUrl,
  }) => UpdateMenuItemInput(
    expectedVersion: baseline.version,
    name: name.trim() == baseline.name ? null : name.trim(),
    baseUnit: baseUnit.trim() == baseline.baseUnit ? null : baseUnit.trim(),
    salePrice: salePrice == baseline.salePrice ? null : salePrice,
    costPrice: costPrice == baseline.costPrice ? null : costPrice,
    sku: sku.trim() == (baseline.sku ?? '') ? null : sku.trim(),
    description: description.trim() == (baseline.description ?? '')
        ? null
        : description.trim(),
    imageUrl: imageUrl.trim() == (baseline.imageUrl ?? '')
        ? null
        : imageUrl.trim(),
  );
}
