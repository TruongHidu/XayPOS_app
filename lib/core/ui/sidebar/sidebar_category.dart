import 'sidebar_menu_item.dart';

/// Groups related [SidebarMenuItem]s under a common heading.
///
/// Categories are displayed as section headers inside the sidebar.
/// If only one category is visible after filtering, the header is
/// hidden to avoid redundant UI.
class SidebarCategory {
  const SidebarCategory({required this.title, required this.items});

  /// Section heading displayed above the items (e.g. "VẬN HÀNH").
  final String title;

  /// Menu items that belong to this category.
  final List<SidebarMenuItem> items;
}
