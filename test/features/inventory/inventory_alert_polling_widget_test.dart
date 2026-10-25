import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/app.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/realtime/realtime_config.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/inventory/data/dto/inventory_alert_dto.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_alert.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_events.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_alert_detail_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/inventory_alert_notice_overlay.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/inventory_alert_sync_status.dart';
import '../../helpers/auth_fakes.dart';
import '../../helpers/realtime_fakes.dart';
import 'inventory_alert_fakes.dart';
import 'inventory_fakes.dart';

final _notice = find.byKey(const ValueKey('inventory-alert-notice'));
final _view = find.byKey(const ValueKey('inventory-alert-notice-view'));

InventoryAlert _row(
  String id,
  int minute, {
  String status = 'OPEN',
  int version = 0,
}) {
  final time = DateTime.utc(2026, 10, 24, 8, minute);
  final data = inventoryAlertJson(id: id, status: status, version: version)
    ..['triggeredAt'] = time.toIso8601String()
    ..['createdAt'] = time.toIso8601String()
    ..['updatedAt'] = time.add(const Duration(minutes: 1)).toIso8601String();
  if (status == 'ACKNOWLEDGED') {
    data['acknowledgedAt'] = time
        .add(const Duration(minutes: 1))
        .toIso8601String();
  }
  if (status == 'RESOLVED') {
    data['resolvedAt'] = time.add(const Duration(minutes: 1)).toIso8601String();
  }
  return InventoryAlertDto.parse(data);
}

class _Host {
  _Host(this.container, this.router, this.repository, this.auth, this.factory);
  final ProviderContainer container;
  final GoRouter router;
  final FakeInventoryAlerts repository;
  final AuthController auth;
  final FakeRealtimeFactory factory;
}

Future<_Host> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final events = SessionEvents();
  final repository = FakeInventoryAlerts()..rows = [_row('a1', 0)];
  final factory = FakeRealtimeFactory();
  final auth = makeController(
    sessionEvents: events,
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: alertPermissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: alertFeatures)),
  );
  await auth.login(
    const LoginCredentials(email: 'test@example.com', password: 'password'),
  );
  final routerProvider = Provider((ref) {
    final router = GoRouter(
      initialLocation: '/workspace',
      routes: [
        GoRoute(
          path: '/workspace',
          builder: (_, _) => const Scaffold(
            body: Center(
              child: SizedBox(width: 600, child: InventoryAlertSyncStatus()),
            ),
          ),
        ),
        GoRoute(
          path: '/app/inventory',
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('Danh sách cảnh báo'))),
        ),
        GoRoute(
          path: '/app/inventory/alerts/:id',
          builder: (_, state) => Scaffold(
            body: InventoryAlertDetailScreen(id: state.pathParameters['id']!),
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
            mode: RealtimeTransportMode.polling,
          ),
        ),
        realtimePreferenceStorageProvider.overrideWithValue(
          MemoryRealtimePreferenceStorage(true),
        ),
        realtimeTransportFactoryProvider.overrideWithValue(factory.call),
        inventoryAlertRepositoryProvider.overrideWithValue(repository),
      ],
      child: const App(),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(InventoryAlertNoticeOverlay)),
  );
  addTearDown(events.dispose);
  return _Host(
    container,
    container.read(appRouterProvider),
    repository,
    auth,
    factory,
  );
}

