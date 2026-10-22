import '../../../../core/values/ingredient_quantity.dart';

enum AllocationStatus {
  reserved('RESERVED', 'Đang giữ nguyên liệu'),
  consumed('CONSUMED', 'Đã tiêu thụ'),
  released('RELEASED', 'Đã giải phóng giữ chỗ'),
  skipped('SKIPPED', 'Không áp dụng quản lý kho'),
  notSubmitted('NOT_SUBMITTED', 'Món chưa gửi');

  const AllocationStatus(this.code, this.label);
  final String code, label;
}

enum AllocationSkipReason {
  inventoryDisabled(
    'INVENTORY_FEATURE_DISABLED',
    'Chưa bật tính năng kho tại thời điểm chấp nhận món.',
  ),
  noRecipe('SNAPSHOT_NO_RECIPE', 'Khi gửi món chưa có công thức.'),
  recipeDisabled(
    'SNAPSHOT_FEATURE_DISABLED',
    'Khi gửi món chưa bật tính năng công thức.',
  ),
  noTrackedIngredients(
    'NO_TRACKED_INGREDIENTS',
    'Không có nguyên liệu cần theo dõi tồn.',
  ),
  legacyUnavailable(
    'LEGACY_UNAVAILABLE',
    'Dòng món cũ chưa có dữ liệu giữ/tiêu thụ nguyên liệu.',
  );

  const AllocationSkipReason(this.code, this.label);
  final String code, label;
}

class OrderItemAllocation {
  OrderItemAllocation({
    required this.orderId,
    required this.orderItemId,
    required this.id,
    required this.recipeSnapshotId,
    required this.status,
    required this.skipReason,
    required this.warehouseId,
    required this.reservedAt,
    required this.consumedAt,
    required this.releasedAt,
    required List<AllocationIngredient> ingredients,
  }) : ingredients = List.unmodifiable(ingredients);
  final String orderId, orderItemId;
  final String? id, recipeSnapshotId, warehouseId;
  final AllocationStatus status;
  final AllocationSkipReason? skipReason;
  final DateTime? reservedAt, consumedAt, releasedAt;
  final List<AllocationIngredient> ingredients;
}

class AllocationIngredient {
  const AllocationIngredient({
    required this.reservationId,
    required this.recipeUsageId,
    required this.ingredientId,
    required this.sku,
    required this.name,
    required this.unit,
    required this.quantity,
  });
  final String reservationId, recipeUsageId, ingredientId, name, unit;
  final String? sku;
  final IngredientQuantity quantity;
}
