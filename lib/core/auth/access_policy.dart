import '../../features/auth/domain/entities/user_role.dart';
import '../../features/subscription/domain/entities/entitlement.dart';
import '../values/inventory_mode.dart';
import 'app_session.dart';

abstract final class AccessPolicy {
  static bool canSetRecipeApplication(
    AppSession? session, {
    required bool enabled,
  }) =>
      canMenu(session, 'MENU_UPDATE') &&
      (!enabled || session!.features.contains('RECIPE_MANAGEMENT'));

  // Only switching a mode on needs its feature, so a lost plan never blocks
  // keeping the current mode or leaving it.
  static bool canSetInventoryMode(
    AppSession? session, {
    required bool creating,
    required InventoryMode from,
    required InventoryMode to,
  }) {
    if (!canMenu(session, creating ? 'MENU_CREATE' : 'MENU_UPDATE')) {
      return false;
    }
    if (from == to) return true;
    return switch (to) {
      InventoryMode.none => true,
      InventoryMode.direct => session!.features.contains(
        'INVENTORY_MANAGEMENT',
      ),
      // A new item has no recipe yet: choosing this leads to creating one.
      InventoryMode.recipe =>
        creating
            ? canRecipe(session, 'RECIPE_CREATE')
            : session!.features.contains('RECIPE_MANAGEMENT'),
    };
  }

