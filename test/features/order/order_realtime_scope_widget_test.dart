import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/app.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/realtime/realtime_config.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_state.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/inventory_alert_notice_overlay.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_detail_screen.dart';
import '../../helpers/auth_fakes.dart';
import '../../helpers/realtime_fakes.dart';
import '../inventory/inventory_alert_fakes.dart';
import '../inventory/inventory_alert_realtime_test.dart' show alertEvent;
import '../menu/menu_fakes.dart';
import '../qr_order/qr_fakes.dart';
import '../tables/table_fakes.dart';
import 'order_fakes.dart';

const _permissions = {
  ...orderPermissions,
  ...alertPermissions,
  'TABLE_TRANSFER',
};
const _features = {...orderFeatures, ...alertFeatures};
final _notice = find.byKey(const ValueKey('inventory-alert-notice'));

class _Host {
  _Host(this.container, this.events, this.auth, this.factory, this.alerts);
  final ProviderContainer container;
  final SessionEvents events;
  final AuthController auth;
  final FakeRealtimeFactory factory;
  final FakeInventoryAlerts alerts;
}

Future<_Host> _pumpOrderApp(
  WidgetTester tester, {
  RealtimeTransportMode mode = RealtimeTransportMode.websocket,
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final events = SessionEvents();
  final factory = FakeRealtimeFactory();
  final alerts = FakeInventoryAlerts();
  final tables = TableServer()..session = sessionJson(id: sessionId);
  final orders = FakeOrders()
    ..current = OrderDto.detail(
      orderJson(status: 'CONFIRMED', confirmed: true)
        ..['serviceType'] = 'DINE_IN'
        ..['tableSessionId'] = sessionId,
    );
  final auth = makeController(
    sessionEvents: events,
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: _permissions))
      ..restoreResult = Success(makeAuthSession(permissions: _permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: _features)),
  );
  await auth.login(
    const LoginCredentials(email: 'test@example.com', password: 'password'),
  );
  addTearDown(() {
    events.dispose();
    tables.close();
  });
  // Use the production App and router so notice, bootstrap, auth redirect,
  // order scope and table scope providers are all mounted together.
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((_) => auth),
        realtimeConfigProvider.overrideWithValue(
          RealtimeConfig(enabled: false, mode: mode),
        ),
        realtimePreferenceStorageProvider.overrideWithValue(
          MemoryRealtimePreferenceStorage(true),
        ),
        realtimeTransportFactoryProvider.overrideWithValue(factory.call),
        inventoryAlertRepositoryProvider.overrideWithValue(alerts),
        orderRepositoryProvider.overrideWithValue(orders),
        qrRequestRepositoryProvider.overrideWithValue(FakeQrRequests()),
        restaurantTableRepositoryProvider.overrideWithValue(tables.tables),
        tableAreaRepositoryProvider.overrideWithValue(tables.areas),
        tableSessionRepositoryProvider.overrideWithValue(tables.sessions),
        menuItemRepositoryProvider.overrideWithValue(FakeMenuItems()),
        menuGroupRepositoryProvider.overrideWithValue(FakeMenuGroups()),
      ],
      child: const App(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(InventoryAlertNoticeOverlay)),
  );
  container.read(appRouterProvider).go('/app/orders/o1');
  await tester.pumpAndSettle();
  expect(find.byType(OrderDetailScreen), findsOneWidget);
  expect(find.byType(InventoryAlertNoticeOverlay), findsOneWidget);
  if (mode == RealtimeTransportMode.websocket) {
    expect(factory.transports, hasLength(1));
    factory.last.connected();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  } else {
    expect(factory.transports, isEmpty);
    expect(alerts.queries, hasLength(1));
  }
  expect(tester.takeException(), isNull);
  return _Host(container, events, auth, factory, alerts);
}

