import '../../domain/entities/ingredient_inputs.dart';
import '../../domain/entities/ingredient_query.dart';

abstract final class IngredientRequests {
  static Map<String, dynamic> query(IngredientQuery q) => {
    if (q.q.trim().isNotEmpty) 'q': q.q.trim(),
    if (q.active != null) 'active': q.active,
    if (q.trackInventory != null) 'trackInventory': q.trackInventory,
    'page': q.page,
    'size': q.size,
    'sortBy': q.sortBy,
    'direction': q.direction,
  };

  static Map<String, dynamic> create(CreateIngredientInput input) {
    final sku = input.sku?.trim().toUpperCase();
    final desc = input.description?.trim();
    return {
      'name': input.name.trim(),
      'baseUnit': input.baseUnit.trim(),
      if (sku != null && sku.isNotEmpty) 'sku': sku,
      if (desc != null && desc.isNotEmpty) 'description': desc,
      if (input.costPrice != null) 'costPrice': input.costPrice!.toNumber(),
      if (input.costConfigured != null) 'costConfigured': input.costConfigured,
      'trackInventory': input.trackInventory,
      'active': input.active,
    };
  }

  static Map<String, dynamic> update(UpdateIngredientInput input) => {
    if (input.name != null) 'name': input.name!.trim(),
    if (input.baseUnit != null) 'baseUnit': input.baseUnit!.trim(),
    if (input.sku != null) 'sku': input.sku!.trim().toUpperCase(),
    if (input.description != null) 'description': input.description!.trim(),
    if (input.costPrice != null) 'costPrice': input.costPrice!.toNumber(),
    if (input.costConfigured != null) 'costConfigured': input.costConfigured,
    if (input.trackInventory != null) 'trackInventory': input.trackInventory,
    'expectedVersion': input.expectedVersion,
  };
}
