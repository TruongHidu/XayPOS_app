import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/ui/shell/app_shell.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_queries.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_events.dart';

import '../../../helpers/auth_fakes.dart';
import '../../../features/inventory/inventory_fakes.dart';

class _BadgeBalances extends FakeBalances {
  int total = 7;
  final countQueries = <LowStockQuery>[];

  @override
  Future<Result<InventoryPage<InventoryBalance>>> lowStock(
    LowStockQuery q,
  ) async {
    countQueries.add(q);
    return Success(
      InventoryPage(
        content: total == 0 ? [] : [balance(quantity: 1, min: 10)],
        page: 0,
        size: 1,
        totalElements: total,
        totalPages: total,
      ),
    );
  }
}

void main() {
  for (final entitled in [true, false]) {
    testWidgets(
      'shell low-stock badge respects feature=$entitled and live count',
      (tester) async {
        final balances = _BadgeBalances();
        final auth = makeController(
          authRepository: FakeAuthRepository()
            ..loginResult = Success(
              makeAuthSession(permissions: {'INVENTORY_VIEW'}),
            ),
          entitlementRepository: FakeEntitlementRepository()
            ..result = Success(
              makeEntitlement(
                features: {
                  'INVENTORY_MANAGEMENT',
                  if (entitled) 'LOW_STOCK_ALERT',
                },
              ),
            ),
        );
        await auth.login(
          const LoginCredentials(
            email: 'badge@example.test',
            password: 'password',
          ),
        );
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith((_) => auth),
            inventoryBalanceRepositoryProvider.overrideWithValue(balances),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: AppShell(
                initialSection: 'reports',
                child: Center(child: Text('Màn khác')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Menu'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('Mở rộng Kho'));
        await tester.tap(find.byTooltip('Mở rộng Kho'));
        await tester.pumpAndSettle();

        final badge = find.byKey(
          const ValueKey('sidebar-badge-inventory-low-stock'),
        );
        if (entitled) {
          expect(badge, findsOneWidget);
          expect(
            find.descendant(of: badge, matching: find.text('7')),
            findsOneWidget,
          );
          expect(
            balances.countQueries.every((q) => q.warehouseId == null),
            isTrue,
          );
          expect(
            balances.countQueries.every((q) => q.filters.size == 1),
            isTrue,
          );
          balances.total = 0;
          container
              .read(inventoryEventsProvider)
              .emit(const InventoryChange(InventoryChangeKind.alertSync, null));
          await tester.pumpAndSettle();
          expect(badge, findsNothing);
        } else {
          expect(badge, findsNothing);
          expect(find.text('Tồn thấp hiện tại'), findsNothing);
          expect(balances.countQueries, isEmpty);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
