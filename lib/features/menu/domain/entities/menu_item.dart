import 'menu_group.dart';
import 'menu_price.dart';

enum AvailabilityStatus {
  available('AVAILABLE'),
  outOfStock('OUT_OF_STOCK');

  const AvailabilityStatus(this.code);
  final String code;

  static AvailabilityStatus parse(String code) => switch (code) {
    'AVAILABLE' => available,
    'OUT_OF_STOCK' => outOfStock,
    _ => throw FormatException('Unknown availabilityStatus: $code'),
  };
}

class MenuItem {
  const MenuItem({
    required this.id,
    required this.group,
    required this.sku,
    required this.name,
    required this.baseUnit,
    required this.description,
    required this.imageUrl,
    required this.salePrice,
    this.costPrice,
    required this.active,
    required this.availabilityStatus,
    required this.sellable,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final MenuItemGroupSummary? group;
  final String? sku;
  final String name;
  final String baseUnit;
  final String? description;
  final String? imageUrl;
  final MenuPrice salePrice;

  /// Null means the response omitted this field, so the stored cost is unknown.
  /// An explicit JSON null is normalized to zero by the DTO.
  final MenuPrice? costPrice;
  final bool active;
  final AvailabilityStatus availabilityStatus;
  final bool sellable;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
}
