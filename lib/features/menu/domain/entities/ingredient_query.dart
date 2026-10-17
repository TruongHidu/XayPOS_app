class IngredientQuery {
  const IngredientQuery({
    this.q = '',
    this.active,
    this.trackInventory,
    this.page = 0,
    this.size = 20,
    this.sortBy = 'createdAt',
    this.direction = 'desc',
  });

  final String q;
  final bool? active;
  final bool? trackInventory;
  final int page;
  final int size;
  final String sortBy;
  final String direction;

  static const allowedSortBy = {
    'createdAt',
    'updatedAt',
    'name',
    'sku',
    'costPrice',
  };

  bool get hasFilters =>
      q.trim().isNotEmpty || active != null || trackInventory != null;

  bool get isValid =>
      q.trim().length <= 100 &&
      page >= 0 &&
      size >= 1 &&
      size <= 100 &&
      const {'asc', 'desc'}.contains(direction) &&
      allowedSortBy.contains(sortBy);

  IngredientQuery copyWith({
    String? q,
    bool? Function()? active,
    bool? Function()? trackInventory,
    int? page,
    int? size,
    String? sortBy,
    String? direction,
  }) => IngredientQuery(
    q: q ?? this.q,
    active: active != null ? active() : this.active,
    trackInventory: trackInventory != null
        ? trackInventory()
        : this.trackInventory,
    page: page ?? this.page,
    size: size ?? this.size,
    sortBy: sortBy ?? this.sortBy,
    direction: direction ?? this.direction,
  );
}
