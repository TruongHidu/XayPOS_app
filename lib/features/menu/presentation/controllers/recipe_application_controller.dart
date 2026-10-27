import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/menu_inputs.dart';
import '../../domain/entities/menu_item.dart';
import '../../domain/entities/recipe.dart';
import '../../domain/use_cases/menu_item_use_cases.dart';
import 'menu_catalog_events.dart';

/// Application is a menu mutation. Recipe activity and recipe lock versions are
/// deliberately not used to determine the menu toggle or its expectedVersion.
class RecipeApplicationController extends ChangeNotifier {
  RecipeApplicationController({
    required this.menuItemId,
    required this.session,
    required this.get,
    required this.update,
    required this.events,
    this.itemPending,
    this.onAccessDenied,
  }) : _scope = AccessPolicy.menuScope(session()) {
    _revision = events.itemRevision;
    events.addListener(_catalogChanged);
  }
  final String menuItemId;
  final AppSession? Function() session;
  final Object? _scope;
  final GetMenuItemDetail get;
  // Supplied by MenuItemController.update: shares its item mutation lock.
  final Future<Result<MenuItem>> Function(String, UpdateMenuItemInput) update;
  final bool Function()? itemPending;
  final MenuCatalogEvents events;
  final Future<void> Function(Failure)? onAccessDenied;
  MenuItem? _item;
  MenuItem? get item => canRead ? _item : null;
  Recipe? savedDefinition;
  Failure? failure;
  bool loading = false, _busy = false, stale = false;
  bool needsVerification = false, _disposed = false;
  int _generation = 0, _revision = 0;
  bool get current => !_disposed && _scope == AccessPolicy.menuScope(session());
  bool get canRead => current && AccessPolicy.canMenu(session(), 'MENU_VIEW');
  bool canSet(bool enabled) =>
      current &&
      AccessPolicy.canSetRecipeApplication(session(), enabled: enabled);
  bool get busy => _busy || itemPending?.call() == true;

  /// The surrounding menu detail already owns this current REST response.
  /// Seed only the initial read; never replace a pending or verified state.
  void seed(MenuItem? value) {
    if (!canRead ||
        value == null ||
        value.id != menuItemId ||
        _item != null ||
        loading ||
        _busy ||
        needsVerification) {
      return;
    }
    _item = value;
  }

  Future<void> loadIfNeeded() => _item == null ? load() : Future.value();
  void signalsChanged() {
    if (current) notifyListeners();
  }

  static const unavailable = Failure(
    type: FailureType.forbidden,
    code: 'MENU_SCOPE_CHANGED',
    message: 'Phiên làm việc hoặc quyền cập nhật món đã thay đổi.',
  );
  static const pending = Failure(
    type: FailureType.conflict,
    code: 'MENU_BUSY',
    message: 'Thao tác với món đang được xử lý. Vui lòng chờ.',
  );
  static const unexpected = Failure(
    type: FailureType.internal,
    code: 'INVALID_MENU_RESPONSE',
    message: 'Chưa xác minh được cấu hình món. Hãy tải lại để kiểm tra.',
  );

  void _changed() {
    if (current) notifyListeners();
  }

  void _catalogChanged() {
    if (!current || _revision == events.itemRevision) return;
    _revision = events.itemRevision;
    if (events.changedItemId != null && events.changedItemId != menuItemId) {
      return;
    }
    if (_busy) {
      return; // Our PATCH response, never an event, resolves the intent.
    }
    ++_generation;
    stale = true;
    unawaited(load());
  }

  Future<Result<MenuItem>> _read() async {
    if (!canRead) return const Error(unavailable);
    Result<MenuItem> result;
    try {
      result = await get(menuItemId);
    } catch (_) {
      result = const Error(unexpected);
    }
    if (!canRead) return const Error(unavailable);
    if (result case Success(value: final value)) {
      if (value.id != menuItemId || value.version < (_item?.version ?? -1)) {
        return const Error(unexpected);
      }
    }
    return result;
  }

  Future<void> load() async {
    if (!canRead || _busy) return;
    final generation = ++_generation;
    loading = true;
    _changed();
    final result = await _read();
    if (!canRead || generation != _generation) return;
    switch (result) {
      case Success(value: final value):
        _item = value;
        failure = null;
        stale = false;
        needsVerification = false;
      case Error(failure: final error):
        failure = error;
        stale = _item != null;
        await _report(error);
    }
    loading = false;
    _changed();
  }

  Future<Result<MenuItem>> setEnabled(bool enabled) async {
    if (!canSet(enabled) || !canRead) return const Error(unavailable);
    if (busy) return const Error(pending);
    if (needsVerification) return Error(failure ?? unexpected);
    _busy = true;
    ++_generation;
    loading = false;
    failure = null;
    _changed();
    try {
      return await _set(enabled);
    } finally {
      _busy = false;
      _changed();
    }
  }

