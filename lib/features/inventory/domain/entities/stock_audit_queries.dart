import 'inventory_instant_range.dart';
import 'stock_audit.dart';

class StockAuditQuery {
  const StockAuditQuery({
    this.q = '',
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
  final StockAuditStatus? status;
  final InventoryInstantRange? dates;
  final int page, size;
  static const sorts = {'createdAt', 'startedAt', 'updatedAt', 'auditCode'};
  bool get valid =>
      q.trim().length <= 100 &&
      page >= 0 &&
      size >= 1 &&
      size <= 100 &&
      (warehouseId == null || warehouseId!.trim().isNotEmpty) &&
      sorts.contains(sortBy) &&
      const {'asc', 'desc'}.contains(direction) &&
      (dates?.valid ?? true);
  StockAuditQuery copyWith({
    String? q,
    StockAuditStatus? Function()? status,
    String? Function()? warehouseId,
    InventoryInstantRange? Function()? dates,
    int? page,
    int? size,
    String? sortBy,
    String? direction,
  }) => StockAuditQuery(
    q: q ?? this.q,
    status: status == null ? this.status : status(),
    warehouseId: warehouseId == null ? this.warehouseId : warehouseId(),
    dates: dates == null ? this.dates : dates(),
    page: page ?? this.page,
    size: size ?? this.size,
    sortBy: sortBy ?? this.sortBy,
    direction: direction ?? this.direction,
  );
}

class StockAuditItemQuery {
  const StockAuditItemQuery({
    this.q = '',
    this.counted,
    this.differenceOnly = false,
    this.page = 0,
    this.size = 20,
    this.sortBy = 'name',
    this.direction = 'asc',
  });
  final String q, sortBy, direction;
  final bool? counted;
  final bool differenceOnly;
  final int page, size;
  static const sorts = {
    'name',
    'sku',
    'systemQuantity',
    'countedQuantity',
    'differenceQuantity',
  };
  bool get valid =>
      q.trim().length <= 100 &&
      page >= 0 &&
      size >= 1 &&
      size <= 100 &&
      sorts.contains(sortBy) &&
      const {'asc', 'desc'}.contains(direction);
  StockAuditItemQuery copyWith({
    String? q,
    bool? Function()? counted,
    bool? differenceOnly,
    int? page,
    int? size,
    String? sortBy,
    String? direction,
  }) => StockAuditItemQuery(
    q: q ?? this.q,
    counted: counted == null ? this.counted : counted(),
    differenceOnly: differenceOnly ?? this.differenceOnly,
    page: page ?? this.page,
    size: size ?? this.size,
    sortBy: sortBy ?? this.sortBy,
    direction: direction ?? this.direction,
  );
}
