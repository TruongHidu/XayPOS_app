import 'package:flutter/material.dart';

import 'sidebar_category.dart';
import 'sidebar_menu_item.dart';

/// An animated sidebar (drawer) that slides in from the left edge.
///
/// Uses an [AnimationController] owned by the parent via [animation] so
/// the parent can trigger open/close from a hamburger icon.
///
/// Expandable categories retain their presentation state while the drawer closes.
class AppSidebar extends StatefulWidget {
  const AppSidebar({
    super.key,
    required this.animation,
    required this.categories,
    required this.selectedId,
    required this.onItemTap,
    required this.onLogout,
    required this.userName,
    required this.userRole,
    this.itemBadges = const {},
    this.restaurantName,
    this.packageCode,
  });

  /// Drives the slide-in / slide-out transition.
  final Animation<double> animation;

  /// Visible menu categories (already filtered by permission/feature).
  final List<SidebarCategory> categories;

  /// The [SidebarMenuItem.id] of the currently active item.
  final String? selectedId;

  /// Optional counts displayed beside visible menu items.
  final Map<String, int> itemBadges;

  /// Called when the user taps on a menu item.
  final ValueChanged<SidebarMenuItem> onItemTap;

  /// Called when the user taps "Đăng xuất".
  final VoidCallback onLogout;

  /// Display name of the authenticated user.
  final String userName;

  /// Human-readable role label.
  final String userRole;

  /// Optional restaurant name shown in the header.
  final String? restaurantName;

  /// Optional package code (BASIC / PRO / PREMIUM).
  final String? packageCode;

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  static const double _width = 280;
  final Map<String, bool> _expanded = {};

  @override
  void initState() {
    super.initState();
    _syncExpansion();
  }

  @override
  void didUpdateWidget(covariant AppSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncExpansion(selectionChanged: oldWidget.selectedId != widget.selectedId);
  }

  void _syncExpansion({bool selectionChanged = false}) {
    final categories = widget.categories.where(
      (category) => category.collapsible,
    );
    final titles = categories.map((category) => category.title).toSet();
    _expanded.removeWhere((title, _) => !titles.contains(title));
    for (final category in categories) {
      final containsSelection = category.items.any(
        (item) => item.id == widget.selectedId,
      );
      _expanded.putIfAbsent(category.title, () => containsSelection);
      if (selectionChanged && containsSelection) {
        _expanded[category.title] = true;
      }
    }
  }

  /// Whether to show category headers (hidden when there is only one).
  bool get _showHeaders => widget.categories.length > 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: widget.animation,
      builder: (context, child) {
        final slide =
            Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero).animate(
              CurvedAnimation(
                parent: widget.animation,
                curve: Curves.easeOutCubic,
              ),
            );
        final fade = Tween<double>(begin: 0, end: 0.5).animate(
          CurvedAnimation(parent: widget.animation, curve: Curves.easeOut),
        );

        return Stack(
          children: [
            // Scrim – tapping anywhere dismisses the sidebar.
            if (widget.animation.value > 0)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    if (widget.animation is AnimationController) {
                      (widget.animation as AnimationController).reverse();
                    }
                  },
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: fade.value),
                  ),
                ),
              ),

            // Sidebar panel
            SlideTransition(
              position: slide,
              child: Material(
                elevation: widget.animation.value == 0 ? 0 : 16,
                shadowColor: Colors.black26,
                child: SizedBox(
                  width: _width,
                  height: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          colorScheme.surface,
                          colorScheme.surfaceContainerLowest,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Column(
                        children: [
                          // _Header(
                          //   userName: userName,
                          //   userRole: userRole,
                          //   restaurantName: restaurantName,
                          //   packageCode: packageCode,
                          // ),
                          const Divider(height: 1),
                          Expanded(child: _buildCategoryList(context)),
                          const Divider(height: 1),
                          _LogoutTile(onTap: widget.onLogout),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategoryList(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _Header(
          userName: widget.userName,
          userRole: widget.userRole,
          restaurantName: widget.restaurantName,
          packageCode: widget.packageCode,
        ),
        for (int i = 0; i < widget.categories.length; i++) ...[
          if (widget.categories[i].collapsible)
            _buildExpandableCategory(context, widget.categories[i])
          else ...[
            // Category header
            if (_showHeaders) ...[
              if (i > 0) const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  widget.categories[i].title,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
            // Menu items within category
            for (final item in widget.categories[i].items)
              _MenuTile(
                item: item,
                badgeCount: widget.itemBadges[item.id],
                isSelected: item.id == widget.selectedId,
                onTap: () => widget.onItemTap(item),
              ),
          ],
        ],
      ],
    );
  }

  Widget _buildExpandableCategory(
    BuildContext context,
    SidebarCategory category,
  ) {
    final expanded = _expanded[category.title] ?? false;
    final active = category.items.any((item) => item.id == widget.selectedId);
    final colors = Theme.of(context).colorScheme;
    void toggle() => setState(() => _expanded[category.title] = !expanded);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Semantics(
            expanded: expanded,
            child: ListTile(
              key: ValueKey('sidebar-group-${category.title}'),
              minTileHeight: 56,
              contentPadding: const EdgeInsets.only(left: 16, right: 4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: Icon(
                category.icon ?? Icons.folder_outlined,
                color: active ? colors.primary : colors.onSurfaceVariant,
                size: 22,
              ),
              title: Text(
                category.title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: active ? colors.primary : colors.onSurface,
                ),
              ),
              trailing: IconButton(
                tooltip:
                    '${expanded ? 'Thu gọn' : 'Mở rộng'} ${category.title}',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: toggle,
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ),
              onTap: toggle,
            ),
          ),
        ),
        if (expanded)
          for (final item in category.items)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _MenuTile(
                key: ValueKey('sidebar-item-${item.id}'),
                item: item,
                badgeCount: widget.itemBadges[item.id],
                isSelected: item.id == widget.selectedId,
                onTap: () => widget.onItemTap(item),
              ),
            ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────
// Private sub-widgets
// ──────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.userName,
    required this.userRole,
    this.restaurantName,
    this.packageCode,
  });

  final String userName;
  final String userRole;
  final String? restaurantName;
  final String? packageCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 28,
            backgroundColor: colorScheme.primaryContainer,
            child: Text(
              userName.isNotEmpty ? userName[0].toUpperCase() : '?',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // User name
          Text(
            userName,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          // Role badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              userRole,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (restaurantName != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 14,
                  color: colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    restaurantName!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (packageCode != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.workspace_premium_outlined,
                  size: 14,
                  color: colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Text(
                  'Gói: $packageCode',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuTile extends StatefulWidget {
  const _MenuTile({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
    this.badgeCount,
  });

  final SidebarMenuItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final int? badgeCount;

  @override
  State<_MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<_MenuTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isActive = widget.isSelected;
    final badgeCount = widget.badgeCount ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isActive
                ? colorScheme.primaryContainer.withValues(alpha: 0.7)
                : _hovering
                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: Icon(
              widget.item.icon,
              color: isActive
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              size: 22,
            ),
            title: Text(
              widget.item.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
            trailing: badgeCount > 0
                ? Semantics(
                    key: ValueKey('sidebar-badge-${widget.item.id}'),
                    label: '$badgeCount mục',
                    child: ExcludeSemantics(
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.error,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onError,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
            onTap: widget.onTap,
          ),
        ),
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  const _LogoutTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(Icons.logout, color: theme.colorScheme.error, size: 22),
        title: Text(
          'Đăng xuất',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.error,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
