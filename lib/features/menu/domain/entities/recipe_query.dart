class RecipeQuery {
  const RecipeQuery({
    this.page = 0,
    this.size = 20,
    this.sortBy = 'recipeVersion',
    this.direction = 'desc',
  });

  final int page;
  final int size;
  final String sortBy;
  final String direction;

  static const allowedSortBy = {'recipeVersion', 'createdAt', 'updatedAt'};

  bool get isValid =>
      page >= 0 &&
      size >= 1 &&
      size <= 100 &&
      allowedSortBy.contains(sortBy) &&
      const {'asc', 'desc'}.contains(direction);

  RecipeQuery copyWith({
    int? page,
    int? size,
    String? sortBy,
    String? direction,
  }) => RecipeQuery(
    page: page ?? this.page,
    size: size ?? this.size,
    sortBy: sortBy ?? this.sortBy,
    direction: direction ?? this.direction,
  );
}
