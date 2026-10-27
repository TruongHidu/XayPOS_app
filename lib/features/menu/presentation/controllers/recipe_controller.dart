import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/menu_page.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/entities/recipe_inputs.dart';
import '../../domain/entities/recipe_query.dart';
import '../../domain/use_cases/recipe_use_cases.dart';
import '../../domain/validation/recipe_validation.dart';
import 'menu_catalog_events.dart';

/// The active aggregate and paginated summaries for one menu item.
/// Drafts belong to the form, so reads and catalog events cannot replace them.
class RecipeController extends ChangeNotifier {
  RecipeController({
    required this.menuItemId,
    required AppSession? Function() session,
    required GetActiveRecipe active,
    required GetRecipeHistory history,
    required GetRecipeDetail detail,
    required CreateRecipe create,
    required CreateRecipeVersion createVersion,
    required DeactivateRecipe deactivate,
    required MenuCatalogEvents events,
    this.onAccessDenied,
    RecipeQuery query = const RecipeQuery(),
  }) : _session = session,
       _scope = AccessPolicy.recipeScope(session()),
       _getActive = active,
       _getHistory = history,
       _getDetail = detail,
       _create = create,
       _createVersion = createVersion,
       _deactivate = deactivate,
       _events = events,
       _query = query {
    _eventRevision = events.recipeRevision;
    events.addListener(_catalogChanged);
  }

  final String menuItemId;
  final AppSession? Function() _session;
  final Object? _scope;
  final GetActiveRecipe _getActive;
  final GetRecipeHistory _getHistory;
  final GetRecipeDetail _getDetail;
  final CreateRecipe _create;
  final CreateRecipeVersion _createVersion;
  final DeactivateRecipe _deactivate;
  final MenuCatalogEvents _events;
  final Future<void> Function(Failure)? onAccessDenied;

  Recipe? _active;
  bool _activeLoaded = false;
  bool _activeLoading = false;
  Failure? _activeFailure;
  MenuPage<RecipeSummary>? _history;
  bool _historyRequested = false;
  bool _historyLoading = false;
  Failure? _historyFailure;
  RecipeQuery _query;
  bool _busy = false;
  bool _disposed = false;
  bool _publishing = false;
  bool _baselineNeedsReload = false;
  int _activeGeneration = 0;
  int _historyGeneration = 0;
  late int _eventRevision;
  final _detailGenerations = <String, int>{};

  bool get isCurrent =>
      !_disposed && _scope == AccessPolicy.recipeScope(_session());
  bool can(String permission) =>
      isCurrent && AccessPolicy.canRecipe(_session(), permission);
  Recipe? get active => isCurrent ? _active : null;
  bool get activeLoaded => isCurrent && _activeLoaded;
  bool get activeLoading => isCurrent && _activeLoading;
  Failure? get activeFailure => isCurrent ? _activeFailure : expired;
  MenuPage<RecipeSummary>? get history => isCurrent ? _history : null;
  bool get historyLoading => isCurrent && _historyLoading;
  Failure? get historyFailure => isCurrent ? _historyFailure : expired;
  RecipeQuery get query => isCurrent ? _query : const RecipeQuery();
  bool get busy => isCurrent && _busy;
  bool get baselineNeedsReload => isCurrent && _baselineNeedsReload;

  static const expired = Failure(
    type: FailureType.forbidden,
    code: 'RECIPE_SCOPE_CHANGED',
    message: 'Phiên làm việc hoặc quyền truy cập công thức đã thay đổi.',
  );
  static const unchanged = Failure(
    type: FailureType.validation,
    code: 'SAME_RECIPE_VERSION_NOT_ALLOWED',
    message: 'Công thức chưa có thay đổi thực tế.',
  );
  static const baselineChanged = Failure(
    type: FailureType.conflict,
    code: 'CONCURRENT_RECIPE_UPDATE',
    message:
        'Phiên bản hiện hành đã thay đổi. Hãy tải lại để kiểm tra trước khi lưu; bản nháp vẫn được giữ.',
  );

  static Failure validation(Map<String, String> errors) => Failure(
    type: FailureType.validation,
    code: 'VALIDATION_ERROR',
    message: 'Vui lòng kiểm tra thông tin công thức.',
    fieldErrors: errors,
  );

