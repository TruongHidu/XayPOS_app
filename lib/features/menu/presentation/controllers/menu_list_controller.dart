import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/paging/endless_pages.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/menu_page.dart';
import '../../domain/entities/menu_query.dart';

class MenuListState<T> {
  const MenuListState({
    this.query = const MenuQuery(),
    this.rows = const [],
    this.loading = false,
    this.hasLoaded = false,
    this.failure,
    this.totalElements = 0,
    this.totalPages = 0,
  });
  final MenuQuery query;
  final List<T> rows;
  final bool loading;
  final bool hasLoaded;
  final Failure? failure;
  final int totalElements;
  final int totalPages;
  bool get initialLoading => loading && !hasLoaded;
  bool get hasMore => query.page < totalPages - 1;

  MenuListState<T> copyWith({
    MenuQuery? query,
    List<T>? rows,
    bool? loading,
    bool? hasLoaded,
    Failure? Function()? failure,
    int? totalElements,
    int? totalPages,
  }) => MenuListState(
    query: query ?? this.query,
    rows: rows == null ? this.rows : List.unmodifiable(rows),
    loading: loading ?? this.loading,
    hasLoaded: hasLoaded ?? this.hasLoaded,
    failure: failure != null ? failure() : this.failure,
    totalElements: totalElements ?? this.totalElements,
    totalPages: totalPages ?? this.totalPages,
  );
}

/// Shared request lifecycle only; business operations stay in each controller.
abstract class MenuListController<T> extends ChangeNotifier {
  MenuListController({
    required AppSession? Function() session,
    required Future<Result<MenuPage<T>>> Function(MenuQuery) list,
    required this.items,
    required Object Function(T) idOf,
    this.onAccessDenied,
    MenuQuery query = const MenuQuery(),
  }) : _session = session,
       endless = EndlessPages<T>(idOf),
       _scope = AccessPolicy.menuScope(session()),
       _list = list,
       _state = MenuListState(query: query);

  final AppSession? Function() _session;
  final Object? _scope;
  final Future<Result<MenuPage<T>>> Function(MenuQuery) _list;
  final EndlessPages<T> endless;
  final Future<void> Function(Failure)? onAccessDenied;
  final bool items;
  MenuListState<T> _state;
  MenuListState<T> get state => _state;
  bool _disposed = false;
  int _generation = 0;
  Timer? _debounce;
  final _pending = <String>{};
  final _detailGeneration = <String, int>{};
  bool get isCurrent =>
      !_disposed && _scope == AccessPolicy.menuScope(_session());
  bool can(String permission) =>
      isCurrent && AccessPolicy.canMenu(_session(), permission);
  bool isPending(String id) => _pending.contains(id);

  static const expired = Failure(
    type: FailureType.forbidden,
    code: 'MENU_SCOPE_CHANGED',
    message: 'Phiên làm việc hoặc quyền truy cập thực đơn đã thay đổi.',
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

  void setQuery(MenuQuery query, {bool debounce = false}) {
    if (!can('MENU_VIEW')) return;
    _debounce?.cancel();
    _generation++;
    if (!query.isValid(items: items)) {
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

  void search(String value) =>
      setQuery(_state.query.copyWith(q: value.trim()), debounce: true);
  void setPage(int page) {
    if (!can('MENU_VIEW') ||
        page < 0 ||
        page >= _state.totalPages && page != 0) {
      return;
    }
    _state = _state.copyWith(query: _state.query.copyWith(page: page));
    unawaited(load());
  }

  Future<void> load() async {
    if (!can('MENU_VIEW')) return;
    _debounce?.cancel();
    final generation = ++_generation;
    final query = _state.query;
    _state = _state.copyWith(loading: true, failure: () => null);
    notifyListeners();
    final result = await endless.read(
      page: query.page,
      fetch: (page) => _list(query.copyWith(page: page)),
      content: (page) => page.content,
      totalPages: (page) => page.totalPages,
      active: () => can('MENU_VIEW') && generation == _generation,
    );
    if (!can('MENU_VIEW') || generation != _generation) return;
    switch (result) {
      case Success(value: final pages):
        final page = pages.last;
        if (query.page > 0 && pages.rows.isEmpty) {
          final lastPage = page.totalPages > 0 ? page.totalPages - 1 : 0;
          if (lastPage < query.page) {
            _state = _state.copyWith(query: query.copyWith(page: lastPage));
            await load();
            return;
          }
        }
        _state = _state.copyWith(
          query: query.copyWith(page: pages.lastPage),
          rows: pages.rows,
          loading: false,
          hasLoaded: true,
          totalElements: page.totalElements,
          totalPages: page.totalPages,
        );
      case Error(failure: final failure):
        await report(failure);
        if (!can('MENU_VIEW') || generation != _generation) return;
        _state = _state.copyWith(loading: false, failure: () => failure);
    }
    notifyListeners();
  }

  /// Appends the next page; a failure keeps the rows already shown.
  Future<void> loadMore() async {
    final current = _state;
    if (!can('MENU_VIEW') ||
        current.loading ||
        endless.loadingMore ||
        !current.hasMore ||
        _debounce?.isActive == true) {
      return;
    }
    final generation = ++_generation;
    final query = current.query.copyWith(page: current.query.page + 1);
    endless.begin();
    notifyListeners();
    final result = await _list(query);
    if (!can('MENU_VIEW') || generation != _generation) return;
    switch (result) {
      case Success(value: final page):
        _state = _state.copyWith(
          query: query,
          rows: endless.append(current.rows, page.content),
          totalElements: page.totalElements,
          totalPages: page.totalPages,
        );
      case Error(failure: final failure):
        await report(failure);
        if (!can('MENU_VIEW') || generation != _generation) return;
        endless.fail(failure);
    }
    notifyListeners();
  }

  Future<Result<T>> readDetail(
    String id,
    Future<Result<T>> Function() request,
  ) async {
    if (!can('MENU_VIEW')) return const Error(expired);
    final generation = (_detailGeneration[id] ?? 0) + 1;
    _detailGeneration[id] = generation;
    final result = await request();
    if (!can('MENU_VIEW') || _detailGeneration[id] != generation) {
      return const Error(expired);
    }
    if (result case Error(failure: final failure)) {
      await report(failure);
      if (failure.type == FailureType.notFound && can('MENU_VIEW')) {
        await load();
      }
    }
    return can('MENU_VIEW') ? result : const Error(expired);
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
          code: 'MENU_BUSY',
          message: 'Thao tác đang được xử lý. Vui lòng chờ.',
        ),
      );
    }
    notifyListeners();
    try {
      final result = await operation();
      if (!can(permission)) return const Error(expired);
      if (result case Success(value: final value)) {
        onSuccess?.call(value);
        await load();
      } else if (result case Error(failure: final failure)) {
        onFailure?.call(failure);
        await report(failure);
        if (failure.type == FailureType.notFound && can('MENU_VIEW')) {
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
    super.dispose();
  }
}
