import '../../../../core/result/result.dart';
import '../../domain/entities/menu_item.dart';
import '../../domain/entities/menu_inputs.dart';
import '../../domain/entities/menu_page.dart';
import '../../domain/entities/menu_query.dart';
import '../../domain/repositories/menu_item_repository.dart';
import '../data_sources/menu_remote_data_source.dart';
import 'menu_result.dart';

class MenuItemRepositoryImpl implements MenuItemRepository {
  const MenuItemRepositoryImpl(this._remote);
  final MenuRemoteDataSource _remote;
  @override
  Future<Result<MenuPage<MenuItem>>> list(MenuQuery query) =>
      menuResult(() async => (await _remote.listItems(query)).toEntity());
  @override
  Future<Result<MenuItem>> detail(String id) =>
      menuResult(() async => (await _remote.getItem(id)).toEntity());
  @override
  Future<Result<MenuItem>> create(CreateMenuItemInput input) =>
      menuResult(() async => (await _remote.createItem(input)).toEntity());
  @override
  Future<Result<MenuItem>> update(String id, UpdateMenuItemInput input) =>
      menuResult(() async => (await _remote.updateItem(id, input)).toEntity());
  @override
  Future<Result<MenuItem>> setStatus(
    String id,
    bool active,
    int expectedVersion,
  ) => menuResult(
    () async =>
        (await _remote.setItemStatus(id, active, expectedVersion)).toEntity(),
  );
  @override
  Future<Result<void>> delete(String id, int expectedVersion) =>
      menuResult(() async => _remote.deleteItem(id, expectedVersion));
  @override
  Future<Result<MenuItem>> setAvailability(
    String id,
    AvailabilityStatus status,
    int expectedVersion,
  ) => menuResult(
    () async =>
        (await _remote.setAvailability(id, status, expectedVersion)).toEntity(),
  );
  @override
  Future<Result<MenuItem>> setGroup(
    String id,
    String? groupId,
    int expectedVersion,
  ) => menuResult(
    () async =>
        (await _remote.setGroup(id, groupId, expectedVersion)).toEntity(),
  );
}