  // Historical ingredient reads have their own effective capability intersection.
  static bool canViewOrderRecipeSnapshot(AppSession? session) =>
      canOrders(session, 'ORDER_VIEW') &&
      session!.permissions.contains('RECIPE_VIEW') &&
      session.features.contains('RECIPE_MANAGEMENT');
  // Direct stock lines need no recipe rights; the server still guards the
  // recipe rights per line, because a line's mode is unknown before reading it.
  static bool canViewOrderItemAllocation(AppSession? session) =>
      canOrders(session, 'ORDER_VIEW') &&
      session!.permissions.contains('INVENTORY_VIEW') &&
      session.features.contains('INVENTORY_MANAGEMENT');
  static Object? inventoryScope(AppSession? session) => menuScope(session);
  static bool canViewInventoryAlerts(AppSession? session) =>
      canInventory(session, 'INVENTORY_VIEW') &&
      session!.features.contains('LOW_STOCK_ALERT');
  static bool canAcknowledgeInventoryAlert(AppSession? session) =>
      canViewInventoryAlerts(session) &&
      canInventory(session, 'INVENTORY_ALERT_ACKNOWLEDGE');
  static bool canViewStockAudits(AppSession? session) =>
      canInventory(session, 'INVENTORY_VIEW') &&
      session!.features.contains('STOCK_AUDIT');
  static bool canManageStockAudits(AppSession? session) =>
      canViewStockAudits(session) &&
      canInventory(session, 'STOCK_AUDIT_MANAGE');
  static bool canConfirmStockAudits(AppSession? session) =>
      canViewStockAudits(session) &&
      canInventory(session, 'STOCK_AUDIT_CONFIRM');
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
        'INVENTORY_ALERT_ACKNOWLEDGE',
        'STOCK_AUDIT_MANAGE',
        'STOCK_AUDIT_CONFIRM',
      }.contains(permission) &&
      session.permissions.contains(permission) &&
      (!const {
            'INVENTORY_ALERT_ACKNOWLEDGE',
            'STOCK_AUDIT_MANAGE',
            'STOCK_AUDIT_CONFIRM',
          }.contains(permission) ||
          session.permissions.contains('INVENTORY_VIEW')) &&
      (permission != 'INVENTORY_ALERT_ACKNOWLEDGE' ||
          session.features.contains('LOW_STOCK_ALERT')) &&
      (!const {
            'STOCK_AUDIT_MANAGE',
            'STOCK_AUDIT_CONFIRM',
          }.contains(permission) ||
          session.features.contains('STOCK_AUDIT'));

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

  /// The takeaway board is a work queue: it shows only to staff who can move a
  /// takeaway order along (confirm, pay, complete or start one), not to
  /// read-only order viewers such as the kitchen.
  static bool canTakeawayOrders(AppSession? session) =>
      canOrders(session, 'ORDER_VIEW') &&
      session!.features.contains('POS_QUICK_ORDER') &&
      (canOrders(session, 'ORDER_CREATE') ||
          canOrders(session, 'ORDER_UPDATE') ||
          canOrders(session, 'ORDER_COMPLETE') ||
          canRecordOrderPayment(session));

  /// The QR inbox only helps someone who can at least reject a request.
  static bool canHandleQrRequests(AppSession? session) =>
      canOrders(session, 'ORDER_VIEW') && canOrders(session, 'ORDER_UPDATE');

  static Object? tableScope(AppSession? session) => menuScope(session);

  /// Gọi món shows when there is something to do there: work the table board,
  /// start a takeaway order, or handle QR requests. Reading orders alone is
  /// what Đơn hàng is for.
  static bool canOrderWorkspace(AppSession? session) =>
      (canTables(session, 'TABLE_VIEW') &&
          (canOrders(session, 'ORDER_VIEW') ||
              canOrders(session, 'ORDER_CREATE'))) ||
      (canCreateOrder(session, takeaway: true) &&
          canMenu(session, 'MENU_VIEW')) ||
      canHandleQrRequests(session);
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

  /// Setting or removing the receiving bank account changes where customers'
  /// money goes, so it takes the profile-edit right.
  static bool canManageTransferAccount(AppSession? session) =>
      session != null &&
      session.permissions.contains('RESTAURANT_PROFILE_UPDATE');

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

  static Object? referenceMarginScope(AppSession? session) =>
      menuScope(session);

  /// Historical reference-cost reporting is its own effective capability.
  /// Do not compose ordinary report/order helpers: those retain legacy role gates.
  static bool canViewReferenceMarginReports(AppSession? session) =>
      session != null &&
      session.authenticatedUser.restaurantId?.trim().isNotEmpty == true &&
      session.subscriptionStatus == SubscriptionStatus.active &&
      session.permissions.contains('ORDER_VIEW') &&
      session.permissions.contains('REPORT_DETAIL_VIEW') &&
      session.features.contains('ORDER_MANAGEMENT') &&
      session.features.contains('DETAIL_REPORT');

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

  static Object? cashbookScope(AppSession? session) => menuScope(session);

  static bool canCashbook(AppSession? session, String permission) =>
      session != null &&
      session.authenticatedUser.restaurantId?.trim().isNotEmpty == true &&
      !const {
        UserRole.cashier,
        UserRole.superAdmin,
        UserRole.unsupported,
      }.contains(session.authenticatedUser.role) &&
      session.subscriptionStatus == SubscriptionStatus.active &&
      session.features.contains('DETAIL_REPORT') &&
      const {
        'CASHBOOK_VIEW',
        'CASHBOOK_CREATE',
        'CASHBOOK_VOID',
      }.contains(permission) &&
      session.permissions.contains(permission);

  /// Receipt links read inventory documents, so both grants are required.
  static bool canLinkCashbookStockReceipt(AppSession? session) =>
      canCashbook(session, 'CASHBOOK_CREATE') &&
      canInventory(session, 'INVENTORY_VIEW');
  static bool canReconcileCashbookReceipts(AppSession? session) =>
      canCashbook(session, 'CASHBOOK_VIEW') &&
      canInventory(session, 'INVENTORY_VIEW');

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

  /// The one rule for each top-level section, shared by the sidebar, the
  /// bottom tabs and the router so they can never disagree. Null for an id
  /// this policy doesn't know.
  ///
  /// Package features and permissions decide visibility; the role only
  /// orders sections (see the bottom tabs), because staff can be granted or
  /// denied single permissions beyond their role's defaults.
  static bool? canSeeSection(AppSession session, String id) => switch (id) {
    'orders' => canOrders(session, 'ORDER_VIEW'),
    'order-create' => canOrderWorkspace(session),
    'takeaway-orders' => canTakeawayOrders(session),
    'kitchen-display' => canKitchen(session, 'KITCHEN_VIEW'),
    'tables' => canTables(session, 'TABLE_VIEW'),
    'menu' => canMenuWorkspace(session),
    'staff' => canStaff(session, 'STAFF_VIEW'),
    'inventory' ||
    'inventory-documents' => canInventory(session, 'INVENTORY_VIEW'),
    'inventory-alerts' => canViewInventoryAlerts(session),
    'inventory-audits' => canViewStockAudits(session),
    // Tổng quan leads with today's takings, so it follows the daily report.
    'overview' => canDailyReport(session),
    'daily-revenue' => canDailyReport(session),
    'reports' => canDetailReport(session),
    'reference-margin-reports' => canViewReferenceMarginReports(session),
    'cashbook' => canCashbook(session, 'CASHBOOK_VIEW'),
    // Cài đặt holds the account's own pages, so whoever reaches the shell may open it.
    'settings' => canOpenRoute(session, '/app/home'),
    _ => null,
  };

  /// Section ids behind the plain top-level routes.
  static const _sectionRoutes = {
    '/app/kitchen': 'kitchen-display',
    // Old link; the router sends it to the kitchen screen.
    '/app/dish-status': 'kitchen-display',
    '/app/orders': 'orders',
    '/app/takeaway': 'takeaway-orders',
    '/app/order-create': 'order-create',
    '/app/overview': 'overview',
    '/app/daily-revenue': 'daily-revenue',
    '/app/inventory/balances': 'inventory',
    '/app/inventory/warehouses': 'inventory',
    '/app/inventory/stock-documents': 'inventory-documents',
    '/app/inventory/alerts': 'inventory-alerts',
    '/app/inventory/low-stock': 'inventory-alerts',
    '/app/inventory/audits': 'inventory-audits',
    '/app/reports': 'reports',
    '/app/cashbook': 'cashbook',
    '/app/reference-margin': 'reference-margin-reports',
    '/app/tables': 'tables',
    '/app/menu': 'menu',
    '/app/staff': 'staff',
    '/app/settings': 'settings',
  };

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

    // Existing cashier operations remain web-only. This separately granted
    // read capability can enter its own Flutter report without opening them.
    if (user.role == UserRole.cashier) {
      return canViewReferenceMarginReports(session)
          ? '/app/reference-margin'
          : '/cashier-web-only';
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
    // "Gọi thêm món" opened from Đơn hàng or the takeaway board: the same
    // rule as from Gọi món below.
    if (RegExp(r'^/app/(orders|takeaway)/[^/]+/add-items$').hasMatch(path)) {
      return canOrders(session, 'ORDER_UPDATE') &&
          canMenu(session, 'MENU_VIEW') &&
          (!path.startsWith('/app/takeaway/') || canTakeawayOrders(session));
    }
    if (path.startsWith('/app/orders/')) {
      return canOrders(session, 'ORDER_VIEW');
    }
    if (path.startsWith('/app/takeaway/')) return canTakeawayOrders(session);
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
    }
    if (path == '/app/inventory') {
      return switch (uri?.queryParameters['tab']) {
        'alerts' ||
        'lowStock' ||
        'low-stock' => canViewInventoryAlerts(session),
        'audits' => canViewStockAudits(session),
        _ => canInventory(session, 'INVENTORY_VIEW'),
      };
    }
    // Plain section routes follow the same rule as the sidebar.
    final section = _sectionRoutes[path];
    if (section != null) return canSeeSection(session, section)!;
    if (path == '/app/inventory/audits/new') {
      return canManageStockAudits(session);
    }
    if (RegExp(r'^/app/inventory/audits/[^/]+$').hasMatch(path)) {
      return canViewStockAudits(session);
    }
    if (RegExp(r'^/app/inventory/alerts/[^/]+$').hasMatch(path)) {
      return canViewInventoryAlerts(session);
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
    // Unified app shell — allowed if subscribed and has features.
    if (location == '/app/home') {
      final user = session.authenticatedUser;
      final isRestaurantRole =
          user.role == UserRole.owner ||
          user.role == UserRole.manager ||
          user.role == UserRole.waiter ||
          user.role == UserRole.kitchen;
      return (isRestaurantRole || canViewReferenceMarginReports(session)) &&
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
        canCashbook(session, 'CASHBOOK_VIEW') ||
        canViewReferenceMarginReports(session) ||
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
