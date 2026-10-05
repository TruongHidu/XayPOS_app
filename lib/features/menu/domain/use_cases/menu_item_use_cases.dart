import '../../../../core/result/result.dart';
import '../entities/menu_item.dart';
import '../entities/menu_inputs.dart';
import '../entities/menu_page.dart';
import '../entities/menu_query.dart';
import '../repositories/menu_item_repository.dart';

class GetMenuItems {
  const GetMenuItems(this._repository);
  final MenuItemRepository _repository;
  Future<Result<MenuPage<MenuItem>>> call(MenuQuery query) =>
      _repository.list(query);
}

class GetMenuItemDetail {
  const GetMenuItemDetail(this._repository);
  final MenuItemRepository _repository;
  Future<Result<MenuItem>> call(String id) => _repository.detail(id);
}

class CreateMenuItem {
  const CreateMenuItem(this._repository);
  final MenuItemRepository _repository;
  Future<Result<MenuItem>> call(CreateMenuItemInput input) =>
      _repository.create(input);
}

class UpdateMenuItem {
  const UpdateMenuItem(this._repository);
  final MenuItemRepository _repository;
  Future<Result<MenuItem>> call(String id, UpdateMenuItemInput input) =>
      _repository.update(id, input);
}

class SetMenuItemStatus {
  const SetMenuItemStatus(this._repository);
  final MenuItemRepository _repository;
  Future<Result<MenuItem>> call(String id, bool active, int expectedVersion) =>
      _repository.setStatus(id, active, expectedVersion);
}

class DeleteMenuItem {
  const DeleteMenuItem(this._repository);
  final MenuItemRepository _repository;
  Future<Result<void>> call(String id, int expectedVersion) =>
      _repository.delete(id, expectedVersion);
}

class SetMenuItemAvailability {
  const SetMenuItemAvailability(this._repository);
  final MenuItemRepository _repository;
  Future<Result<MenuItem>> call(
    String id,
    AvailabilityStatus status,
    int expectedVersion,
  ) => _repository.setAvailability(id, status, expectedVersion);
}

class SetMenuItemGroup {
  const SetMenuItemGroup(this._repository);
  final MenuItemRepository _repository;
  Future<Result<MenuItem>> call(
    String id,
    String? groupId,
    int expectedVersion,
  ) => _repository.setGroup(id, groupId, expectedVersion);
}
