import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/router/app_routes.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/ui/shell/app_shell.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_balances_screen.dart';
import '../../../helpers/auth_fakes.dart';
import '../../../features/inventory/inventory_fakes.dart';

void main() {
  for (final viewport in [
    (width: 320.0, scale: 1.0),
    (width: 320.0, scale: 2.0),
    (width: 1200.0, scale: 1.0),
  ]) {
    for (final source in [
      (
        path: AppRoutes.reports,
        section: 'reports',
        content: 'Chi tiết báo cáo',
      ),
      (
        path: '/app/inventory/stock-documents/d1',
        section: 'inventory-documents',
        content: 'Chi tiết chứng từ',
      ),
    ]) {
      testWidgets(
        'Kho collapses, reopens and navigates from ${source.path} at ${viewport.width} px/${viewport.scale}x',
        (tester) async {
          tester.view.physicalSize = Size(viewport.width, 900);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = viewport.scale;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final auth = makeController(
            authRepository: FakeAuthRepository()
              ..loginResult = Success(
                makeAuthSession(
                  permissions: {'INVENTORY_VIEW', 'REPORT_DETAIL_VIEW'},
                ),
              ),
            entitlementRepository: FakeEntitlementRepository()
              ..result = Success(
                makeEntitlement(
                  features: {'INVENTORY_MANAGEMENT', 'DETAIL_REPORT'},
                ),
              ),
          );
          await auth.login(
            const LoginCredentials(
              email: 'navigation@example.com',
              password: 'password',
            ),
          );
          final router = GoRouter(
            initialLocation: source.path,
            routes: [
              GoRoute(
                path: source.path,
                builder: (_, _) => AppShell(
                  initialSection: source.section,
                  child: Center(child: Text(source.content)),
                ),
              ),
              GoRoute(
                path: AppRoutes.inventoryBalances,
                builder: (_, _) => const AppShell(
                  initialSection: 'inventory',
                  child: InventoryBalancesScreen(),
                ),
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                authControllerProvider.overrideWith((ref) => auth),
                warehouseRepositoryProvider.overrideWithValue(FakeWarehouses()),
                inventoryBalanceRepositoryProvider.overrideWithValue(
                  FakeBalances(),
                ),
              ],
              child: MaterialApp.router(
                theme: AppTheme.light,
                routerConfig: router,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text(source.content), findsOneWidget);
          await tester.tap(find.byTooltip('Menu'));
          await tester.pumpAndSettle();
          if (find.byTooltip('Thu gọn Kho').evaluate().isNotEmpty) {
            await tester.ensureVisible(find.byTooltip('Thu gọn Kho'));
            await tester.tap(find.byTooltip('Thu gọn Kho'));
            await tester.pumpAndSettle();
          }
          expect(find.widgetWithText(ListTile, 'Tồn kho'), findsNothing);
          await tester.ensureVisible(find.byTooltip('Mở rộng Kho'));
          await tester.tap(find.byTooltip('Mở rộng Kho'));
          await tester.pumpAndSettle();
          expect(find.widgetWithText(ListTile, 'Tồn kho'), findsOneWidget);
          expect(router.routeInformationProvider.value.uri.path, source.path);
          await tester.tap(find.byTooltip('Thu gọn Kho'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Menu'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Menu'));
          await tester.pumpAndSettle();
          expect(find.widgetWithText(ListTile, 'Tồn kho'), findsNothing);
          await tester.ensureVisible(find.byTooltip('Mở rộng Kho'));
          await tester.tap(find.byTooltip('Mở rộng Kho'));
          await tester.pumpAndSettle();
          final inventory = find.widgetWithText(ListTile, 'Tồn kho');
          await tester.ensureVisible(inventory);
          await tester.tap(inventory);
          await tester.pumpAndSettle();
          expect(
            router.routeInformationProvider.value.uri.path,
            AppRoutes.inventoryBalances,
          );
          expect(find.byType(InventoryBalancesScreen), findsOneWidget);
          expect(find.text('Tồn kho'), findsWidgets);
          expect(find.text(source.content), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
