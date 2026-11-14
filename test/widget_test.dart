import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/app.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/platform/external_link_opener.dart';
import 'package:pos_saas_app/app/shell/app_shell.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/presentation/widgets/support_footer.dart';
import 'package:pos_saas_app/features/menu/presentation/screens/menu_management_screen.dart';

import 'helpers/auth_fakes.dart';
import 'features/menu/menu_fakes.dart';

void main() {
  testWidgets('login screen displays Xây POS controls', (tester) async {
    final controller = await _unauthenticatedController();
    await _pumpApp(tester, controller);

    expect(find.text('Tên gian hàng'), findsNothing);
    expect(find.text('.kiotviet.vn'), findsNothing);
    expect(find.text('Gmail'), findsOneWidget);
    expect(find.text('Mật khẩu'), findsOneWidget);
    expect(find.text('Đăng nhập'), findsOneWidget);
    expect(find.text('Xây POS'), findsOneWidget);
    expect(find.textContaining('KiotViet'), findsNothing);
  });

  testWidgets('support actions do not overflow on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _unauthenticatedController();
    await _pumpApp(tester, controller);

    expect(find.text('Gọi 1900 6522'), findsOneWidget);
    // No SUPPORT_WEB_URL in the test configuration: the link stays hidden.
    expect(find.byKey(const ValueKey('support-web')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign-up opens the restaurant registration page on the web', (
    tester,
  ) async {
    final opened = <Uri>[];
    final controller = await _unauthenticatedController();
    await _pumpApp(
      tester,
      controller,
      openLink: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    expect(find.text('Chưa có tài khoản?'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('register-button')));
    await tester.tap(find.byKey(const Key('register-button')));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://xaypos.hiducourse.click/register')]);
  });

  testWidgets('a register page that cannot open says so', (tester) async {
    final controller = await _unauthenticatedController();
    await _pumpApp(tester, controller, openLink: (_) async => false);
    await tester.ensureVisible(find.byKey(const Key('register-button')));
    await tester.tap(find.byKey(const Key('register-button')));
    await tester.pumpAndSettle();
    expect(
      find.text('Không mở được trang đăng ký xaypos.hiducourse.click.'),
      findsOneWidget,
    );
  });

  testWidgets('support footer offers the hotline and the website', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0, visits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupportFooter(
            phone: '0909 123 456',
            onCall: () => calls++,
            webLabel: 'xaypos.vn',
            onWeb: () => visits++,
            stackActions: true,
          ),
        ),
      ),
    );
    expect(find.text('Gọi 0909 123 456'), findsOneWidget);
    expect(find.text('xaypos.vn'), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const ValueKey('support-call'))).dy,
      lessThanOrEqualTo(
        tester.getCenter(find.byKey(const ValueKey('support-web'))).dy,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('support-call')));
    await tester.tap(find.byKey(const ValueKey('support-web')));
    expect((calls, visits), (1, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('login form uses desktop width', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await _unauthenticatedController();
    await _pumpApp(tester, controller);

    expect(
      tester.getSize(find.byKey(const Key('email-field'))).width,
      closeTo(1400, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('password visibility can be toggled', (tester) async {
    final controller = await _unauthenticatedController();
    await _pumpApp(tester, controller);

    await tester.enterText(find.byKey(const Key('password-field')), 'secret');
    await tester.tap(find.byKey(const Key('password-visibility-button')));
    await tester.pump();

    expect(find.text('secret'), findsOneWidget);
  });

  testWidgets('invalid form errors are rendered next to fields', (
    tester,
  ) async {
    final controller = await _unauthenticatedController();
    await _pumpApp(tester, controller);

    await tester.enterText(find.byKey(const Key('email-field')), 'invalid');
    await tester.tap(find.byKey(const Key('login-button')));
    await tester.pump();

    expect(find.text('Email không đúng định dạng.'), findsOneWidget);
    expect(find.text('Vui lòng nhập mật khẩu.'), findsOneWidget);
  });

  testWidgets('router sends an authenticated owner to management', (
    tester,
  ) async {
    final controller = makeController();
    await controller.login(
      const LoginCredentials(email: 'owner@example.com', password: 'password'),
    );
    await _pumpApp(tester, controller);

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(MenuManagementScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<AuthController> _unauthenticatedController() async {
  final controller = makeController();
  await controller.restore();
  return controller;
}

Future<void> _pumpApp(
  WidgetTester tester,
  AuthController controller, {
  Future<bool> Function(Uri)? openLink,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => controller),
        if (openLink != null)
          externalLinkOpenerProvider.overrideWithValue(openLink),
        menuItemRepositoryProvider.overrideWithValue(FakeMenuItems()),
        menuGroupRepositoryProvider.overrideWithValue(FakeMenuGroups()),
      ],
      child: const App(),
    ),
  );
  await tester.pumpAndSettle();
}
