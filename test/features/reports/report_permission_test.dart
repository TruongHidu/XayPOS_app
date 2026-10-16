import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/ui/sidebar/app_sidebar_registry.dart';
import 'package:pos_saas_app/core/ui/sidebar/sidebar_filter.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/subscription/domain/entities/entitlement.dart';

import '../../helpers/auth_fakes.dart';

void main() {
  group('Report Permissions & Access Policy', () {
    test(
      'canDailyReport returns true only with REPORT_DAILY_VIEW + DAILY_REVENUE',
      () {
        final validSession = makeAppSession(
          permissions: {'REPORT_DAILY_VIEW'},
          features: {'DAILY_REVENUE'},
          status: SubscriptionStatus.active,
        );
        expect(AccessPolicy.canDailyReport(validSession), isTrue);

        final missingPerm = makeAppSession(
          permissions: {'REPORT_VIEW'},
          features: {'DAILY_REVENUE'},
          status: SubscriptionStatus.active,
        );
        expect(AccessPolicy.canDailyReport(missingPerm), isFalse);

        final missingFeature = makeAppSession(
          permissions: {'REPORT_DAILY_VIEW'},
          features: {'REPORTING'},
          status: SubscriptionStatus.active,
        );
        expect(AccessPolicy.canDailyReport(missingFeature), isFalse);

        final inactiveSub = makeAppSession(
          permissions: {'REPORT_DAILY_VIEW'},
          features: {'DAILY_REVENUE'},
          status: SubscriptionStatus.inactive,
        );
        expect(AccessPolicy.canDailyReport(inactiveSub), isFalse);
      },
    );

    test(
      'canDetailReport returns true only with REPORT_DETAIL_VIEW + DETAIL_REPORT',
      () {
        final validSession = makeAppSession(
          permissions: {'REPORT_DETAIL_VIEW'},
          features: {'DETAIL_REPORT'},
          status: SubscriptionStatus.active,
        );
        expect(AccessPolicy.canDetailReport(validSession), isTrue);

        // Does not require ORDER_VIEW, PAYMENT_VIEW, or MENU_VIEW
        expect(validSession.permissions.contains('ORDER_VIEW'), isFalse);
        expect(validSession.permissions.contains('PAYMENT_VIEW'), isFalse);
        expect(validSession.permissions.contains('MENU_VIEW'), isFalse);

        final oldMappingSession = makeAppSession(
          permissions: {'REPORT_VIEW'},
          features: {'REPORTING'},
          status: SubscriptionStatus.active,
        );
        expect(AccessPolicy.canDetailReport(oldMappingSession), isFalse);

        final inactiveSub = makeAppSession(
          permissions: {'REPORT_DETAIL_VIEW'},
          features: {'DETAIL_REPORT'},
          status: SubscriptionStatus.inactive,
        );
        expect(AccessPolicy.canDetailReport(inactiveSub), isFalse);
      },
    );

    test('Daily and Detail report permissions are strictly independent', () {
      final dailyOnly = makeAppSession(
        permissions: {'REPORT_DAILY_VIEW'},
        features: {'DAILY_REVENUE'},
      );
      expect(AccessPolicy.canDailyReport(dailyOnly), isTrue);
      expect(AccessPolicy.canDetailReport(dailyOnly), isFalse);
      expect(
        AccessPolicy.canOpenRoute(dailyOnly, '/app/daily-revenue'),
        isTrue,
      );
      expect(AccessPolicy.canOpenRoute(dailyOnly, '/app/reports'), isFalse);

      final detailOnly = makeAppSession(
        permissions: {'REPORT_DETAIL_VIEW'},
        features: {'DETAIL_REPORT'},
      );
      expect(AccessPolicy.canDailyReport(detailOnly), isFalse);
      expect(AccessPolicy.canDetailReport(detailOnly), isTrue);
      expect(AccessPolicy.canOpenRoute(detailOnly, '/app/reports'), isTrue);
      expect(
        AccessPolicy.canOpenRoute(detailOnly, '/app/daily-revenue'),
        isFalse,
      );
    });

    test(
      'User with ONLY detail report can enter appHome and see reports route',
      () {
        final detailOnly = makeAppSession(
          permissions: {'REPORT_DETAIL_VIEW'},
          features: {'DETAIL_REPORT'},
          role: UserRole.manager,
          status: SubscriptionStatus.active,
        );

        expect(AccessPolicy.initialRouteFor(detailOnly), '/app/home');
        expect(AccessPolicy.canOpenRoute(detailOnly, '/app/home'), isTrue);
        expect(AccessPolicy.canOpenRoute(detailOnly, '/app/reports'), isTrue);
      },
    );

    test('Sidebar items filter correctly based on report permissions', () {
      final allItems = AppSidebarRegistry.categories
          .expand((c) => c.items)
          .toList();

      final dailyOnly = makeAppSession(
        permissions: {'REPORT_DAILY_VIEW'},
        features: {'DAILY_REVENUE'},
      );
      final dailyFiltered = filterMenuItems(dailyOnly, allItems);
      expect(dailyFiltered.any((item) => item.id == 'daily-revenue'), isTrue);
      expect(dailyFiltered.any((item) => item.id == 'reports'), isFalse);

      final detailOnly = makeAppSession(
        permissions: {'REPORT_DETAIL_VIEW'},
        features: {'DETAIL_REPORT'},
      );
      final detailFiltered = filterMenuItems(detailOnly, allItems);
      expect(detailFiltered.any((item) => item.id == 'reports'), isTrue);
      expect(detailFiltered.any((item) => item.id == 'daily-revenue'), isFalse);
    });
  });
}
