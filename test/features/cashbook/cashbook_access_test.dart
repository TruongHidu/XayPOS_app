import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/ui/sidebar/app_sidebar_registry.dart';
import 'package:pos_saas_app/core/ui/sidebar/sidebar_filter.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/subscription/domain/entities/entitlement.dart';

import '../../helpers/auth_fakes.dart';
import 'cashbook_fakes.dart';

void main() {
  test(
    'cashbook view needs the permission, DETAIL_REPORT and a staff role',
    () {
      final full = makeAppSession(
        permissions: cashbookPermissions,
        features: cashbookFeatures,
      );
      expect(AccessPolicy.canCashbook(full, 'CASHBOOK_VIEW'), isTrue);
      expect(AccessPolicy.canCashbook(full, 'REPORT_DETAIL_VIEW'), isFalse);
      expect(AccessPolicy.canCashbook(null, 'CASHBOOK_VIEW'), isFalse);
      expect(
        AccessPolicy.canCashbook(
          makeAppSession(
            permissions: {'CASHBOOK_VIEW'},
            features: {'INVENTORY_MANAGEMENT'},
          ),
          'CASHBOOK_VIEW',
        ),
        isFalse,
      );
      for (final role in [UserRole.cashier, UserRole.superAdmin]) {
        expect(
          AccessPolicy.canCashbook(
            makeAppSession(
              role: role,
              permissions: cashbookPermissions,
              features: cashbookFeatures,
            ),
            'CASHBOOK_VIEW',
          ),
          isFalse,
          reason: role.name,
        );
      }
      expect(
        AccessPolicy.canCashbook(
          makeAppSession(
            permissions: cashbookPermissions,
            features: cashbookFeatures,
            status: SubscriptionStatus.inactive,
          ),
          'CASHBOOK_VIEW',
        ),
        isFalse,
      );
    },
  );

  test('receipt link and reconciliation also need inventory access', () {
    final noInventory = makeAppSession(
      permissions: {'CASHBOOK_VIEW', 'CASHBOOK_CREATE'},
      features: {'DETAIL_REPORT', 'INVENTORY_MANAGEMENT'},
    );
    expect(AccessPolicy.canCashbook(noInventory, 'CASHBOOK_CREATE'), isTrue);
    expect(AccessPolicy.canLinkCashbookStockReceipt(noInventory), isFalse);
    expect(AccessPolicy.canReconcileCashbookReceipts(noInventory), isFalse);

    final noFeature = makeAppSession(
      permissions: cashbookPermissions,
      features: {'DETAIL_REPORT'},
    );
    expect(AccessPolicy.canReconcileCashbookReceipts(noFeature), isFalse);

    final full = makeAppSession(
      permissions: cashbookPermissions,
      features: cashbookFeatures,
    );
    expect(AccessPolicy.canLinkCashbookStockReceipt(full), isTrue);
    expect(AccessPolicy.canReconcileCashbookReceipts(full), isTrue);
  });

  test('route and sidebar follow the same capability', () {
    final viewer = makeAppSession(
      permissions: {'CASHBOOK_VIEW'},
      features: {'DETAIL_REPORT'},
    );
    expect(AccessPolicy.canOpenRoute(viewer, '/app/cashbook'), isTrue);
    expect(AccessPolicy.initialRouteFor(viewer), '/app/home');

    bool visible(AppSession session) => filterCategories(
      session,
      AppSidebarRegistry.categories,
    ).expand((c) => c.items).any((i) => i.id == 'cashbook');
    expect(visible(viewer), isTrue);
    expect(
      visible(
        makeAppSession(
          role: UserRole.waiter,
          permissions: {'MENU_VIEW'},
          features: {'MENU_MANAGEMENT', 'DETAIL_REPORT'},
        ),
      ),
      isFalse,
    );
  });
}
