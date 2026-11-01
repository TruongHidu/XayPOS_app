import '../../../../core/values/item_type.dart';
import 'inventory_quantity.dart';

class Warehouse {
  const Warehouse({
    required this.id,
    required this.code,
    required this.name,
    required this.isDefault,
    required this.active,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id, code, name;
  final bool isDefault, active;
  final int version;
  final DateTime createdAt, updatedAt;
}

class InventoryBalance {
  const InventoryBalance({
    required this.balanceId,
    required this.configured,
    required this.warehouseId,
    required this.warehouseCode,
    required this.stockItemId,
    required this.itemType,
    required this.ingredientSku,
    required this.ingredientName,
    required this.baseUnit,
    required this.ingredientActive,
    required this.quantity,
    required this.reservedQuantity,
    required this.availableQuantity,
    required this.minQuantity,
    required this.lowStock,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });
  final String? balanceId, ingredientSku;
  final String warehouseId,
      warehouseCode,
      stockItemId,
      ingredientName,
      baseUnit;
  final ItemType itemType;
  final bool configured, ingredientActive, lowStock;
  final InventoryQuantity quantity,
      reservedQuantity,
      availableQuantity,
      minQuantity;
  final int? version;
  final DateTime? createdAt, updatedAt;
  String get key => '$warehouseId:$stockItemId';
}

class InventoryPage<T> {
  InventoryPage({
    required List<T> content,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  }) : content = List.unmodifiable(content);
  final List<T> content;
  final int page, size, totalElements, totalPages;
}
