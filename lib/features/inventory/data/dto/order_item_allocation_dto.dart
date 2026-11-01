import '../../../../core/network/read_json.dart';
import '../../../../core/values/item_type.dart';
import '../../domain/entities/order_item_allocation.dart';
import 'stock_item_ref_dto.dart';

abstract final class OrderItemAllocationDto {
  static OrderItemAllocation parse(Object? raw) {
    final j = ReadJson.object(raw);
    final direct = j['directStockSnapshot'];
    if (direct != null && direct is! bool) {
      throw const FormatException('Invalid directStockSnapshot');
    }
    final directStock = direct == true;
    final ingredients = ReadJson.list(j, 'ingredients').map((raw) {
      final row = ReadJson.object(raw), stockItem = StockItemRefDto.parse(row);
      return AllocationIngredient(
        reservationId: ReadJson.text(row, 'reservationId'),
        recipeUsageId: ReadJson.optionalText(row, 'recipeUsageId'),
        stockItemId: stockItem.stockItemId,
        itemType: stockItem.itemType,
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
      directStock: directStock,
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
    if (ingredients.any(
      (e) => directStock
          ? e.itemType != ItemType.menuItem || e.recipeUsageId != null
          : e.recipeUsageId == null,
    )) {
      throw const FormatException('Invalid allocation stock line');
    }
    final usages = ingredients.map((e) => e.recipeUsageId).nonNulls;
    if (ingredients.map((e) => e.stockItemId).toSet().length !=
            ingredients.length ||
        ingredients.map((e) => e.reservationId).toSet().length !=
            ingredients.length ||
        usages.toSet().length != usages.length) {
      throw const FormatException('Duplicate allocation ingredient');
    }
    return value;
  }
}
