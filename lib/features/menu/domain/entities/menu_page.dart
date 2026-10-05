class MenuPage<T> {
  MenuPage({
    required List<T> content,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  }) : content = List.unmodifiable(content);
  final List<T> content;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;
}
