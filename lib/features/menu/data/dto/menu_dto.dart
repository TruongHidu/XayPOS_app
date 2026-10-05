import '../../domain/entities/menu_group.dart';
import '../../domain/entities/menu_item.dart';
import '../../domain/entities/menu_page.dart';
import '../../domain/entities/menu_price.dart';

class MenuGroupDto {
  const MenuGroupDto._(this._entity);
  final MenuGroup _entity;
  factory MenuGroupDto.fromJson(Object? value) {
    final json = _object(value);
    return MenuGroupDto._(
      MenuGroup(
        id: _string(json, 'id'),
        name: _string(json, 'name'),
        displayOrder: _integer(json, 'displayOrder'),
        active: _boolean(json, 'active'),
        version: _integer(json, 'version'),
        createdAt: _date(json, 'createdAt'),
        updatedAt: _date(json, 'updatedAt'),
      ),
    );
  }
  MenuGroup toEntity() => _entity;
}

class MenuItemDto {
  const MenuItemDto._(this._entity);
  final MenuItem _entity;
  factory MenuItemDto.fromJson(Object? value) {
    final json = _object(value);
    final group = json['group'] == null ? null : _object(json['group']);
    final price = json['salePrice'];
    if (price is! num) throw const FormatException('Invalid salePrice');
    final costPrice = json['costPrice'];
    if (costPrice != null && costPrice is! num) {
      throw const FormatException('Invalid costPrice');
    }
    return MenuItemDto._(
      MenuItem(
        id: _string(json, 'id'),
        name: _string(json, 'name'),
        group: group == null
            ? null
            : MenuItemGroupSummary(
                id: _string(group, 'id'),
                name: _string(group, 'name'),
                active: _boolean(group, 'active'),
              ),
        sku: _nullableString(json, 'sku'),
        baseUnit: _string(json, 'baseUnit'),
        description: _nullableString(json, 'description'),
        imageUrl: _nullableString(json, 'imageUrl'),
        salePrice: MenuPrice.fromNumber(price),
        costPrice: json.containsKey('costPrice')
            ? MenuPrice.fromNumber((costPrice ?? 0) as num)
            : null,
        active: _boolean(json, 'active'),
        availabilityStatus: AvailabilityStatus.parse(
          _string(json, 'availabilityStatus'),
        ),
        sellable: _boolean(json, 'sellable'),
        version: _integer(json, 'version'),
        createdAt: _date(json, 'createdAt'),
        updatedAt: _date(json, 'updatedAt'),
      ),
    );
  }
  MenuItem toEntity() => _entity;
}

class MenuPageDto<T> {
  const MenuPageDto._(this._page);
  final MenuPage<T> _page;
  factory MenuPageDto.fromJson(Object? value, T Function(Object?) parse) {
    final json = _object(value);
    final content = json['content'];
    final size = _integer(json, 'size');
    if (content is! List || size < 1 || size > 100 || content.length > size) {
      throw const FormatException('Invalid menu page');
    }
    return MenuPageDto._(
      MenuPage(
        content: content.map(parse).toList(),
        page: _integer(json, 'page'),
        size: size,
        totalElements: _integer(json, 'totalElements'),
        totalPages: _integer(json, 'totalPages'),
      ),
    );
  }
  MenuPage<T> toEntity() => _page;
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected menu object');
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
