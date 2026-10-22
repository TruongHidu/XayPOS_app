import '../../../../core/network/read_json.dart';
import '../../domain/entities/order_item_allocation.dart';

abstract final class OrderItemAllocationDto {
  static OrderItemAllocation parse(Object? raw) {
    final j = ReadJson.object(raw);
    final ingredients = ReadJson.list(j, 'ingredients').map((raw) {
      final row = ReadJson.object(raw);
      return AllocationIngredient(
        reservationId: ReadJson.text(row, 'reservationId'),
        recipeUsageId: ReadJson.text(row, 'recipeUsageId'),
        ingredientId: ReadJson.text(row, 'ingredientId'),
        sku: ReadJson.optionalText(row, 'sku'),
        name: ReadJson.text(row, 'name'),
        unit: ReadJson.text(row, 'unit'),
        quantity: ReadJson.quantity(row, 'quantity', positive: true),
      );
    }).toList();
    final value = OrderItemAllocation(
      orderId: ReadJson.text(j, 'orderId'),
      orderItemId: ReadJson.text(j, 'orderItemId'),
      id: ReadJson.optionalText(j, 'allocationId'),
      recipeSnapshotId: ReadJson.optionalText(j, 'recipeSnapshotId'),
      status: ReadJson.enumeration(
        j['status'],
        AllocationStatus.values,
        (e) => e.code,
      ),
      skipReason: j['skipReason'] == null
          ? null
          : ReadJson.enumeration<AllocationSkipReason>(
              j['skipReason'],
              AllocationSkipReason.values,
              (e) => e.code,
            ),
      warehouseId: ReadJson.optionalText(j, 'warehouseId'),
      reservedAt: ReadJson.date(j, 'reservedAt'),
      consumedAt: ReadJson.date(j, 'consumedAt'),
      releasedAt: ReadJson.date(j, 'releasedAt'),
      ingredients: ingredients,
    );
    final notSubmitted = value.status == AllocationStatus.notSubmitted;
    final skipped = value.status == AllocationStatus.skipped;
    if (notSubmitted
        ? value.id != null ||
              value.recipeSnapshotId != null ||
              value.skipReason != null
        : value.id == null) {
      throw const FormatException('Invalid allocation identity');
    }
    if (skipped != (value.skipReason != null)) {
      throw const FormatException('Invalid allocation skip reason');
    }
    if (skipped || notSubmitted) {
      if (value.warehouseId != null ||
          value.reservedAt != null ||
          value.consumedAt != null ||
          value.releasedAt != null ||
          ingredients.isNotEmpty) {
        throw const FormatException('Invalid skipped/unsubmitted allocation');
      }
    } else if (value.recipeSnapshotId == null ||
        value.warehouseId == null ||
        value.reservedAt == null ||
        ingredients.isEmpty ||
        (value.status == AllocationStatus.consumed) !=
            (value.consumedAt != null) ||
        (value.status == AllocationStatus.released) !=
            (value.releasedAt != null)) {
      throw const FormatException('Invalid allocation lifecycle');
    }
    if (ingredients.map((e) => e.ingredientId).toSet().length !=
            ingredients.length ||
        ingredients.map((e) => e.reservationId).toSet().length !=
            ingredients.length ||
        ingredients.map((e) => e.recipeUsageId).toSet().length !=
            ingredients.length) {
      throw const FormatException('Duplicate allocation ingredient');
    }
    return value;
  }
}
