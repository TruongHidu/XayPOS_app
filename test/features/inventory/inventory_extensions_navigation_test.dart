import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_management_screen.dart';
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
  testWidgets(
    'workspace mounts only the chosen extension and lists need no per-row detail GET',
    (tester) async {
      final alerts = FakeInventoryAlerts(), audits = FakeStockAudits();
      await _pump(tester, alerts: alerts, audits: audits);
      expect(alerts.queries, isEmpty);
      expect(audits.queries, isEmpty);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Cảnh báo'));
      expect(alerts.queries, hasLength(1));
      expect(alerts.detailIds, isEmpty);
      expect(audits.queries, isEmpty);
      await _tap(tester, find.widgetWithText(ChoiceChip, 'Kiểm kê'));
      expect(audits.queries, hasLength(1));
      expect(audits.details, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'real routes open alert/audit detail while keeping inventory shell selection',
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
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await _tap(tester, find.widgetWithText(ListTile, 'Kho'));
      expect(find.byType(InventoryManagementScreen), findsOneWidget);
      expect(
        container
            .read(appRouterProvider)
            .routeInformationProvider
            .value
            .uri
            .path,
        '/app/inventory',
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
      expect(find.byType(InventoryManagementScreen), findsOneWidget);
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
}
