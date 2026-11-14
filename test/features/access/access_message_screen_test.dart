import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/platform/external_link_opener.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/access/presentation/access_message_screen.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/subscription/domain/entities/entitlement.dart';
import '../../helpers/auth_fakes.dart';

const _subscribe = ValueKey('subscribe-button');
const _recheck = ValueKey('subscription-recheck');

Future<(List<Uri>, FakeEntitlementRepository)> _pump(
  WidgetTester tester, {
  UserRole role = UserRole.owner,
  SubscriptionStatus status = SubscriptionStatus.missing,
  Failure? entitlementFailure,
}) async {
  final entitlements = FakeEntitlementRepository()
    ..result = entitlementFailure != null
        ? Error(entitlementFailure)
        : Success(makeEntitlement(status: status));
  final auth = makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(role: role))
      ..restoreResult = Success(makeAuthSession(role: role)),
    entitlementRepository: entitlements,
  );
  await auth.login(
    const LoginCredentials(email: 'a@b.com', password: 'password'),
  );
  final opened = <Uri>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        externalLinkOpenerProvider.overrideWithValue((uri) async {
          opened.add(uri);
          return true;
        }),
      ],
      child: const MaterialApp(
        home: AccessMessageScreen(
          title: 'Nhà hàng chưa có gói hoạt động',
          ownerMessage: 'Vui lòng chọn hoặc mua gói để tiếp tục.',
          staffMessage: 'Vui lòng liên hệ chủ nhà hàng.',
          offerSubscription: true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (opened, entitlements);
}

void main() {
  testWidgets('an owner without a package can sign up on the web', (
    tester,
  ) async {
    final (opened, _) = await _pump(tester);
    expect(find.text('Đăng ký gói'), findsOneWidget);
    await tester.tap(find.byKey(_subscribe));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://xaypos.hiducourse.click/onboarding')]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an expired package is offered as a renewal', (tester) async {
    await _pump(tester, status: SubscriptionStatus.inactive);
    expect(find.text('Gia hạn gói'), findsOneWidget);
    expect(find.textContaining('đã hết hạn'), findsOneWidget);
  });

  testWidgets('the server saying the package expired offers a renewal', (
    tester,
  ) async {
    await _pump(
      tester,
      entitlementFailure: const Failure(
        type: FailureType.subscriptionNotActive,
        code: 'SUBSCRIPTION_NOT_ACTIVE',
        message: 'Gói dịch vụ của nhà hàng đã hết hạn.',
        subscriptionExpired: true,
      ),
    );
    expect(find.text('Gia hạn gói'), findsOneWidget);
    expect(find.text('Đăng ký gói'), findsNothing);
  });

  testWidgets('never having a package offers to subscribe', (tester) async {
    await _pump(
      tester,
      entitlementFailure: const Failure(
        type: FailureType.subscriptionNotActive,
        code: 'SUBSCRIPTION_NOT_ACTIVE',
        message: 'Nhà hàng chưa có gói hoạt động.',
      ),
    );
    expect(find.text('Đăng ký gói'), findsOneWidget);
    expect(find.text('Gia hạn gói'), findsNothing);
  });

  testWidgets('re-checking after paying says when it is not active yet', (
    tester,
  ) async {
    final (_, entitlements) = await _pump(tester);
    await tester.tap(find.byKey(_recheck));
    await tester.pumpAndSettle();
    expect(find.textContaining('Gói chưa hoạt động'), findsOneWidget);
    expect(entitlements.calls, greaterThanOrEqualTo(2));
  });

  testWidgets('a manager is told to ask the owner instead', (tester) async {
    await _pump(tester, role: UserRole.manager);
    expect(find.byKey(_subscribe), findsNothing);
    expect(find.text('Vui lòng liên hệ chủ nhà hàng.'), findsOneWidget);
  });

  testWidgets('iOS never sends the owner out to pay', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pump(tester);
      expect(find.byKey(_subscribe), findsNothing);
      expect(find.text('Đăng xuất'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
