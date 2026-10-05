import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/menu_group.dart';
import '../../domain/entities/menu_inputs.dart';
import '../../domain/use_cases/menu_group_use_cases.dart';
import '../../domain/validation/menu_validation.dart';
import 'menu_catalog_events.dart';
import 'menu_list_controller.dart';

class MenuGroupController extends MenuListController<MenuGroup> {
  MenuGroupController({
    required super.session,
    required GetMenuGroups list,
    required GetMenuGroupDetail detail,
    required CreateMenuGroup create,
    required UpdateMenuGroup update,
    required SetMenuGroupStatus status,
    required DeleteMenuGroup delete,
    required MenuCatalogEvents events,
    super.onAccessDenied,
  }) : _detail = detail,
       _create = create,
       _update = update,
       _status = status,
       _delete = delete,
       _events = events,
       super(list: list.call, items: false);
  final GetMenuGroupDetail _detail;
  final CreateMenuGroup _create;
  final UpdateMenuGroup _update;
  final SetMenuGroupStatus _status;
  final DeleteMenuGroup _delete;
  final MenuCatalogEvents _events;

  Future<Result<MenuGroup>> detail(String id) =>
      readDetail(id, () => _detail(id));
  Future<Result<MenuGroup>> create(CreateMenuGroupInput input) async {
    final errors = MenuValidation.group(input);
    if (errors.isNotEmpty) return Error(MenuListController.validation(errors));
    return mutate(
      'create',
      'MENU_CREATE',
      () => _create(input),
      onSuccess: (_) => _events.groupsChanged(),
    );
  }

  Future<Result<MenuGroup>> update(
    String id,
    UpdateMenuGroupInput input,
  ) async {
    if (input.isEmpty) return const Error(MenuListController.emptyUpdate);
    final errors = MenuValidation.groupPatch(input);
    if (errors.isNotEmpty) return Error(MenuListController.validation(errors));
    return mutate(
      id,
      'MENU_UPDATE',
      () => _update(id, input),
      onSuccess: (_) => _events.groupsChanged(),
      onFailure: (f) => _notFound(id, f),
    );
  }

  Future<Result<MenuGroup>> setStatus(MenuGroup baseline, bool active) =>
      mutate(
        baseline.id,
        'MENU_UPDATE',
        () => _status(baseline.id, active, baseline.version),
        onSuccess: (_) => _events.groupsChanged(),
        onFailure: (f) => _notFound(baseline.id, f),
      );
  Future<Result<void>> delete(MenuGroup baseline) => mutate(
    baseline.id,
    'MENU_DELETE',
    () => _delete(baseline.id, baseline.version),
    onSuccess: (_) => _events.groupsChanged(deletedId: baseline.id),
    onFailure: (f) => _notFound(baseline.id, f),
  );
  void _notFound(String id, Failure failure) {
    if (failure.code == 'MENU_GROUP_NOT_FOUND') {
      _events.groupsChanged(deletedId: id);
    }
  }
}
