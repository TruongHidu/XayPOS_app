import '../../../../core/result/result.dart';
import '../entities/menu_group.dart';
import '../entities/menu_inputs.dart';
import '../entities/menu_page.dart';
import '../entities/menu_query.dart';
import '../repositories/menu_group_repository.dart';

class GetMenuGroups {
  const GetMenuGroups(this._repository);
  final MenuGroupRepository _repository;
  Future<Result<MenuPage<MenuGroup>>> call(MenuQuery query) =>
      _repository.list(query);
}

class GetMenuGroupDetail {
  const GetMenuGroupDetail(this._repository);
  final MenuGroupRepository _repository;
  Future<Result<MenuGroup>> call(String id) => _repository.detail(id);
}

class CreateMenuGroup {
  const CreateMenuGroup(this._repository);
  final MenuGroupRepository _repository;
  Future<Result<MenuGroup>> call(CreateMenuGroupInput input) =>
      _repository.create(input);
}

class UpdateMenuGroup {
  const UpdateMenuGroup(this._repository);
  final MenuGroupRepository _repository;
  Future<Result<MenuGroup>> call(String id, UpdateMenuGroupInput input) =>
      _repository.update(id, input);
}

class SetMenuGroupStatus {
  const SetMenuGroupStatus(this._repository);
  final MenuGroupRepository _repository;
  Future<Result<MenuGroup>> call(String id, bool active, int expectedVersion) =>
      _repository.setStatus(id, active, expectedVersion);
}

class DeleteMenuGroup {
  const DeleteMenuGroup(this._repository);
  final MenuGroupRepository _repository;
  Future<Result<void>> call(String id, int expectedVersion) =>
      _repository.delete(id, expectedVersion);
}