Future<void> _advance(WidgetTester tester, Duration duration) async {
  await tester.pump(duration);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'REST baseline is silent and a new episode opens the matching detail without WebSocket',
    (tester) async {
      final host = await _pump(tester);
      expect(host.repository.queries, hasLength(1));
      expect(host.repository.queries.single.status, isNull);
      expect(host.repository.queries.single.size, 100);
      expect(host.factory.transports, isEmpty);
      expect(_notice, findsNothing);
      expect(find.text('Đang kiểm tra cảnh báo mỗi 20 giây.'), findsOneWidget);

      host.repository.rows = [_row('a2', 1), _row('a1', 0)];
      await _advance(tester, const Duration(seconds: 20));
      expect(_notice, findsOneWidget);
      expect(find.text('Có cảnh báo tồn thấp mới.'), findsOneWidget);
      expect(host.repository.detailIds, isEmpty);
      await tester.tap(_view);
      await tester.pumpAndSettle();
      expect(
        host.router.routerDelegate.currentConfiguration.uri.path,
        '/app/inventory/alerts/a2',
      );
      expect(host.repository.detailIds, ['a2']);
      expect(host.repository.acknowledgements, isEmpty);
      expect(_notice, findsNothing);
      expect(host.factory.transports, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'later polls do not notify again for known episodes, ACK or RESOLVED rows',
    (tester) async {
      final host = await _pump(tester);
      host.repository.rows = [_row('a2', 1), _row('a1', 0)];
      await _advance(tester, const Duration(seconds: 20));
      expect(_notice, findsOneWidget);
      await _advance(tester, const Duration(seconds: 5));
      expect(_notice, findsNothing);
      host.repository.rows = [
        _row('closed', 2, status: 'RESOLVED', version: 1),
        _row('a2', 1, status: 'ACKNOWLEDGED', version: 1),
        _row('a1', 0, version: 1),
      ];
      await _advance(tester, const Duration(seconds: 20));
      expect(_notice, findsNothing);
      expect(host.factory.transports, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'turning off automatic updates closes the notice and stops REST polling',
    (tester) async {
      final host = await _pump(tester);
      host.repository.rows = [_row('a2', 1), _row('a1', 0)];
      await _advance(tester, const Duration(seconds: 20));
      expect(_notice, findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('inventory-alert-realtime-toggle')),
      );
      await tester.pumpAndSettle();
      expect(_notice, findsNothing);
      final requests = host.repository.queries.length;
      await _advance(tester, const Duration(minutes: 1));
      expect(host.repository.queries, hasLength(requests));
      expect(
        find.text('Đang tắt. Bạn có thể tải lại cảnh báo khi cần.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'background rejects a late response and resume establishes a silent baseline',
    (tester) async {
      final host = await _pump(tester);
      final pending = Completer<Result<InventoryPage<InventoryAlert>>>();
      host.repository.onList = (_) => pending.future;
      await _advance(tester, const Duration(seconds: 20));
      host.container.read(realtimeForegroundProvider.notifier).state = false;
      await tester.pumpAndSettle();
      pending.complete(Success(inventoryPage([_row('a2', 1), _row('a1', 0)])));
      await tester.pumpAndSettle();
      expect(_notice, findsNothing);
      final requests = host.repository.queries.length;
      await _advance(tester, const Duration(minutes: 1));
      expect(host.repository.queries, hasLength(requests));

      host.repository.onList = null;
      host.repository.rows = [_row('a2', 1), _row('a1', 0)];
      host.container.read(realtimeForegroundProvider.notifier).state = true;
      await tester.pumpAndSettle();
      expect(_notice, findsNothing);
      host.repository.rows = [_row('a3', 2), _row('a2', 1), _row('a1', 0)];
      await _advance(tester, const Duration(seconds: 20));
      expect(_notice, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'logout stops polling and a pending response cannot publish an old-scope notice',
    (tester) async {
      final host = await _pump(tester);
      final pending = Completer<Result<InventoryPage<InventoryAlert>>>();
      host.repository.onList = (_) => pending.future;
      await _advance(tester, const Duration(seconds: 20));
      await host.auth.logout();
      await tester.pumpAndSettle();
      pending.complete(Success(inventoryPage([_row('a2', 1), _row('a1', 0)])));
      await tester.pumpAndSettle();
      expect(_notice, findsNothing);
      final requests = host.repository.queries.length;
      await _advance(tester, const Duration(minutes: 1));
      expect(host.repository.queries, hasLength(requests));
      expect(host.factory.transports, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'local balance changes refresh alerts after debounce without waiting twenty seconds',
    (tester) async {
      final host = await _pump(tester);
      host.repository.rows = [_row('a2', 1), _row('a1', 0)];
      host.container
          .read(inventoryEventsProvider)
          .emit(
            const InventoryChange(
              InventoryChangeKind.balance,
              'w1',
              ingredientId: 'i1',
            ),
          );
      await tester.pump(const Duration(milliseconds: 399));
      expect(host.repository.queries, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(host.repository.queries, hasLength(2));
      expect(_notice, findsOneWidget);
      expect(host.factory.transports, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
