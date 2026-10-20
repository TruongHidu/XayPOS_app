import '../../features/auth/domain/entities/user_role.dart';
import '../../features/subscription/domain/entities/entitlement.dart';
import 'app_session.dart';

abstract final class AccessPolicy {
  static Object? inventoryScope(AppSession? session) => menuScope(session);
  static bool canInventory(AppSession? session, String permission) =>
      session != null &&
      session.authenticatedUser.restaurantId?.trim().isNotEmpty == true &&
      !const {
        UserRole.cashier,
        UserRole.superAdmin,
        UserRole.unsupported,
      }.contains(session.authenticatedUser.role) &&
      session.subscriptionStatus == SubscriptionStatus.active &&
      session.features.contains('INVENTORY_MANAGEMENT') &&
      const {
        'INVENTORY_VIEW',
        'WAREHOUSE_CREATE',
        'WAREHOUSE_UPDATE',
        'WAREHOUSE_DELETE',
        'INVENTORY_THRESHOLD_UPDATE',
        'INVENTORY_RECEIVE',
        'INVENTORY_ISSUE',
        'INVENTORY_ADJUST',
      }.contains(permission) &&
      session.permissions.contains(permission);

  static Object? kitchenScope(AppSession? session) => menuScope(session);

  static bool canKitchen(AppSession? session, String permission) =>
      session != null &&
      session.authenticatedUser.restaurantId?.trim().isNotEmpty == true &&
      !const {
        UserRole.cashier,
        UserRole.superAdmin,
        UserRole.unsupported,
      }.contains(session.authenticatedUser.role) &&
      session.subscriptionStatus == SubscriptionStatus.active &&
      session.features.contains('KITCHEN_DISPLAY') &&
      const {
        'KITCHEN_VIEW',
        'KITCHEN_START_COOKING',
        'KITCHEN_MARK_READY',
      }.contains(permission) &&
      session.permissions.contains(permission);

  static Object? orderScope(AppSession? session) => menuScope(session);

  static bool canOrders(AppSession? session, String permission) =>
      session != null &&
      session.authenticatedUser.restaurantId?.trim().isNotEmpty == true &&
      !const {
        UserRole.cashier,
        UserRole.superAdmin,
        UserRole.unsupported,
      }.contains(session.authenticatedUser.role) &&
      session.subscriptionStatus == SubscriptionStatus.active &&
      session.features.contains('ORDER_MANAGEMENT') &&
      const {
        'ORDER_VIEW',
        'ORDER_CREATE',
        'ORDER_UPDATE',
        'ORDER_CANCEL',
        'ORDER_COMPLETE',
        'ORDER_MARK_SERVED',
      }.contains(permission) &&
      session.permissions.contains(permission);

  static bool canCreateOrder(AppSession? session, {required bool takeaway}) =>
      canOrders(session, 'ORDER_CREATE') &&
      session!.features.contains(
        takeaway ? 'POS_QUICK_ORDER' : 'TABLE_MANAGEMENT',
      );

  static Object? tableScope(AppSession? session) => menuScope(session);
  static bool canOrderWorkspace(AppSession? session) =>
      canOrders(session, 'ORDER_VIEW') || canOrders(session, 'ORDER_CREATE');
  static bool canSubmitOrder(AppSession? session, {required bool takeaway}) =>
      canCreateOrder(session, takeaway: takeaway) &&
      canOrders(session, 'ORDER_UPDATE');

  static bool canAppendOrder(AppSession? session, {required bool takeaway}) =>
      canOrders(session, 'ORDER_UPDATE') &&
      session!.features.contains(
        takeaway ? 'POS_QUICK_ORDER' : 'TABLE_MANAGEMENT',
      );

  static bool canRecordOrderPayment(AppSession? session) =>
      session != null &&
      session.authenticatedUser.restaurantId?.trim().isNotEmpty == true &&
      !const {
        UserRole.cashier,
        UserRole.superAdmin,
        UserRole.unsupported,
      }.contains(session.authenticatedUser.role) &&
      session.subscriptionStatus == SubscriptionStatus.active &&
      session.features.contains('PAYMENT_MANAGEMENT') &&
      session.permissions.contains('PAYMENT_CREATE') &&
      session.permissions.contains('PAYMENT_CONFIRM');

  static bool canCompleteOrder(AppSession? session, {required bool takeaway}) =>
      canOrders(session, 'ORDER_COMPLETE') &&
      (takeaway || canTables(session, 'TABLE_CLOSE'));

