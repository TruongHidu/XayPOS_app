import 'package:flutter/widgets.dart';

/// Represents a single item in the application sidebar.
///
/// Each item has a label, icon, and a route path.
/// Access to the item is controlled by [requiredPermissions] and
/// [requiredFeatures] — the item is shown only when all conditions are met.
class SidebarMenuItem {
  const SidebarMenuItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.routePath,
    this.requiredPermissions = const [],
    this.requiredFeatures = const [],
  });

  /// Unique identifier used as key in lists.
  final String id;

  /// Display label for this menu item.
  final String label;

  /// Icon shown next to the label.
  final IconData icon;

  /// The route to navigate to when this item is tapped.
  final String routePath;

  /// Permission strings that the session must have (all required).
  final List<String> requiredPermissions;

  /// Feature strings that the subscription must have (all required).
  final List<String> requiredFeatures;
}
