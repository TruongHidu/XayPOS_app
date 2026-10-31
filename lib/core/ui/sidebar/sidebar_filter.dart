import '../../auth/access_policy.dart';
import '../../auth/app_session.dart';
import 'sidebar_category.dart';
import 'sidebar_menu_item.dart';

/// Filters a list of [SidebarMenuItem] based on the current [AppSession].
///
/// An item is visible when:
///  - All [SidebarMenuItem.requiredPermissions] are present in the session.
///  - All [SidebarMenuItem.requiredFeatures] are present in the session.
List<SidebarMenuItem> filterMenuItems(
  AppSession session,
  List<SidebarMenuItem> allItems,
) {
  return allItems.where((item) {
    if (item.id == 'kitchen-display') {
      return AccessPolicy.canKitchen(session, 'KITCHEN_VIEW');
    }
    if (item.id == 'dish-status') {
      return AccessPolicy.canKitchen(session, 'KITCHEN_VIEW') &&
          (AccessPolicy.canKitchen(session, 'KITCHEN_START_COOKING') ||
              AccessPolicy.canKitchen(session, 'KITCHEN_MARK_READY'));
    }
    if (item.id == 'orders') {
      return AccessPolicy.canOrders(session, 'ORDER_VIEW');
    }
    if (item.id == 'order-create') {
      return AccessPolicy.canOrderWorkspace(session);
    }
    if (item.id == 'takeaway-orders') {
      return AccessPolicy.canTakeawayOrders(session);
    }
    if (item.id == 'tables') {
      return AccessPolicy.canTables(session, 'TABLE_VIEW');
    }
    if (item.id == 'menu') return AccessPolicy.canMenuWorkspace(session);
    if (item.id == 'staff') return AccessPolicy.canStaff(session, 'STAFF_VIEW');
    if (const {
      'inventory',
      'inventory-warehouses',
      'inventory-documents',
      'inventory-transactions',
    }.contains(item.id)) {
      return AccessPolicy.canInventory(session, 'INVENTORY_VIEW');
    }
    if (item.id == 'inventory-low-stock' || item.id == 'inventory-alerts') {
      return AccessPolicy.canViewInventoryAlerts(session);
    }
    if (item.id == 'inventory-audits') {
      return AccessPolicy.canViewStockAudits(session);
    }
    if (item.id == 'daily-revenue') {
      return AccessPolicy.canDailyReport(session);
    }
    if (item.id == 'reports') {
      return AccessPolicy.canDetailReport(session);
    }
    if (item.id == 'reference-margin-reports') {
      return AccessPolicy.canViewReferenceMarginReports(session);
    }
    if (item.id == 'cashbook') {
      return AccessPolicy.canCashbook(session, 'CASHBOOK_VIEW');
    }
    final hasAllPermissions = item.requiredPermissions.every(
      (p) => session.permissions.contains(p),
    );
    final hasAllFeatures = item.requiredFeatures.every(
      (f) => session.features.contains(f),
    );
    final hasAny =
        item.requiredAnyPermissions.isEmpty ||
        item.requiredAnyPermissions.any(session.permissions.contains);
    return hasAllPermissions && hasAny && hasAllFeatures;
  }).toList();
}

/// Filters a list of [SidebarCategory] based on the current [AppSession].
///
/// Each category's items are filtered by [filterMenuItems]. Categories
/// that end up with zero visible items are removed entirely.
List<SidebarCategory> filterCategories(
  AppSession session,
  List<SidebarCategory> allCategories,
) {
  final result = <SidebarCategory>[];
  for (final category in allCategories) {
    final visibleItems = filterMenuItems(session, category.items);
    if (visibleItems.isNotEmpty) {
      result.add(
        SidebarCategory(
          title: category.title,
          items: visibleItems,
          collapsible: category.collapsible,
          icon: category.icon,
        ),
      );
    }
  }
  return result;
}
