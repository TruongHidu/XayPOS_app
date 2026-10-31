import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/app/router/app_routes.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_balances_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_alerts_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_audits_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_warehouses_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_documents_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_transactions_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_low_stock_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_alert_detail_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/stock_audit_detail_screen.dart';
import '../../helpers/auth_fakes.dart';
import 'inventory_fakes.dart';
import 'stock_fakes.dart';
import 'inventory_alert_fakes.dart';
import 'stock_audit_fakes.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required FakeInventoryAlerts alerts,
  required FakeStockAudits audits,
  Set<String>? permissions,
  Set<String>? features,
  String location = '/app/inventory',
}) async {
  tester.view.physicalSize = const Size(1200, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(
        makeAuthSession(
          permissions:
              permissions ?? {...alertPermissions, ...stockAuditPermissions},
        ),
      ),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(
        makeEntitlement(
          features: features ?? {...alertFeatures, ...stockAuditFeatures},
        ),
      ),
  );
  await auth.login(
    const LoginCredentials(
      email: 'inventory@example.com',
      password: 'password',
    ),
  );
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      inventoryAlertRepositoryProvider.overrideWithValue(alerts),
      stockAuditRepositoryProvider.overrideWithValue(audits),
      warehouseRepositoryProvider.overrideWithValue(FakeWarehouses()),
      inventoryBalanceRepositoryProvider.overrideWithValue(FakeBalances()),
      stockDocumentRepositoryProvider.overrideWithValue(FakeStockDocuments()),
      inventoryTransactionRepositoryProvider.overrideWithValue(
        FakeStockTransactions(),
      ),
      stockKeyGeneratorProvider.overrideWithValue(FakeStockKeys()),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(appRouterProvider)..go(location);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('each inventory destination has its own routable screen', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      alerts: FakeInventoryAlerts(),
      audits: FakeStockAudits(),
    );
    final router = container.read(appRouterProvider);
    for (final destination in [
      (path: AppRoutes.inventoryBalances, screen: InventoryBalancesScreen),
      (path: AppRoutes.inventoryWarehouses, screen: InventoryWarehousesScreen),
      (path: AppRoutes.inventoryDocuments, screen: InventoryDocumentsScreen),
      (
        path: AppRoutes.inventoryTransactions,
        screen: InventoryTransactionsScreen,
      ),
      (path: AppRoutes.inventoryLowStock, screen: InventoryLowStockScreen),
      (path: AppRoutes.inventoryAlerts, screen: InventoryAlertsScreen),
      (path: AppRoutes.inventoryAudits, screen: InventoryAuditsScreen),
    ]) {
      router.go(destination.path);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, destination.path);
      expect(find.byType(destination.screen), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('legacy inventory links redirect to the corresponding screen', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      alerts: FakeInventoryAlerts(),
      audits: FakeStockAudits(),
    );
    final router = container.read(appRouterProvider);
    for (final link in [
      (legacy: '/app/inventory', destination: AppRoutes.inventoryBalances),
      (
        legacy: '/app/inventory?tab=warehouses',
        destination: AppRoutes.inventoryWarehouses,
      ),
      (
        legacy: '/app/inventory?tab=documents',
        destination: AppRoutes.inventoryDocuments,
      ),
      (
        legacy: '/app/inventory?tab=transactions',
        destination: AppRoutes.inventoryTransactions,
      ),
      (
        legacy: '/app/inventory?tab=lowStock',
        destination: AppRoutes.inventoryLowStock,
      ),
      (
        legacy: '/app/inventory?tab=alerts',
        destination: AppRoutes.inventoryAlerts,
      ),
      (
        legacy: '/app/inventory?tab=audits',
        destination: AppRoutes.inventoryAudits,
      ),
    ]) {
      router.go(link.legacy);
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, link.destination);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'workspace mounts only the chosen extension and lists need no per-row detail GET',
    (tester) async {
      final alerts = FakeInventoryAlerts(), audits = FakeStockAudits();
      await _pump(tester, alerts: alerts, audits: audits);
      expect(alerts.queries, isEmpty);
      expect(audits.queries, isEmpty);
      await _tap(tester, find.byTooltip('Menu'));
      await _tap(tester, find.widgetWithText(ListTile, 'Cảnh báo tồn kho'));
      expect(find.byType(InventoryAlertsScreen), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(alerts.queries, hasLength(1));
      expect(alerts.detailIds, isEmpty);
      expect(audits.queries, isEmpty);
      await _tap(tester, find.byTooltip('Menu'));
      await _tap(tester, find.widgetWithText(ListTile, 'Kiểm kê'));
      expect(find.byType(InventoryAuditsScreen), findsOneWidget);
      expect(audits.queries, hasLength(1));
      expect(audits.details, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'real routes open alert/audit detail and back leads to the inventory shell',
    (tester) async {
      final alerts = FakeInventoryAlerts(), audits = FakeStockAudits();
      final container = await _pump(
        tester,
        alerts: alerts,
        audits: audits,
        location: '/app/inventory/alerts/a1',
      );
      expect(find.byType(InventoryAlertDetailScreen), findsOneWidget);
      expect(alerts.detailIds, ['a1']);
      container.read(appRouterProvider).go('/app/inventory/audits/a1');
      await tester.pumpAndSettle();
      expect(find.byType(StockAuditDetailScreen), findsOneWidget);
      expect(audits.details, 1);
      expect(audits.itemQueries, hasLength(1));
      expect(find.text('Chi tiết kiểm kê'), findsOneWidget);
      expect(find.byTooltip('Menu'), findsNothing);
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await _tap(tester, find.widgetWithText(ListTile, 'Tồn kho'));
      expect(find.byType(InventoryBalancesScreen), findsOneWidget);
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        AppRoutes.inventoryBalances,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'feature guards reject extension deep links without issuing their requests',
    (tester) async {
      final alerts = FakeInventoryAlerts(), audits = FakeStockAudits();
      final container = await _pump(
        tester,
        alerts: alerts,
        audits: audits,
        features: {'INVENTORY_MANAGEMENT'},
        location: '/app/inventory/alerts/a1',
      );
      expect(find.byType(InventoryBalancesScreen), findsOneWidget);
      expect(alerts.detailIds, isEmpty);
      container.read(appRouterProvider).go('/app/inventory/audits/new');
      await tester.pumpAndSettle();
      expect(audits.details, 0);
      expect(audits.sentKeys, isEmpty);
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        AccessPolicy.initialRouteFor(
          container.read(authControllerProvider).state.session!,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'missing extension features hide sidebar entries and reject their list routes',
    (tester) async {
      final alerts = FakeInventoryAlerts(), audits = FakeStockAudits();
      final container = await _pump(
        tester,
        alerts: alerts,
        audits: audits,
        permissions: {'INVENTORY_VIEW'},
        features: {'INVENTORY_MANAGEMENT'},
      );
      await _tap(tester, find.byTooltip('Menu'));
      expect(find.widgetWithText(ListTile, 'Tồn kho'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Chứng từ kho'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Cảnh báo tồn kho'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Tồn thấp hiện tại'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Kiểm kê'), findsNothing);
      for (final location in [
        AppRoutes.inventoryAlerts,
        AppRoutes.inventoryAudits,
        AppRoutes.inventoryLowStock,
      ]) {
        container.read(appRouterProvider).go(location);
        await tester.pumpAndSettle();
        expect(
          container
              .read(appRouterProvider)
              .routeInformationProvider
              .value
              .uri
              .path,
          isNot(location),
        );
      }
      expect(alerts.queries, isEmpty);
      expect(audits.queries, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
