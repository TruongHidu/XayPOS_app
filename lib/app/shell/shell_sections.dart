import 'package:flutter/material.dart';

import '../../core/auth/access_policy.dart';
import '../../core/auth/app_session.dart';
import '../../features/inventory/presentation/screens/inventory_alerts_screen.dart';
import '../../features/inventory/presentation/screens/inventory_audits_screen.dart';
import '../../features/inventory/presentation/screens/inventory_balances_screen.dart';
import '../../features/inventory/presentation/screens/inventory_documents_screen.dart';
import '../../features/kitchen/presentation/screens/kitchen_display_screen.dart';
import '../../features/menu/presentation/screens/menu_management_screen.dart';
import '../../features/menu/presentation/widgets/menu_filter_panel.dart';
import '../../features/order/presentation/screens/order_list_screen.dart';
import '../../features/order/presentation/screens/order_service_context_screen.dart';
import '../../features/order/presentation/screens/takeaway_orders_screen.dart';
import '../../features/overview/presentation/screens/overview_screen.dart';
import '../../features/reference_margin_reports/presentation/screens/reference_margin_reports_screen.dart';
import '../../features/reports/presentation/screens/daily_revenue_screen.dart';
import '../../features/reports/presentation/screens/reports_screen.dart';
import '../../features/reports/presentation/widgets/report_filter_panel.dart';
import '../../features/staff/presentation/screens/staff_management_screen.dart';
import '../../features/tables/presentation/screens/tables_management_screen.dart';

/// What the shell mounts for a sidebar section opened without a route child,
/// and the app bar actions that screen contributes.
class ShellSection {
  const ShellSection(this.build, {this.actions = const []});

  /// Screens keyed by the session's access scope remount when it changes.
  final Widget Function(AppSession session) build;
  final List<Widget> actions;
}

/// The feature screens behind each sidebar id. Lives in the app layer so
/// `core` never imports a feature.
final Map<String, ShellSection> shellSections = {
  'overview': ShellSection(
    (s) => OverviewScreen(key: ValueKey(AccessPolicy.reportScope(s))),
  ),
  'orders': ShellSection((_) => const OrderListScreen()),
  'order-create': ShellSection((_) => const OrderServiceContextScreen()),
  'takeaway-orders': ShellSection((_) => const TakeawayOrdersScreen()),
  'kitchen-display': ShellSection(
    (s) => KitchenDisplayScreen(key: ValueKey(AccessPolicy.kitchenScope(s))),
  ),
  'staff': ShellSection((_) => const StaffManagementScreen()),
  'menu': ShellSection(
    (s) => MenuManagementScreen(key: ValueKey(AccessPolicy.menuScope(s))),
    actions: const [MenuFilterAction()],
  ),
  'tables': ShellSection(
    (s) => TablesManagementScreen(key: ValueKey(AccessPolicy.tableScope(s))),
  ),
  'daily-revenue': ShellSection(
    (s) => DailyRevenueScreen(key: ValueKey(AccessPolicy.reportScope(s))),
  ),
  'reports': ShellSection(
    (s) => ReportsScreen(key: ValueKey(AccessPolicy.reportScope(s))),
    actions: const [ReportFilterAction()],
  ),
  'reference-margin-reports': ShellSection(
    (s) => ReferenceMarginReportsScreen(
      key: ValueKey(AccessPolicy.referenceMarginScope(s)),
    ),
  ),
  'inventory': ShellSection((_) => const InventoryBalancesScreen()),
  'inventory-documents': ShellSection((_) => const InventoryDocumentsScreen()),
  'inventory-alerts': ShellSection((_) => const InventoryAlertsScreen()),
  'inventory-audits': ShellSection((_) => const InventoryAuditsScreen()),
};
