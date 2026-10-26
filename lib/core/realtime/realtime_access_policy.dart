import '../auth/app_session.dart';
import '../../features/auth/domain/entities/user_role.dart';
import '../../features/subscription/domain/entities/entitlement.dart';

/// Read capabilities of the wire contract, independent of app navigation gates.
abstract final class RealtimeAccessPolicy {
  static bool staff(AppSession? session) =>
      session != null &&
      session.authenticatedUser.restaurantId?.trim().isNotEmpty == true &&
      session.authenticatedUser.role != UserRole.superAdmin &&
      session.authenticatedUser.role != UserRole.unsupported &&
      session.subscriptionStatus == SubscriptionStatus.active;

  static bool orders(AppSession? session) =>
      staff(session) &&
      session!.permissions.contains('ORDER_VIEW') &&
      session.features.contains('ORDER_MANAGEMENT');

  static bool kitchen(AppSession? session) =>
      staff(session) &&
      session!.permissions.contains('KITCHEN_VIEW') &&
      session.features.contains('KITCHEN_DISPLAY');

  static bool inventory(AppSession? session) =>
      staff(session) &&
      const {
        UserRole.owner,
        UserRole.manager,
        UserRole.waiter,
        UserRole.kitchen,
      }.contains(session!.authenticatedUser.role) &&
      session.permissions.contains('INVENTORY_VIEW') &&
      session.features.contains('INVENTORY_MANAGEMENT') &&
      session.features.contains('LOW_STOCK_ALERT');
}
