import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/ui/sidebar/app_sidebar_registry.dart';
import 'package:pos_saas_app/core/ui/sidebar/sidebar_filter.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/tables/domain/entities/table_query.dart';
import '../../helpers/auth_fakes.dart';
import 'table_fakes.dart';

void main() {
  test('route and sidebar share feature/permission gates, no owner bypass', () {
    for (final role in UserRole.values) {
      for (final features in [
        <String>{},
        {'TABLE_MANAGEMENT'},
      ]) {
        for (final permissions in [
          <String>{},
          {'TABLE_VIEW'},
          {'TABLE_OPEN'},
        ]) {
          final session = makeAppSession(
            role: role,
            permissions: permissions,
            features: features,
          );
          final expected =
              const {
                UserRole.owner,
                UserRole.manager,
                UserRole.waiter,
                UserRole.kitchen,
              }.contains(role) &&
              features.isNotEmpty &&
              permissions.contains('TABLE_VIEW');
          expect(AccessPolicy.canOpenRoute(session, '/app/tables'), expected);
          expect(
            filterCategories(
              session,
              AppSidebarRegistry.categories,
            ).expand((c) => c.items).any((i) => i.id == 'tables'),
            expected,
          );
          expect(AccessPolicy.canTables(session, 'TABLE_UPDATE'), false);
          if (role == UserRole.cashier) {
            expect(AccessPolicy.initialRouteFor(session), '/cashier-web-only');
          }
          if (role == UserRole.superAdmin) {
            expect(AccessPolicy.initialRouteFor(session), '/admin-web-only');
          }
        }
      }
    }
    for (final permission in tablePermissions) {
      final session = makeAppSession(
        permissions: {permission},
        features: {'TABLE_MANAGEMENT'},
      );
      for (final operation in tablePermissions) {
        expect(
          AccessPolicy.canTables(session, operation),
          operation == permission,
        );
      }
    }
  });
  test(
    'providers preserve filters on token rotation and reset tenant/logout/permissions',
    () async {
      final events = SessionEvents(), server = TableServer();
      final repo = FakeAuthRepository()
        ..loginResult = Success(makeAuthSession(permissions: tablePermissions));
      final auth = makeController(
        authRepository: repo,
        sessionEvents: events,
        entitlementRepository: FakeEntitlementRepository()
          ..result = Success(makeEntitlement(features: {'TABLE_MANAGEMENT'})),
      );
      await auth.login(
        const LoginCredentials(email: 'a@b.com', password: 'password'),
      );
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          restaurantTableRepositoryProvider.overrideWithValue(server.tables),
          tableAreaRepositoryProvider.overrideWithValue(server.areas),
          tableSessionRepositoryProvider.overrideWithValue(server.sessions),
        ],
      );
      addTearDown(events.dispose);
      addTearDown(server.close);
      addTearDown(container.dispose);
      final sub = container.listen(
        restaurantTableControllerProvider,
        (_, next) {},
      );
      addTearDown(sub.close);
      final first = container.read(restaurantTableControllerProvider);
      first.setQuery(const TableQuery(q: 'draft'));
      events.refreshed(
        makeAuthSession(
          permissions: tablePermissions,
          tokens: makeTokens(accessToken: 'new'),
        ),
      );
      await container.pump();
      expect(
        identical(first, container.read(restaurantTableControllerProvider)),
        true,
      );
      expect(first.query.q, 'draft');
      events.refreshed(makeAuthSession(permissions: {'TABLE_VIEW'}));
      await container.pump();
      final reduced = container.read(restaurantTableControllerProvider);
      expect(identical(first, reduced), false);
      expect(reduced.query.q, '');
      expect(first.isCurrent, false);
      events.refreshed(
        makeAuthSession(restaurantId: 'other', permissions: {'TABLE_VIEW'}),
      );
      await container.pump();
      expect(
        identical(reduced, container.read(restaurantTableControllerProvider)),
        false,
      );
      await auth.logout();
      await container.pump();
      expect(container.read(restaurantTableControllerProvider).rows, isEmpty);
    },
  );
  test(
    'bounded access recovery does not loop on repeated server refusal',
    () async {
      final repo = FakeAuthRepository()
        ..loginResult = Success(makeAuthSession(permissions: tablePermissions))
        ..restoreResult = Success(
          makeAuthSession(permissions: tablePermissions),
        );
      final auth = makeController(
        authRepository: repo,
        entitlementRepository: FakeEntitlementRepository()
          ..result = Success(makeEntitlement(features: {'TABLE_MANAGEMENT'})),
      );
      addTearDown(auth.dispose);
      await auth.login(
        const LoginCredentials(email: 'a@b.com', password: 'password'),
      );
      final messages = <String>[],
          recovery = TableAccessRecovery(auth, messages.add);
      const failure = Failure(
        type: FailureType.forbidden,
        code: 'FORBIDDEN',
        message: 'Denied',
      );
      await recovery.handle(failure);
      await recovery.handle(failure);
      await recovery.handle(failure);
      expect(repo.restoreCalls, 1);
      expect(messages.length, 3);
      expect(auth.state.session, isNotNull);
    },
  );
}
