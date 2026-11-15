import '../../core/ui/sidebar/sidebar_menu_item.dart';
import '../../features/auth/domain/entities/user_role.dart';

/// The sections each role opens all day, most used first. The first one the
/// user can open is also where the app starts. Visibility itself comes from
/// permissions and features, never from this list.
List<String> _preferredTabs(UserRole role) => switch (role) {
  UserRole.kitchen => const ['kitchen-display', 'orders'],
  UserRole.owner ||
  UserRole.manager => const ['overview', 'order-create', 'orders', 'reports'],
  _ => const ['order-create', 'orders', 'takeaway-orders', 'tables'],
};

/// Only what this user may open, so permissions stay in the sidebar filter.
List<SidebarMenuItem> bottomTabsFor(
  UserRole role,
  List<SidebarMenuItem> visible,
) => [
  for (final id in _preferredTabs(role))
    ...visible.where((item) => item.id == id),
];
