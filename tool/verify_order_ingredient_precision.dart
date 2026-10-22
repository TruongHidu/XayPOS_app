import 'package:pos_saas_app/core/network/exact_json.dart';
import 'package:pos_saas_app/features/order/data/dto/order_recipe_snapshot_dto.dart';
import 'package:pos_saas_app/features/inventory/data/dto/order_item_allocation_dto.dart';

void main() {
  final snapshot = OrderRecipeSnapshotDto.parse(
    decodeExactJson(r'''{
    "orderId":"o1","orderItemId":"line1","snapshotStatus":"CAPTURED",
    "recipeId":"r1","recipeVersion":2,"yieldQuantity":10.000,"yieldUnit":"phần",
    "orderQuantity":3.000,"orderUnit":"phần","capturedAt":"2026-10-20T08:00:00Z",
    "ingredients":[{"ingredientId":"i1","sku":null,"name":"Nguyên liệu lịch sử",
      "unit":"g","recipeQuantity":0.001,"wastePercent":0.01,
      "trackInventory":true,"requiredQuantity":99999999999.999}]
  }'''),
  );
  check(
    snapshot.ingredients.single.requiredQuantity.scaled.toString() ==
        '99999999999999',
  );
  check(snapshot.ingredients.single.recipeQuantity.toString() == '0.001');
  check(snapshot.ingredients.single.wastePercent == 1);
  final allocation = OrderItemAllocationDto.parse(
    decodeExactJson(r'''{
    "allocationId":"a1","orderId":"o1","orderItemId":"line1","recipeSnapshotId":"s1",
    "status":"CONSUMED","skipReason":null,"warehouseId":"w-old",
    "reservedAt":"2026-10-20T08:00:00Z","consumedAt":"2026-10-20T08:05:00Z","releasedAt":null,
    "ingredients":[{"reservationId":"r1","recipeUsageId":"u1","ingredientId":"i1",
      "sku":null,"name":"Lịch sử","unit":"g","quantity":99999999999.999}]
  }'''),
  );
  check(allocation.ingredients.single.quantity.toString() == '99999999999.999');
}

void check(bool condition) {
  if (!condition) throw StateError('Order ingredient precision regression');
}
