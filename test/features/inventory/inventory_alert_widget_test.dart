import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_alert.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_alert_detail_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/inventory_alert_list.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/inventory_alert_widgets.dart';
import '../../helpers/auth_fakes.dart';
import 'inventory_alert_fakes.dart';
import 'inventory_fakes.dart';

Future<GoRouter> _pump(
  WidgetTester tester,
  FakeInventoryAlerts alerts, {
  String location = '/app/inventory?tab=alerts',
  Set<String> permissions = alertPermissions,
  Set<String> features = alertFeatures,
  double width = 1200,
  double scale = 1,
  AuthController? auth,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  auth ??= makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: features)),
  );
  if (auth.state.session == null) {
    await auth.login(
      const LoginCredentials(email: 'alerts@example.com', password: 'password'),
    );
  }
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/app/inventory',
        builder: (_, _) => const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: InventoryAlertList(),
          ),
        ),
      ),
      GoRoute(
        path: '/app/inventory/alerts/:id',
        builder: (_, s) => Scaffold(
          body: InventoryAlertDetailScreen(id: s.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/app/inventory/transactions',
        builder: (_, s) => Scaffold(body: Text('Ledger ${s.uri.query}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((_) => auth!),
        inventoryAlertRepositoryProvider.overrideWithValue(alerts),
        warehouseRepositoryProvider.overrideWithValue(FakeWarehouses()),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'list is lazy full DTO and opens snapshot/current detail; ACK is server state',
    (tester) async {
      final repo = FakeInventoryAlerts();
      await _pump(tester, repo);
      expect(repo.queries, hasLength(1));
      expect(repo.detailIds, isEmpty);
      await tester.ensureVisible(find.text('Chi tiết').first);
      await tester.tap(find.text('Chi tiết').first);
      await tester.pumpAndSettle();
      expect(repo.detailIds, ['a1']);
      expect(find.text('Tại thời điểm phát cảnh báo'), findsOneWidget);
      expect(find.text('Số dư hiện tại'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('acknowledge-inventory-alert')),
      );
      await tester.tap(
        find.byKey(const ValueKey('acknowledge-inventory-alert')),
      );
      await tester.pumpAndSettle();
      expect(repo.acknowledgements, hasLength(1));
      expect(find.text('Đã xem'), findsOneWidget);
      expect(find.textContaining('user-ack'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('acknowledge-inventory-alert')),
        findsNothing,
      );
    },
  );
  testWidgets(
    'reader sees history and null comparison without ACK; ledger query carries only source IDs',
    (tester) async {
      final repo = FakeInventoryAlerts()
        ..rows = [
          inventoryAlert(
            status: 'RESOLVED',
            reason: 'INGREDIENT_UNIT_CHANGED',
            comparable: false,
          ),
        ];
      final router = await _pump(
        tester,
        repo,
        permissions: {'INVENTORY_VIEW'},
        location: '/app/inventory/alerts/a1',
      );
      expect(find.text('Không còn dữ liệu so sánh'), findsOneWidget);
      expect(
        find.textContaining('Đơn vị nguyên liệu đã thay đổi'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('acknowledge-inventory-alert')),
        findsNothing,
      );
      await tester.ensureVisible(find.text('Lịch sử giao dịch'));
      await tester.tap(find.text('Lịch sử giao dịch'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.queryParameters, {
        'warehouseId': 'w1',
        'ingredientId': 'i1',
      });
    },
  );
  testWidgets(
    'missing feature blocks direct detail and list without requesting alerts',
    (tester) async {
      final repo = FakeInventoryAlerts();
      final router = await _pump(
        tester,
        repo,
        features: {'INVENTORY_MANAGEMENT'},
        location: '/app/inventory/alerts/a1',
      );
      expect(repo.detailIds, isEmpty);
      router.go('/app/inventory?tab=alerts');
      await tester.pumpAndSettle();
      expect(repo.queries, isEmpty);
      expect(find.textContaining('Bạn cần quyền xem kho'), findsOneWidget);
    },
  );
  testWidgets(
    'late read is discarded after closing screen and feature revocation removes controls',
    (tester) async {
      final entitlements = FakeEntitlementRepository()
        ..result = Success(makeEntitlement(features: alertFeatures));
      final auth = makeController(
        authRepository: FakeAuthRepository()
          ..loginResult = Success(
            makeAuthSession(permissions: alertPermissions),
          ),
        entitlementRepository: entitlements,
      );
      final pending = Completer<Result<InventoryAlert>>(),
          repo = FakeInventoryAlerts();
      final router = await _pump(
        tester,
        repo,
        auth: auth,
        location: '/app/inventory/alerts/a1',
      );
      expect(
        find.byKey(const ValueKey('acknowledge-inventory-alert')),
        findsOneWidget,
      );
      entitlements.result = Success(
        makeEntitlement(features: {'INVENTORY_MANAGEMENT'}),
      );
      await auth.login(
        const LoginCredentials(
          email: 'alerts@example.com',
          password: 'password',
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('acknowledge-inventory-alert')),
        findsNothing,
      );
      expect(repo.acknowledgements, isEmpty);
      entitlements.result = Success(makeEntitlement(features: alertFeatures));
      await auth.login(
        const LoginCredentials(
          email: 'alerts@example.com',
          password: 'password',
        ),
      );
      await tester.pumpAndSettle();
      repo.onDetail = (_) => pending.future;
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold).first),
      );
      final read = container.read(inventoryAlertDetailProvider('a1')).load();
      await tester.pump();
      router.go('/app/inventory?tab=alerts');
      await tester.pumpAndSettle();
      pending.complete(Success(inventoryAlert()));
      await read;
      await tester.pumpAndSettle();
      expect(find.byType(InventoryAlertDetailScreen), findsNothing);
      expect(tester.takeException(), null);
    },
  );
  for (final width in [320.0, 600.0, 800.0, 1200.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('alert list/detail long names responsive $width at $scale', (
        tester,
      ) async {
        final repo = FakeInventoryAlerts()
          ..rows = [
            inventoryAlert(
              name:
                  'Nguyên liệu có tên rất dài để đối chiếu đúng dữ liệu lịch sử ' *
                  4,
            ),
          ];
        final router = await _pump(tester, repo, width: width, scale: scale);
        expect(tester.takeException(), null);
        router.go('/app/inventory/alerts/a1');
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
        await tester.ensureVisible(find.text('Lịch sử giao dịch'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
      });
    }
  }
  testWidgets(
    'feature-aware picker guard dismisses after capability disappears',
    (tester) async {
      final entitlements = FakeEntitlementRepository()
        ..result = Success(makeEntitlement(features: alertFeatures));
      final auth = makeController(
        authRepository: FakeAuthRepository()
          ..loginResult = Success(
            makeAuthSession(permissions: alertPermissions),
          ),
        entitlementRepository: entitlements,
      );
      final repo = FakeInventoryAlerts();
      await _pump(tester, repo, auth: auth);
      await tester.ensureVisible(find.byType(InventoryAlertDateFilter));
      await tester.tap(find.text('Ngày phát cảnh báo'));
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsOneWidget);
      entitlements.result = Success(
        makeEntitlement(features: {'INVENTORY_MANAGEMENT'}),
      );
      await auth.login(
        const LoginCredentials(
          email: 'alerts@example.com',
          password: 'password',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DateRangePickerDialog), findsNothing);
      expect(tester.takeException(), null);
    },
  );
}