  Future<void> loadActive() async {
    if (!can('RECIPE_VIEW')) return;
    final generation = ++_activeGeneration;
    _activeLoading = true;
    _activeFailure = null;
    notifyListeners();
    final result = await _getActive(menuItemId);
    if (!can('RECIPE_VIEW') || generation != _activeGeneration) return;
    switch (result) {
      case Success(value: final recipe):
        _active = recipe;
        _activeLoaded = true;
        _baselineNeedsReload = false;
      case Error(failure: final failure):
        if (failure.code == 'ACTIVE_RECIPE_NOT_FOUND') {
          _active = null;
          _activeLoaded = true;
          _baselineNeedsReload = false;
        } else {
          await report(failure);
          if (!can('RECIPE_VIEW') || generation != _activeGeneration) return;
          _activeFailure = failure;
        }
    }
    _activeLoading = false;
    notifyListeners();
  }

  Future<void> loadHistory() async {
    if (!can('RECIPE_VIEW')) return;
    final query = _query;
    if (!query.isValid) {
      _historyFailure = validation({'query': 'Bộ lọc lịch sử không hợp lệ.'});
      _historyLoading = false;
      notifyListeners();
      return;
    }
    final generation = ++_historyGeneration;
    _historyRequested = true;
    _historyLoading = true;
    _historyFailure = null;
    notifyListeners();
    final result = await _getHistory(menuItemId, query);
    if (!can('RECIPE_VIEW') || generation != _historyGeneration) return;
    switch (result) {
      case Success(value: final page):
        if (query.page > 0 && page.content.isEmpty) {
          final last = page.totalPages > 0 ? page.totalPages - 1 : 0;
          if (last < query.page) {
            _query = query.copyWith(page: last);
            await loadHistory();
            return;
          }
        }
        _history = page;
      case Error(failure: final failure):
        await report(failure);
        if (!can('RECIPE_VIEW') || generation != _historyGeneration) return;
        _historyFailure = failure;
    }
    _historyLoading = false;
    notifyListeners();
  }

  void setHistoryQuery(RecipeQuery query) {
    if (!can('RECIPE_VIEW')) return;
    ++_historyGeneration;
    if (!query.isValid) {
      _historyFailure = validation({'query': 'Bộ lọc lịch sử không hợp lệ.'});
      _historyLoading = false;
      notifyListeners();
      return;
    }
    final orderingChanged =
        query.sortBy != _query.sortBy ||
        query.direction != _query.direction ||
        query.size != _query.size;
    _query = orderingChanged ? query.copyWith(page: 0) : query;
    unawaited(loadHistory());
  }

  Future<Result<Recipe>> detail(String recipeId) async {
    if (!can('RECIPE_VIEW')) return const Error(expired);
    final generation = (_detailGenerations[recipeId] ?? 0) + 1;
    _detailGenerations[recipeId] = generation;
    final result = await _getDetail(menuItemId, recipeId);
    if (!can('RECIPE_VIEW') || _detailGenerations[recipeId] != generation) {
      return const Error(expired);
    }
    if (result case Error(failure: final failure)) await report(failure);
    return can('RECIPE_VIEW') && _detailGenerations[recipeId] == generation
        ? result
        : const Error(expired);
  }

  Future<Result<Recipe>> create(RecipeInput input) async {
    if (!can('RECIPE_CREATE')) return const Error(expired);
    final errors = RecipeValidation.input(input);
    if (errors.isNotEmpty) return Error(validation(errors));
    if (_baselineNeedsReload) return const Error(baselineChanged);
    if (_active != null) {
      return const Error(
        Failure(
          type: FailureType.conflict,
          code: 'ACTIVE_RECIPE_ALREADY_EXISTS',
          message: 'Món đã có phiên bản hiện hành. Hãy tải lại để kiểm tra.',
        ),
      );
    }
    return _mutate('RECIPE_CREATE', () => _create(menuItemId, input));
  }

