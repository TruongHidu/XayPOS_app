import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/app.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/realtime/realtime_config.dart';
import 'package:pos_saas_app/core/realtime/realtime_transport.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_alert_detail_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/stock_audit_detail_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/inventory_alert_list.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/inventory_alert_notice_overlay.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/stock_audit_exit_guard.dart';
import '../../helpers/auth_fakes.dart';
import '../../helpers/realtime_fakes.dart';
import 'inventory_alert_fakes.dart';
import 'inventory_alert_realtime_test.dart' show alertEvent;
import 'inventory_fakes.dart';
import 'stock_audit_fakes.dart';

final _allPermissions = {...alertPermissions, ...stockAuditPermissions};
final _allFeatures = {...alertFeatures, ...stockAuditFeatures};
final _notice = find.byKey(const ValueKey('inventory-alert-notice'));
final _view = find.byKey(const ValueKey('inventory-alert-notice-view'));
final _close = find.byKey(const ValueKey('inventory-alert-notice-close'));

Future<_Host> _pump(
  WidgetTester tester, {
  double width = 1200,
  double scale = 1,
  bool keyboard = false,
  bool noticeFirst = false,
  String location = '/workspace',
  Set<String>? permissions,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  if (keyboard) tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.resetViewInsets);
  final events = SessionEvents(), factory = FakeRealtimeFactory();
  final repo = FakeInventoryAlerts(), taps = ValueNotifier<int>(0);
  final auth = makeController(
    sessionEvents: events,
    authRepository: FakeAuthRepository()
      ..loginResult = Success(
        makeAuthSession(permissions: permissions ?? _allPermissions),
      ),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: _allFeatures)),
  );
  await auth.login(
    const LoginCredentials(email: 'test@example.com', password: 'password'),
  );
  final routerProvider = Provider((ref) {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/workspace',
          builder: (_, _) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('workspace-action'),
                onPressed: () => taps.value++,
                child: const Text('Tiếp tục thao tác'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/app/inventory/alerts',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: InventoryAlertList(),
            ),
          ),
        ),
        GoRoute(
          path: '/app/inventory/alerts/:id',
          builder: (_, state) => Scaffold(
            body: InventoryAlertDetailScreen(id: state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/app/inventory/audits/:id',
          onExit: (context, state) =>
              confirmStockAuditExit(context, ref, state.pathParameters['id']),
          builder: (_, state) => Scaffold(
            body: StockAuditDetailScreen(id: state.pathParameters['id']!),
          ),
        ),
      ],
    );
    ref.onDispose(router.dispose);
    return router;
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((_) => auth),
        appRouterProvider.overrideWith((ref) => ref.watch(routerProvider)),
        realtimeConfigProvider.overrideWithValue(
          const RealtimeConfig(
            enabled: false,
            mode: RealtimeTransportMode.websocket,
          ),
        ),
        realtimePreferenceStorageProvider.overrideWithValue(
          MemoryRealtimePreferenceStorage(true),
        ),
        realtimeTransportFactoryProvider.overrideWithValue(factory.call),
        inventoryAlertRepositoryProvider.overrideWithValue(repo),
        stockAuditRepositoryProvider.overrideWithValue(FakeStockAudits()),
        warehouseRepositoryProvider.overrideWithValue(FakeWarehouses()),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          if (noticeFirst) {
            ref.watch(inventoryAlertNoticeAvailableProvider);
            ref.watch(inventoryAlertNoticeControllerProvider);
          }
          return const App();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(InventoryAlertNoticeOverlay)),
  );
  final router = container.read(appRouterProvider);
  if (factory.transports.isNotEmpty) {
    factory.last.connected();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }
  addTearDown(taps.dispose);
  addTearDown(events.dispose);
  return _Host(container, router, factory, repo, auth, events, taps);
}

