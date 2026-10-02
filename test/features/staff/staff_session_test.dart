import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/staff/presentation/controllers/staff_list_controller.dart';
import '../../helpers/auth_fakes.dart';
import 'staff_fakes.dart';

void main() {
  test(
    'logout/account/tenant changes invalidate staff list and permission state',
    () async {
      final events = SessionEvents();
      final authRepo = FakeAuthRepository()
        ..loginResult = Success(makeAuthSession(permissions: staffPermissions));
      final entitlements = FakeEntitlementRepository()
        ..result = Success(makeEntitlement(features: staffFeatures));
      final auth = makeController(
        authRepository: authRepo,
        entitlementRepository: entitlements,
        sessionEvents: events,
      );
      await auth.login(
        const LoginCredentials(
          email: 'owner@example.com',
          password: 'password',
        ),
      );
      final repo = FakeStaffRepository()..delayedList = true;
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          staffRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(events.dispose);
      container.listen<StaffListController>(
        staffListControllerProvider,
        (_, _) {},
      );
      final old = container.read(staffListControllerProvider);
      await Future<void>.delayed(Duration.zero);
      events.refreshed(
        makeAuthSession(
          permissions: staffPermissions,
          tokens: makeTokens(accessToken: 'rotated'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        identical(old, container.read(staffListControllerProvider)),
        isTrue,
      );
      final permissions = container.read(staffPermissionControllerProvider);
      await permissions.load('A');
      permissions.setPermissionState('ORDER_CANCEL', 'grant');
      events.refreshed(
        makeAuthSession(
          restaurantId: 'tenant-2',
          permissions: staffPermissions,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final changed = container.read(staffListControllerProvider);
      expect(identical(old, changed), false);
      expect(changed.state.staffList, isEmpty);
      expect(
        container.read(staffPermissionControllerProvider).state.config,
        isNull,
      );
      repo.lists.first.complete(Success(page('OLD_TENANT')));
      await Future<void>.delayed(Duration.zero);
      expect(changed.state.staffList, isEmpty);
      expect(await old.toggleStatus(staffId: 'A', active: true), isNotNull);
      expect(entitlements.calls, 2);
      await auth.logout();
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(staffListControllerProvider).state.staffList,
        isEmpty,
      );
      expect(
        container.read(staffPermissionControllerProvider).state.localGrants,
        isEmpty,
      );
      authRepo.loginResult = Success(
        makeAuthSession(
          restaurantId: 'tenant-3',
          permissions: staffPermissions,
        ),
      );
      await auth.login(
        const LoginCredentials(email: 'new@example.com', password: 'password'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        container.read(staffListControllerProvider).state.staffList,
        isEmpty,
      );
      for (final pending in repo.lists) {
        if (!pending.isCompleted) pending.complete(Success(page('NEW')));
      }
      await Future<void>.delayed(Duration.zero);
    },
  );
}
