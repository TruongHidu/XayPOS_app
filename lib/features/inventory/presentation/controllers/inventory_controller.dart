import 'package:flutter/foundation.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import 'inventory_events.dart';

class InventoryController extends ChangeNotifier {
  InventoryController({
    required this.session,
    required this.events,
    this.onAccessDenied,
  }) : scope = AccessPolicy.inventoryScope(session()) {
    events.addListener(changed);
  }
  final AppSession? Function() session;
  final Object? scope;
  final InventoryEvents events;
  final Future<void> Function(Failure)? onAccessDenied;
  bool _disposed = false;
  final Map<String, int> _reads = {};
  bool get current =>
      !_disposed && scope == AccessPolicy.inventoryScope(session());
  bool can(String permission) =>
      current &&
      AccessPolicy.canInventory(session(), 'INVENTORY_VIEW') &&
      AccessPolicy.canInventory(session(), permission);
  bool get canLowStock =>
      can('INVENTORY_VIEW') && session()!.features.contains('LOW_STOCK_ALERT');
  void changed() {
    if (current) notifyListeners();
  }

  static const denied = Failure(
    type: FailureType.forbidden,
    code: 'INVENTORY_SCOPE_CHANGED',
    message: 'Phiên làm việc hoặc quyền quản lý kho đã thay đổi.',
  );
  static const busy = Failure(
    type: FailureType.conflict,
    code: 'INVENTORY_BUSY',
    message: 'Thao tác trên dữ liệu này đang được xử lý.',
  );
  static const invalidResponse = Failure(
    type: FailureType.internal,
    code: 'INVALID_INVENTORY_RESPONSE',
    message: 'Chưa xác minh được dữ liệu kho. Hãy tải lại để kiểm tra.',
  );
  static Failure invalid(Map<String, String> errors) => Failure(
    type: FailureType.validation,
    code: 'VALIDATION_ERROR',
    message: 'Vui lòng kiểm tra thông tin đã nhập.',
    fieldErrors: errors,
  );
  static bool needsVerification(Failure failure) =>
      failure.isNetwork ||
      failure.type == FailureType.internal ||
      const {
        'CONCURRENT_WAREHOUSE_UPDATE',
        'CONCURRENT_INVENTORY_UPDATE',
        'WAREHOUSE_INACTIVE',
        'CONCURRENT_STOCK_DOCUMENT_UPDATE',
        'CONFIRMED_STOCK_DOCUMENT_IMMUTABLE',
        'STOCK_DOCUMENT_CANCELLED',
        'STOCK_DOCUMENT_ITEM_NOT_FOUND',
        'INGREDIENT_UNIT_CHANGED',
        'INSUFFICIENT_STOCK',
      }.contains(failure.code);
  static bool unknown(Failure? failure) =>
      failure != null &&
      (failure.isNetwork || failure.type == FailureType.internal);
  Future<void> report(Failure failure) async {
    if (current &&
        const {
          FailureType.unauthorized,
          FailureType.forbidden,
          FailureType.featureNotEntitled,
          FailureType.subscriptionNotActive,
          FailureType.restaurantInactive,
        }.contains(failure.type)) {
      await onAccessDenied?.call(failure);
    }
  }

  Future<Result<T>> read<T>(
    String key,
    Future<Result<T>> Function() call, {
    bool lowStock = false,
  }) async {
    if (!can('INVENTORY_VIEW') || lowStock && !canLowStock) {
      return const Error(denied);
    }
    final generation = (_reads[key] ?? 0) + 1;
    _reads[key] = generation;
    final result = await call();
    if (!current || _reads[key] != generation || lowStock && !canLowStock) {
      return const Error(denied);
    }
    if (result case Error(failure: final f)) await report(f);
    return current ? result : const Error(denied);
  }

  Future<Result<T>> mutate<T>(
    String key,
    String permission,
    Future<Result<T>> Function() call, {
    required void Function(T) applied,
  }) async {
    if (!can(permission)) return const Error(denied);
    final verification = events.verification(key);
    if (verification != null) return Error(verification);
    if (!events.lock(key)) return const Error(busy);
    try {
      final result = await call();
      if (!can(permission)) return const Error(denied);
      switch (result) {
        case Success(value: final value):
          applied(value);
        case Error(failure: final f):
          await report(f);
          if (!current) return const Error(denied);
          if (needsVerification(f)) events.requireVerification(key, f);
      }
      return result;
    } catch (_) {
      if (current) events.requireVerification(key, invalidResponse);
      return const Error(invalidResponse);
    } finally {
      if (current) events.unlock(key);
    }
  }

  @override
  void dispose() {
    events.removeListener(changed);
    _disposed = true;
    super.dispose();
  }
}