Future<void> _open(
  WidgetTester tester,
  _Host host, {
  String id = 'a1',
  String event = 'e1',
}) async {
  host.factory.last.handlers['inventory-alerts']!(
    alertEvent(id: id, eventId: event, version: 0, status: 'OPEN'),
  );
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  for (final input in ['settings', 'coordinator', 'bootstrap', 'notice']) {
    testWidgets(
      'rebuilding $input with an active notice has no provider cycle',
      (tester) async {
        final host = await _pump(tester, noticeFirst: true);
        await _open(tester, host);
        host.container.invalidate(inventoryAlertNoticeAvailableProvider);
        switch (input) {
          case 'settings':
            host.container.invalidate(realtimeSettingsProvider);
          case 'coordinator':
            host.container.invalidate(
              inventoryAlertRealtimeCoordinatorProvider,
            );
          case 'bootstrap':
            host.container.invalidate(realtimeBootstrapProvider);
          case 'notice':
            host.container.invalidate(inventoryAlertNoticeControllerProvider);
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final change in ['token', 'permission', 'tenant']) {
    testWidgets(
      'notice-first subscription survives $change during provider refresh',
      (tester) async {
        final host = await _pump(tester, noticeFirst: true);
        await _open(tester, host);
        final permissions = change == 'permission'
            ? {'MENU_VIEW'}
            : _allPermissions;
        host.container.invalidate(inventoryAlertNoticeAvailableProvider);
        host.events.refreshed(
          makeAuthSession(
            restaurantId: change == 'tenant' ? 'other' : 'restaurant-1',
            permissions: permissions,
            tokens: makeTokens(accessToken: 'new-access'),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'one OPEN appears at bottom right without a metadata GET or blocking underlying actions',
    (tester) async {
      final host = await _pump(tester);
      await _open(tester, host);
      expect(_notice, findsOneWidget);
      expect(find.text('Có cảnh báo tồn thấp mới.'), findsOneWidget);
      expect(host.repo.queries, isEmpty);
      expect(host.repo.detailIds, isEmpty);
      final rect = tester.getRect(_notice);
      expect(rect.right, closeTo(1184, 1));
      expect(rect.width, lessThanOrEqualTo(420));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(_close));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await tester.tap(find.byKey(const ValueKey('workspace-action')));
      expect(host.taps.value, 1);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(_notice, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'single action opens matching detail and close dismisses immediately',
    (tester) async {
      final host = await _pump(tester);
      await _open(tester, host);
      await tester.tap(_close);
      await tester.pumpAndSettle();
      expect(_notice, findsNothing);
      await _open(tester, host, id: 'a2', event: 'e2');
      host.repo.rows = [inventoryAlert(id: 'a2')];
      await tester.tap(_view);
      await tester.pumpAndSettle();
      expect(
        host.router.routerDelegate.currentConfiguration.uri.path,
        '/app/inventory/alerts/a2',
      );
      expect(host.repo.detailIds, ['a2']);
      expect(host.repo.acknowledgements, isEmpty);
      expect(_notice, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('burst produces one count notice and View opens alerts list', (
    tester,
  ) async {
    final host = await _pump(tester);
    for (final id in ['a1', 'a2', 'a3']) {
      host.factory.last.handlers['inventory-alerts']!(
        alertEvent(id: id, eventId: 'e-$id', version: 0, status: 'OPEN'),
      );
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(_notice, findsOneWidget);
    expect(find.text('Có 3 cảnh báo tồn thấp mới.'), findsOneWidget);
    expect(host.repo.queries, isEmpty);
    await tester.tap(_view);
    await tester.pumpAndSettle();
    expect(
      host.router.routerDelegate.currentConfiguration.uri.toString(),
      '/app/inventory/alerts',
    );
    expect(host.repo.queries, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ACK, RESOLVED and reconnect resync produce no new notification',
    (tester) async {
      final host = await _pump(tester);
      for (final status in ['ACKNOWLEDGED', 'RESOLVED']) {
        host.factory.last.handlers['inventory-alerts']!(
          alertEvent(id: 'a-$status', eventId: status, status: status),
        );
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(_notice, findsNothing);
      host.factory.last.fail(
        const RealtimeProblem(RealtimeFailureKind.network),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      host.factory.last.connected();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(_notice, findsNothing);
      expect(host.repo.queries, isEmpty);
      expect(host.repo.detailIds, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final end in ['off', 'background', 'logout', 'tenant', 'permission']) {
    testWidgets('$end clears visible notice and rejects old socket callbacks', (
      tester,
    ) async {
      final host = await _pump(tester);
      await _open(tester, host);
      final oldMessage = host.factory.last.handlers['inventory-alerts']!;
      switch (end) {
        case 'off':
          await host.container.read(realtimeSettingsProvider).setEnabled(false);
        case 'background':
          host.container.read(realtimeForegroundProvider.notifier).state =
              false;
        case 'logout':
          await host.auth.logout();
        case 'tenant':
          host.events.refreshed(
            makeAuthSession(
              restaurantId: 'other',
              permissions: _allPermissions,
            ),
          );
        case 'permission':
          host.events.refreshed(makeAuthSession(permissions: {'MENU_VIEW'}));
      }
      await tester.pumpAndSettle();
      expect(_notice, findsNothing);
      oldMessage(
        alertEvent(id: 'late', eventId: 'late', version: 0, status: 'OPEN'),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(_notice, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'View keeps dirty audit protected and repeated action cannot stack exit dialogs',
    (tester) async {
      final host = await _pump(tester, location: '/app/inventory/audits/a1');
      final audit = host.container.read(stockAuditDetailProvider('a1'));
      audit.edit(audit.rows.first, rawQuantity: '9');
      await tester.pumpAndSettle();
      await _open(tester, host);
      final action = tester.widget<TextButton>(_view).onPressed!;
      action();
      action();
      await tester.pumpAndSettle();
      expect(find.text('Còn bản nhập chưa lưu'), findsOneWidget);
      expect(_notice, findsNothing);
      await tester.tap(find.text('Ở lại'));
      await tester.pumpAndSettle();
      expect(
        host.router.routerDelegate.currentConfiguration.uri.path,
        '/app/inventory/audits/a1',
      );
      expect(audit.draft('ai1')!.rawQuantity, '9');
      expect(host.repo.detailIds, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 800.0]) {
    testWidgets('notice fits $width with large text and keyboard', (
      tester,
    ) async {
      final host = await _pump(tester, width: width, scale: 2, keyboard: true);
      await _open(tester, host, id: 'a1');
      expect(_notice, findsOneWidget);
      final rect = tester.getRect(_notice);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(700));
      await tester.ensureVisible(_close);
      await tester.tap(_close);
      await tester.pumpAndSettle();
      expect(_notice, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

class _Host {
  _Host(
    this.container,
    this.router,
    this.factory,
    this.repo,
    this.auth,
    this.events,
    this.taps,
  );
  final ProviderContainer container;
  final GoRouter router;
  final FakeRealtimeFactory factory;
  final FakeInventoryAlerts repo;
  final AuthController auth;
  final SessionEvents events;
  final ValueNotifier<int> taps;
}
