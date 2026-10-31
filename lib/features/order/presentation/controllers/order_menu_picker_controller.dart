import 'dart:async';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/paging/endless_pages.dart';
import '../../../../core/result/result.dart';
import '../../../menu/domain/entities/menu_group.dart';
import '../../../menu/domain/entities/menu_item.dart';
import '../../../menu/domain/entities/menu_page.dart';
import '../../../menu/domain/entities/menu_query.dart';
import '../../../menu/domain/use_cases/menu_item_use_cases.dart';
import '../../../menu/domain/use_cases/menu_group_use_cases.dart';
import '../../../menu/presentation/controllers/menu_catalog_events.dart';
import 'order_controller.dart';

class OrderMenuPickerController extends OrderController {
  OrderMenuPickerController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.itemsUseCase,
    required this.groupsUseCase,
    required this.catalog,
    required this.permission,
  }) {
    catalog.addListener(_event);
  }
  final GetMenuItems itemsUseCase;
  final GetMenuGroups groupsUseCase;
  final MenuCatalogEvents catalog;
  final String permission;
  MenuQuery query = const MenuQuery(
    active: true,
    sortBy: 'name',
    direction: 'asc',
  );
  MenuPage<MenuItem>? page;
  final endless = EndlessPages<MenuItem>((item) => item.id);
  bool get hasMore => query.page < (page?.totalPages ?? 0) - 1;
  final List<MenuGroup> _groups = [];
  List<MenuGroup> get groups => List.unmodifiable(_groups);
  int _groupPage = 0, _groupTotal = 1, _generation = 0, _groupGeneration = 0;
  bool loading = false, groupsLoading = false;
  Failure? failure, groupsFailure;
  Timer? _debounce;
  bool get hasMoreGroups => _groupPage < _groupTotal;
  bool get allowed =>
      can(permission) && AccessPolicy.canMenu(session(), 'MENU_VIEW');
  void _event() {
    if (catalog.deletedGroupId == query.groupId) {
      query = query.copyWith(groupId: () => null, page: 0);
    }
    unawaited(load());
    unawaited(loadGroups(reset: true));
  }

  void search(String text) {
    _debounce?.cancel();
    ++_generation;
    query = query.copyWith(q: text, page: 0);
    page = null;
    loading = false;
    changed();
    _debounce = Timer(const Duration(milliseconds: 350), load);
  }

  void group(String? id) {
    _debounce?.cancel();
    ++_generation;
    page = null;
    query = query.copyWith(groupId: () => id, page: 0);
    unawaited(load());
  }

  Future<void> go(int index) {
    query = query.copyWith(page: index);
    return load();
  }

  Future<void> load() async {
    if (!allowed) return;
    if (!query.isValid(items: true)) {
      failure = OrderController.invalid({'q': 'Tìm kiếm tối đa 100 ký tự.'});
      loading = false;
      changed();
      return;
    }
    final g = ++_generation;
    loading = true;
    failure = null;
    changed();
    final q = query;
    final result = await endless.read(
      page: q.page,
      fetch: (index) => itemsUseCase(q.copyWith(page: index)),
      content: (v) => v.content,
      totalPages: (v) => v.totalPages,
      active: () => allowed && g == _generation,
    );
    if (!allowed || g != _generation) return;
    switch (result) {
      case Success(value: final pages):
        if (pages.lastPage != q.page) {
          query = query.copyWith(page: pages.lastPage);
        }
        page = _pageOf(pages.rows, pages.last);
      case Error(failure: final f):
        failure = f;
        await report(f);
    }
    loading = false;
    changed();
  }

  /// Appends the next page; a failure keeps the items already shown.
  Future<void> loadMore() async {
    final shown = page;
    if (shown == null ||
        !hasMore ||
        !allowed ||
        loading ||
        endless.loadingMore ||
        _debounce?.isActive == true) {
      return;
    }
    final g = ++_generation;
    final next = query.copyWith(page: query.page + 1);
    endless.begin();
    changed();
    final result = await itemsUseCase(next);
    if (!allowed || g != _generation) return;
    switch (result) {
      case Success(value: final v):
        query = next;
        page = _pageOf(endless.append(shown.content, v.content), v);
      case Error(failure: final f):
        endless.fail(f);
        await report(f);
    }
    changed();
  }

  MenuPage<MenuItem> _pageOf(List<MenuItem> rows, MenuPage<MenuItem> v) =>
      MenuPage(
        content: rows,
        page: v.page,
        size: v.size,
        totalElements: v.totalElements,
        totalPages: v.totalPages,
      );

  Future<void> loadGroups({bool reset = false}) async {
    if (!allowed || groupsLoading && !reset) return;
    if (reset) {
      _groups.clear();
      _groupPage = 0;
      _groupTotal = 1;
    }
    if (!hasMoreGroups) return;
    final g = ++_groupGeneration;
    groupsLoading = true;
    groupsFailure = null;
    changed();
    final result = await groupsUseCase(
      MenuQuery(
        active: true,
        page: _groupPage,
        sortBy: 'displayOrder',
        direction: 'asc',
      ),
    );
    if (!allowed || g != _groupGeneration) return;
    switch (result) {
      case Success(value: final v):
        _groups.addAll(
          v.content.where((item) => !_groups.any((old) => old.id == item.id)),
        );
        _groupPage = v.page + 1;
        _groupTotal = v.totalPages;
      case Error(failure: final f):
        groupsFailure = f;
        await report(f);
    }
    groupsLoading = false;
    changed();
  }

  @override
  void dispose() {
    ++_generation;
    ++_groupGeneration;
    _debounce?.cancel();
    catalog.removeListener(_event);
    _groups.clear();
    page = null;
    super.dispose();
  }
}
