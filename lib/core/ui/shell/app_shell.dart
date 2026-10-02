import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../auth/app_session.dart';
import '../sidebar/app_sidebar.dart';
import '../sidebar/app_sidebar_registry.dart';
import '../sidebar/sidebar_filter.dart';
import '../sidebar/sidebar_menu_item.dart';

import '../../../features/staff/presentation/screens/staff_management_screen.dart';

/// The single unified shell for the entire application.
///
/// Replaces the former role-specific shells (ManagementShell,
/// CashierShell, StaffShell, KitchenShell). The sidebar content
/// is built dynamically from [AppSidebarRegistry], filtered by the
/// user's effective permissions and subscription features.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, this.initialSection});

  /// Optional initial section id, used when navigating from a route.
  final String? initialSection;

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

  void _onItemTap(SidebarMenuItem item) {
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: _toggleSidebar,
          tooltip: 'Menu',
          icon: AnimatedIcon(
            icon: AnimatedIcons.menu_close,
            progress: _sidebarController,
          ),
        ),
        title: Text(_currentTitle(allVisibleItems)),
        actions: [
          IconButton(
            onPressed: controller.logout,
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Stack(
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

    if (selected.id == 'staff') {
      return const StaffManagementScreen();
    }

    // Placeholder content for each section.
    // Will be replaced by real feature widgets when implemented.
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected.icon,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              selected.label,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
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
