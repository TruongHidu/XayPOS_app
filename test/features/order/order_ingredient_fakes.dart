import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_recipe_snapshot.dart';
import 'package:pos_saas_app/features/order/domain/repositories/order_recipe_snapshot_repository.dart';
import 'package:pos_saas_app/features/order/data/dto/order_recipe_snapshot_dto.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/order_item_allocation.dart';
import 'package:pos_saas_app/features/inventory/domain/repositories/order_item_allocation_repository.dart';
import 'package:pos_saas_app/features/inventory/data/dto/order_item_allocation_dto.dart';

const ingredientReadPermissions = {
  'ORDER_VIEW',
  'RECIPE_VIEW',
  'INVENTORY_VIEW',
};
const ingredientReadFeatures = {
  'ORDER_MANAGEMENT',
  'RECIPE_MANAGEMENT',
  'INVENTORY_MANAGEMENT',
};
Map<String, dynamic> snapshotJson({
  String order = 'o1',
  String line = 'line1',
  String status = 'CAPTURED',
}) => {
  'orderId': order,
  'orderItemId': line,
  'snapshotStatus': status,
  'recipeId': status == 'CAPTURED' ? 'recipe-2' : null,
  'recipeVersion': status == 'CAPTURED' ? 2 : null,
  'yieldQuantity': status == 'CAPTURED' ? 10.000 : null,
  'yieldUnit': status == 'CAPTURED' ? 'phần' : null,
  'orderQuantity': 3.000,
  'orderUnit': 'phần',
  'capturedAt': {'LEGACY_UNAVAILABLE', 'NOT_SUBMITTED'}.contains(status)
      ? null
      : '2026-10-20T08:00:00Z',
  'ingredients': [
    if (status == 'CAPTURED')
      {
        'ingredientId': 'i1',
        'sku': 'BEEF',
        'name': 'Thịt bò đã chốt',
        'unit': 'g',
        'recipeQuantity': 1000.000,
        'wastePercent': 5.00,
        'trackInventory': true,
        'requiredQuantity': 315.000,
      },
    if (status == 'CAPTURED')
      {
        'ingredientId': 'i2',
        'sku': null,
        'name': 'Gia vị không theo dõi tồn',
        'unit': 'g',
        'recipeQuantity': 1.000,
        'wastePercent': 0.00,
        'trackInventory': false,
        'requiredQuantity': 0.300,
      },
  ],
};
Map<String, dynamic> allocationJson({
  String order = 'o1',
  String line = 'line1',
  String status = 'RESERVED',
  String reason = 'NO_TRACKED_INGREDIENTS',
}) => {
  'allocationId': status == 'NOT_SUBMITTED' ? null : 'a1',
  'orderId': order,
  'orderItemId': line,
  'recipeSnapshotId': {'NOT_SUBMITTED', 'SKIPPED'}.contains(status)
      ? null
      : 's1',
  'status': status,
  'skipReason': status == 'SKIPPED' ? reason : null,
  'warehouseId': {'NOT_SUBMITTED', 'SKIPPED'}.contains(status)
      ? null
      : 'warehouse-historical',
  'reservedAt': {'NOT_SUBMITTED', 'SKIPPED'}.contains(status)
      ? null
      : '2026-10-20T08:00:00Z',
  'consumedAt': status == 'CONSUMED' ? '2026-10-20T08:05:00Z' : null,
  'releasedAt': status == 'RELEASED' ? '2026-10-20T08:05:00Z' : null,
  'ingredients': [
    if (!{'NOT_SUBMITTED', 'SKIPPED'}.contains(status))
      {
        'reservationId': 'reservation-1',
        'recipeUsageId': 'usage-1',
        'ingredientId': 'i1',
        'sku': 'BEEF',
        'name': 'Thịt bò đã chốt',
        'unit': 'g',
        'quantity': 315.000,
      },
  ],
};

class FakeOrderSnapshots implements OrderRecipeSnapshotRepository {
  final calls = <(String, String)>[];
  Future<Result<OrderRecipeSnapshot>> Function(String, String)? onGet;
  Map<String, dynamic> value = snapshotJson();
  @override
  Future<Result<OrderRecipeSnapshot>> get(
    String orderId,
    String orderItemId,
  ) async {
    calls.add((orderId, orderItemId));
    return onGet != null
        ? onGet!(orderId, orderItemId)
        : Success(OrderRecipeSnapshotDto.parse(value));
  }
}

class FakeOrderAllocations implements OrderItemAllocationRepository {
  final calls = <(String, String)>[];
  Future<Result<OrderItemAllocation>> Function(String, String)? onGet;
  Map<String, dynamic> value = allocationJson();
  @override
  Future<Result<OrderItemAllocation>> get(
    String orderId,
    String orderItemId,
  ) async {
    calls.add((orderId, orderItemId));
    return onGet != null
        ? onGet!(orderId, orderItemId)
        : Success(OrderItemAllocationDto.parse(value));
  }
}
