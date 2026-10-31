import 'dart:async';
import '../../domain/entities/menu_group.dart';
import '../../domain/entities/menu_query.dart';
import '../../domain/use_cases/menu_group_use_cases.dart';
import 'menu_catalog_events.dart';
import 'menu_list_controller.dart';

class MenuGroupSelectorController extends MenuListController<MenuGroup> {
  MenuGroupSelectorController({
    required super.session,
    required GetMenuGroups list,
    required this.activeOnly,
    required MenuCatalogEvents events,
    super.onAccessDenied,
  }) : _events = events,
       super(
         list: list.call,
         items: false,
         idOf: (group) => group.id,
         query: MenuQuery(
           active: activeOnly ? true : null,
           sortBy: 'name',
           direction: 'asc',
         ),
       ) {
    _revision = events.groupRevision;
    events.addListener(_changed);
  }
  final bool activeOnly;
  final MenuCatalogEvents _events;
  late int _revision;
  @override
  void setQuery(MenuQuery query, {bool debounce = false}) => super.setQuery(
    activeOnly ? query.copyWith(active: () => true) : query,
    debounce: debounce,
  );
  void _changed() {
    if (!isCurrent || _revision == _events.groupRevision) return;
    _revision = _events.groupRevision;
    unawaited(load());
  }

  @override
  void dispose() {
    _events.removeListener(_changed);
    super.dispose();
  }
}
