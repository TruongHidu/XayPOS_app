import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/cashbook/presentation/screens/cashbook_screen.dart';
import 'package:pos_saas_app/features/cashbook/domain/entities/cashbook_enums.dart';
import 'package:pos_saas_app/features/cashbook/presentation/widgets/cashbook_filter_panel.dart';
import 'package:pos_saas_app/features/cashbook/presentation/widgets/cashbook_format.dart';

import '../../helpers/auth_fakes.dart';
import 'cashbook_fakes.dart';

Future<AuthController> _auth({
  Set<String> permissions = cashbookPermissions,
  Set<String> features = cashbookFeatures,
}) async {
  final repo = FakeAuthRepository()
    ..loginResult = Success(makeAuthSession(permissions: permissions));
  final entitlement = FakeEntitlementRepository()
    ..result = Success(makeEntitlement(features: features));
  final auth = makeController(
    authRepository: repo,
    entitlementRepository: entitlement,
  );
  await auth.login(
    const LoginCredentials(email: 'user@example.com', password: 'password'),
  );
  return auth;
}

void main() {
  late FakeCashbookRepository repo;

  setUp(() => repo = FakeCashbookRepository());

  Future<void> pump(
    WidgetTester tester,
    AuthController auth, {
    Size size = const Size(1400, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((_) => auth),
          cashbookRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: const [CashbookFilterAction()]),
            body: const CashbookScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('flow tab shows totals labelled as cash difference, not profit', (
    tester,
  ) async {
    await pump(tester, await _auth());
    expect(find.text('Tổng thu'), findsOneWidget);
    expect(find.text('Tổng chi'), findsOneWidget);
    expect(find.text('Chênh lệch thu chi'), findsOneWidget);
    expect(find.textContaining('Lợi nhuận'), findsNothing);
    expect(find.text('+500.000 VND'), findsOneWidget);
    expect(find.text('+1.000.000 VND'), findsOneWidget);
    expect(find.text('−100.000 VND'), findsOneWidget);
    expect(find.text('Đối chiếu phiếu nhập'), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(
      find.byKey(const ValueKey('cashbook-create-action')),
      findsOneWidget,
    );
  });

  testWidgets('viewer without create or inventory grants sees a reduced UI', (
    tester,
  ) async {
    await pump(
      tester,
      await _auth(permissions: {'CASHBOOK_VIEW'}, features: {'DETAIL_REPORT'}),
    );
    expect(find.byKey(const ValueKey('cashbook-create-action')), findsNothing);
    expect(find.text('Tổng chi'), findsOneWidget);
  });

  testWidgets('create button floats at the bottom right of the screen', (
    tester,
  ) async {
    await pump(tester, await _auth());
    final fab = find.byKey(const ValueKey('cashbook-create-action'));
    expect(
      find.descendant(of: find.byType(AppBar), matching: fab),
      findsNothing,
    );
    final center = tester.getCenter(fab);
    expect(center.dx, greaterThan(1400 / 2));
    expect(center.dy, greaterThan(1000 / 2));
  });

  testWidgets('expense form validates before sending anything', (tester) async {
    await pump(tester, await _auth());
    await tester.tap(find.byKey(const ValueKey('cashbook-create-action')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Chỉ ghi nhận sau khi đã trả tiền'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('expense-form-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Chọn danh mục chi.'), findsOneWidget);
    expect(find.text('Nhập số tiền đã chi.'), findsOneWidget);
    expect(repo.createKeys, isEmpty);
  });

  testWidgets('phone width stacks the layout without overflow', (tester) async {
    await pump(tester, await _auth(), size: const Size(375, 812));
    expect(tester.takeException(), isNull);
    expect(find.text('Tổng thu'), findsOneWidget);
    expect(find.text('Thu bán hàng'), findsWidgets);
  });

  test('short codes keep prefix and tail; short ones stay whole', () {
    expect(
      cashbookShortCode('EXP-DCA6AD4F2B094A9395FEE9FCD1079655'),
      'EXP-DCA6…079655',
    );
    expect(
      cashbookShortCode('OD-4814F1688A8C46D6B4221BD939D3B552'),
      'OD-4814…D3B552',
    );
    expect(cashbookShortCode('RCV-20261030-E74DBDAD'), 'RCV-20261030-E74DBDAD');
  });

  testWidgets('phone cards shorten 36-character server codes', (tester) async {
    repo.entries = [
      testEntry(
        sourceType: CashbookSourceType.expenseVoucher,
        sourceId: 'expense-1',
        type: CashbookEntryType.expense,
        code: 'EXP-DCA6AD4F2B094A9395FEE9FCD1079655',
      ),
    ];
    await pump(tester, await _auth(), size: const Size(375, 812));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('EXP-DCA6…079655'), findsOneWidget);
    expect(find.textContaining('EXP-DCA6AD4F'), findsNothing);
  });
}
