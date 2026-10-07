import 'table_entities.dart';

enum TableQueryKind { areas, tables, sessions }

class TableQuery {
  const TableQuery({
    this.q = '',
    this.active,
    this.areaId,
    this.status,
    this.occupied,
    this.tableId,
    this.sessionStatus,
    this.openedFrom,
    this.openedTo,
    this.page = 0,
    this.size = 20,
    this.sortBy = 'displayOrder',
    this.direction = 'desc',
  });
  final String q, sortBy, direction;
  final bool? active, occupied;
  final String? areaId, tableId;
  final TableStatus? status;
  final TableSessionStatus? sessionStatus;
  final DateTime? openedFrom, openedTo;
  final int page, size;
  bool valid(TableQueryKind kind) =>
      q.length <= 100 &&
      page >= 0 &&
      size >= 1 &&
      size <= 100 &&
      const {'asc', 'desc'}.contains(direction) &&
      (openedFrom == null ||
          openedTo == null ||
          !openedFrom!.isAfter(openedTo!)) &&
      switch (kind) {
        TableQueryKind.areas => const {
          'displayOrder',
          'name',
          'createdAt',
          'updatedAt',
        }.contains(sortBy),
        TableQueryKind.tables => const {
          'displayOrder',
          'name',
          'code',
          'capacity',
          'createdAt',
          'updatedAt',
        }.contains(sortBy),
        TableQueryKind.sessions => const {
          'openedAt',
          'sessionCode',
          'createdAt',
          'updatedAt',
        }.contains(sortBy),
      };
  TableQuery copyWith({
    String? q,
    bool? Function()? active,
    String? Function()? areaId,
    TableStatus? Function()? status,
    bool? Function()? occupied,
    TableSessionStatus? Function()? sessionStatus,
    DateTime? Function()? openedFrom,
    DateTime? Function()? openedTo,
    int? page,
    String? sortBy,
    String? direction,
  }) => TableQuery(
    q: q ?? this.q,
    active: active != null ? active() : this.active,
    areaId: areaId != null ? areaId() : this.areaId,
    status: status != null ? status() : this.status,
    occupied: occupied != null ? occupied() : this.occupied,
    tableId: tableId,
    sessionStatus: sessionStatus != null ? sessionStatus() : this.sessionStatus,
    openedFrom: openedFrom != null ? openedFrom() : this.openedFrom,
    openedTo: openedTo != null ? openedTo() : this.openedTo,
    page: page ?? this.page,
    size: size,
    sortBy: sortBy ?? this.sortBy,
    direction: direction ?? this.direction,
  );
}
