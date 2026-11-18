import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sidebar/sidebar_menu_item.dart';

/// One-tap switching between a role's main sections. Everything else stays in
/// the sidebar, reached from the last tab. Which sections become tabs is the
/// app's decision (`app/shell/shell_tabs.dart`); this widget only draws them.
class AppBottomTabs extends StatelessWidget {
  const AppBottomTabs({
    super.key,
    required this.tabs,
    required this.selectedId,
    required this.hasMore,
    required this.badges,
    required this.onTab,
    required this.onMore,
    this.moreOpen = false,
  });

  /// Bar height above the system inset; the menu sheet stops right above it.
  static const double height = 64;

  final List<SidebarMenuItem> tabs;
  final String? selectedId;
  final bool hasMore;

  /// The menu opened from "Khác" is showing, so "Khác" is the lit tab.
  final bool moreOpen;

  /// Counts by section id; those outside [tabs] add up on the last tab.
  final Map<String, int> badges;
  final ValueChanged<SidebarMenuItem> onTab;
  final VoidCallback onMore;

  /// A section outside the tabs lives under "Khác".
  int get _selectedIndex {
    if (hasMore && moreOpen) return tabs.length;
    final index = tabs.indexWhere((tab) => tab.id == selectedId);
    if (index >= 0) return index;
    return hasMore ? tabs.length : 0;
  }

  Widget _icon(IconData icon, int count) => Badge(
    isLabelVisible: count > 0,
    label: Text(count > 99 ? '99+' : '$count'),
    child: Icon(icon),
  );

  @override
  Widget build(BuildContext context) {
    final tabIds = {for (final tab in tabs) tab.id};
    final moreCount = badges.entries
        .where((entry) => !tabIds.contains(entry.key))
        .fold(0, (sum, entry) => sum + entry.value);
    // A hairline separates the white bar from the grey page above it.
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      // Tab labels stay readable without pushing the bar off the screen.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: NavigationBar(
          height: height,
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
                label: tab.compactLabel,
              ),
            if (hasMore)
              NavigationDestination(
                key: const ValueKey('bottom-tab-more'),
                icon: _icon(Icons.menu, moreCount),
                label: 'Khác',
                // Long press says what it opens; also what tests look for.
                tooltip: 'Menu',
              ),
          ],
        ),
      ),
    );
  }
}
