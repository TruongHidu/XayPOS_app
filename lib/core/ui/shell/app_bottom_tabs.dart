import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../features/auth/domain/entities/user_role.dart';
import '../sidebar/sidebar_menu_item.dart';

/// The sections each role opens all day, most used first. The first one the
/// user can open is also where the app starts. Visibility itself comes from
/// permissions and features, never from this list.
List<String> _preferredTabs(UserRole role) => switch (role) {
  UserRole.kitchen => const ['kitchen-display', 'orders'],
  UserRole.owner ||
  UserRole.manager => const ['order-create', 'orders', 'reports', 'menu'],
  _ => const ['order-create', 'orders', 'takeaway-orders', 'tables'],
};

/// Sidebar labels are too long for five tabs on a phone.
const _shortLabels = {
  'takeaway-orders': 'Mang đi',
  'tables': 'Bàn',
  'kitchen-display': 'Bếp',
};

/// Only what this user may open, so permissions stay in the sidebar filter.
List<SidebarMenuItem> bottomTabsFor(
  UserRole role,
  List<SidebarMenuItem> visible,
) => [
  for (final id in _preferredTabs(role))
    ...visible.where((item) => item.id == id),
];

/// One-tap switching between a role's main sections. Everything else stays in
/// the sidebar, reached from the last tab.
class AppBottomTabs extends StatelessWidget {
  const AppBottomTabs({
    super.key,
    required this.tabs,
    required this.selectedId,
    required this.hasMore,
    required this.badges,
    required this.onTab,
    required this.onMore,
  });

  final List<SidebarMenuItem> tabs;
  final String? selectedId;
  final bool hasMore;

  /// Counts by section id; those outside [tabs] add up on the last tab.
  final Map<String, int> badges;
  final ValueChanged<SidebarMenuItem> onTab;
  final VoidCallback onMore;

  /// A section outside the tabs lives under "Khác".
  int get _selectedIndex {
    final index = tabs.indexWhere((tab) => tab.id == selectedId);
    if (index >= 0) return index;
    return hasMore ? tabs.length : 0;
  }

  Widget _icon(IconData icon, int count) => Badge(
    isLabelVisible: count > 0,
    label: Text('$count'),
    child: Icon(icon),
  );

  @override
  Widget build(BuildContext context) {
    final tabIds = {for (final tab in tabs) tab.id};
    final moreCount = badges.entries
        .where((entry) => !tabIds.contains(entry.key))
        .fold(0, (sum, entry) => sum + entry.value);
    return NavigationBar(
      height: 64,
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) {
        HapticFeedback.selectionClick();
        if (index < tabs.length) {
          onTab(tabs[index]);
        } else {
          onMore();
        }
      },
      destinations: [
        for (final tab in tabs)
          NavigationDestination(
            key: ValueKey('bottom-tab-${tab.id}'),
            icon: _icon(tab.icon, badges[tab.id] ?? 0),
            label: _shortLabels[tab.id] ?? tab.label,
          ),
        if (hasMore)
          NavigationDestination(
            key: const ValueKey('bottom-tab-more'),
            icon: _icon(Icons.menu, moreCount),
            label: 'Khác',
          ),
      ],
    );
  }
}
