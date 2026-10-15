import 'package:flutter/foundation.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/app_session.dart';
import '../../../../core/errors/failure.dart';

class KitchenController extends ChangeNotifier {
  KitchenController({required this.session, this.onAccessDenied})
    : scope = AccessPolicy.kitchenScope(session());
  final AppSession? Function() session;
  final Object? scope;
  final Future<void> Function(Failure)? onAccessDenied;
  bool _disposed = false;
  bool get current =>
      !_disposed && scope == AccessPolicy.kitchenScope(session());
  bool can(String permission) =>
      current && AccessPolicy.canKitchen(session(), permission);
  void changed() {
    if (current) notifyListeners();
  }

  Future<void> report(Failure f) async {
    if (current &&
        const {
          FailureType.unauthorized,
          FailureType.forbidden,
          FailureType.featureNotEntitled,
          FailureType.subscriptionNotActive,
          FailureType.restaurantInactive,
        }.contains(f.type)) {
      await onAccessDenied?.call(f);
    }
  }

  static const denied = Failure(
    type: FailureType.forbidden,
    code: 'KITCHEN_ACCESS_CHANGED',
    message: 'Phiên làm việc hoặc quyền bếp đã thay đổi.',
  );
  static const busy = Failure(
    type: FailureType.conflict,
    code: 'KITCHEN_BUSY',
    message:
        'Đơn đang có thao tác cần xử lý. Vui lòng hoàn tất hoặc kiểm tra lại.',
  );
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
