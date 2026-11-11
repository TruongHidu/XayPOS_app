import '../../auth/access_policy.dart';
import '../../auth/app_session.dart';
import 'sidebar_category.dart';
import 'sidebar_menu_item.dart';

/// Filters a list of [SidebarMenuItem] based on the current [AppSession].
///
/// An item is visible when [AccessPolicy.canSeeSection] allows it, or, for
/// an id the policy doesn't know, when its required permissions and features
/// are all present in the session.
List<SidebarMenuItem> filterMenuItems(
  AppSession session,
  List<SidebarMenuItem> allItems,
) {
  return allItems.where((item) {
    // Known sections share the router's rule; the fields below only cover
    // items the policy hasn't learned yet.
    final known = AccessPolicy.canSeeSection(session, item.id);
    if (known != null) return known;
    final hasAllPermissions = item.requiredPermissions.every(
      (p) => session.permissions.contains(p),
    );
    final hasAllFeatures = item.requiredFeatures.every(
      (f) => session.features.contains(f),
    );
    final hasAny =
        item.requiredAnyPermissions.isEmpty ||
        item.requiredAnyPermissions.any(session.permissions.contains);
    return hasAllPermissions && hasAny && hasAllFeatures;
  }).toList();
}

/// Filters a list of [SidebarCategory] based on the current [AppSession].
///
/// Each category's items are filtered by [filterMenuItems]. Categories
/// that end up with zero visible items are removed entirely.
List<SidebarCategory> filterCategories(
  AppSession session,
  List<SidebarCategory> allCategories,
) {
  final result = <SidebarCategory>[];
  for (final category in allCategories) {
    final visibleItems = filterMenuItems(session, category.items);
    if (visibleItems.isNotEmpty) {
      result.add(
        SidebarCategory(
          title: category.title,
          items: visibleItems,
          collapsible: category.collapsible,
          icon: category.icon,
        ),
      );
    }
  }
  return result;
}
