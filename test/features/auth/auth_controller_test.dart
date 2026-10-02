import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_state.dart';
import 'package:pos_saas_app/features/subscription/domain/entities/entitlement.dart';

import '../../helpers/auth_fakes.dart';

const credentials = LoginCredentials(
  email: 'owner@example.com',
  password: 'password',
);

void main() {
  group('AuthController login and role routing', () {
    test('OWNER active opens management shell', () async {
      final state = await _login(role: UserRole.owner);
      expect(AccessPolicy.initialRouteFor(state.session!), '/app/home');
    });

    test('MANAGER active opens management shell', () async {
      final state = await _login(role: UserRole.manager);
      expect(AccessPolicy.initialRouteFor(state.session!), '/app/home');
    });

    test('WAITER with table access opens tables', () async {
      final state = await _login(
        role: UserRole.waiter,
        permissions: {'TABLE_VIEW', 'TABLE_MANAGEMENT'},
        features: {'TABLE_MANAGEMENT'},
      );
      expect(AccessPolicy.initialRouteFor(state.session!), '/app/home');
    });

    test('WAITER with only order view opens orders', () async {
      final state = await _login(
        role: UserRole.waiter,
        permissions: {'ORDER_VIEW'},
        features: {'ORDER_MANAGEMENT'},
      );
      expect(AccessPolicy.initialRouteFor(state.session!), '/app/home');
    });

    test('KITCHEN with permission and feature opens kitchen', () async {
      final state = await _login(
        role: UserRole.kitchen,
        permissions: {'KITCHEN_VIEW'},
        features: {'KITCHEN_DISPLAY'},
      );
      expect(AccessPolicy.initialRouteFor(state.session!), '/app/home');
    });

    test('CASHIER loads entitlement and opens web-only', () async {
      final entitlement = FakeEntitlementRepository();
      final state = await _login(
        role: UserRole.cashier,
        entitlementRepository: entitlement,
      );
      expect(entitlement.calls, 1);
      expect(AccessPolicy.initialRouteFor(state.session!), '/cashier-web-only');
    });

    test('SUPER_ADMIN skips entitlement and opens admin web-only', () async {
      final entitlement = FakeEntitlementRepository();
      final state = await _login(
        role: UserRole.superAdmin,
        restaurantId: null,
        entitlementRepository: entitlement,
      );
      expect(entitlement.calls, 0);
      expect(AccessPolicy.initialRouteFor(state.session!), '/admin-web-only');
    });

    test('null restaurant id opens admin web-only safely', () async {
      final state = await _login(role: UserRole.owner, restaurantId: null);
      expect(AccessPolicy.initialRouteFor(state.session!), '/admin-web-only');
    });

    test('unknown role opens unsupported role', () async {
      final state = await _login(role: UserRole.unsupported);
      expect(AccessPolicy.initialRouteFor(state.session!), '/unsupported-role');
    });
  });

  group('AuthController failures', () {
    test('INVALID_CREDENTIALS remains a login failure', () async {
      final auth = FakeAuthRepository()
        ..loginResult = const Error(
          Failure(
            type: FailureType.invalidCredentials,
            message: 'Email hoặc mật khẩu không đúng',
          ),
        );
      final controller = makeController(authRepository: auth);
      await controller.login(credentials);

      expect(controller.state.failureStage, AuthFailureStage.login);
      expect(controller.state.message, 'Email hoặc mật khẩu không đúng');
    });

    test('RESTAURANT_INACTIVE exposes friendly message', () async {
      final auth = FakeAuthRepository()
        ..loginResult = const Error(
          Failure(
            type: FailureType.restaurantInactive,
            message:
                'Nhà hàng đang bị khóa hoặc tạm ngừng hoạt động. Vui lòng liên hệ quản trị viên.',
          ),
        );
      final controller = makeController(authRepository: auth);
      await controller.login(credentials);
      expect(controller.state.message, contains('Nhà hàng đang bị khóa'));
    });

    test(
      'client validation maps errors to email and password fields',
      () async {
        final auth = FakeAuthRepository();
        final controller = makeController(authRepository: auth);
        await controller.login(
          const LoginCredentials(email: 'not-email', password: ''),
        );

        expect(
          controller.state.fieldErrors.keys,
          containsAll(['email', 'password']),
        );
        expect(auth.loginCalls, 0);
      },
    );

    test('server VALIDATION_ERROR preserves field errors', () async {
      final auth = FakeAuthRepository()
        ..loginResult = const Error(
          Failure(
            type: FailureType.validation,
            message: 'Thông tin nhập chưa hợp lệ.',
            fieldErrors: {'email': 'Email đã bị khóa'},
          ),
        );
      final controller = makeController(authRepository: auth);
      await controller.login(credentials);
      expect(controller.state.fieldErrors['email'], 'Email đã bị khóa');
    });

    test('OWNER without subscription remains logged in', () async {
      final entitlement = FakeEntitlementRepository()
        ..result = const Error(
          Failure(
            type: FailureType.subscriptionNotActive,
            message: 'Nhà hàng chưa có gói hoạt động.',
          ),
        );
      final state = await _login(
        role: UserRole.owner,
        entitlementRepository: entitlement,
      );
      expect(state.status, AuthStatus.authenticated);
      expect(
        AccessPolicy.initialRouteFor(state.session!),
        '/subscription-required',
      );
    });

    test('WAITER without subscription opens unavailable screen', () async {
      final state = await _login(
        role: UserRole.waiter,
        status: SubscriptionStatus.missing,
      );
      expect(
        AccessPolicy.initialRouteFor(state.session!),
        '/subscription-unavailable',
      );
    });

    test('KITCHEN without subscription opens unavailable screen', () async {
      final state = await _login(
        role: UserRole.kitchen,
        permissions: {'KITCHEN_VIEW'},
        features: {'KITCHEN_DISPLAY'},
        status: SubscriptionStatus.missing,
      );
      expect(
        AccessPolicy.initialRouteFor(state.session!),
        '/subscription-unavailable',
      );
    });

    test(
      'entitlement network failure keeps session and supports retry',
      () async {
        final entitlement = FakeEntitlementRepository()
          ..result = const Error(networkFailure);
        final auth = FakeAuthRepository();
        final controller = makeController(
          authRepository: auth,
          entitlementRepository: entitlement,
        );
        await controller.login(credentials);

        expect(controller.state.failureStage, AuthFailureStage.entitlement);
        expect(controller.state.session, isNotNull);

        entitlement.result = Success(makeEntitlement());
        await controller.retry();
        expect(controller.state.status, AuthStatus.authenticated);
      },
    );
  });

  group('restore and logout', () {
    test('valid restored token bootstraps the correct shell', () async {
      final auth = FakeAuthRepository()
        ..restoreResult = Success(makeAuthSession());
      final controller = makeController(authRepository: auth);
      await controller.restore();
      expect(controller.state.status, AuthStatus.authenticated);
      expect(
        AccessPolicy.initialRouteFor(controller.state.session!),
        '/app/home',
      );
    });

    test('network restore error does not become unauthenticated', () async {
      final auth = FakeAuthRepository()
        ..restoreResult = const Error(networkFailure);
      final controller = makeController(authRepository: auth);
      await controller.restore();
      expect(controller.state.failureStage, AuthFailureStage.restore);
    });

    test(
      'successful interceptor refresh replaces user and both tokens',
      () async {
        final events = SessionEvents();
        final controller = makeController(sessionEvents: events);
        await controller.login(credentials);

        events.refreshed(
          makeAuthSession(
            permissions: {'MENU_VIEW', 'ORDER_VIEW'},
            tokens: makeTokens(
              accessToken: 'rotated-access',
              refreshToken: 'rotated-refresh',
            ),
          ),
        );

        expect(controller.state.session?.tokens.accessToken, 'rotated-access');
        expect(
          controller.state.session?.tokens.refreshToken,
          'rotated-refresh',
        );
        expect(controller.state.session?.permissions, contains('ORDER_VIEW'));
      },
    );

    test('invalid refresh event clears session and returns to login', () async {
      final events = SessionEvents();
      final controller = makeController(sessionEvents: events);
      await controller.login(credentials);
      events.invalidate();
      expect(controller.state.status, AuthStatus.unauthenticated);
      expect(controller.state.session, isNull);
    });

    test('logout clears controller session even when remote fails', () async {
      final auth = FakeAuthRepository()
        ..logoutResult = const Error(networkFailure);
      final controller = makeController(authRepository: auth);
      await controller.login(credentials);
      await controller.logout();
      expect(controller.state.status, AuthStatus.unauthenticated);
      expect(auth.logoutCalls, 1);
    });

    test('login never prints password or tokens', () async {
      final output = <String>[];
      final controller = makeController();
      await runZoned(
        () => controller.login(credentials),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => output.add(line),
        ),
      );
      final logs = output.join('\n');
      expect(logs, isNot(contains('password')));
      expect(logs, isNot(contains('access-token')));
      expect(logs, isNot(contains('refresh-token')));
    });
  });
}

Future<AuthState> _login({
  required UserRole role,
  String? restaurantId = 'restaurant-1',
  Set<String> permissions = const {'MENU_VIEW'},
  Set<String> features = const {'MENU_MANAGEMENT'},
  SubscriptionStatus status = SubscriptionStatus.active,
  FakeEntitlementRepository? entitlementRepository,
}) async {
  final auth = FakeAuthRepository()
    ..loginResult = Success(
      makeAuthSession(
        role: role,
        restaurantId: restaurantId,
        permissions: permissions,
      ),
    );
  final entitlement = entitlementRepository ?? FakeEntitlementRepository();
  if (entitlementRepository == null) {
    entitlement.result = Success(
      makeEntitlement(status: status, features: features),
    );
  }
  final controller = makeController(
    authRepository: auth,
    entitlementRepository: entitlement,
  );
  await controller.login(credentials);
  return controller.state;
}
