import 'package:flutter/foundation.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import 'order_events.dart';

class OrderController extends ChangeNotifier {
  OrderController({
    required this.session,
    required this.events,
    this.onAccessDenied,
  }) : scope = AccessPolicy.orderScope(session());
  final AppSession? Function() session;
  final Object? scope;
  final OrderEvents events;
  final Future<void> Function(Failure)? onAccessDenied;
  bool _disposed = false;
  bool get current => !_disposed && scope == AccessPolicy.orderScope(session());
  bool can(String permission) =>
      current && AccessPolicy.canOrders(session(), permission);
  void changed() {
    if (current) notifyListeners();
  }

  static const denied = Failure(
    type: FailureType.forbidden,
    code: 'ORDER_ACCESS_CHANGED',
    message: 'Phiên làm việc hoặc quyền gọi món đã thay đổi.',
  );
  static const busyFailure = Failure(
    type: FailureType.conflict,
    code: 'ORDER_BUSY',
    message: 'Thao tác đang được xử lý.',
  );
  static Failure invalid(Map<String, String> fields) => Failure(
    type: FailureType.validation,
    code: 'VALIDATION_ERROR',
    message: 'Vui lòng kiểm tra thông tin đã nhập.',
    fieldErrors: fields,
  );
  Future<Result<T>> invoke<T>(
    String permission,
    Future<Result<T>> Function() call,
  ) async {
    if (!can(permission)) return const Error(denied);
    final result = await call();
    if (!can(permission)) return const Error(denied);
    if (result case Error(failure: final f)) {
      await report(f);
    }
    return can(permission) ? result : const Error(denied);
  }

  Future<void> report(Failure f) async {
    if (current &&
        const {
          FailureType.forbidden,
          FailureType.unauthorized,
          FailureType.featureNotEntitled,
          FailureType.subscriptionNotActive,
          FailureType.restaurantInactive,
        }.contains(f.type)) {
      await onAccessDenied?.call(f);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