  // Reading/rejecting the QR backlog remains possible after QR grants expire.
  static bool canApproveQrRequest(
    AppSession? session, {
    required bool takeaway,
    required bool opensSession,
  }) =>
      canOrders(session, 'ORDER_CREATE') &&
      canOrders(session, 'ORDER_UPDATE') &&
      session!.features.contains('QR_MENU_VIEW') &&
      session.features.contains(
        takeaway ? 'QR_STATIC_ORDER' : 'QR_TABLE_ORDER',
      ) &&
      (takeaway || session.features.contains('TABLE_MANAGEMENT')) &&
      (!opensSession || canTables(session, 'TABLE_OPEN'));

  static bool canTables(AppSession? session, String permission) =>
      session != null &&
      const {
        UserRole.owner,
        UserRole.manager,
        UserRole.waiter,
        UserRole.kitchen,
      }.contains(session.authenticatedUser.role) &&
      session.authenticatedUser.restaurantId?.trim().isNotEmpty == true &&
      session.subscriptionStatus == SubscriptionStatus.active &&
      session.features.contains('TABLE_MANAGEMENT') &&
      const {
        'TABLE_VIEW',
        'TABLE_CREATE',
        'TABLE_UPDATE',
        'TABLE_OPEN',
        'TABLE_CLOSE',
        'TABLE_TRANSFER',
      }.contains(permission) &&
      session.permissions.contains(permission);
  static Object? menuScope(AppSession? session) {
    if (session == null) return null;
    return (
      userId: session.authenticatedUser.id,
      restaurantId: session.authenticatedUser.restaurantId,
      role: session.authenticatedUser.role,
      permissions: (session.permissions.toList()..sort()).join(','),
      features: (session.features.toList()..sort()).join(','),
      subscriptionId: session.subscriptionId,
      status: session.subscriptionStatus,
    );
  }

  static Object? reportScope(AppSession? session) => menuScope(session);

  static bool canDailyReport(AppSession? session) =>
      session != null &&
      session.authenticatedUser.restaurantId?.trim().isNotEmpty == true &&
      !const {
        UserRole.cashier,
        UserRole.superAdmin,
        UserRole.unsupported,
      }.contains(session.authenticatedUser.role) &&
      session.subscriptionStatus == SubscriptionStatus.active &&
      session.features.contains('DAILY_REVENUE') &&
      session.permissions.contains('REPORT_DAILY_VIEW');

  static bool canDetailReport(AppSession? session) =>
      session != null &&
      session.authenticatedUser.restaurantId?.trim().isNotEmpty == true &&
      !const {
        UserRole.cashier,
        UserRole.superAdmin,
        UserRole.unsupported,
      }.contains(session.authenticatedUser.role) &&
      session.subscriptionStatus == SubscriptionStatus.active &&
      session.features.contains('DETAIL_REPORT') &&
      session.permissions.contains('REPORT_DETAIL_VIEW');

  static bool canMenu(AppSession? session, String permission) =>
      session != null &&
      const {
        UserRole.owner,
        UserRole.manager,
        UserRole.waiter,
        UserRole.kitchen,
      }.contains(session.authenticatedUser.role) &&
      session.authenticatedUser.restaurantId?.trim().isNotEmpty == true &&
      session.subscriptionStatus == SubscriptionStatus.active &&
      session.features.contains('MENU_MANAGEMENT') &&
      const {
        'MENU_VIEW',
        'MENU_CREATE',
        'MENU_UPDATE',
        'MENU_DELETE',
      }.contains(permission) &&
      session.permissions.contains(permission);

  static Object? ingredientScope(AppSession? session) => menuScope(session);

  static Object? recipeScope(AppSession? session) => menuScope(session);

  static bool canRecipe(AppSession? session, String permission) =>
      session != null &&
      const {
        UserRole.owner,
        UserRole.manager,
        UserRole.waiter,
        UserRole.kitchen,
      }.contains(session.authenticatedUser.role) &&
      session.authenticatedUser.restaurantId?.trim().isNotEmpty == true &&
      session.subscriptionStatus == SubscriptionStatus.active &&
      session.features.contains('RECIPE_MANAGEMENT') &&
      const {
        'RECIPE_VIEW',
        'RECIPE_CREATE',
        'RECIPE_UPDATE',
        'RECIPE_DELETE',
      }.contains(permission) &&
      session.permissions.contains(permission);

  static bool canIngredient(AppSession? session, String permission) =>
      session != null &&
      const {
        UserRole.owner,
        UserRole.manager,
        UserRole.waiter,
        UserRole.kitchen,
      }.contains(session.authenticatedUser.role) &&
      session.authenticatedUser.restaurantId?.trim().isNotEmpty == true &&
      session.subscriptionStatus == SubscriptionStatus.active &&
      (session.features.contains('RECIPE_MANAGEMENT') ||
          session.features.contains('INVENTORY_MANAGEMENT')) &&
      const {
        'INGREDIENT_VIEW',
        'INGREDIENT_CREATE',
        'INGREDIENT_UPDATE',
        'INGREDIENT_DELETE',
      }.contains(permission) &&
      session.permissions.contains(permission);

