class ReportPage<T> {
  const ReportPage({
    required this.content,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });

  final List<T> content;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;

  /// The same totals over [rows], for lists that join several pages.
  ReportPage<T> withRows(List<T> rows, int page) => ReportPage(
    content: rows,
    page: page,
    size: size,
    totalElements: totalElements,
    totalPages: totalPages,
  );

  bool get isEmpty => content.isEmpty;
  bool get isNotEmpty => content.isNotEmpty;
  bool get hasNextPage => page < totalPages - 1;
  bool get hasPreviousPage => page > 0;

  int get number => page;
  bool get first => page == 0;
  bool get last => page >= totalPages - 1;
  bool get hasNext => hasNextPage;
  bool get hasPrevious => hasPreviousPage;
}
