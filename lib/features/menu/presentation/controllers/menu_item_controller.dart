import 'dart:async';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/menu_group.dart';
import '../../domain/entities/menu_item.dart';
import '../../domain/entities/menu_inputs.dart';
import '../../domain/use_cases/menu_item_use_cases.dart';
import '../../domain/validation/menu_validation.dart';
import 'menu_catalog_events.dart';
import 'menu_list_controller.dart';

class MenuItemController extends MenuListController<MenuItem> {
  MenuItemController({
    required super.session,
    required GetMenuItems list,
    required GetMenuItemDetail detail,
    required CreateMenuItem create,
    required UpdateMenuItem update,
    required SetMenuItemStatus status,
    required SetMenuItemAvailability availability,
    required SetMenuItemGroup group,
    required DeleteMenuItem delete,
    required MenuCatalogEvents events,
    super.onAccessDenied,
  }) : _detail = detail,
       _create = create,
       _update = update,
       _status = status,
       _availability = availability,
       _group = group,
       _delete = delete,
       _events = events,
       super(list: list.call, items: true) {
    _groupRevision = events.groupRevision;
    events.addListener(_groupsChanged);
  }
  final GetMenuItemDetail _detail;
  final CreateMenuItem _create;
  final UpdateMenuItem _update;
  final SetMenuItemStatus _status;
  final SetMenuItemAvailability _availability;
  final SetMenuItemGroup _group;
  final DeleteMenuItem _delete;
  final MenuCatalogEvents _events;
  late int _groupRevision;

  void _groupsChanged() {
    if (!isCurrent || _groupRevision == _events.groupRevision) return;
    _groupRevision = _events.groupRevision;
    if (_events.deletedGroupId != null &&
        state.query.groupId == _events.deletedGroupId) {
      setQuery(state.query.copyWith(groupId: () => null));
    } else {
      unawaited(load());
    }
  }

  Future<Result<MenuItem>> detail(String id) =>
      readDetail(id, () => _detail(id));
  Future<Result<MenuItem>> create(
    CreateMenuItemInput input, {
    MenuItemGroupSummary? selectedGroup,
  }) async {
    final errors = MenuValidation.item(input);
    if (selectedGroup != null &&
        (!selectedGroup.active || selectedGroup.id != input.groupId)) {
      errors['groupId'] = 'Chỉ được chọn nhóm đang hoạt động.';
    }
    if (errors.isNotEmpty) return Error(MenuListController.validation(errors));
    return mutate(
      'create',
      'MENU_CREATE',
      () => _create(input),
      onSuccess: (item) => _events.itemChanged(item.id),
      onFailure: (failure) => _groupFailure(failure, input.groupId),
    );
  }

  Future<Result<MenuItem>> update(String id, UpdateMenuItemInput input) async {
    if (input.isEmpty) return const Error(MenuListController.emptyUpdate);
    final errors = MenuValidation.itemPatch(input);
    if (errors.isNotEmpty) return Error(MenuListController.validation(errors));
    return mutate(
      id,
      'MENU_UPDATE',
      () => _update(id, input),
      onSuccess: (item) => _events.itemChanged(item.id),
    );
  }

  Future<Result<MenuItem>> setStatus(MenuItem baseline, bool active) => mutate(
    baseline.id,
    'MENU_UPDATE',
    () => _status(baseline.id, active, baseline.version),
    onSuccess: (item) => _events.itemChanged(item.id),
  );
  Future<Result<MenuItem>> setAvailability(
    MenuItem baseline,
    AvailabilityStatus status,
  ) async {
    if (!baseline.active) {
      return const Error(
        Failure(
          type: FailureType.conflict,
          code: 'INVALID_MENU_ITEM_TRANSITION',
          message:
              'Món đang ngừng bán. Hãy bật món trước khi đổi tình trạng có hàng.',
        ),
      );
    }
    return mutate(
      baseline.id,
      'MENU_UPDATE',
      () => _availability(baseline.id, status, baseline.version),
      onSuccess: (item) => _events.itemChanged(item.id),
    );
  }

  Future<Result<MenuItem>> setGroup(
    MenuItem baseline,
    MenuItemGroupSummary? group,
  ) async {
    if (group != null && !group.active) {
      return const Error(
        Failure(
          type: FailureType.conflict,
          code: 'MENU_GROUP_INACTIVE',
          message: 'Không thể chuyển món vào nhóm đã ngừng hoạt động.',
        ),
      );
    }
    return mutate(
      baseline.id,
      'MENU_UPDATE',
      () => _group(baseline.id, group?.id, baseline.version),
      onSuccess: (item) => _events.itemChanged(item.id),
      onFailure: (failure) => _groupFailure(failure, group?.id),
    );
  }

  Future<Result<void>> delete(MenuItem baseline) => mutate(
    baseline.id,
    'MENU_DELETE',
    () => _delete(baseline.id, baseline.version),
    onSuccess: (_) => _events.itemChanged(baseline.id),
  );
  void _groupFailure(Failure failure, String? id) {
    if (failure.code == 'MENU_GROUP_NOT_FOUND') {
      _events.groupsChanged(deletedId: id);
    } else if (failure.code == 'MENU_GROUP_INACTIVE') {
      _events.groupsChanged();
    }
  }

  @override
  void dispose() {
    _events.removeListener(_groupsChanged);
    super.dispose();
  }
}