  static bool canMenuWorkspace(AppSession? session) =>
      canMenu(session, 'MENU_VIEW') ||
      canIngredient(session, 'INGREDIENT_VIEW');

  /// Session boundary for staff data. Routine token rotation keeps open forms
  /// and filters; identity, tenant, authority or entitlement changes reset them.
  static Object? staffScope(AppSession? session) {
    if (session == null) return null;
    return (
      userId: session.authenticatedUser.id,
      restaurantId: session.authenticatedUser.restaurantId,
      role: session.authenticatedUser.role,
      permissions: (session.permissions.toList()..sort()).join(','),
      features: (session.features.toList()..sort()).join(','),
      status: session.subscriptionStatus,
      maxStaff: session.maxStaff,
    );
  }

  static bool canStaff(AppSession? session, String permission) {
    if (session == null) return false;
    final role = session.authenticatedUser.role;
    return (role == UserRole.owner || role == UserRole.manager) &&
        session.subscriptionStatus == SubscriptionStatus.active &&
        session.authenticatedUser.restaurantId != null &&
        session.permissions.contains(permission) &&
        session.features.contains('STAFF_MANAGEMENT') &&
        (permission != 'STAFF_PERMISSION_MANAGE' ||
            session.features.contains('STAFF_PERMISSION'));
  }

  static bool canAssignStaffRole(AppSession? session, String code) =>
      session != null &&
      (session.authenticatedUser.role == UserRole.owner ||
          session.authenticatedUser.role == UserRole.manager) &&
      (const {'WAITER', 'KITCHEN', 'CASHIER'}.contains(code) ||
          (code == 'MANAGER' &&
              session.authenticatedUser.role == UserRole.owner));

  static bool canManageStaff(
    AppSession? session,
    String permission,
    String staffId,
    String roleCode,
  ) =>
      canStaff(session, permission) &&
      session!.authenticatedUser.id != staffId &&
      canAssignStaffRole(session, roleCode);

  static bool hasPermission(AppSession session, String permission) {
    return session.permissions.contains(permission);
  }

  static bool hasFeature(AppSession session, String feature) {
    return session.features.contains(feature);
  }

  static bool canAccess(
    AppSession session, {
    required String permission,
    String? feature,
  }) {
    return hasPermission(session, permission) &&
        (feature == null || hasFeature(session, feature));
  }

  static bool canAccessAny(
    AppSession session,
    Iterable<({String permission, String? feature})> requirements,
  ) {
    return requirements.any(
      (item) => canAccess(
        session,
        permission: item.permission,
        feature: item.feature,
      ),
    );
  }

  /// Determines the initial route after successful authentication.
  ///
  /// All restaurant roles with an active subscription and at least one
  /// accessible feature are sent to the unified `/app/home` shell. The
  /// shell's sidebar then shows only the items the user is permitted to see.
  static String initialRouteFor(AppSession session) {
    final user = session.authenticatedUser;

    // Super admin or user without a restaurant → admin web only.
    if (user.role == UserRole.superAdmin || user.restaurantId == null) {
      return '/admin-web-only';
    }

    // Cashier uses a separate web-based system.
    if (user.role == UserRole.cashier) {
      return '/cashier-web-only';
    }

    // Unsupported roles.
    if (user.role == UserRole.unsupported) {
      return '/unsupported-role';
    }

    // Subscription check.
    final subscriptionActive =
        session.subscriptionStatus == SubscriptionStatus.active;

    if (!subscriptionActive) {
      // Owner / Manager can act on subscription; others just see a message.
      if (user.role == UserRole.owner || user.role == UserRole.manager) {
        return '/subscription-required';
      }
      return '/subscription-unavailable';
    }

    // Must have at least one accessible feature to enter the app.
    if (!_hasAnyAccessibleFeature(session)) {
      return '/no-accessible-feature';
    }

    // All checks passed → unified app shell.
    return '/app/home';
  }

