import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/order/presentation/screens/order_list_screen.dart';
import '../../../features/order/presentation/screens/order_service_context_screen.dart';
import '../../../features/kitchen/presentation/screens/kitchen_display_screen.dart';

import '../../../app/providers.dart';
import '../../auth/app_session.dart';
import '../../auth/access_policy.dart';
import '../sidebar/app_sidebar.dart';
import '../sidebar/app_sidebar_registry.dart';
import '../sidebar/sidebar_filter.dart';
import '../sidebar/sidebar_menu_item.dart';

import '../../../features/staff/presentation/screens/staff_management_screen.dart';
import '../../../features/menu/presentation/screens/menu_management_screen.dart';
import '../../../features/tables/presentation/screens/tables_management_screen.dart';
import '../../../features/reports/presentation/screens/daily_revenue_screen.dart';
import '../../../features/reports/presentation/screens/reports_screen.dart';
import '../../../features/inventory/presentation/screens/inventory_management_screen.dart';

/// The single unified shell for the entire application.
///
/// Replaces the former role-specific shells (ManagementShell,
/// CashierShell, StaffShell, KitchenShell). The sidebar content
/// is built dynamically from [AppSidebarRegistry], filtered by the
/// user's effective permissions and subscription features.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    this.initialSection,
    this.child,
    this.showAppBar = true,
  });
  final Widget? child;

  /// Optional initial section id, used when navigating from a route.
  final String? initialSection;
  final bool showAppBar;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sidebarController;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _sidebarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _selectedId = widget.initialSection;
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection) {
      _selectedId = widget.initialSection;
    }
  }

  @override
  void dispose() {
    _sidebarController.dispose();
    super.dispose();
  }

  void _toggleSidebar() {
    if (_sidebarController.isCompleted) {
      _sidebarController.reverse();
    } else {
      _sidebarController.forward();
    }
  }

  void _onItemTap(SidebarMenuItem item) async {
    if (const {
      'orders',
      'order-create',
      'tables',
      'menu',
      'staff',
      'kitchen-display',
      'dish-status',
      'daily-revenue',
      'reports',
    }.contains(item.id)) {
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        if (item.id == 'order-create' &&
            GoRouterState.of(
              context,
            ).uri.path.startsWith('/app/order-create')) {
          final allowed = await ref.read(orderExitGuardProvider).allow(context);
          if (!mounted || !allowed) return;
        }
        _sidebarController.reverse();
        router.go(item.routePath);
        return;
      }
    }
    setState(() => _selectedId = item.id);
    _sidebarController.reverse();
    // Navigation to the actual feature screens will be wired
    // as those screens are implemented.
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(authControllerProvider);
    final session = controller.state.session;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final visibleCategories = filterCategories(
      session,
      AppSidebarRegistry.categories,
    );

    // Flatten all visible items to pick a default selection.
    final allVisibleItems = visibleCategories.expand((c) => c.items).toList();

    // Pick the first item as selected if nothing is selected yet.
    if (_selectedId == null && allVisibleItems.isNotEmpty) {
      _selectedId = allVisibleItems.first.id;
    }

    final width = MediaQuery.sizeOf(context).width;
    final largeScreen = width >= 1024;
    final mediumScreen = width >= 600;
    final toolbarHeight = largeScreen
        ? 80.0
        : mediumScreen
        ? 72.0
        : kToolbarHeight;
    final menuButtonSize = largeScreen
        ? 72.0
        : mediumScreen
        ? 64.0
        : 48.0;
    final menuIconSize = largeScreen
        ? 36.0
        : mediumScreen
        ? 32.0
        : 24.0;

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              toolbarHeight: toolbarHeight,
              leadingWidth: menuButtonSize + (mediumScreen ? 16 : 8),
              leading: Center(
                child: SizedBox.square(
                  dimension: menuButtonSize,
                  child: IconButton(
                    onPressed: _toggleSidebar,
                    tooltip: 'Menu',
                    iconSize: menuIconSize,
                    style: IconButton.styleFrom(
                      fixedSize: Size.square(menuButtonSize),
                      padding: EdgeInsets.zero,
                    ),
                    icon: AnimatedIcon(
                      icon: AnimatedIcons.menu_close,
                      progress: _sidebarController,
                      size: menuIconSize,
                    ),
                  ),
                ),
              ),
              title: Text(_currentTitle(allVisibleItems)),
              // actions: [
              //   IconButton(
              //     onPressed: controller.logout,
              //     tooltip: 'Đăng xuất',
              //     icon: const Icon(Icons.logout),
              //   ),
              // ],
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Main content area
          Positioned.fill(child: _buildContent(session, allVisibleItems)),

          // Sidebar overlay
          AppSidebar(
            animation: _sidebarController,
            categories: visibleCategories,
            selectedId: _selectedId,
            onItemTap: _onItemTap,
            onLogout: controller.logout,
            userName: session.authenticatedUser.name,
            userRole: _roleName(session),
            restaurantName: session.authenticatedUser.restaurantName,
            packageCode: session.packageCode,
          ),
        ],
      ),
    );
  }

  String _currentTitle(List<SidebarMenuItem> items) {
    final selected = items.where((i) => i.id == _selectedId).firstOrNull;
    return selected?.label ?? 'Xây POS';
  }

  Widget _buildContent(AppSession session, List<SidebarMenuItem> items) {
    // Contextual routes can be authorized without a visible catalog sidebar item.
    if (widget.child != null) {
      return KeyedSubtree(
        key: ValueKey(AccessPolicy.menuScope(session)),
        child: widget.child!,
      );
    }
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Tài khoản chưa được cấp quyền truy cập chức năng nào.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final selected = items.where((i) => i.id == _selectedId).firstOrNull;
    if (selected == null) {
      return const Center(child: Text('Chọn chức năng từ menu.'));
    }
    if (selected.id == 'orders') return const OrderListScreen();
    if (selected.id == 'order-create') return const OrderServiceContextScreen();
    if (selected.id == 'kitchen-display' || selected.id == 'dish-status') {
      return KitchenDisplayScreen(
        key: ValueKey(AccessPolicy.kitchenScope(session)),
      );
    }

    if (selected.id == 'staff') {
      return const StaffManagementScreen();
    }
    if (selected.id == 'menu') {
      return MenuManagementScreen(
        key: ValueKey(AccessPolicy.menuScope(session)),
      );
    }
    if (selected.id == 'tables') {
      return TablesManagementScreen(
        key: ValueKey(AccessPolicy.tableScope(session)),
      );
    }
    if (selected.id == 'daily-revenue') {
      return DailyRevenueScreen(
        key: ValueKey(AccessPolicy.reportScope(session)),
      );
    }
    if (selected.id == 'reports') {
      return ReportsScreen(key: ValueKey(AccessPolicy.reportScope(session)));
    }
    if (selected.id == 'inventory') {
      return const InventoryManagementScreen();
    }

    // Placeholder content for each section.
    // Will be replaced by real feature widgets when implemented.
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected.icon,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        selected.label,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Màn hình ${selected.label} đang được hoàn thiện.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _roleName(AppSession session) {
    return switch (session.authenticatedUser.role.name) {
      'cashier' => 'Thu ngân',
      'owner' => 'Chủ nhà hàng',
      'manager' => 'Quản lý',
      'waiter' => 'Phục vụ',
      'kitchen' => 'Bếp',
      'superAdmin' => 'Super Admin',
      _ => session.authenticatedUser.role.name,
    };
  }
}
