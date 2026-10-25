import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/realtime/realtime_config.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import '../../helpers/auth_fakes.dart';
import '../../helpers/realtime_fakes.dart';
import 'inventory_alert_fakes.dart';
import 'inventory_alert_realtime_test.dart' show alertEvent;

void main() {
  test(
    'default push waits for events without periodic REST alert requests',
    () {
      fakeAsync((clock) {
        final factory = FakeRealtimeFactory();
        final alerts = FakeInventoryAlerts();
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
              const RealtimeConfig(enabled: true),
            ),
            realtimePreferenceStorageProvider.overrideWithValue(
              MemoryRealtimePreferenceStorage(true),
            ),
            realtimeTransportFactoryProvider.overrideWithValue(factory.call),
            inventoryAlertRepositoryProvider.overrideWithValue(alerts),
          ],
        );
        final mount = container.listen(realtimeBootstrapProvider, (_, _) {});
        auth.login(
          const LoginCredentials(
            email: 'push@example.com',
            password: 'password',
          ),
        );
        clock.elapse(Duration.zero);

        expect(
          container.read(realtimeConfigProvider).mode,
          RealtimeTransportMode.websocket,
        );
        expect(container.read(inventoryAlertPollingProvider), isNull);
        expect(factory.transports, hasLength(1));
        factory.last.connected();
        clock.elapse(const Duration(minutes: 1));
        expect(alerts.queries, isEmpty);
        expect(
          container.read(inventoryAlertNoticeControllerProvider).notice,
          isNull,
        );

        factory.last.handlers['inventory-alerts']!(
          alertEvent(
            id: 'new-alert',
            eventId: 'new-open',
            version: 0,
            status: 'OPEN',
          ),
        );
        clock.elapse(const Duration(milliseconds: 399));
        expect(
          container.read(inventoryAlertNoticeControllerProvider).notice,
          isNull,
        );
        clock.elapse(const Duration(milliseconds: 1));
        expect(
          container
              .read(inventoryAlertNoticeControllerProvider)
              .notice
              ?.singleAlertId,
          'new-alert',
        );
        expect(alerts.queries, isEmpty);

        mount.close();
        container.dispose();
        clock.elapse(Duration.zero);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
}
