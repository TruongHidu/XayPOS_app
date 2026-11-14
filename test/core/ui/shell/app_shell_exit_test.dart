import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/app/shell/app_shell.dart';
import 'package:pos_saas_app/core/ui/shell/exit_confirm_dialog.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import '../../../helpers/auth_fakes.dart';

void main() {
  late int exits;

  Future<AuthController> signedIn() async {
    final auth = makeController(
      authRepository: FakeAuthRepository()
        ..loginResult = Success(makeAuthSession(permissions: {'STAFF_VIEW'})),
    );
    await auth.login(
      const LoginCredentials(email: 'a@b.com', password: 'password'),
    );
    return auth;
  }

  Future<void> pumpShell(WidgetTester tester) async {
    final auth = await signedIn();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((ref) => auth)],
        child: const MaterialApp(
          home: AppShell(child: Center(child: Text('Nội dung'))),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  setUp(() {
    exits = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemNavigator.pop') exits++;
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('back on the last screen asks before leaving', (tester) async {
    await pumpShell(tester);
    await pressBack(tester);
    expect(find.text('Bạn có chắc muốn thoát không?'), findsOneWidget);
    expect(exits, 0);

    await tester.tap(find.text('Ở lại'));
    await tester.pumpAndSettle();
    expect(find.byType(ExitConfirmDialog), findsNothing);
    expect(exits, 0);
  });

  testWidgets('the exit button leaves the app', (tester) async {
    await pumpShell(tester);
    await pressBack(tester);
    await tester.tap(find.text('Thoát'));
    await tester.pumpAndSettle();
    expect(exits, 1);
  });

  testWidgets('two quick back presses leave without answering', (tester) async {
    await pumpShell(tester);
    await pressBack(tester);
    await pressBack(tester);
    await tester.pumpAndSettle();
    expect(exits, 1);
  });

  testWidgets('a slow second back only closes the dialog', (tester) async {
    await pumpShell(tester);
    await pressBack(tester);
    await tester.pump(ExitConfirmDialog.doubleBackWindow);
    await pressBack(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ExitConfirmDialog), findsNothing);
    expect(exits, 0);
  });

  testWidgets('tapping outside does not count as leaving', (tester) async {
    await pumpShell(tester);
    await pressBack(tester);
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byType(ExitConfirmDialog), findsOneWidget);
    expect(exits, 0);
  });

  testWidgets('an open sidebar closes before anything else', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await pressBack(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ExitConfirmDialog), findsNothing);
    await pressBack(tester);
    expect(find.byType(ExitConfirmDialog), findsOneWidget);
  });

  testWidgets('with the app router an inner screen falls back, then asks', (
    tester,
  ) async {
    final auth = await signedIn();
    final router = GoRouter(
      initialLocation: '/inner',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const AppShell(child: Center(child: Text('Màn chính'))),
        ),
        GoRoute(
          path: '/inner',
          builder: (context, state) => const AppShell.inner(
            title: 'Chi tiết',
            backFallback: '/',
            child: Center(child: Text('Màn trong')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith((ref) => auth)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Màn trong'), findsOneWidget);

    await pressBack(tester);
    await tester.pumpAndSettle();
    expect(find.text('Màn chính'), findsOneWidget);
    expect(find.byType(ExitConfirmDialog), findsNothing);

    await pressBack(tester);
    expect(find.byType(ExitConfirmDialog), findsOneWidget);
    await pressBack(tester);
    await tester.pumpAndSettle();
    expect(exits, 1);
  });

  testWidgets('a screen with somewhere to return to just goes back', (
    tester,
  ) async {
    await pumpShell(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const AppShell(child: Center(child: Text('Màn trong'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await pressBack(tester);
    await tester.pumpAndSettle();
    expect(find.text('Màn trong'), findsNothing);
    expect(find.byType(ExitConfirmDialog), findsNothing);
    expect(exits, 0);
  });
}
