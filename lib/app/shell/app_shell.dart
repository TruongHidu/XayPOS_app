import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/access_policy.dart';
import '../../core/auth/app_session.dart';
import '../../core/ui/shell/app_bottom_tabs.dart';
import '../../core/ui/shell/exit_confirm_dialog.dart';
import '../../core/ui/sidebar/app_sidebar.dart';
import '../../core/ui/sidebar/app_sidebar_rail.dart';
import '../../core/ui/sidebar/app_sidebar_registry.dart';
import '../../core/ui/sidebar/sidebar_filter.dart';
import '../../core/ui/sidebar/sidebar_menu_item.dart';
import '../../core/ui/widgets/list_states.dart';
import '../../core/ui/widgets/realtime_connection_banner.dart';
import '../providers.dart';
import '../theme/app_tokens.dart';
import 'shell_sections.dart';
import 'shell_tabs.dart';

/// The single unified shell for the entire application.
///
/// The sidebar content is built from [AppSidebarRegistry], filtered by the
/// user's effective permissions and subscription features.
///
/// * Phones and portrait tablets (< 1024): bottom tabs for the role's main
///   sections, the full sidebar as a drawer from the menu button.
/// * Landscape tablets and POS screens (>= 1024): a rail of every section
///   stays on the left; the menu button opens the full sidebar over it.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({
    super.key,
    this.initialSection,
    this.child,
    this.showAppBar = true,
    this.actions,
  }) : innerTitle = null,
       backFallback = null;

  /// A screen opened from another one: it replaces the sidebar with a titled
  /// app bar whose back button returns to the previous screen.
  const AppShell.inner({
    super.key,
    required String title,
    required String this.backFallback,
    required Widget this.child,
    this.actions,
  }) : innerTitle = title,
       initialSection = null,
       showAppBar = true;

  final Widget? child;

  /// Optional initial section id, used when navigating from a route.
  final String? initialSection;
  final bool showAppBar;

  /// App bar actions contributed by the routed [child].
  final List<Widget>? actions;

  /// App bar title of an inner screen; null for a sidebar screen.
  final String? innerTitle;

  /// Where back leads when there is no previous screen, as after a deep link.
  final String? backFallback;

  bool get isInner => innerTitle != null;

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
      duration: AppDurations.slow,
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
      final session = ref.read(authControllerProvider).state.session;
      if (AccessPolicy.canViewInventoryAlerts(session)) {
        ref.read(inventoryLowStockCountProvider).refreshIfStale();
      }
      if (AccessPolicy.canTakeawayOrders(session)) {
        ref.read(takeawayCountRefresherProvider).refreshIfStale();
      }
    }
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(widget.backFallback!);
    }
  }

  /// The device back button on the bottom screen of the stack.
  Future<void> _onRootBack() async {
    if (!_sidebarController.isDismissed) {
      unawaited(_sidebarController.reverse());
      return;
    }
    if (widget.isInner) {
      _goBack();
      return;
    }
    final exit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ExitConfirmDialog(),
    );
    if (exit != true || !mounted) return;
    // Leaving must not silently drop an order still being composed or sent.
    final allowed = await ref.read(orderExitGuardProvider).allow(context);
    if (allowed) await SystemNavigator.pop();
  }

  Future<void> _onItemTap(SidebarMenuItem item) async {
    final router = GoRouter.maybeOf(context);
    final routed =
        shellSections.containsKey(item.id) ||
        const {'cashbook', 'settings'}.contains(item.id);
    if (router != null && routed) {
      if (item.id == 'order-create' &&
          GoRouterState.of(context).uri.path.startsWith('/app/order-create')) {
        final allowed = await ref.read(orderExitGuardProvider).allow(context);
        if (!mounted || !allowed) return;
      }
      _sidebarController.reverse();
      router.go(item.routePath);
      return;
    }
    setState(() => _selectedId = item.id);
    _sidebarController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(authControllerProvider);
    final session = controller.state.session;
    if (session == null) {
      return const Scaffold(body: LoadingState());
    }

    final visibleCategories = filterCategories(
      session,
      AppSidebarRegistry.categories,
    );
    final lowStockCount = AccessPolicy.canViewInventoryAlerts(session)
        ? ref.watch(
            inventoryLowStockCountProvider.select((counter) => counter.count),
          )
        : null;
    final takeawayCount = AccessPolicy.canTakeawayOrders(session)
        ? ref.watch(takeawayCountProvider)
        : null;

    // Flatten all visible items to pick a default selection.
    final allVisibleItems = visibleCategories.expand((c) => c.items).toList();

    final tabs = bottomTabsFor(session.authenticatedUser.role, allVisibleItems);

    // Start on the role's main section, e.g. the kitchen screen for kitchen
    // staff; fall back to the first item the user may open.
    if (_selectedId == null && allVisibleItems.isNotEmpty) {
      _selectedId = (tabs.firstOrNull ?? allVisibleItems.first).id;
    }

    final badges = {
      // Tồn kho holds the low-stock filter, so its count shows there.
      if (lowStockCount != null && lowStockCount > 0)
        'inventory': lowStockCount,
      if (takeawayCount != null && takeawayCount > 0)
        'takeaway-orders': takeawayCount,
    };
    final width = MediaQuery.sizeOf(context).width;
    final expanded = AppBreakpoints.isExpanded(width);
    final hasMoreSections = allVisibleItems.length > tabs.length;
    // Composing and billing hide the app bar to keep the cart in full view.
    final showTabs =
        !expanded &&
        !widget.isInner &&
        widget.showAppBar &&
        tabs.length + (hasMoreSections ? 1 : 0) >= 2;
    final showRail =
        expanded &&
        !widget.isInner &&
        widget.showAppBar &&
        allVisibleItems.length >= 2;
    final medium = width >= AppBreakpoints.medium;
    final selected = shellSections[_selectedId];

    return PopScope(
      canPop: ModalRoute.of(context)?.isFirst == false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onRootBack());
      },
      child: Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                toolbarHeight: medium ? 64 : kToolbarHeight,
                titleSpacing: AppSpacing.xs,
                leading: IconButton(
                  onPressed: widget.isInner ? _goBack : _toggleSidebar,
                  tooltip: widget.isInner ? 'Quay lại' : 'Menu',
                  icon: widget.isInner
                      ? const Icon(Icons.arrow_back)
                      : AnimatedIcon(
                          icon: AnimatedIcons.menu_close,
                          progress: _sidebarController,
                        ),
                ),
                title: Text(
                  widget.innerTitle ?? _currentTitle(allVisibleItems),
                ),
                actions: [
                  ...?widget.actions,
                  // Mirrors _buildContent, which mounts these screens itself.
                  if (widget.child == null) ...?selected?.actions,
                  SizedBox(width: medium ? AppSpacing.md : AppSpacing.xs),
                ],
              )
            : null,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Main content area. Composing and billing hide the app bar and
            // draw their own safe-area header, so the strip stays off them.
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showRail)
                    AppSidebarRail(
                      categories: visibleCategories,
                      selectedId: _selectedId,
                      itemBadges: badges,
                      onItemTap: _onItemTap,
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        if (widget.showAppBar) const RealtimeConnectionBanner(),
                        Expanded(
                          child: _buildContent(session, allVisibleItems),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Sidebar overlay
            if (!widget.isInner)
              AppSidebar(
                animation: _sidebarController,
                categories: visibleCategories,
                itemBadges: badges,
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
        bottomNavigationBar: showTabs
            ? AppBottomTabs(
                tabs: tabs,
                selectedId: _selectedId,
                hasMore: hasMoreSections,
                badges: badges,
                onTab: _onItemTap,
                onMore: _toggleSidebar,
              )
            : null,
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
      return const EmptyState(
        icon: Icons.lock_outline,
        message: 'Tài khoản chưa được cấp quyền truy cập chức năng nào.',
      );
    }

    final selected = items.where((i) => i.id == _selectedId).firstOrNull;
    if (selected == null) {
      return const Center(child: Text('Chọn chức năng từ menu.'));
    }
    final section = shellSections[selected.id];
    if (section != null) return section.build(session);

    return EmptyState(
      icon: selected.icon,
      message: selected.label,
      hint: 'Màn hình ${selected.label} đang được hoàn thiện.',
    );
  }

  String _roleName(AppSession session) => session.authenticatedUser.role.label;
}
