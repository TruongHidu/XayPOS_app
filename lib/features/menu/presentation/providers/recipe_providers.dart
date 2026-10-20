import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/data_sources/recipe_remote_data_source.dart';
import '../../data/repositories/recipe_repository_impl.dart';
import '../../domain/repositories/recipe_repository.dart';
import '../../domain/use_cases/ingredient_use_cases.dart';
import '../../domain/use_cases/recipe_use_cases.dart';
import '../controllers/recipe_controller.dart';
import '../controllers/recipe_cost_controller.dart';
import '../../domain/use_cases/menu_item_use_cases.dart';
import '../controllers/recipe_ingredient_selector_controller.dart';

final recipeScopeProvider = authControllerProvider.select(
  (auth) => AccessPolicy.recipeScope(auth.state.session),
);

typedef RecipeCostTarget = ({String menuItemId, String recipeId});

final recipeCostProvider = ChangeNotifierProvider.autoDispose
    .family<RecipeCostController, RecipeCostTarget>((ref, target) {
      ref.watch(recipeScopeProvider);
      final auth = ref.read(authControllerProvider);
      final controller = RecipeCostController(
        menuItemId: target.menuItemId,
        recipeId: target.recipeId,
        session: () => auth.state.session,
        get: GetRecipeCostEstimate(ref.watch(recipeRepositoryProvider)),
        events: ref.read(menuCatalogEventsProvider),
        onAccessDenied: ref.read(recipeAccessRecoveryProvider).handle,
      );
      Future.microtask(controller.load);
      return controller;
    });

final recipeMenuPriceProvider = ChangeNotifierProvider.autoDispose
    .family<RecipeMenuPriceController, String>((ref, menuItemId) {
      ref.watch(recipeScopeProvider);
      final auth = ref.read(authControllerProvider);
      final controller = RecipeMenuPriceController(
        menuItemId: menuItemId,
        session: () => auth.state.session,
        get: GetMenuItemDetail(ref.watch(menuItemRepositoryProvider)),
        events: ref.read(menuCatalogEventsProvider),
      );
      Future.microtask(controller.load);
      return controller;
    });

final recipeRemoteDataSourceProvider = Provider(
  (ref) => RecipeRemoteDataSource(ref.watch(apiClientsProvider).authenticated),
);

final recipeRepositoryProvider = Provider<RecipeRepository>(
  (ref) => RecipeRepositoryImpl(ref.watch(recipeRemoteDataSourceProvider)),
);

/// Shared across active/history/detail/picker: at most one restore per scope.
class RecipeAccessRecovery {
  RecipeAccessRecovery(this.auth, this.notice);
  final AuthController auth;
  final void Function(String) notice;
  final _handledScopes = <Object?>{};
  Future<void>? _inFlight;

  Future<void> handle(Failure failure) async {
    notice(failure.message);
    final scope = AccessPolicy.recipeScope(auth.state.session);
    if (!_handledScopes.add(scope)) return;
    final pending = _inFlight;
    if (pending != null) {
      await pending;
      return;
    }
    final future = auth.restore();
    _inFlight = future;
    try {
      await future;
    } finally {
      _inFlight = null;
    }
  }
}

final recipeAccessRecoveryProvider = Provider(
  (ref) => RecipeAccessRecovery(
    ref.read(authControllerProvider),
    (message) => ref.read(menuNoticeProvider.notifier).state = message,
  ),
);

final recipeControllerProvider = ChangeNotifierProvider.autoDispose
    .family<RecipeController, String>((ref, menuItemId) {
      ref.watch(recipeScopeProvider);
      final auth = ref.read(authControllerProvider);
      final repository = ref.watch(recipeRepositoryProvider);
      final controller = RecipeController(
        menuItemId: menuItemId,
        session: () => auth.state.session,
        active: GetActiveRecipe(repository),
        history: GetRecipeHistory(repository),
        detail: GetRecipeDetail(repository),
        create: CreateRecipe(repository),
        createVersion: CreateRecipeVersion(repository),
        deactivate: DeactivateRecipe(repository),
        events: ref.read(menuCatalogEventsProvider),
        onAccessDenied: ref.read(recipeAccessRecoveryProvider).handle,
      );
      Future.microtask(controller.loadActive);
      return controller;
    });

final recipeIngredientSelectorProvider = ChangeNotifierProvider.autoDispose
    .family<RecipeIngredientSelectorController, String>((ref, menuItemId) {
      ref.watch(recipeScopeProvider);
      final auth = ref.read(authControllerProvider);
      final repository = ref.watch(ingredientRepositoryProvider);
      final controller = RecipeIngredientSelectorController(
        menuItemId: menuItemId,
        session: () => auth.state.session,
        list: GetIngredients(repository),
        detail: GetIngredientDetail(repository),
        events: ref.read(menuCatalogEventsProvider),
        onAccessDenied: ref.read(recipeAccessRecoveryProvider).handle,
      );
      Future.microtask(controller.load);
      return controller;
    });
