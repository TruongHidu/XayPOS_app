import '../../domain/entities/menu_inputs.dart';
import '../../domain/entities/menu_query.dart';

abstract final class MenuRequests {
  static Map<String, dynamic> query(MenuQuery q) => {
    if (q.q.trim().isNotEmpty) 'q': q.q.trim(),
    if (q.active != null) 'active': q.active,
    'page': q.page,
    'size': q.size,
    'sortBy': q.sortBy,
    'direction': q.direction,
    if (q.groupId != null) 'groupId': q.groupId,
    if (q.availabilityStatus != null)
      'availabilityStatus': q.availabilityStatus!.code,
    if (q.sellable != null) 'sellable': q.sellable,
  };
  static Map<String, dynamic> createGroup(CreateMenuGroupInput input) => {
    'name': input.name.trim(),
    'displayOrder': input.displayOrder,
    'active': input.active,
  };
  static Map<String, dynamic> updateGroup(UpdateMenuGroupInput input) => {
    if (input.name != null) 'name': input.name!.trim(),
    if (input.displayOrder != null) 'displayOrder': input.displayOrder,
    'expectedVersion': input.expectedVersion,
  };
  static Map<String, dynamic> createItem(CreateMenuItemInput input) => {
    'name': input.name.trim(),
    'baseUnit': input.baseUnit.trim(),
    'salePrice': input.salePrice.toNumber(),
    if (input.costPrice != null) 'costPrice': input.costPrice!.toNumber(),
    if (input.costConfigured != null) 'costConfigured': input.costConfigured,
    'recipeEnabled': input.recipeEnabled,
    'groupId': input.groupId,
    'sku': input.sku?.trim(),
    'description': input.description?.trim(),
    'imageUrl': input.imageUrl?.trim(),
    'active': input.active,
  };
  static Map<String, dynamic> updateItem(UpdateMenuItemInput input) => {
    if (input.name != null) 'name': input.name!.trim(),
    if (input.baseUnit != null) 'baseUnit': input.baseUnit!.trim(),
    if (input.salePrice != null) 'salePrice': input.salePrice!.toNumber(),
    if (input.costPrice != null) 'costPrice': input.costPrice!.toNumber(),
    if (input.costConfigured != null) 'costConfigured': input.costConfigured,
    if (input.recipeEnabled != null) 'recipeEnabled': input.recipeEnabled,
    if (input.sku != null) 'sku': input.sku!.trim(),
    if (input.description != null) 'description': input.description!.trim(),
    if (input.imageUrl != null) 'imageUrl': input.imageUrl!.trim(),
    'expectedVersion': input.expectedVersion,
  };
}
