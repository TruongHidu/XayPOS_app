import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide group;
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/ui/sidebar/app_sidebar_registry.dart';
import 'package:pos_saas_app/core/ui/sidebar/sidebar_filter.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_price.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_query.dart';
import 'menu_fakes.dart';
import '../../helpers/auth_fakes.dart';

void main() {
  test(
    'sidebar and route have identical menu policy for restaurant and web-only roles',
    () {
      for (final role in UserRole.values) {
        for (final permission in [
          <String>{},
          {'MENU_VIEW'},
        ]) {
          final session = makeAppSession(role: role, permissions: permission);
          final visible = filterCategories(
            session,
            AppSidebarRegistry.categories,
          ).expand((c) => c.items).any((i) => i.id == 'menu');
          expect(visible, AccessPolicy.canOpenRoute(session, '/app/menu'));
          if (role == UserRole.cashier) {
            expect(AccessPolicy.initialRouteFor(session), '/cashier-web-only');
          }
          if (role == UserRole.superAdmin) {
            expect(AccessPolicy.initialRouteFor(session), '/admin-web-only');
          }
        }
      }
    },
  );
  test(
    'provider scope survives token rotation, replaces state on tenant change and logout',
    () async {
      final events = SessionEvents();
      final authRepo = FakeAuthRepository()
        ..loginResult = Success(makeAuthSession(permissions: menuPermissions));
      final auth = makeController(
        authRepository: authRepo,
        sessionEvents: events,
      );
      await auth.login(
        const LoginCredentials(email: 'menu@example.com', password: 'password'),
      );
      final items = FakeMenuItems()..rows = [item()];
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          menuItemRepositoryProvider.overrideWithValue(items),
          menuGroupRepositoryProvider.overrideWithValue(FakeMenuGroups()),
        ],
      );
      addTearDown(events.dispose);
      addTearDown(container.dispose);
      final subscription = container.listen(
        menuItemControllerProvider,
        (_, next) {},
      );
      addTearDown(subscription.close);
      final first = container.read(menuItemControllerProvider);
      container.read(menuGroupFilterProvider.notifier).state = item().group;
      first.setQuery(const MenuQuery(q: 'draft query'));
      await Future<void>.delayed(Duration.zero);
      events.refreshed(
        makeAuthSession(
          permissions: menuPermissions,
          tokens: makeTokens(accessToken: 'new'),
        ),
      );
      await container.pump();
      expect(
        identical(container.read(menuItemControllerProvider), first),
        true,
      );
      expect(first.state.query.q, 'draft query');
      expect(container.read(menuGroupFilterProvider)?.id, 'g1');
      items.rows = [];
      events.refreshed(
        makeAuthSession(
          restaurantId: 'new-tenant',
          permissions: menuPermissions,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      final second = container.read(menuItemControllerProvider);
      expect(identical(second, first), false);
      expect(first.isCurrent, false);
      expect(second.state.query.q, '');
      expect(second.state.rows, isEmpty);
      expect(container.read(menuGroupFilterProvider), isNull);
      await auth.logout();
      await container.pump();
      expect(second.isCurrent, false);
      expect(container.read(menuItemControllerProvider).state.rows, isEmpty);
    },
  );
  test(
    'read-only owner cannot create, update or delete through controllers',
    () async {
      final auth = makeController();
      await auth.login(
        const LoginCredentials(email: 'menu@example.com', password: 'password'),
      );
      final items = FakeMenuItems();
      final groups = FakeMenuGroups();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          menuItemRepositoryProvider.overrideWithValue(items),
          menuGroupRepositoryProvider.overrideWithValue(groups),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(menuItemControllerProvider);
      await controller.create(
        CreateMenuItemInput(
          name: 'Tea',
          baseUnit: 'cup',
          salePrice: MenuPrice.parse('0.01'),
        ),
      );
      await controller.update(
        'i1',
        const UpdateMenuItemInput(expectedVersion: 9, name: 'New'),
      );
      await controller.delete(item());
      await controller.setStatus(item(), false);
      await container.read(menuGroupControllerProvider).delete(group());
      expect(items.writes, isEmpty);
      expect(groups.writes, isEmpty);
    },
  );
  test(
    'access recovery refreshes once, preserves notice and does not log out every 403',
    () async {
      final repository = FakeAuthRepository()
        ..loginResult = Success(makeAuthSession(permissions: menuPermissions))
        ..restoreResult = Success(
          makeAuthSession(permissions: menuPermissions),
        );
      final auth = makeController(authRepository: repository);
      addTearDown(auth.dispose);
      await auth.login(
        const LoginCredentials(email: 'menu@example.com', password: 'password'),
      );
      final notices = <String>[];
      final recovery = MenuAccessRecovery(auth, notices.add);
      const failure = Failure(
        type: FailureType.forbidden,
        code: 'FORBIDDEN',
        message: 'Access changed',
      );
      await Future.wait([recovery.handle(failure), recovery.handle(failure)]);
      await recovery.handle(failure);
      expect(repository.restoreCalls, 1);
      expect(repository.logoutCalls, 0);
      expect(auth.state.session, isNotNull);
      expect(notices, isNotEmpty);
    },
  );
}
