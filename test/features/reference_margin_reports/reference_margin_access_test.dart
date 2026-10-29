import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/ui/sidebar/app_sidebar_registry.dart';
import 'package:pos_saas_app/core/ui/sidebar/sidebar_filter.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/subscription/domain/entities/entitlement.dart';

import '../../helpers/auth_fakes.dart';

const marginPermissions = {'ORDER_VIEW', 'REPORT_DETAIL_VIEW'};
const marginFeatures = {'ORDER_MANAGEMENT', 'DETAIL_REPORT'};

AppSession _session({
  UserRole role = UserRole.owner,
  String? restaurantId = 'restaurant-1',
  Set<String> permissions = marginPermissions,
  Set<String> features = marginFeatures,
  SubscriptionStatus status = SubscriptionStatus.active,
  String? packageCode = 'PRO',
}) {
  final session = makeAppSession(
    role: role,
    restaurantId: restaurantId,
    permissions: permissions,
    features: features,
    status: status,
  );
  return AppSession(
    authenticatedUser: session.authenticatedUser,
    tokens: session.tokens,
    permissions: session.permissions,
    features: session.features,
    subscriptionStatus: session.subscriptionStatus,
    subscriptionId: session.subscriptionId,
    packageCode: packageCode,
  );
}

void main() {
  test('reference-margin capability requires each permission and feature', () {
    expect(AccessPolicy.canViewReferenceMarginReports(_session()), isTrue);
    expect(AccessPolicy.canViewReferenceMarginReports(null), isFalse);
    for (final permission in marginPermissions) {
      expect(
        AccessPolicy.canViewReferenceMarginReports(
          _session(permissions: {...marginPermissions}..remove(permission)),
        ),
        isFalse,
        reason: permission,
      );
    }
    for (final feature in marginFeatures) {
      expect(
        AccessPolicy.canViewReferenceMarginReports(
          _session(features: {...marginFeatures}..remove(feature)),
        ),
        isFalse,
        reason: feature,
      );
    }
  });

  test('subscription and nonempty tenant are required', () {
    for (final status in SubscriptionStatus.values) {
      expect(
        AccessPolicy.canViewReferenceMarginReports(_session(status: status)),
        status == SubscriptionStatus.active,
        reason: status.name,
      );
    }
    for (final tenant in <String?>[null, '', '   ']) {
      expect(
        AccessPolicy.canViewReferenceMarginReports(
          _session(restaurantId: tenant),
        ),
        isFalse,
      );
    }
  });

  test('capability is based on effective grants, not role or package name', () {
    for (final role in UserRole.values) {
      expect(
        AccessPolicy.canViewReferenceMarginReports(_session(role: role)),
        isTrue,
        reason: role.name,
      );
    }
    for (final package in <String?>['BASIC', 'PRO', 'NEW_PACKAGE', null]) {
      expect(
        AccessPolicy.canViewReferenceMarginReports(
          _session(packageCode: package),
        ),
        isTrue,
        reason: '$package',
      );
      expect(
        AccessPolicy.canViewReferenceMarginReports(
          _session(packageCode: package, features: {}),
        ),
        isFalse,
      );
    }
  });

  test('ordinary reports keep their independent permission/feature guards', () {
    final daily = _session(
      permissions: {'REPORT_DAILY_VIEW'},
      features: {'DAILY_REVENUE'},
    );
    final detail = _session(
      permissions: {'REPORT_DETAIL_VIEW'},
      features: {'DETAIL_REPORT'},
    );
    expect(AccessPolicy.canDailyReport(daily), isTrue);
    expect(AccessPolicy.canDetailReport(detail), isTrue);
    expect(AccessPolicy.canViewReferenceMarginReports(daily), isFalse);
    expect(AccessPolicy.canViewReferenceMarginReports(detail), isFalse);
    expect(AccessPolicy.canOpenRoute(daily, '/app/daily-revenue'), isTrue);
    expect(AccessPolicy.canOpenRoute(detail, '/app/reports'), isTrue);
  });

  test(
    'cashier can enter its granted report without opening legacy operations',
    () {
      final cashier = _session(role: UserRole.cashier);
      expect(AccessPolicy.initialRouteFor(cashier), '/app/reference-margin');
      expect(
        AccessPolicy.canOpenRoute(cashier, '/app/reference-margin'),
        isTrue,
      );
      expect(
        AccessPolicy.canOpenRoute(
          cashier,
          '/app/reference-margin?currencyCode=USD',
        ),
        isTrue,
      );
      expect(AccessPolicy.canOpenRoute(cashier, '/app/home'), isTrue);
      expect(AccessPolicy.canOpenRoute(cashier, '/app/orders'), isFalse);
      expect(AccessPolicy.canOpenRoute(cashier, '/app/reports'), isFalse);
      expect(AccessPolicy.canOpenRoute(cashier, '/app/daily-revenue'), isFalse);
      expect(
        AccessPolicy.canOpenRoute(cashier, '/app/reference-margin/not-a-route'),
        isFalse,
      );
      final denied = _session(
        role: UserRole.cashier,
        permissions: {'ORDER_VIEW'},
      );
      expect(AccessPolicy.initialRouteFor(denied), '/cashier-web-only');
      expect(
        AccessPolicy.canOpenRoute(denied, '/app/reference-margin'),
        isFalse,
      );
      expect(AccessPolicy.canOpenRoute(denied, '/app/home'), isFalse);
    },
  );

  test(
    'separate sidebar entry uses the complete capability, including subscription',
    () {
      final items = AppSidebarRegistry.categories
          .expand((c) => c.items)
          .toList();
      final entry = items.singleWhere(
        (item) => item.id == 'reference-margin-reports',
      );
      expect(entry.routePath, '/app/reference-margin');
      expect(entry.requiredPermissions.toSet(), marginPermissions);
      expect(entry.requiredFeatures.toSet(), marginFeatures);
      expect(
        filterMenuItems(
          _session(role: UserRole.cashier),
          items,
        ).map((e) => e.id),
        contains('reference-margin-reports'),
      );
      for (final session in [
        _session(permissions: {'REPORT_DETAIL_VIEW'}),
        _session(features: {'DETAIL_REPORT'}),
        _session(status: SubscriptionStatus.inactive),
      ]) {
        expect(
          filterMenuItems(session, items).map((e) => e.id),
          isNot(contains('reference-margin-reports')),
        );
        expect(
          AccessPolicy.canOpenRoute(session, '/app/reference-margin'),
          isFalse,
        );
      }
    },
  );

  test(
    'scope preserves token rotation and changes on tenant/authority/entitlement',
    () {
      final session = _session();
      final original = AccessPolicy.referenceMarginScope(session);
      final rotated = session.copyWithAuth(
        user: session.authenticatedUser,
        tokens: makeTokens(
          accessToken: 'rotated-access',
          refreshToken: 'rotated-refresh',
        ),
      );
      expect(AccessPolicy.referenceMarginScope(rotated), original);
      expect(
        AccessPolicy.referenceMarginScope(
          _session(restaurantId: 'restaurant-2'),
        ),
        isNot(original),
      );
      expect(
        AccessPolicy.referenceMarginScope(
          _session(permissions: {'ORDER_VIEW'}),
        ),
        isNot(original),
      );
      expect(
        AccessPolicy.referenceMarginScope(
          _session(features: {'ORDER_MANAGEMENT'}),
        ),
        isNot(original),
      );
      expect(
        AccessPolicy.referenceMarginScope(
          _session(status: SubscriptionStatus.inactive),
        ),
        isNot(original),
      );
    },
  );
}
