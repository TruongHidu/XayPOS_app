import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/data_sources/menu_remote_data_source.dart';
import '../../data/repositories/ingredient_repository_impl.dart';
import '../../data/repositories/menu_group_repository_impl.dart';
import '../../data/repositories/menu_item_repository_impl.dart';
import '../../domain/repositories/ingredient_repository.dart';
import '../../domain/repositories/menu_group_repository.dart';
import '../../domain/entities/menu_group.dart';
import '../../domain/repositories/menu_item_repository.dart';
import '../../domain/use_cases/ingredient_use_cases.dart';
import '../../domain/use_cases/menu_group_use_cases.dart';
import '../../domain/use_cases/menu_item_use_cases.dart';
import '../controllers/ingredient_controller.dart';
import '../controllers/menu_catalog_events.dart';
import '../controllers/menu_group_controller.dart';
import '../controllers/menu_group_selector_controller.dart';
import '../controllers/menu_item_controller.dart';

final menuRemoteDataSourceProvider = Provider(
  (ref) => MenuRemoteDataSource(ref.watch(apiClientsProvider).authenticated),
);
final menuGroupRepositoryProvider = Provider<MenuGroupRepository>(
  (ref) => MenuGroupRepositoryImpl(ref.watch(menuRemoteDataSourceProvider)),
);
final menuItemRepositoryProvider = Provider<MenuItemRepository>(
  (ref) => MenuItemRepositoryImpl(ref.watch(menuRemoteDataSourceProvider)),
);
final ingredientRepositoryProvider = Provider<IngredientRepository>(
  (ref) => IngredientRepositoryImpl(ref.watch(menuRemoteDataSourceProvider)),
);
final menuNoticeProvider = StateProvider<String?>((ref) => null);
final menuScopeProvider = Provider<Object?>(
  (ref) => ref.watch(
    authControllerProvider.select(
      (auth) => AccessPolicy.menuScope(auth.state.session),
    ),
  ),
);
final ingredientScopeProvider = Provider<Object?>(
  (ref) => ref.watch(
    authControllerProvider.select(
      (auth) => AccessPolicy.ingredientScope(auth.state.session),
    ),
  ),
);

enum MenuWorkspaceTab { menuItems, menuGroups, ingredients }

/// Tab picked in the menu workspace. Shared with the app bar filter action,
/// so read it through [resolveMenuTab] to apply permission fallbacks.
final menuWorkspaceTabProvider = StateProvider.autoDispose<MenuWorkspaceTab>((
  ref,
) {
  ref.watch(menuScopeProvider);
  ref.watch(ingredientScopeProvider);
  return MenuWorkspaceTab.menuItems;
});

MenuWorkspaceTab resolveMenuTab(
  MenuWorkspaceTab selected, {
  required bool canMenuView,
  required bool canIngredientView,
}) {
  if (!canMenuView && selected != MenuWorkspaceTab.ingredients) {
    return MenuWorkspaceTab.ingredients;
  }
  if (!canIngredientView && selected == MenuWorkspaceTab.ingredients) {
    return MenuWorkspaceTab.menuItems;
  }
  return selected;
}

final menuGroupFilterProvider = StateProvider<MenuItemGroupSummary?>((ref) {
  ref.watch(menuScopeProvider);
  return null;
});

final menuCatalogEventsProvider = ChangeNotifierProvider((ref) {
  ref.watch(menuScopeProvider);
  return MenuCatalogEvents();
});

/// One access recovery attempt per scope, shared by lists/selector/dialogs.
/// A repeated server refusal cannot cause an endless restore/request loop.
class MenuAccessRecovery {
  MenuAccessRecovery(this.auth, this.notice);
  final AuthController auth;
  final void Function(String) notice;
  final _handledScopes = <Object?>{};
  Future<void>? _inFlight;
  Future<void> handle(Failure failure) async {
    notice(failure.message);
    final scope = AccessPolicy.menuScope(auth.state.session);
    if (!_handledScopes.add(scope)) return;
    final pending = _inFlight;
    if (pending != null) {
      await pending;
      return;
    }
    final future = auth.revalidateAccess();
    _inFlight = future;
    try {
      await future;
    } finally {
      _inFlight = null;
    }
  }
}

