import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/router/app_routes.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/order/presentation/widgets/order_widgets.dart';
import '../../helpers/auth_fakes.dart';

const _warehouseFailure = Failure(
  type: FailureType.conflict,
  code: 'INVENTORY_DEFAULT_WAREHOUSE_REQUIRED',
  message: 'Chưa có kho mặc định.',
);

Future<GoRouter> _pump(
  WidgetTester tester, {
  required Set<String> permissions,
  bool inDialog = false,
}) async {
  final auth = makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(
        makeEntitlement(features: {'ORDER_MANAGEMENT', 'INVENTORY_MANAGEMENT'}),
      ),
  );
  await auth.login(
    const LoginCredentials(email: 'owner@example.com', password: 'password'),
  );
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: inDialog
              ? Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const Dialog(
                        child: OrderFailurePanel(failure: _warehouseFailure),
                      ),
                    ),
                    child: const Text('Mở'),
                  ),
                )
              : const OrderFailurePanel(failure: _warehouseFailure),
        ),
      ),
      GoRoute(
        path: AppRoutes.inventoryWarehouses,
        builder: (_, _) => const Scaffold(body: Text('Trang kho')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authControllerProvider.overrideWith((_) => auth)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('warehouse managers can open warehouse settings over the order', (
    tester,
  ) async {
    await _pump(tester, permissions: {'ORDER_VIEW', 'WAREHOUSE_UPDATE'});
    await tester.tap(find.text('Mở quản lý kho'));
    await tester.pumpAndSettle();
    expect(find.text('Trang kho'), findsOneWidget);
  });

  testWidgets('other staff only see the message', (tester) async {
    await _pump(tester, permissions: {'ORDER_VIEW'});
    expect(find.text('Chưa có kho mặc định.'), findsOneWidget);
    expect(find.text('Mở quản lý kho'), findsNothing);
  });

  testWidgets('dialogs keep their draft by not offering the link', (
    tester,
  ) async {
    await _pump(
      tester,
      permissions: {'ORDER_VIEW', 'WAREHOUSE_UPDATE'},
      inDialog: true,
    );
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có kho mặc định.'), findsOneWidget);
    expect(find.text('Mở quản lý kho'), findsNothing);
  });
}
