import 'stock_document.dart';

/// Inclusive instants. Day factories use local calendar boundaries, then UTC.
class StockDateRange {
  StockDateRange({this.from, this.to});
  factory StockDateRange.days(DateTime from, DateTime to) => StockDateRange(
    from: DateTime(from.year, from.month, from.day).toUtc(),
    to: DateTime(
      to.year,
      to.month,
      to.day + 1,
    ).toUtc().subtract(const Duration(microseconds: 1)),
  );
  final DateTime? from, to;
  bool get valid => from == null || to == null || !from!.isAfter(to!);
}

class StockDocumentQuery {
  const StockDocumentQuery({
    this.q = '',
    this.type,
    this.status,
    this.warehouseId,
    this.dates,
    this.page = 0,
    this.size = 20,
    this.sortBy = 'createdAt',
    this.direction = 'desc',
  });
  final String q, sortBy, direction;
  final String? warehouseId;
  final StockDocumentType? type;
  final StockDocumentStatus? status;
  final StockDateRange? dates;
  final int page, size;
  static const sorts = {
    'documentCode',
    'documentType',
    'status',
    'createdAt',
    'updatedAt',
    'totalCost',
  };
  bool get valid =>
      q.trim().length <= 100 &&
      page >= 0 &&
      size >= 1 &&
      size <= 100 &&
      sorts.contains(sortBy) &&
      const {'asc', 'desc'}.contains(direction) &&
      (dates?.valid ?? true);
  StockDocumentQuery copyWith({
    String? q,
    StockDocumentType? Function()? type,
    StockDocumentStatus? Function()? status,
    String? Function()? warehouseId,
    StockDateRange? Function()? dates,
    int? page,
    int? size,
    String? sortBy,
    String? direction,
  }) => StockDocumentQuery(
    q: q ?? this.q,
    type: type == null ? this.type : type(),
    status: status == null ? this.status : status(),
    warehouseId: warehouseId == null ? this.warehouseId : warehouseId(),
    dates: dates == null ? this.dates : dates(),
    page: page ?? this.page,
    size: size ?? this.size,
    sortBy: sortBy ?? this.sortBy,
    direction: direction ?? this.direction,
  );
}

class InventoryTransactionQuery {
  const InventoryTransactionQuery({
    this.orderId,
    this.orderItemId,
    this.source,
    this.warehouseId,
    this.ingredientId,
    this.documentId,
    this.type,
    this.dates,
    this.page = 0,
    this.size = 20,
    this.sortBy = 'createdAt',
    this.direction = 'desc',
  });
  final String? warehouseId, ingredientId, documentId;
  final String? orderId, orderItemId;
  final InventoryTransactionSource? source;
  final InventoryTransactionType? type;
  final StockDateRange? dates;
  final int page, size;
  final String sortBy, direction;
  bool get valid =>
      page >= 0 &&
      size >= 1 &&
      size <= 100 &&
      sortBy == 'createdAt' &&
      const {'asc', 'desc'}.contains(direction) &&
      (dates?.valid ?? true);
  InventoryTransactionQuery copyWith({
    String? Function()? orderId,
    String? Function()? orderItemId,
    InventoryTransactionSource? Function()? source,
    String? Function()? warehouseId,
    String? Function()? ingredientId,
    String? Function()? documentId,
    InventoryTransactionType? Function()? type,
    StockDateRange? Function()? dates,
    int? page,
    int? size,
    String? direction,
  }) => InventoryTransactionQuery(
    orderId: orderId == null ? this.orderId : orderId(),
    orderItemId: orderItemId == null ? this.orderItemId : orderItemId(),
    source: source == null ? this.source : source(),
    warehouseId: warehouseId == null ? this.warehouseId : warehouseId(),
    ingredientId: ingredientId == null ? this.ingredientId : ingredientId(),
    documentId: documentId == null ? this.documentId : documentId(),
    type: type == null ? this.type : type(),
    dates: dates == null ? this.dates : dates(),
    page: page ?? this.page,
    size: size ?? this.size,
    direction: direction ?? this.direction,
  );
}
