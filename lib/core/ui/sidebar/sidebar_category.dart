import 'package:flutter/widgets.dart';

import 'sidebar_menu_item.dart';

/// Groups related [SidebarMenuItem]s under a common heading.
///
/// Categories are displayed as section headers inside the sidebar.
/// Non-collapsible headers are hidden when only one category is visible.
class SidebarCategory {
  const SidebarCategory({
    required this.title,
    required this.items,
    this.collapsible = false,
    this.icon,
  });

  /// Section heading displayed above the items (e.g. "VẬN HÀNH").
  final String title;

  /// Menu items that belong to this category.
  final List<SidebarMenuItem> items;

  /// Allows related destinations to be shown or hidden from their header.
  final bool collapsible;
  final IconData? icon;
}