  Future<Result<Recipe>> createVersion(
    Recipe baseline,
    RecipeInput input,
  ) async {
    if (!can('RECIPE_UPDATE')) return const Error(expired);
    final errors = RecipeValidation.input(input);
    if (errors.isNotEmpty) return Error(validation(errors));
    if (_baselineNeedsReload ||
        !baseline.active ||
        baseline.version < 0 ||
        baseline.menuItemId != menuItemId ||
        _active?.id != baseline.id ||
        _active?.version != baseline.version) {
      return const Error(baselineChanged);
    }
    if (input.sameAs(baseline)) return const Error(unchanged);
    final versionInput = CreateRecipeVersionInput(
      expectedVersion: baseline.version,
      yieldQuantity: input.yieldQuantity,
      ingredients: input.ingredients,
    );
    return _mutate(
      'RECIPE_UPDATE',
      () => _createVersion(menuItemId, baseline.id, versionInput),
    );
  }

  Future<Result<void>> deactivate(Recipe baseline) async {
    if (!can('RECIPE_DELETE')) return const Error(expired);
    if (baseline.menuItemId != menuItemId || baseline.version < 0) {
      return const Error(baselineChanged);
    }
    return _mutate<void>(
      'RECIPE_DELETE',
      () => _deactivate(menuItemId, baseline.id, baseline.version),
      reloadActive: true,
    );
  }

  Future<Result<T>> _mutate<T>(
    String permission,
    Future<Result<T>> Function() operation, {
    bool reloadActive = false,
  }) async {
    if (!can(permission)) return const Error(expired);
    if (_busy) {
      return const Error(
        Failure(
          type: FailureType.conflict,
          code: 'RECIPE_BUSY',
          message: 'Thao tác công thức đang được xử lý. Vui lòng chờ.',
        ),
      );
    }
    _busy = true;
    notifyListeners();
    try {
      final result = await operation();
      if (!can(permission)) return const Error(expired);
      switch (result) {
        case Success(value: final value):
          // Supersede reads started before this successful mutation.
          ++_activeGeneration;
          ++_historyGeneration;
          _activeLoading = false;
          _historyLoading = false;
          if (value is Recipe) {
            _active = value;
            _activeLoaded = true;
            _activeFailure = null;
            _baselineNeedsReload = false;
          }
          _publishing = true;
          try {
            _events.recipeChanged(menuItemId);
          } finally {
            _publishing = false;
          }
          notifyListeners();
          // DELETE targets a specific id; a newer active recipe may exist.
          if (reloadActive) await loadActive();
          if (_historyRequested && can('RECIPE_VIEW')) await loadHistory();
        case Error(failure: final failure):
          if (const {
            'CONCURRENT_RECIPE_UPDATE',
            'ACTIVE_RECIPE_ALREADY_EXISTS',
            'RECIPE_NOT_ACTIVE',
            'RECIPE_NOT_FOUND',
            'ACTIVE_RECIPE_NOT_FOUND',
            'RECIPE_APPLICATION_ENABLED',
          }.contains(failure.code)) {
            _baselineNeedsReload = true;
            // A read started before this refusal cannot verify the baseline.
            ++_activeGeneration;
            _activeLoading = false;
          }
          await report(failure);
          if (!can(permission)) return const Error(expired);
          if (failure.isNetwork) {
            return Error(
              Failure(
                type: failure.type,
                code: failure.code,
                fieldErrors: failure.fieldErrors,
                message:
                    'Chưa xác định công thức đã được lưu hay chưa. Hãy kiểm tra phiên bản hiện hành và lịch sử trước khi gửi lại.',
              ),
            );
          }
      }
      return can(permission) ? result : const Error(expired);
    } finally {
      _busy = false;
      if (isCurrent) notifyListeners();
    }
  }

  Future<void> refresh() async {
    final historyWasRequested = _historyRequested;
    await Future.wait([loadActive(), if (historyWasRequested) loadHistory()]);
  }

  void _catalogChanged() {
    if (!isCurrent || _eventRevision == _events.recipeRevision) return;
    _eventRevision = _events.recipeRevision;
    if (_publishing || _events.changedRecipeMenuItemId != menuItemId) return;
    unawaited(refresh());
  }

  Future<void> report(Failure failure) async {
    if (!isCurrent) return;
    if (const {
      FailureType.unauthorized,
      FailureType.forbidden,
      FailureType.featureNotEntitled,
      FailureType.subscriptionNotActive,
      FailureType.restaurantInactive,
    }.contains(failure.type)) {
      await onAccessDenied?.call(failure);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_activeGeneration;
    ++_historyGeneration;
    _events.removeListener(_catalogChanged);
    super.dispose();
  }
}
