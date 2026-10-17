import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/ingredient_query.dart';
import '../../domain/use_cases/ingredient_use_cases.dart';
import 'menu_catalog_events.dart';

/// Search state owned by the recipe picker, independent of catalog filters.
/// Selected ingredients and entered quantities remain in the form's draft.
class RecipeIngredientSelectorState {
  const RecipeIngredientSelectorState({
    this.query = const IngredientQuery(
      active: true,
      sortBy: 'name',
      direction: 'asc',
    ),
    this.rows = const [],
    this.loading = false,
    this.hasLoaded = false,
    this.failure,
    this.totalElements = 0,
    this.totalPages = 0,
  });

  final IngredientQuery query;
  final List<Ingredient> rows;
  final bool loading;
  final bool hasLoaded;
  final Failure? failure;
  final int totalElements;
  final int totalPages;

  bool get initialLoading => loading && !hasLoaded;

  RecipeIngredientSelectorState copyWith({
    IngredientQuery? query,
    List<Ingredient>? rows,
    bool? loading,
    bool? hasLoaded,
    Failure? Function()? failure,
    int? totalElements,
    int? totalPages,
  }) => RecipeIngredientSelectorState(
    query: query ?? this.query,
    rows: rows == null ? this.rows : List.unmodifiable(rows),
    loading: loading ?? this.loading,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    failure: failure != null ? failure() : this.failure,
    totalElements: totalElements ?? this.totalElements,
    totalPages: totalPages ?? this.totalPages,
  );
}

class RecipeIngredientSelectorController extends ChangeNotifier {
  RecipeIngredientSelectorController({
    required this.menuItemId,
    required AppSession? Function() session,
    required GetIngredients list,
    required GetIngredientDetail detail,
    MenuCatalogEvents? events,
    this.onAccessDenied,
  }) : _session = session,
       _scope = AccessPolicy.recipeScope(session()),
       _list = list,
       _detail = detail,
       _events = events {
    _ingredientRevision = events?.ingredientRevision ?? 0;
    events?.addListener(_catalogChanged);
  }

  final String menuItemId;
  final AppSession? Function() _session;
  final Object? _scope;
  final GetIngredients _list;
  final GetIngredientDetail _detail;
  final MenuCatalogEvents? _events;
  final Future<void> Function(Failure)? onAccessDenied;
  RecipeIngredientSelectorState _state = const RecipeIngredientSelectorState();
  bool _disposed = false;
  int _generation = 0;
  int _ingredientRevision = 0;
  Timer? _debounce;
  final _detailGenerations = <String, int>{};

  bool get isCurrent =>
      !_disposed && _scope == AccessPolicy.recipeScope(_session());
  bool get canRead =>
      isCurrent && AccessPolicy.canIngredient(_session(), 'INGREDIENT_VIEW');
  RecipeIngredientSelectorState get state => isCurrent
      ? _state
      : const RecipeIngredientSelectorState(failure: expired);
  IngredientQuery get query => state.query;
  List<Ingredient> get rows => state.rows;
  int get totalPages => state.totalPages;
  bool get loading => state.loading;
  Failure? get failure => state.failure;

  static const expired = Failure(
    type: FailureType.forbidden,
    code: 'RECIPE_INGREDIENT_ACCESS_REQUIRED',
    message:
        'Cần quyền xem danh mục nguyên liệu để tìm, thêm hoặc xác minh nguyên liệu cho công thức.',
  );

  void search(String value) {
    if (!canRead) return;
    _debounce?.cancel();
    ++_generation;
    final query = _state.query.copyWith(q: value.trim(), page: 0);
    _state = _state.copyWith(
      query: query,
      loading: false,
      failure: () => query.isValid
          ? null
          : const Failure(
              type: FailureType.validation,
              code: 'VALIDATION_ERROR',
              message: 'Từ khóa tìm nguyên liệu có tối đa 100 ký tự.',
              fieldErrors: {'q': 'Từ khóa có tối đa 100 ký tự.'},
            ),
    );
    notifyListeners();
    if (query.isValid) {
      _debounce = Timer(const Duration(milliseconds: 350), load);
    }
  }

  void setPage(int page) {
    if (!canRead || page < 0 || (page >= _state.totalPages && page != 0)) {
      return;
    }
    _debounce?.cancel();
    _state = _state.copyWith(query: _state.query.copyWith(page: page));
    unawaited(load());
  }

  Future<void> load() async {
    if (!canRead) return;
    _debounce?.cancel();
    final query = _state.query;
    if (!query.isValid) return;
    final generation = ++_generation;
    _state = _state.copyWith(loading: true, failure: () => null);
    notifyListeners();
    final result = await _list(query);
    if (!canRead || generation != _generation) return;
    switch (result) {
      case Success(value: final page):
        if (query.page > 0 && page.content.isEmpty) {
          final last = page.totalPages > 0 ? page.totalPages - 1 : 0;
          if (last < query.page) {
            _state = _state.copyWith(query: query.copyWith(page: last));
            await load();
            return;
          }
        }
        _state = _state.copyWith(
          rows: page.content,
          totalElements: page.totalElements,
          totalPages: page.totalPages,
          hasLoaded: true,
          loading: false,
        );
      case Error(failure: final failure):
        await _report(failure);
        if (!canRead || generation != _generation) return;
        _state = _state.copyWith(loading: false, failure: () => failure);
    }
    notifyListeners();
  }

  Future<Result<Ingredient>> detail(String id) async {
    if (!canRead) return const Error(expired);
    final generation = (_detailGenerations[id] ?? 0) + 1;
    _detailGenerations[id] = generation;
    final result = await _detail(id);
    if (!canRead || _detailGenerations[id] != generation) {
      return const Error(expired);
    }
    if (result case Error(failure: final failure)) await _report(failure);
    return canRead && _detailGenerations[id] == generation
        ? result
        : const Error(expired);
  }

  Future<void> _report(Failure failure) async {
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

  void _catalogChanged() {
    final events = _events;
    if (!canRead ||
        events == null ||
        _ingredientRevision == events.ingredientRevision) {
      return;
    }
    _ingredientRevision = events.ingredientRevision;
    // A pending search keeps its own debounce and current draft remains local.
    if (_debounce?.isActive != true) unawaited(load());
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _debounce?.cancel();
    _events?.removeListener(_catalogChanged);
    super.dispose();
  }
}
