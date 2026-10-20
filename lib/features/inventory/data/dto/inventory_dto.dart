import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/inventory_quantity.dart';

abstract final class InventoryDto {
  static Map<String, dynamic> object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid inventory object');
    }
    return value;
  }

  static String text(Map<String, dynamic> j, String key) {
    if (j[key] is! String || (j[key] as String).trim().isEmpty) {
      throw FormatException('Invalid $key');
    }
    return j[key] as String;
  }

  static String? optionalText(Map<String, dynamic> j, String key) {
    if (!j.containsKey(key) || j[key] != null && j[key] is! String) {
      throw FormatException('Invalid $key');
    }
    return j[key] as String?;
  }

  static int integer(Map<String, dynamic> j, String key) {
    if (j[key] is! int || (j[key] as int) < 0) {
      throw FormatException('Invalid $key');
    }
    return j[key] as int;
  }

  static bool boolean(Map<String, dynamic> j, String key) {
    if (j[key] is! bool) throw FormatException('Invalid $key');
    return j[key] as bool;
  }

  static DateTime? date(
    Map<String, dynamic> j,
    String key, {
    bool nullable = false,
  }) {
    if (!j.containsKey(key)) throw FormatException('Missing $key');
    if (j[key] == null && nullable) return null;
    final value = text(j, key);
    if (!RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
    ).hasMatch(value)) {
      throw FormatException('Invalid $key');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) throw FormatException('Invalid $key');
    return parsed;
  }

  static InventoryQuantity quantity(Map<String, dynamic> j, String key) {
    if (j[key] is! num) throw FormatException('Invalid $key');
    return InventoryQuantity.fromNumber(j[key] as num);
  }

  static Warehouse warehouse(Object? value) {
    final j = object(value);
    final row = Warehouse(
      id: text(j, 'id'),
      code: text(j, 'code'),
      name: text(j, 'name'),
      isDefault: boolean(j, 'isDefault'),
      active: boolean(j, 'active'),
      version: integer(j, 'version'),
      createdAt: date(j, 'createdAt')!,
      updatedAt: date(j, 'updatedAt')!,
    );
    if (row.isDefault && !row.active) {
      throw const FormatException('Inactive default warehouse');
    }
    return row;
  }

  static InventoryBalance balance(Object? value) {
    final j = object(value);
    if (!j.containsKey('version')) {
      throw const FormatException('Missing version');
    }
    final row = InventoryBalance(
      balanceId: optionalText(j, 'balanceId'),
      configured: boolean(j, 'configured'),
      warehouseId: text(j, 'warehouseId'),
      warehouseCode: text(j, 'warehouseCode'),
      ingredientId: text(j, 'ingredientId'),
      ingredientSku: optionalText(j, 'ingredientSku'),
      ingredientName: text(j, 'ingredientName'),
      baseUnit: text(j, 'baseUnit'),
      ingredientActive: boolean(j, 'ingredientActive'),
      quantity: quantity(j, 'quantity'),
      minQuantity: quantity(j, 'minQuantity'),
      lowStock: boolean(j, 'lowStock'),
      version: j['version'] == null ? null : integer(j, 'version'),
      createdAt: date(j, 'createdAt', nullable: true),
      updatedAt: date(j, 'updatedAt', nullable: true),
    );
    if (row.configured
        ? row.balanceId == null ||
              row.version == null ||
              row.createdAt == null ||
              row.updatedAt == null
        : row.balanceId != null ||
              row.version != null ||
              row.createdAt != null ||
              row.updatedAt != null ||
              row.quantity != InventoryQuantity.zero ||
              row.minQuantity != InventoryQuantity.zero ||
              row.lowStock) {
      throw const FormatException('Invalid logical/physical balance');
    }
    if (row.lowStock !=
        (row.minQuantity.scaled > 0 &&
            row.quantity.compareTo(row.minQuantity) <= 0)) {
      throw const FormatException('Invalid low stock flag');
    }
    return row;
  }

  static InventoryPage<T> page<T>(
    Object? value,
    T Function(Object?) parse,
    int expectedPage,
  ) {
    final j = object(value), content = j['content'];
    final page = integer(j, 'page'),
        size = integer(j, 'size'),
        total = integer(j, 'totalElements'),
        pages = integer(j, 'totalPages');
    if (content is! List ||
        page != expectedPage ||
        size < 1 ||
        size > 100 ||
        content.length > size ||
        total < content.length) {
      throw const FormatException('Invalid inventory page');
    }
    return InventoryPage(
      content: content.map(parse).toList(),
      page: page,
      size: size,
      totalElements: total,
      totalPages: pages,
    );
  }
}
