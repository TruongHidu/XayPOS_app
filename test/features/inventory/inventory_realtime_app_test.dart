import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/realtime/realtime_config.dart';
import 'package:pos_saas_app/core/realtime/realtime_transport.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import '../../helpers/auth_fakes.dart';
import '../../helpers/realtime_fakes.dart';
import 'inventory_alert_fakes.dart';
import 'inventory_alert_realtime_test.dart' show alertEvent;

const _credentials = LoginCredentials(
  email: 'test@example.com',
  password: 'password',
);
// Derived binding changes commit on Riverpod's zero-duration scheduler timer.
// Elapse zero time to flush that work as well as transport microtasks.
void main() {
  test(
    'runtime switch enables an OFF-default build and disabling cancels retry and debounce',
    () {
      fakeAsync((clock) {
        final factory = FakeRealtimeFactory(),
            preferences = MemoryRealtimePreferenceStorage();
        final auth = makeController(
          authRepository: FakeAuthRepository()
            ..loginResult = Success(
              makeAuthSession(permissions: alertPermissions),
            ),
          entitlementRepository: FakeEntitlementRepository()
            ..result = Success(makeEntitlement(features: alertFeatures)),
        );
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith((_) => auth),
            realtimeConfigProvider.overrideWithValue(
              const RealtimeConfig(
                enabled: false,
                mode: RealtimeTransportMode.websocket,
              ),
            ),
            realtimePreferenceStorageProvider.overrideWithValue(preferences),
            realtimeTransportFactoryProvider.overrideWithValue(factory.call),
          ],
        );
        final mount = container.listen(realtimeBootstrapProvider, (_, _) {});
        auth.login(_credentials);
        clock.elapse(Duration.zero);
        expect(factory.transports, isEmpty);
        final settings = container.read(realtimeSettingsProvider);
        settings.setEnabled(true);
        clock.elapse(Duration.zero);
        expect(factory.transports, hasLength(1));
        factory.last.connected();
        clock.elapse(const Duration(milliseconds: 400));
        final events = container.read(inventoryEventsProvider),
            revision = events.revision;
        final oldMessage = factory.last.handlers['inventory-alerts']!;
        oldMessage(alertEvent());
        factory.last.fail(const RealtimeProblem(RealtimeFailureKind.network));
        clock.elapse(Duration.zero);
        settings.setEnabled(false);
        clock.elapse(Duration.zero);
        oldMessage(alertEvent(eventId: 'late', version: 2));
        clock.elapse(const Duration(minutes: 2));
        expect(factory.transports, hasLength(1));
        expect(factory.last.closed, true);
        expect(events.revision, revision);
        expect(preferences.value, false);
        expect(clock.pendingTimers, isEmpty);
        // REST fallback must still be signalled after a foreground resume while OFF.
        container.read(realtimeForegroundProvider.notifier).state = false;
        clock.elapse(Duration.zero);
        container.read(realtimeForegroundProvider.notifier).state = true;
        clock.elapse(Duration.zero);
        clock.elapse(const Duration(milliseconds: 400));
        expect(events.revision, revision + 1);
        expect(factory.transports, hasLength(1));
        mount.close();
        container.dispose();
        clock.elapse(Duration.zero);
      });
    },
  );

  for (final input in [
    (
      role: UserRole.waiter,
      permissions: {'INVENTORY_VIEW'},
      features: alertFeatures,
      allowed: true,
    ),
    (
      role: UserRole.owner,
      permissions: <String>{},
      features: alertFeatures,
      allowed: false,
    ),
    (
      role: UserRole.kitchen,
      permissions: {'INVENTORY_VIEW'},
      features: {'INVENTORY_MANAGEMENT'},
      allowed: false,
    ),
    (
      role: UserRole.superAdmin,
      permissions: alertPermissions,
      features: alertFeatures,
      allowed: false,
    ),
  ]) {
    test(
      'channel uses effective policy for ${input.role} grants=${input.permissions}',
      () {
        fakeAsync((clock) {
          final factory = FakeRealtimeFactory();
          final auth = makeController(
            authRepository: FakeAuthRepository()
              ..loginResult = Success(
                makeAuthSession(
                  role: input.role,
                  permissions: input.permissions,
                ),
              ),
            entitlementRepository: FakeEntitlementRepository()
              ..result = Success(makeEntitlement(features: input.features)),
          );
          final container = ProviderContainer(
            overrides: [
              authControllerProvider.overrideWith((_) => auth),
              realtimePreferenceStorageProvider.overrideWithValue(
                MemoryRealtimePreferenceStorage(),
              ),
              realtimeConfigProvider.overrideWithValue(
                const RealtimeConfig(
                  enabled: true,
                  mode: RealtimeTransportMode.websocket,
                ),
              ),
              realtimeTransportFactoryProvider.overrideWithValue(factory.call),
            ],
          );
          final mount = container.listen(realtimeBootstrapProvider, (_, _) {});
          clock.elapse(Duration.zero);
          expect(factory.transports, isEmpty);
          auth.login(_credentials);
          clock.elapse(Duration.zero);
          expect(factory.transports.length, input.allowed ? 1 : 0);
          if (input.allowed) {
            factory.last.connected();
            expect(factory.last.destinations, ['/user/queue/inventory-alerts']);
            expect(
              auth.state.session!.permissions.contains(
                'INVENTORY_ALERT_ACKNOWLEDGE',
              ),
              false,
            );
          }
          mount.close();
          container.dispose();
          clock.elapse(Duration.zero);
          expect(clock.pendingTimers, isEmpty);
        });
      },
    );
  }

  test(
    'login, token refresh, background, foreground, permission revocation and logout are scoped',
    () {
      fakeAsync((clock) {
        final factory = FakeRealtimeFactory(), events = SessionEvents();
        final auth = makeController(
          sessionEvents: events,
          authRepository: FakeAuthRepository()
            ..loginResult = Success(
              makeAuthSession(permissions: alertPermissions),
            ),
          entitlementRepository: FakeEntitlementRepository()
            ..result = Success(makeEntitlement(features: alertFeatures)),
        );
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith((_) => auth),
            realtimePreferenceStorageProvider.overrideWithValue(
              MemoryRealtimePreferenceStorage(),
            ),
            realtimeConfigProvider.overrideWithValue(
              const RealtimeConfig(
                enabled: true,
                mode: RealtimeTransportMode.websocket,
              ),
            ),
            realtimeTransportFactoryProvider.overrideWithValue(factory.call),
          ],
        );
        final mount = container.listen(realtimeBootstrapProvider, (_, _) {});
        clock.elapse(Duration.zero);
        auth.login(_credentials);
        clock.elapse(Duration.zero);
        factory.last.connected();
        final old = factory.last;
        events.refreshed(
          makeAuthSession(
            permissions: alertPermissions,
            tokens: makeTokens(accessToken: 'new-access'),
          ),
        );
        clock.elapse(Duration.zero);
        expect(old.closed, true);
        expect(factory.last.token, 'new-access');
        factory.last.connected();
        container.read(realtimeForegroundProvider.notifier).state = false;
        clock.elapse(Duration.zero);
        expect(factory.last.closed, true);
        final before = factory.transports.length;
        clock.elapse(const Duration(minutes: 5));
        expect(factory.transports.length, before);
        container.read(realtimeForegroundProvider.notifier).state = true;
        clock.elapse(Duration.zero);
        factory.last.connected();
        final coordinator = container.read(
          inventoryAlertRealtimeCoordinatorProvider,
        )!;
        coordinator.receive('{malformed}');
        events.refreshed(
          makeAuthSession(
            permissions: {'MENU_VIEW'},
            tokens: makeTokens(accessToken: 'revoked'),
          ),
        );
        clock.elapse(Duration.zero);
        expect(factory.last.closed, true);
        expect(
          container.read(inventoryAlertRealtimeCoordinatorProvider),
          isNull,
        );
        auth.logout();
        clock.elapse(Duration.zero);
        clock.elapse(const Duration(minutes: 5));
        expect(factory.transports.length, before + 1);
        mount.close();
        container.dispose();
        events.dispose();
        clock.elapse(Duration.zero);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test(
    'same denied grants remain blocked after revalidation without token refresh',
    () {
      fakeAsync((clock) {
        final factory = FakeRealtimeFactory();
        final repository = FakeAuthRepository()
          ..loginResult = Success(
            makeAuthSession(permissions: alertPermissions),
          )
          ..restoreResult = Success(
            makeAuthSession(permissions: alertPermissions),
          );
        final auth = makeController(
          authRepository: repository,
          entitlementRepository: FakeEntitlementRepository()
            ..result = Success(makeEntitlement(features: alertFeatures)),
        );
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith((_) => auth),
            realtimePreferenceStorageProvider.overrideWithValue(
              MemoryRealtimePreferenceStorage(),
            ),
            realtimeConfigProvider.overrideWithValue(
              const RealtimeConfig(
                enabled: true,
                mode: RealtimeTransportMode.websocket,
              ),
            ),
            realtimeTransportFactoryProvider.overrideWithValue(factory.call),
          ],
        );
        final mount = container.listen(realtimeBootstrapProvider, (_, _) {});
        auth.login(_credentials);
        clock.elapse(Duration.zero);
        factory.last.connected();
        factory.last.fail(
          const RealtimeProblem(RealtimeFailureKind.stomp, code: 'FORBIDDEN'),
        );
        clock.elapse(Duration.zero);
        clock.elapse(const Duration(minutes: 5));
        expect(repository.restoreCalls, 1);
        expect(repository.refreshCalls, 0);
        expect(factory.transports, hasLength(1));
        expect(auth.state.session, isNotNull);
        mount.close();
        container.dispose();
        clock.elapse(Duration.zero);
      });
    },
  );
}
