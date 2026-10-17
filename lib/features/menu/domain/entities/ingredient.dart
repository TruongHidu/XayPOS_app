import 'menu_price.dart';

class Ingredient {
  const Ingredient({
    required this.id,
    required this.sku,
    required this.name,
    required this.baseUnit,
    required this.description,
    required this.costPrice,
    required this.trackInventory,
    required this.active,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String? sku;
  final String name;
  final String baseUnit;
  final String? description;
  final MenuPrice costPrice;
  final bool trackInventory;
  final bool active;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
}