  Future<Result<MenuItem>> _set(bool enabled) async {
    if (!canSet(enabled)) return const Error(unavailable);
    final currentMenu = await _read();
    if (!current || !canSet(enabled)) return const Error(unavailable);
    if (currentMenu case Error(failure: final error)) {
      failure = error;
      stale = _item != null;
      await _report(error);
      return Error(error);
    }
    final baseline = (currentMenu as Success<MenuItem>).value;
    _item = baseline;
    needsVerification = false;
    stale = false;
    if (baseline.recipeEnabled == enabled) {
      if (enabled) savedDefinition = null;
      return Success(baseline);
    }
    Result<MenuItem> result;
    try {
      result = await update(
        menuItemId,
        UpdateMenuItemInput(
          expectedVersion: baseline.version,
          recipeEnabled: enabled,
        ),
      );
    } catch (_) {
      result = const Error(unexpected);
    }
    if (!current || !canSet(enabled)) return const Error(unavailable);
    switch (result) {
      case Success(value: final value):
        if (value.id != menuItemId ||
            value.version < baseline.version ||
            value.recipeEnabled != enabled) {
          failure = unexpected;
          needsVerification = true;
          stale = true;
          return const Error(unexpected);
        }
        _item = value;
        failure = null;
        stale = false;
        needsVerification = false;
        if (enabled) savedDefinition = null;
      case Error(failure: final error):
        failure = error;
        stale = true;
        needsVerification =
            error.isNetwork ||
            error.type == FailureType.internal ||
            error.type == FailureType.conflict ||
            error.type == FailureType.notFound;
      // The shared menu mutation pipeline has already performed access recovery.
    }
    return result;
  }

  /// Definition success is retained even if the separately authorized PATCH fails.
  Future<Result<Recipe>> saveAndEnable(
    Future<Result<Recipe>> Function() saveDefinition,
  ) async {
    if (!canSet(true) || !canRead) return const Error(unavailable);
    if (busy) return const Error(pending);
    if (needsVerification) return Error(failure ?? unexpected);
    if (savedDefinition != null) return Error(failure ?? unexpected);
    _busy = true;
    ++_generation;
    loading = false;
    failure = null;
    _changed();
    try {
      final saved = await saveDefinition();
      if (!current) return const Error(unavailable);
      if (saved case Error(failure: final error)) return Error(error);
      final recipe = (saved as Success<Recipe>).value;
      savedDefinition = recipe;
      final applied = await _set(true);
      if (!current) return const Error(unavailable);
      if (applied case Error(failure: final error)) {
        failure = Failure(
          type: error.type,
          code: error.code,
          fieldErrors: error.fieldErrors,
          message: 'Đã lưu công thức, chưa bật sử dụng. ${error.message}',
        );
        return Error(failure!);
      }
      return Success(recipe);
    } finally {
      _busy = false;
      _changed();
    }
  }

  Future<Result<void>> disableAndArchive(
    Recipe baseline,
    Future<Result<void>> Function() archive,
  ) async {
    if (!current || !AccessPolicy.canRecipe(session(), 'RECIPE_DELETE')) {
      return const Error(unavailable);
    }
    if (busy) return const Error(pending);
    if (baseline.menuItemId != menuItemId) return const Error(unexpected);
    _busy = true;
    ++_generation;
    loading = false;
    failure = null;
    _changed();
    var disabled = false;
    try {
      // Inactive historical definitions do not require disabling today's application.
      if (baseline.active && canRead) {
        final latest = await _read();
        if (!current) return const Error(unavailable);
        if (latest case Error(failure: final error)) {
          failure = error;
          await _report(error);
          return Error(error);
        }
        _item = (latest as Success<MenuItem>).value;
        if (_item!.recipeEnabled) {
          final result = await _set(false);
          if (result case Error(failure: final error)) return Error(error);
          disabled = true;
        }
      }
      if (!current || !AccessPolicy.canRecipe(session(), 'RECIPE_DELETE')) {
        return const Error(unavailable);
      }
      final result = await archive();
      if (!current) return const Error(unavailable);
      if (result case Error(failure: final error)) {
        failure = disabled
            ? Failure(
                type: error.type,
                code: error.code,
                fieldErrors: error.fieldErrors,
                message:
                    'Đã tắt sử dụng công thức; chưa lưu trữ được phiên bản. ${error.message}',
              )
            : error;
        needsVerification =
            error.isNetwork ||
            error.type == FailureType.internal ||
            error.type == FailureType.conflict;
        return Error(failure!);
      }
      return result;
    } finally {
      _busy = false;
      _changed();
    }
  }

  Future<void> _report(Failure error) async {
    if (!current) return;
    if (const {
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
    _item = null;
    savedDefinition = null;
    events.removeListener(_catalogChanged);
    super.dispose();
  }
}