Future<void> _showNotice(WidgetTester tester, _Host host) async {
  host.factory.last.handlers['inventory-alerts']!(
    alertEvent(eventId: 'new-before-refresh', version: 0, status: 'OPEN'),
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  expect(_notice, findsOneWidget);
  expect(host.alerts.queries, isEmpty);
  expect(host.alerts.detailIds, isEmpty);
}

Future<void> _connectReplacement(WidgetTester tester, _Host host) async {
  host.factory.last.connected();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
  expect(find.byType(OrderDetailScreen), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets(
    'polling access recovery preserves the dine-in draft when grants stay unchanged',
    (tester) async {
      final host = await _pumpOrderApp(
        tester,
        mode: RealtimeTransportMode.polling,
      );
      final transfer = host.container.read(
        orderTableTransferProvider(sessionId),
      );
      final detail = host.container.read(orderDetailProvider('o1'));
      transfer.setReason('Keep this reason during access revalidation');
      final statuses = <AuthStatus>[];
      void observeAuth() => statuses.add(host.auth.state.status);
      host.auth.addListener(observeAuth);
      addTearDown(() => host.auth.removeListener(observeAuth));
      host.alerts.onList = (_) async => const Error(
        Failure(
          type: FailureType.forbidden,
          code: 'FORBIDDEN',
          message: 'No permission to read alerts',
        ),
      );

      final polling = host.container.read(inventoryAlertPollingProvider)!;
      polling.refresh();
      await tester.pumpAndSettle();

      expect(statuses, isNotEmpty);
      expect(
        statuses.every((status) => status == AuthStatus.authenticated),
        isTrue,
      );
      expect(host.auth.state.status, AuthStatus.authenticated);
      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(
        host.container.read(orderTableTransferProvider(sessionId)),
        same(transfer),
      );
      expect(host.container.read(orderDetailProvider('o1')), same(detail));
      expect(transfer.reason, 'Keep this reason during access revalidation');
      expect(transfer.isCurrent, isTrue);
      expect(host.container.read(inventoryAlertPollingProvider), same(polling));
      expect(polling.failure?.type, FailureType.forbidden);
      expect(host.factory.transports, isEmpty);
      expect(_notice, findsNothing);
      final queries = host.alerts.queries.length;
      await tester.pump(const Duration(minutes: 2));
      await tester.pumpAndSettle();
      expect(host.alerts.queries, hasLength(queries));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'token rotation with a visible alert keeps the dine-in transfer controller',
    (tester) async {
      final host = await _pumpOrderApp(tester);
      final transfer = host.container.read(
        orderTableTransferProvider(sessionId),
      );
      transfer.setReason('Keep this transfer reason');
      await _showNotice(tester, host);
      final oldTransport = host.factory.last;

      host.events.refreshed(
        makeAuthSession(
          permissions: _permissions,
          tokens: makeTokens(accessToken: 'rotated-access'),
        ),
      );
      await tester.pumpAndSettle();

      expect(oldTransport.closed, isTrue);
      expect(host.factory.last.token, 'rotated-access');
      expect(
        host.container.read(orderTableTransferProvider(sessionId)),
        same(transfer),
      );
      expect(transfer.reason, 'Keep this transfer reason');
      expect(transfer.isCurrent, isTrue);
      expect(_notice, findsNothing);
      await _connectReplacement(tester, host);
    },
  );

  testWidgets(
    'permission changes with a visible alert replace the dine-in transfer controller',
    (tester) async {
      final host = await _pumpOrderApp(tester);
      final transfer = host.container.read(
        orderTableTransferProvider(sessionId),
      );
      transfer.setReason('Old permission scope');
      await _showNotice(tester, host);
      final oldTransport = host.factory.last;

      host.events.refreshed(
        makeAuthSession(
          permissions: {..._permissions, 'ORDER_COMPLETE'},
          tokens: makeTokens(accessToken: 'changed-permissions'),
        ),
      );
      await tester.pumpAndSettle();

      final replacement = host.container.read(
        orderTableTransferProvider(sessionId),
      );
      expect(replacement, isNot(same(transfer)));
      expect(transfer.isCurrent, isFalse);
      expect(replacement.reason, isEmpty);
      expect(replacement.currentSession?.id, sessionId);
      expect(oldTransport.closed, isTrue);
      expect(_notice, findsNothing);
      await _connectReplacement(tester, host);
    },
  );

  testWidgets(
    'tenant switches with a visible alert replace the dine-in transfer controller',
    (tester) async {
      final host = await _pumpOrderApp(tester);
      final transfer = host.container.read(
        orderTableTransferProvider(sessionId),
      );
      transfer.setReason('Old tenant reason');
      await _showNotice(tester, host);
      final oldTransport = host.factory.last;

      host.events.refreshed(
        makeAuthSession(
          restaurantId: 'restaurant-2',
          permissions: _permissions,
          tokens: makeTokens(accessToken: 'second-tenant-access'),
        ),
      );
      await tester.pumpAndSettle();

      final replacement = host.container.read(
        orderTableTransferProvider(sessionId),
      );
      expect(
        host.auth.state.session?.authenticatedUser.restaurantId,
        'restaurant-2',
      );
      expect(replacement, isNot(same(transfer)));
      expect(transfer.isCurrent, isFalse);
      expect(replacement.reason, isEmpty);
      expect(replacement.currentSession?.id, sessionId);
      expect(oldTransport.closed, isTrue);
      expect(_notice, findsNothing);
      await _connectReplacement(tester, host);
    },
  );

  testWidgets('old socket callbacks cannot publish a toast after logout', (
    tester,
  ) async {
    final host = await _pumpOrderApp(tester);
    await _showNotice(tester, host);
    final oldTransport = host.factory.last;
    final oldMessage = oldTransport.handlers['inventory-alerts']!;
    final transportCount = host.factory.transports.length;

    await host.auth.logout();
    await tester.pumpAndSettle();
    expect(oldTransport.closed, isTrue);
    expect(_notice, findsNothing);
    expect(find.byType(OrderDetailScreen), findsNothing);

    oldMessage(
      alertEvent(
        eventId: 'late-old-socket',
        id: 'a2',
        version: 0,
        status: 'OPEN',
      ),
    );
    oldTransport.connected();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(_notice, findsNothing);
    expect(host.factory.transports, hasLength(transportCount));
    expect(host.alerts.queries, isEmpty);
    expect(host.alerts.detailIds, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
