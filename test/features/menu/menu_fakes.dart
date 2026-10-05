import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_group.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_item.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_page.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_query.dart';
import 'package:pos_saas_app/features/menu/domain/repositories/menu_group_repository.dart';
import 'package:pos_saas_app/features/menu/domain/repositories/menu_item_repository.dart';

const menuPermissions = {
  'MENU_VIEW',
  'MENU_CREATE',
  'MENU_UPDATE',
  'MENU_DELETE',
};
Map<String, dynamic> groupJson({
  int version = 7,
  bool active = true,
  String id = 'g1',
}) => {
  'id': id,
  'name': 'Đồ uống',
  'displayOrder': 0,
  'active': active,
  'version': version,
  'createdAt': '2026-01-01T10:00:00Z',
  'updatedAt': '2026-01-02T10:00:00+07:00',
};
Map<String, dynamic> itemJson({
  int version = 9,
  bool active = true,
  bool sellable = true,
}) => {
  'id': 'i1',
  'name': 'Trà đào',
  'baseUnit': 'ly',
  'salePrice': 35000.5,
  'active': active,
  'availabilityStatus': 'AVAILABLE',
  'sellable': sellable,
  'version': version,
  'sku': 'TEA',
  'description': null,
  'imageUrl': null,
  'group': {'id': 'g1', 'name': 'Đồ uống', 'active': true},
  'createdAt': '2026-01-01T10:00:00Z',
  'updatedAt': '2026-01-02T10:00:00+07:00',
};
MenuItem item({int version = 9, bool active = true}) =>
    MenuItemDto.fromJson(itemJson(version: version, active: active)).toEntity();
MenuGroup group({int version = 7, bool active = true}) => MenuGroupDto.fromJson(
  groupJson(version: version, active: active),
).toEntity();
MenuPage<T> page<T>(List<T> rows, {int index = 0, int pages = 1, int? total}) =>
    MenuPage(
      content: rows,
      page: index,
      size: 20,
      totalElements: total ?? rows.length,
      totalPages: pages,
    );

class FakeMenuItems implements MenuItemRepository {
  MenuItem current = item();
  List<MenuItem> rows = [];
  final queries = <MenuQuery>[];
  final writes = <(String, int)>[];
  UpdateMenuItemInput? lastUpdate;
  CreateMenuItemInput? lastCreate;
  String? lastGroup;
  int detailCalls = 0;
  Future<Result<MenuPage<MenuItem>>> Function(MenuQuery)? onList;
  Future<Result<MenuItem>> Function()? onWrite;
  Future<Result<MenuItem>> Function()? onDetail;
  @override
  Future<Result<MenuPage<MenuItem>>> list(MenuQuery query) async {
    queries.add(query);
    return onList != null
        ? onList!(query)
        : Success(page(rows, index: query.page));
  }

  @override
  Future<Result<MenuItem>> detail(String id) async {
    detailCalls++;
    return onDetail != null ? onDetail!() : Success(current);
  }

  Future<Result<MenuItem>> _write(String operation, int version) async {
    writes.add((operation, version));
    return onWrite != null ? onWrite!() : Success(current);
  }

  @override
  Future<Result<MenuItem>> create(CreateMenuItemInput input) {
    lastCreate = input;
    return _write('create', -1);
  }

  @override
  Future<Result<MenuItem>> update(String id, UpdateMenuItemInput input) {
    lastUpdate = input;
    return _write('update', input.expectedVersion);
  }

  @override
  Future<Result<MenuItem>> setStatus(
    String id,
    bool active,
    int expectedVersion,
  ) => _write('status', expectedVersion);
  @override
  Future<Result<MenuItem>> setAvailability(
    String id,
    AvailabilityStatus status,
    int expectedVersion,
  ) => _write('availability', expectedVersion);
  @override
  Future<Result<MenuItem>> setGroup(
    String id,
    String? groupId,
    int expectedVersion,
  ) {
    lastGroup = groupId;
    return _write('group', expectedVersion);
  }

  @override
  Future<Result<void>> delete(String id, int expectedVersion) async {
    final result = await _write('delete', expectedVersion);
    return switch (result) {
      Success() => const Success(null),
      Error(failure: final failure) => Error(failure),
    };
  }
}

class FakeMenuGroups implements MenuGroupRepository {
  MenuGroup current = group();
  List<MenuGroup> rows = [];
  final queries = <MenuQuery>[];
  final writes = <(String, int)>[];
  Future<Result<MenuPage<MenuGroup>>> Function(MenuQuery)? onList;
  Future<Result<MenuGroup>> Function()? onWrite;
  @override
  Future<Result<MenuPage<MenuGroup>>> list(MenuQuery query) async {
    queries.add(query);
    return onList != null
        ? onList!(query)
        : Success(page(rows, index: query.page));
  }

  @override
  Future<Result<MenuGroup>> detail(String id) async => Success(current);
  Future<Result<MenuGroup>> _write(String operation, int version) async {
    writes.add((operation, version));
    return onWrite != null ? onWrite!() : Success(current);
  }

  @override
  Future<Result<MenuGroup>> create(CreateMenuGroupInput input) =>
      _write('create', -1);
  @override
  Future<Result<MenuGroup>> update(String id, UpdateMenuGroupInput input) =>
      _write('update', input.expectedVersion);
  @override
  Future<Result<MenuGroup>> setStatus(
    String id,
    bool active,
    int expectedVersion,
  ) => _write('status', expectedVersion);
  @override
  Future<Result<void>> delete(String id, int expectedVersion) async {
    final result = await _write('delete', expectedVersion);
    return switch (result) {
      Success() => const Success(null),
      Error(failure: final failure) => Error(failure),
    };
  }
}