  /// Whether the user is allowed to open the given [location].
  static bool canOpenRoute(AppSession session, String location) {
    final uri = Uri.tryParse(location);
    final path = uri?.path ?? location;
    if (RegExp(r'^/app/menu/items/[^/]+/recipes$').hasMatch(path)) {
      return canRecipe(session, 'RECIPE_VIEW');
    }
    if (path == '/app/kitchen' || path == '/app/dish-status') {
      return canKitchen(session, 'KITCHEN_VIEW');
    }
    if (path == '/app/orders' || path.startsWith('/app/orders/')) {
      return canOrders(session, 'ORDER_VIEW');
    }
    final billMatch = RegExp(
      r'^/app/order-create/bill/([^/]+)$',
    ).firstMatch(path);
    if (billMatch != null) {
      return canOrders(session, 'ORDER_VIEW');
    }
    final addItemsMatch = RegExp(
      r'^/app/order-create/bill/([^/]+)/add-items$',
    ).firstMatch(path);
    if (addItemsMatch != null) {
      return canOrders(session, 'ORDER_UPDATE') &&
          canMenu(session, 'MENU_VIEW');
    }
    if (path == '/app/order-create') {
      if (uri?.queryParameters['tableId'] != null) {
        return canSubmitOrder(session, takeaway: false) &&
            canTables(session, 'TABLE_VIEW');
      }
      if (uri?.queryParameters['serviceType'] == 'TAKEAWAY') {
        return canCreateOrder(session, takeaway: true);
      }
      if (uri?.queryParameters['tableSessionId'] != null) {
        return canCreateOrder(session, takeaway: false);
      }
      return canOrderWorkspace(session);
    }
    if (path == '/app/daily-revenue') return canDailyReport(session);
    if (path == '/app/inventory') {
      return canInventory(session, 'INVENTORY_VIEW');
    }
    if (path == '/app/inventory/stock-documents/new') {
      return canInventory(session, 'INVENTORY_VIEW') &&
          const {
            'INVENTORY_RECEIVE',
            'INVENTORY_ISSUE',
            'INVENTORY_ADJUST',
          }.any((p) => canInventory(session, p));
    }
    if (path == '/app/inventory/transactions' ||
        RegExp(r'^/app/inventory/stock-documents/[^/]+$').hasMatch(path)) {
      return canInventory(session, 'INVENTORY_VIEW');
    }
    if (path == '/app/reports') return canDetailReport(session);
    if (location == '/app/tables') return canTables(session, 'TABLE_VIEW');
    if (path == '/app/menu') return canMenuWorkspace(session);
    if (location == '/app/staff') return canStaff(session, 'STAFF_VIEW');
    // Unified app shell — allowed if subscribed and has features.
    if (location == '/app/home') {
      final user = session.authenticatedUser;
      final isRestaurantRole =
          user.role == UserRole.owner ||
          user.role == UserRole.manager ||
          user.role == UserRole.waiter ||
          user.role == UserRole.kitchen;
      return isRestaurantRole &&
          session.subscriptionStatus == SubscriptionStatus.active &&
          _hasAnyAccessibleFeature(session);
    }

    // Access message screens — role-appropriate checks.
    final role = session.authenticatedUser.role;
    return switch (location) {
      '/subscription-required' =>
        (role == UserRole.owner || role == UserRole.manager) &&
            session.subscriptionStatus != SubscriptionStatus.active,
      '/subscription-unavailable' =>
        (role == UserRole.waiter || role == UserRole.kitchen) &&
            session.subscriptionStatus != SubscriptionStatus.active,
      '/feature-unavailable' =>
        session.subscriptionStatus == SubscriptionStatus.active &&
            !_hasAnyAccessibleFeature(session),
      '/no-accessible-feature' =>
        initialRouteFor(session) == '/no-accessible-feature',
      '/cashier-web-only' => role == UserRole.cashier,
      '/admin-web-only' =>
        role == UserRole.superAdmin ||
            session.authenticatedUser.restaurantId == null,
      '/unsupported-role' => role == UserRole.unsupported,
      _ => false,
    };
  }

  /// Returns `true` when the user has at least one permission+feature
  /// combination or a contextual recipe route they can open.
  static bool _hasAnyAccessibleFeature(AppSession session) {
    return canStaff(session, 'STAFF_VIEW') ||
        canTables(session, 'TABLE_VIEW') ||
        canMenu(session, 'MENU_VIEW') ||
        canIngredient(session, 'INGREDIENT_VIEW') ||
        canRecipe(session, 'RECIPE_VIEW') ||
        canDailyReport(session) ||
        canDetailReport(session) ||
        canAccessAny(session, const [
          (permission: 'ORDER_VIEW', feature: 'ORDER_MANAGEMENT'),
          (permission: 'ORDER_CREATE', feature: 'ORDER_MANAGEMENT'),
          (permission: 'PAYMENT_VIEW', feature: 'PAYMENT_MANAGEMENT'),
          (permission: 'KITCHEN_VIEW', feature: 'KITCHEN_DISPLAY'),
          (permission: 'INVENTORY_VIEW', feature: 'INVENTORY_MANAGEMENT'),
          (permission: 'DASHBOARD_VIEW', feature: 'REPORTING'),
          (
            permission: 'RESTAURANT_SETTINGS_VIEW',
            feature: 'RESTAURANT_SETTINGS',
          ),
        ]);
  }
}
