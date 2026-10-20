class WarehouseQuery {
  const WarehouseQuery({
    this.q = '',
    this.active,
    this.page = 0,
    this.size = 20,
    this.sortBy = 'createdAt',
    this.direction = 'desc',
  });
  final String q, sortBy, direction;
  final bool? active;
  final int page, size;
  static const sorts = {'code', 'name', 'createdAt', 'updatedAt'};
  bool get valid =>
      q.length <= 100 &&
      page >= 0 &&
      size >= 1 &&
      size <= 100 &&
      sorts.contains(sortBy) &&
      const {'asc', 'desc'}.contains(direction);
  WarehouseQuery copyWith({
    String? q,
    bool? Function()? active,
    int? page,
    int? size,
    String? sortBy,
    String? direction,
  }) => WarehouseQuery(
    q: q ?? this.q,
    active: active == null ? this.active : active(),
    page: page ?? this.page,
    size: size ?? this.size,
    sortBy: sortBy ?? this.sortBy,
    direction: direction ?? this.direction,
  );
}

class InventoryBalanceQuery {
  const InventoryBalanceQuery({
    this.q = '',
    this.ingredientActive,
    this.page = 0,
    this.size = 20,
    this.sortBy = 'ingredientName',
    this.direction = 'asc',
  });
  final String q, sortBy, direction;
  final bool? ingredientActive;
  final int page, size;
  static const sorts = {
    'ingredientName',
    'sku',
    'quantity',
    'minQuantity',
    'updatedAt',
  };
  bool get valid =>
      q.length <= 100 &&
      page >= 0 &&
      size >= 1 &&
      size <= 100 &&
      sorts.contains(sortBy) &&
      const {'asc', 'desc'}.contains(direction);
  InventoryBalanceQuery copyWith({
    String? q,
    bool? Function()? ingredientActive,
    int? page,
    int? size,
    String? sortBy,
    String? direction,
  }) => InventoryBalanceQuery(
    q: q ?? this.q,
    ingredientActive: ingredientActive == null
        ? this.ingredientActive
        : ingredientActive(),
    page: page ?? this.page,
    size: size ?? this.size,
    sortBy: sortBy ?? this.sortBy,
    direction: direction ?? this.direction,
  );
}

class LowStockQuery {
  const LowStockQuery({
    this.warehouseId,
    this.filters = const InventoryBalanceQuery(sortBy: 'quantity'),
  });
  final String? warehouseId;
  final InventoryBalanceQuery filters;
}
