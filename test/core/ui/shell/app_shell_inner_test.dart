import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/ui/shell/app_shell.dart';
import 'package:pos_saas_app/core/ui/sidebar/app_sidebar.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';

import '../../../helpers/auth_fakes.dart';

void main() {
  Future<GoRouter> pump(WidgetTester tester, String location) async {
    final auth = makeController(
      authRepository: FakeAuthRepository()
        ..loginResult = Success(makeAuthSession()),
      entitlementRepository: FakeEntitlementRepository()
        ..result = Success(makeEntitlement()),
    );
    await auth.login(
      const LoginCredentials(email: 'inner@example.com', password: 'password'),
    );
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/list',
          builder: (_, _) => const AppShell(child: Text('Danh sách')),
        ),
        GoRoute(
          path: '/other',
          builder: (_, _) => const AppShell(child: Text('Màn khác')),
        ),
        GoRoute(
          path: '/detail',
          builder: (_, _) => const AppShell.inner(
            title: 'Chi tiết',
            backFallback: '/list',
            child: Text('Nội dung'),
          ),
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

  testWidgets('inner screen swaps the sidebar for a titled back bar', (
    tester,
  ) async {
    await pump(tester, '/detail');
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Chi tiết')),
      findsOneWidget,
    );
    expect(find.byTooltip('Quay lại'), findsOneWidget);
    expect(find.byTooltip('Menu'), findsNothing);
    expect(find.byType(AppSidebar), findsNothing);
  });

  testWidgets('back returns to the screen that opened it', (tester) async {
    final router = await pump(tester, '/other');
    expect(find.byType(AppSidebar), findsOneWidget);
    router.push('/detail');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.text('Màn khác'), findsOneWidget);
  });

  testWidgets('a deep link has no history and falls back to its list', (
    tester,
  ) async {
    await pump(tester, '/detail');
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.text('Danh sách'), findsOneWidget);
  });
}
