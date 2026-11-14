import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/ui/shell/app_bottom_tabs.dart';
import 'package:pos_saas_app/core/ui/sidebar/app_sidebar_registry.dart';
import 'package:pos_saas_app/core/ui/sidebar/sidebar_filter.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import '../../helpers/auth_fakes.dart';

const _features = {
  'ORDER_MANAGEMENT',
  'KITCHEN_DISPLAY',
  'TABLE_MANAGEMENT',
  'POS_QUICK_ORDER',
  'MENU_MANAGEMENT',
  'QR_MENU_VIEW',
  'QR_TABLE_ORDER',
};

/// Seeded defaults for the KITCHEN role on the backend.
const _kitchen = {
  'ORDER_VIEW',
  'ORDER_MARK_SERVED',
  'KITCHEN_VIEW',
  'KITCHEN_START_COOKING',
  'KITCHEN_MARK_READY',
};

List<String> _visible(AppSession session) => [
  for (final item in filterCategories(
    session,
    AppSidebarRegistry.categories,
  ).expand((c) => c.items))
    item.id,
];

void main() {
  test('default kitchen staff see only kitchen work and order reading', () {
    final kitchen = makeAppSession(
      role: UserRole.kitchen,
      permissions: _kitchen,
      features: _features,
    );
    expect(_visible(kitchen), ['orders', 'kitchen-display', 'settings']);
    // The old dish-status link still lands on the kitchen screen.
    expect(AccessPolicy.canOpenRoute(kitchen, '/app/dish-status'), isTrue);
    expect(AccessPolicy.canOpenRoute(kitchen, '/app/order-create'), isFalse);
    expect(AccessPolicy.canOpenRoute(kitchen, '/app/takeaway'), isFalse);
    final visible = filterCategories(
      kitchen,
      AppSidebarRegistry.categories,
    ).expand((c) => c.items).toList();
    expect(
      [for (final tab in bottomTabsFor(UserRole.kitchen, visible)) tab.id],
      ['kitchen-display', 'orders'],
    );
  });

  test('a single granted permission shows its section whatever the role', () {
    final kitchenWithTables = makeAppSession(
      role: UserRole.kitchen,
      permissions: {..._kitchen, 'TABLE_VIEW'},
      features: _features,
    );
    expect(_visible(kitchenWithTables), contains('order-create'));
    expect(_visible(kitchenWithTables), contains('tables'));
  });

  test('Gọi món opens for any one real job, never for reading alone', () {
    AppSession with_(Set<String> permissions) =>
        makeAppSession(permissions: permissions, features: _features);
    expect(AccessPolicy.canOrderWorkspace(with_({'ORDER_VIEW'})), isFalse);
    expect(
      AccessPolicy.canOrderWorkspace(with_({'ORDER_VIEW', 'TABLE_VIEW'})),
      isTrue,
    );
    expect(
      AccessPolicy.canOrderWorkspace(with_({'ORDER_CREATE', 'MENU_VIEW'})),
      isTrue,
    );
    expect(AccessPolicy.canOrderWorkspace(with_({'ORDER_CREATE'})), isFalse);
    expect(
      AccessPolicy.canOrderWorkspace(with_({'ORDER_VIEW', 'ORDER_UPDATE'})),
      isTrue,
    );
  });

  test('sidebar and router agree on every top-level section', () {
    for (final permissions in [
      _kitchen,
      {'ORDER_VIEW'},
      {'ORDER_VIEW', 'ORDER_CREATE', 'ORDER_UPDATE', 'MENU_VIEW', 'TABLE_VIEW'},
      {'INVENTORY_VIEW', 'REPORT_DETAIL_VIEW', 'STAFF_VIEW'},
    ]) {
      final session = makeAppSession(
        permissions: permissions,
        features: {
          ..._features,
          'INVENTORY_MANAGEMENT',
          'DETAIL_REPORT',
          'STAFF_MANAGEMENT',
        },
      );
      final shown = _visible(session).toSet();
      for (final item in AppSidebarRegistry.categories.expand((c) => c.items)) {
        expect(
          AccessPolicy.canOpenRoute(session, item.routePath),
          shown.contains(item.id),
          reason: '${item.id} with $permissions',
        );
      }
    }
  });
}
