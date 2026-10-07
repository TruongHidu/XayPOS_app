enum TableStatus {
  available,
  inactive;

  String get code => name.toUpperCase();
}

enum TableSessionStatus {
  open,
  cancelled,
  closed;

  String get code => name.toUpperCase();
}

class TableArea {
  const TableArea({
    required this.id,
    required this.name,
    required this.description,
    required this.displayOrder,
    required this.active,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String name;
  final String? description;
  final int displayOrder;
  final bool active;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class TableAreaSummary {
  const TableAreaSummary({
    required this.id,
    required this.name,
    required this.active,
  });
  final String id;
  final String name;
  final bool active;
}

class CurrentTableSessionSummary {
  const CurrentTableSessionSummary({
    required this.id,
    required this.sessionCode,
    required this.guestCount,
    required this.openedAt,
    required this.version,
  });
  final String id;
  final String sessionCode;
  final int guestCount;
  final DateTime openedAt;
  final int version;
}

class RestaurantTable {
  const RestaurantTable({
    required this.id,
    required this.code,
    required this.name,
    required this.capacity,
    required this.displayOrder,
    required this.status,
    required this.area,
    required this.occupied,
    required this.currentSession,
    required this.canOpen,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String code;
  final String name;
  final int capacity;
  final int displayOrder;
  final TableStatus status;
  final TableAreaSummary? area;
  final bool occupied;
  final CurrentTableSessionSummary? currentSession;
  final bool canOpen;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class TableSession {
  const TableSession({
    required this.id,
    required this.sessionCode,
    required this.tableId,
    required this.tableCode,
    required this.tableName,
    required this.status,
    required this.guestCount,
    required this.note,
    required this.openedBy,
    required this.openedAt,
    required this.closedBy,
    required this.closedAt,
    required this.cancelReason,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String sessionCode;
  final String tableId;
  final String tableCode;
  final String tableName;
  final TableSessionStatus status;
  final int guestCount;
  final String? note;
  final String openedBy;
  final DateTime openedAt;
  final String? closedBy;
  final DateTime? closedAt;
  final String? cancelReason;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class TableQrPayload {
  const TableQrPayload({
    required this.tableId,
    required this.qrToken,
    required this.qrPath,
    required this.version,
  });
  final String tableId;
  final String qrToken;
  final String qrPath;
  final int version;
}

class TablePage<T> {
  TablePage({
    required List<T> content,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  }) : content = List.unmodifiable(content);
  final List<T> content;
  final int page, size, totalElements, totalPages;
}
