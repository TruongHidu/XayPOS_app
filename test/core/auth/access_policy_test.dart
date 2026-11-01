import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/values/inventory_mode.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';

import '../../helpers/auth_fakes.dart';

void main() {
  test('inventory screens enforce read access and section feature gates', () {
    final base = makeAppSession(
      permissions: {'INVENTORY_VIEW'},
      features: {'INVENTORY_MANAGEMENT'},
    );
    final full = makeAppSession(
      permissions: {'INVENTORY_VIEW'},
      features: {'INVENTORY_MANAGEMENT', 'LOW_STOCK_ALERT', 'STOCK_AUDIT'},
    );
    final noView = makeAppSession(
      permissions: {},
      features: {'INVENTORY_MANAGEMENT', 'LOW_STOCK_ALERT', 'STOCK_AUDIT'},
    );
    for (final path in [
      '/app/inventory/balances',
      '/app/inventory/warehouses',
      '/app/inventory/stock-documents',
      '/app/inventory/transactions',
    ]) {
      expect(AccessPolicy.canOpenRoute(base, path), isTrue, reason: path);
      expect(AccessPolicy.canOpenRoute(noView, path), isFalse, reason: path);
    }
    for (final path in [
      '/app/inventory/low-stock',
      '/app/inventory/alerts',
      '/app/inventory/audits',
      '/app/inventory?tab=alerts',
      '/app/inventory?tab=audits',
      '/app/inventory?tab=lowStock',
    ]) {
      expect(AccessPolicy.canOpenRoute(base, path), isFalse, reason: path);
      expect(AccessPolicy.canOpenRoute(full, path), isTrue, reason: path);
      expect(AccessPolicy.canOpenRoute(noView, path), isFalse, reason: path);
    }
    expect(
      AccessPolicy.canOpenRoute(full, '/app/inventory/audits/new'),
      isFalse,
    );
  });

  test('inventory mode needs a feature only when switching it on', () {
    bool can(
      Set<String> features, {
      InventoryMode from = InventoryMode.none,
      required InventoryMode to,
      bool creating = false,
    }) => AccessPolicy.canSetInventoryMode(
      makeAppSession(
        permissions: {'MENU_CREATE', 'MENU_UPDATE'},
        features: {'MENU_MANAGEMENT', ...features},
      ),
      creating: creating,
      from: from,
      to: to,
    );
    expect(can({'INVENTORY_MANAGEMENT'}, to: InventoryMode.direct), isTrue);
    expect(can({}, to: InventoryMode.direct), isFalse);
    expect(can({}, to: InventoryMode.direct, creating: true), isFalse);
    expect(
      can({}, from: InventoryMode.direct, to: InventoryMode.direct),
      isTrue,
    );
    expect(can({}, from: InventoryMode.direct, to: InventoryMode.none), isTrue);
    expect(can({'RECIPE_MANAGEMENT'}, to: InventoryMode.recipe), isTrue);
    expect(can({}, to: InventoryMode.recipe), isFalse);
    expect(
      can({'RECIPE_MANAGEMENT'}, to: InventoryMode.recipe, creating: true),
      isFalse,
    );
    expect(
      AccessPolicy.canSetInventoryMode(
        makeAppSession(
          permissions: const {'MENU_CREATE', 'RECIPE_CREATE'},
          features: const {'MENU_MANAGEMENT', 'RECIPE_MANAGEMENT'},
        ),
        creating: true,
        from: InventoryMode.none,
        to: InventoryMode.recipe,
      ),
      isTrue,
    );
    expect(
      AccessPolicy.canSetInventoryMode(
        makeAppSession(
          permissions: {'MENU_VIEW'},
          features: {'MENU_MANAGEMENT', 'INVENTORY_MANAGEMENT'},
        ),
        creating: false,
        from: InventoryMode.none,
        to: InventoryMode.direct,
      ),
      isFalse,
    );
  });

  test('missing permission blocks a protected route', () {
    final session = makeAppSession(
      role: UserRole.waiter,
      permissions: const {},
      features: {'TABLE_MANAGEMENT'},
    );
    expect(AccessPolicy.canOpenRoute(session, '/app/home'), isFalse);
    expect(AccessPolicy.initialRouteFor(session), '/no-accessible-feature');
  });

  test('missing feature routes kitchen to no accessible feature', () {
    final session = makeAppSession(
      role: UserRole.kitchen,
      permissions: {'KITCHEN_VIEW'},
      features: const {},
    );
    expect(AccessPolicy.canOpenRoute(session, '/kitchen/orders'), isFalse);
    expect(AccessPolicy.initialRouteFor(session), '/no-accessible-feature');
  });

  test('deep link is accepted only when access policy allows it', () {
    final allowed = makeAppSession(
      role: UserRole.waiter,
      permissions: {'TABLE_VIEW'},
      features: {'TABLE_MANAGEMENT'},
    );
    final denied = makeAppSession(
      role: UserRole.waiter,
      permissions: {'ORDER_VIEW'},
      features: const {},
    );

    expect(AccessPolicy.canOpenRoute(allowed, '/app/home'), isTrue);
    expect(AccessPolicy.canOpenRoute(denied, '/app/home'), isFalse);
  });
}
