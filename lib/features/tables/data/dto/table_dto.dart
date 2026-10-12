import '../../domain/entities/table_entities.dart';

abstract final class TableDto {
  static TableArea tableArea(Object? value) {
    final j = _object(value);
    return TableArea(
      id: _string(j, 'id'),
      name: _string(j, 'name'),
      description: _nullableString(j, 'description'),
      displayOrder: _integer(j, 'displayOrder'),
      active: _boolean(j, 'active'),
      version: _integer(j, 'version'),
      createdAt: _date(j, 'createdAt'),
      updatedAt: _date(j, 'updatedAt'),
    );
  }

  static TableAreaSummary tableAreaSummary(Object? value) {
    final j = _object(value);
    return TableAreaSummary(
      id: _string(j, 'id'),
      name: _string(j, 'name'),
      active: _boolean(j, 'active'),
    );
  }

  static CurrentTableSessionSummary currentTableSessionSummary(Object? value) {
    final j = _object(value);
    return CurrentTableSessionSummary(
      id: _string(j, 'id'),
      sessionCode: _string(j, 'sessionCode'),
      guestCount: _integer(j, 'guestCount'),
      openedAt: _date(j, 'openedAt'),
      version: _integer(j, 'version'),
    );
  }

  static RestaurantTable restaurantTable(Object? value) {
    final j = _object(value);
    return RestaurantTable(
      id: _string(j, 'id'),
      code: _string(j, 'code'),
      name: _string(j, 'name'),
      capacity: _integer(j, 'capacity'),
      displayOrder: _integer(j, 'displayOrder'),
      status: _enum(TableStatus.values, _string(j, 'status')),
      area: j['area'] == null ? null : tableAreaSummary(j['area']),
      occupied: _boolean(j, 'occupied'),
      currentSession: j['currentSession'] == null
          ? null
          : currentTableSessionSummary(j['currentSession']),
      canOpen: _boolean(j, 'canOpen'),
      version: _integer(j, 'version'),
      createdAt: _date(j, 'createdAt'),
      updatedAt: _date(j, 'updatedAt'),
    );
  }

  static TableSession tableSession(Object? value) {
    final j = _object(value);
    return TableSession(
      id: _string(j, 'id'),
      sessionCode: _string(j, 'sessionCode'),
      tableId: _string(j, 'tableId'),
      tableCode: _string(j, 'tableCode'),
      tableName: _string(j, 'tableName'),
      status: _enum(TableSessionStatus.values, _string(j, 'status')),
      guestCount: _integer(j, 'guestCount'),
      note: _nullableString(j, 'note'),
      openedBy: _string(j, 'openedBy'),
      openedAt: _date(j, 'openedAt'),
      closedBy: _nullableString(j, 'closedBy'),
      closedAt: j['closedAt'] == null ? null : _date(j, 'closedAt'),
      cancelReason: _nullableString(j, 'cancelReason'),
      version: _integer(j, 'version'),
      createdAt: _date(j, 'createdAt'),
      updatedAt: _date(j, 'updatedAt'),
    );
  }

  static TableQrPayload tableQrPayload(Object? value) {
    final j = _object(value);
    return TableQrPayload(
      tableId: _string(j, 'tableId'),
      qrToken: _string(j, 'qrToken'),
      qrPath: _string(j, 'qrPath'),
      version: _integer(j, 'version'),
    );
  }

  static TableSnapshot tableSnapshot(Object? value) {
    final j = _object(value);
    return TableSnapshot(
      id: _string(j, 'id'),
      code: _string(j, 'code'),
      name: _string(j, 'name'),
    );
  }

  static TableSessionTransferHistoryEntry tableSessionTransfer(Object? value) {
    final j = _object(value);
    return TableSessionTransferHistoryEntry(
      id: _string(j, 'id'),
      sessionId: _string(j, 'sessionId'),
      fromTable: tableSnapshot(j['fromTable']),
      toTable: tableSnapshot(j['toTable']),
      actorUserId: _string(j, 'actorUserId'),
      reason: _nullableString(j, 'reason'),
      sessionVersionBefore: _integer(j, 'sessionVersionBefore'),
      sessionVersionAfter: _integer(j, 'sessionVersionAfter'),
      transferredAt: _date(j, 'transferredAt'),
    );
  }

  static TablePage<T> page<T>(Object? value, T Function(Object?) parse) {
    final j = _object(value);
    final rows = j['content'];
    final size = _integer(j, 'size');
    if (rows is! List || size < 1 || size > 100 || rows.length > size) {
      throw const FormatException('Invalid page');
    }
    return TablePage(
      content: rows.map(parse).toList(),
      page: _integer(j, 'page'),
      size: size,
      totalElements: _integer(j, 'totalElements'),
      totalPages: _integer(j, 'totalPages'),
    );
  }

  static T _enum<T extends Enum>(List<T> values, String code) {
    for (final v in values) {
      if (v.name.toUpperCase() == code) return v;
    }
    throw const FormatException('Invalid status');
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected tables object');
  }
  return value;
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $key');
  }
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value != null && value is! String) throw FormatException('Invalid $key');
  return value as String?;
}

int _integer(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) throw FormatException('Invalid $key');
  if ((key == 'capacity' || key == 'guestCount') &&
      (value < 1 || value > 32767)) {
    throw FormatException('Invalid $key');
  }
  if (key == 'displayOrder' && value > 2147483647) {
    throw FormatException('Invalid $key');
  }
  return value;
}

bool _boolean(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('Invalid $key');
  return value;
}

DateTime _date(Map<String, dynamic> json, String key) {
  final text = _string(json, key);
  final date = DateTime.tryParse(text);
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-](\d{2}):(\d{2}))$',
  ).firstMatch(text);
  if (date == null || match == null) {
    throw FormatException('Invalid $key');
  }
  int part(int index) => int.parse(match.group(index) ?? '0');
  final days = DateTime.utc(part(1), part(2) + 1, 0).day;
  if (part(2) < 1 ||
      part(2) > 12 ||
      part(3) < 1 ||
      part(3) > days ||
      part(4) > 23 ||
      part(5) > 59 ||
      part(6) > 59 ||
      part(7) > 23 ||
      part(8) > 59) {
    throw FormatException('Invalid $key');
  }
  return date;
}
