import '../../../../core/result/result.dart';
import '../../domain/entities/menu_group.dart';
import '../../domain/entities/menu_inputs.dart';
import '../../domain/entities/menu_page.dart';
import '../../domain/entities/menu_query.dart';
import '../../domain/repositories/menu_group_repository.dart';
import '../data_sources/menu_remote_data_source.dart';
import 'menu_result.dart';

class MenuGroupRepositoryImpl implements MenuGroupRepository {
  const MenuGroupRepositoryImpl(this._remote);
  final MenuRemoteDataSource _remote;
  @override
  Future<Result<MenuPage<MenuGroup>>> list(MenuQuery query) =>
      menuResult(() async => (await _remote.listGroups(query)).toEntity());
  @override
  Future<Result<MenuGroup>> detail(String id) =>
      menuResult(() async => (await _remote.getGroup(id)).toEntity());
  @override
  Future<Result<MenuGroup>> create(CreateMenuGroupInput input) =>
      menuResult(() async => (await _remote.createGroup(input)).toEntity());
  @override
  Future<Result<MenuGroup>> update(String id, UpdateMenuGroupInput input) =>
      menuResult(() async => (await _remote.updateGroup(id, input)).toEntity());
  @override
  Future<Result<MenuGroup>> setStatus(
    String id,
    bool active,
    int expectedVersion,
  ) => menuResult(
    () async =>
        (await _remote.setGroupStatus(id, active, expectedVersion)).toEntity(),
  );
  @override
  Future<Result<void>> delete(String id, int expectedVersion) =>
      menuResult(() async => _remote.deleteGroup(id, expectedVersion));
}
