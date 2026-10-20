import 'package:flutter/foundation.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/menu_item.dart';
import '../../domain/entities/recipe_cost_estimate.dart';
import '../../domain/use_cases/menu_item_use_cases.dart';
import '../../domain/use_cases/recipe_use_cases.dart';
import 'menu_catalog_events.dart';

const _unexpected = Failure(
  type: FailureType.internal,
  message: 'Không thể tải dữ liệu. Vui lòng thử lại.',
);

/// No persistent cache: a panel owns its estimate until it is closed.
class RecipeCostController extends ChangeNotifier {
  RecipeCostController({
    required this.menuItemId,
    required this.recipeId,
    required this.session,
    required this.get,
    required this.events,
    this.onAccessDenied,
  }) : _scope = AccessPolicy.recipeScope(session()) {
    _ingredientRevision = events.ingredientRevision;
    _recipeRevision = events.recipeRevision;
    events.addListener(_catalogChanged);
  }
  final String menuItemId, recipeId;
  final AppSession? Function() session;
  final Object? _scope;
  final GetRecipeCostEstimate get;
  final MenuCatalogEvents events;
  final Future<void> Function(Failure)? onAccessDenied;
  RecipeCostEstimate? _value;
  Failure? failure;
  bool loading = false, stale = false, _disposed = false;
  int _generation = 0, _ingredientRevision = 0, _recipeRevision = 0;
  bool get current =>
      !_disposed &&
      _scope == AccessPolicy.recipeScope(session()) &&
      AccessPolicy.canRecipe(session(), 'RECIPE_VIEW');
  RecipeCostEstimate? get value => current ? _value : null;
  void _catalogChanged() {
    if (!current) return;
    final ingredientChanged =
        _ingredientRevision != events.ingredientRevision &&
        (events.changedIngredientId == null ||
            _value == null ||
            _value!.ingredients.any(
              (e) => e.ingredientId == events.changedIngredientId,
            ));
    final recipeChanged =
        _recipeRevision != events.recipeRevision &&
        events.changedRecipeMenuItemId == menuItemId;
    _ingredientRevision = events.ingredientRevision;
    _recipeRevision = events.recipeRevision;
    if (ingredientChanged || recipeChanged) {
      ++_generation;
      loading = false;
      stale = true;
      notifyListeners();
    }
  }

  Future<void> load() async {
    if (!current || loading) return;
    final generation = ++_generation;
    loading = true;
    failure = null;
    notifyListeners();
    Result<RecipeCostEstimate> result;
    try {
      result = await get(menuItemId, recipeId);
    } catch (_) {
      result = const Error(_unexpected);
    }
    if (!current || generation != _generation) return;
    switch (result) {
      case Success(value: final estimate):
        if (estimate.menuItemId != menuItemId ||
            estimate.recipeId != recipeId) {
          failure = _unexpected;
          stale = _value != null;
        } else {
          _value = estimate;
          stale = false;
        }
      case Error(failure: final error):
        failure = error;
        stale = _value != null;
    }
    loading = false;
    notifyListeners();
    final error = failure;
    if (current &&
        error != null &&
        const {
          FailureType.unauthorized,
          FailureType.forbidden,
          FailureType.featureNotEntitled,
          FailureType.subscriptionNotActive,
          FailureType.restaurantInactive,
        }.contains(error.type)) {
      await onAccessDenied?.call(error);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _value = null;
    events.removeListener(_catalogChanged);
    super.dispose();
  }
}

/// Shared by the workspace header and all recipe panels; one menu detail read.
class RecipeMenuPriceController extends ChangeNotifier {
  RecipeMenuPriceController({
    required this.menuItemId,
    required this.session,
    required this.get,
    required this.events,
  }) : _scope = AccessPolicy.recipeScope(session()) {
    _revision = events.itemRevision;
    events.addListener(_catalogChanged);
  }
  final String menuItemId;
  final AppSession? Function() session;
  final Object? _scope;
  final GetMenuItemDetail get;
  final MenuCatalogEvents events;
  MenuItem? _menu;
  Failure? failure;
  bool loading = false, stale = false, _disposed = false;
  int _generation = 0, _revision = 0;
  bool get current =>
      !_disposed && _scope == AccessPolicy.recipeScope(session());
  bool get allowed => current && AccessPolicy.canMenu(session(), 'MENU_VIEW');
  MenuItem? get menu => allowed ? _menu : null;
  void _catalogChanged() {
    if (!current || _revision == events.itemRevision) return;
    _revision = events.itemRevision;
    if (events.changedItemId == null || events.changedItemId == menuItemId) {
      ++_generation;
      loading = false;
      stale = true;
      notifyListeners();
    }
  }

  Future<void> load() async {
    if (!allowed || loading) return;
    final generation = ++_generation;
    loading = true;
    failure = null;
    notifyListeners();
    Result<MenuItem> result;
    try {
      result = await get(menuItemId);
    } catch (_) {
      result = const Error(_unexpected);
    }
    if (!allowed || generation != _generation) return;
    switch (result) {
      case Success(value: final item):
        if (item.id != menuItemId) {
          failure = _unexpected;
          _menu = null;
        } else {
          _menu = item;
          stale = false;
        }
      case Error(failure: final error):
        failure = error;
        _menu = null;
    }
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _menu = null;
    events.removeListener(_catalogChanged);
    super.dispose();
  }
}
