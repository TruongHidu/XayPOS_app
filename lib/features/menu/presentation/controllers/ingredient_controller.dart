import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/ingredient_inputs.dart';
import '../../domain/entities/ingredient_query.dart';
import '../../domain/use_cases/ingredient_use_cases.dart';
import '../../domain/validation/ingredient_validation.dart';
import 'menu_catalog_events.dart';

class IngredientListState {
  const IngredientListState({
    this.query = const IngredientQuery(),
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

  IngredientListState copyWith({
    IngredientQuery? query,
    List<Ingredient>? rows,
    bool? loading,
    bool? hasLoaded,
    Failure? Function()? failure,
    int? totalElements,
    int? totalPages,
  }) => IngredientListState(
    query: query ?? this.query,
    rows: rows == null ? this.rows : List.unmodifiable(rows),
    loading: loading ?? this.loading,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    failure: failure != null ? failure() : this.failure,
    totalElements: totalElements ?? this.totalElements,
    totalPages: totalPages ?? this.totalPages,
  );
}

class IngredientController extends ChangeNotifier {
  IngredientController({
    required AppSession? Function() session,
    required GetIngredients list,
    required GetIngredientDetail detail,
    required CreateIngredient create,
    required UpdateIngredient update,
    required SetIngredientStatus status,
    required DeleteIngredient delete,
    required MenuCatalogEvents events,
    this.onAccessDenied,
    IngredientQuery query = const IngredientQuery(),
  }) : _session = session,
       _scope = AccessPolicy.ingredientScope(session()),
       _list = list,
       _detail = detail,
       _create = create,
       _update = update,
       _status = status,
       _delete = delete,
       _events = events,
       _state = IngredientListState(query: query) {
    _eventRevision = events.ingredientRevision;
    events.addListener(_catalogChanged);
  }

  final AppSession? Function() _session;
  final Object? _scope;
  final GetIngredients _list;
  final GetIngredientDetail _detail;
  final CreateIngredient _create;
  final UpdateIngredient _update;
  final SetIngredientStatus _status;
  final DeleteIngredient _delete;
  final MenuCatalogEvents _events;
  final Future<void> Function(Failure)? onAccessDenied;

  IngredientListState _state;
  IngredientListState get state => _state;
  bool _disposed = false;
  int _generation = 0;
  Timer? _debounce;
  final _pending = <String>{};
  final _detailGeneration = <String, int>{};
  late int _eventRevision;
  bool _publishing = false,
      _catalogReloadRequested = false,
      _catalogReloadScheduled = false;

  void _catalogChanged() {
    if (!isCurrent || _eventRevision == _events.ingredientRevision) return;
    _eventRevision = _events.ingredientRevision;
    if (_publishing) return;
    ++_generation;
    final id = _events.changedIngredientId;
    for (final key in _detailGeneration.keys.toList()) {
      if (id == null || key == id) {
        _detailGeneration[key] = _detailGeneration[key]! + 1;
      }
    }
    _catalogReloadRequested = true;
    _scheduleCatalogReload();
  }

  void _scheduleCatalogReload() {
    if (_catalogReloadScheduled ||
        !_catalogReloadRequested ||
        _pending.isNotEmpty) {
      return;
    }
    _catalogReloadScheduled = true;
    Future.microtask(() {
      _catalogReloadScheduled = false;
      if (!can('INGREDIENT_VIEW') ||
          !_catalogReloadRequested ||
          _pending.isNotEmpty) {
        return;
      }
      _catalogReloadRequested = false;
      unawaited(load());
    });
  }

  bool get isCurrent =>
      !_disposed && _scope == AccessPolicy.ingredientScope(_session());

  bool can(String permission) =>
      isCurrent && AccessPolicy.canIngredient(_session(), permission);

  bool isPending(String id) => _pending.contains(id);

  static const expired = Failure(
    type: FailureType.forbidden,
    code: 'INGREDIENT_SCOPE_CHANGED',
    message: 'Phiên làm việc hoặc quyền truy cập nguyên liệu đã thay đổi.',
  );

  static const emptyUpdate = Failure(
    type: FailureType.validation,
    code: 'EMPTY_UPDATE_REQUEST',
    message: 'Chưa có thay đổi để lưu.',
  );

  static Failure validation(Map<String, String> errors) => Failure(
    type: FailureType.validation,
    code: 'VALIDATION_ERROR',
    message: 'Vui lòng kiểm tra thông tin đã nhập.',
    fieldErrors: errors,
  );

  void setQuery(IngredientQuery query, {bool debounce = false}) {
    if (!can('INGREDIENT_VIEW')) return;
    _debounce?.cancel();
    _generation++;

    if (!query.isValid) {
      _state = _state.copyWith(
        loading: false,
        failure: () => validation({
          'q': 'Bộ lọc hoặc từ khóa không hợp lệ (tối đa 100 ký tự).',
        }),
      );
      notifyListeners();
      return;
    }

    _state = _state.copyWith(
      query: query.copyWith(page: 0),
      failure: () => null,
    );
    notifyListeners();

    if (debounce) {
      _debounce = Timer(const Duration(milliseconds: 350), load);
    } else {
      unawaited(load());
    }
  }

  void search(String value) {
    final trimmed = value.trim();
    setQuery(_state.query.copyWith(q: trimmed), debounce: true);
  }

  void setActiveFilter(bool? active) {
    setQuery(_state.query.copyWith(active: () => active));
  }

  void setTrackInventoryFilter(bool? trackInventory) {
    setQuery(_state.query.copyWith(trackInventory: () => trackInventory));
  }

  void setSort(String sortBy, {String? direction}) {
    setQuery(
      _state.query.copyWith(
        sortBy: sortBy,
        direction: direction ?? _state.query.direction,
      ),
    );
  }

  void setPageSize(int size) {
    if (size == _state.query.size) return;
    setQuery(_state.query.copyWith(size: size));
  }

  void setPage(int page) {
    if (!can('INGREDIENT_VIEW') ||
        page < 0 ||
        (page >= _state.totalPages && page != 0)) {
      return;
    }
    _state = _state.copyWith(query: _state.query.copyWith(page: page));
    unawaited(load());
  }

  Future<void> load() async {
    if (!can('INGREDIENT_VIEW')) return;
    _debounce?.cancel();
    final generation = ++_generation;
    final query = _state.query;
    _state = _state.copyWith(loading: true, failure: () => null);
    notifyListeners();

    final result = await _list(query);
    if (!can('INGREDIENT_VIEW') || generation != _generation) return;

    switch (result) {
      case Success(value: final page):
        if (query.page > 0 && page.content.isEmpty) {
          final lastPage = page.totalPages > 0 ? page.totalPages - 1 : 0;
          if (lastPage < query.page) {
            _state = _state.copyWith(query: query.copyWith(page: lastPage));
            await load();
            return;
          }
        }
        _state = _state.copyWith(
          rows: page.content,
          loading: false,
          hasLoaded: true,
          totalElements: page.totalElements,
          totalPages: page.totalPages,
        );
      case Error(failure: final failure):
        await report(failure);
        if (!can('INGREDIENT_VIEW') || generation != _generation) return;
        _state = _state.copyWith(loading: false, failure: () => failure);
    }
    notifyListeners();
  }

  Future<Result<Ingredient>> detail(String id) =>
      readDetail(id, () => _detail(id));

  Future<Result<Ingredient>> create(CreateIngredientInput input) async {
    final errors = IngredientValidation.create(input);
    if (errors.isNotEmpty) return Error(validation(errors));

    return mutate(
      'create',
      'INGREDIENT_CREATE',
      () => _create(input),
      onSuccess: (item) => _events.ingredientChanged(item.id),
    );
  }

  Future<Result<Ingredient>> update(
    String id,
    UpdateIngredientInput input,
  ) async {
    if (input.isEmpty) return const Error(emptyUpdate);
    final errors = IngredientValidation.patch(input);
    if (errors.isNotEmpty) return Error(validation(errors));

    return mutate(
      id,
      'INGREDIENT_UPDATE',
      () => _update(id, input),
      onSuccess: (item) => _events.ingredientChanged(item.id),
    );
  }

  Future<Result<Ingredient>> setStatus(Ingredient baseline, bool active) =>
      mutate(
        baseline.id,
        'INGREDIENT_UPDATE',
        () => _status(baseline.id, active, baseline.version),
        onSuccess: (item) => _events.ingredientChanged(item.id),
      );

  Future<Result<void>> delete(Ingredient baseline) => mutate(
    baseline.id,
    'INGREDIENT_DELETE',
    () => _delete(baseline.id, baseline.version),
    onSuccess: (_) => _events.ingredientChanged(baseline.id),
  );

  Future<Result<T>> readDetail<T>(
    String id,
    Future<Result<T>> Function() request,
  ) async {
    if (!can('INGREDIENT_VIEW')) return const Error(expired);
    final generation = (_detailGeneration[id] ?? 0) + 1;
    _detailGeneration[id] = generation;

    final result = await request();
    if (!can('INGREDIENT_VIEW') || _detailGeneration[id] != generation) {
      return const Error(expired);
    }

    if (result case Error(failure: final failure)) {
      await report(failure);
      if (failure.type == FailureType.notFound && can('INGREDIENT_VIEW')) {
        await load();
      }
    }
    return can('INGREDIENT_VIEW') ? result : const Error(expired);
  }

  Future<Result<R>> mutate<R>(
    String key,
    String permission,
    Future<Result<R>> Function() operation, {
    void Function(R)? onSuccess,
    void Function(Failure)? onFailure,
  }) async {
    if (!can(permission)) return const Error(expired);
    if (!_pending.add(key)) {
      return const Error(
        Failure(
          type: FailureType.conflict,
          code: 'INGREDIENT_BUSY',
          message: 'Thao tác đang được xử lý. Vui lòng chờ.',
        ),
      );
    }
    notifyListeners();

    try {
      final result = await operation();
      if (!can(permission)) return const Error(expired);

      if (result case Success(value: final value)) {
        _publishing = true;
        try {
          onSuccess?.call(value);
        } finally {
          _publishing = false;
        }
        await load();
      } else if (result case Error(failure: final failure)) {
        onFailure?.call(failure);
        await report(failure);
        if (failure.type == FailureType.notFound && can('INGREDIENT_VIEW')) {
          await load();
        }
        if (failure.isNetwork) {
          return Error(
            Failure(
              type: failure.type,
              code: failure.code,
              fieldErrors: failure.fieldErrors,
              message:
                  'Chưa xác định thao tác đã được lưu hay chưa. Hãy tải lại để kiểm tra trước khi gửi lại.',
            ),
          );
        }
      }
      return can(permission) ? result : const Error(expired);
    } finally {
      _pending.remove(key);
      _scheduleCatalogReload();
      if (isCurrent) notifyListeners();
    }
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
    _generation++;
    _debounce?.cancel();
    _events.removeListener(_catalogChanged);
    super.dispose();
  }
}