class IngredientAccessRecovery {
  IngredientAccessRecovery(this.auth, this.notice);
  final AuthController auth;
  final void Function(String) notice;
  final _handledScopes = <Object?>{};
  Future<void>? _inFlight;
  Future<void> handle(Failure failure) async {
    notice(failure.message);
    final scope = AccessPolicy.ingredientScope(auth.state.session);
    if (!_handledScopes.add(scope)) return;
    final pending = _inFlight;
    if (pending != null) {
      await pending;
      return;
    }
    final future = auth.revalidateAccess();
    _inFlight = future;
    try {
      await future;
    } finally {
      _inFlight = null;
    }
  }
}

final ingredientAccessRecoveryProvider = Provider(
  (ref) => IngredientAccessRecovery(
    ref.read(authControllerProvider),
    (message) => ref.read(menuNoticeProvider.notifier).state = message,
  ),
);

final menuAccessRecoveryProvider = Provider(
  (ref) => MenuAccessRecovery(
    ref.read(authControllerProvider),
    (message) => ref.read(menuNoticeProvider.notifier).state = message,
  ),
);

final ingredientControllerProvider = ChangeNotifierProvider((ref) {
  ref.watch(ingredientScopeProvider);
  final auth = ref.read(authControllerProvider);
  final repository = ref.watch(ingredientRepositoryProvider);
  final controller = IngredientController(
    session: () => auth.state.session,
    list: GetIngredients(repository),
    detail: GetIngredientDetail(repository),
    create: CreateIngredient(repository),
    update: UpdateIngredient(repository),
    status: SetIngredientStatus(repository),
    delete: DeleteIngredient(repository),
    events: ref.read(menuCatalogEventsProvider),
    onAccessDenied: ref.read(ingredientAccessRecoveryProvider).handle,
  );
  Future.microtask(controller.load);
  return controller;
});

final menuGroupControllerProvider = ChangeNotifierProvider((ref) {
  ref.watch(menuScopeProvider);
  final auth = ref.read(authControllerProvider);
  final repository = ref.watch(menuGroupRepositoryProvider);
  final controller = MenuGroupController(
    session: () => auth.state.session,
    list: GetMenuGroups(repository),
    detail: GetMenuGroupDetail(repository),
    create: CreateMenuGroup(repository),
    update: UpdateMenuGroup(repository),
    status: SetMenuGroupStatus(repository),
    delete: DeleteMenuGroup(repository),
    events: ref.read(menuCatalogEventsProvider),
    onAccessDenied: ref.read(menuAccessRecoveryProvider).handle,
  );
  Future.microtask(controller.load);
  return controller;
});
final menuItemControllerProvider = ChangeNotifierProvider((ref) {
  ref.watch(menuScopeProvider);
  final auth = ref.read(authControllerProvider);
  final repository = ref.watch(menuItemRepositoryProvider);
  final controller = MenuItemController(
    session: () => auth.state.session,
    list: GetMenuItems(repository),
    detail: GetMenuItemDetail(repository),
    create: CreateMenuItem(repository),
    update: UpdateMenuItem(repository),
    status: SetMenuItemStatus(repository),
    availability: SetMenuItemAvailability(repository),
    group: SetMenuItemGroup(repository),
    delete: DeleteMenuItem(repository),
    events: ref.read(menuCatalogEventsProvider),
    onAccessDenied: ref.read(menuAccessRecoveryProvider).handle,
  );
  Future.microtask(controller.load);
  return controller;
});
final menuGroupSelectorProvider = ChangeNotifierProvider.autoDispose
    .family<MenuGroupSelectorController, bool>((ref, activeOnly) {
      ref.watch(menuScopeProvider);
      final auth = ref.read(authControllerProvider);
      final controller = MenuGroupSelectorController(
        session: () => auth.state.session,
        list: GetMenuGroups(ref.watch(menuGroupRepositoryProvider)),
        activeOnly: activeOnly,
        events: ref.read(menuCatalogEventsProvider),
        onAccessDenied: ref.read(menuAccessRecoveryProvider).handle,
      );
      Future.microtask(controller.load);
      return controller;
    });
