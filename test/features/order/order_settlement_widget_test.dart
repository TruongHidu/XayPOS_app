import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_payment.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_detail_screen.dart';
import 'package:pos_saas_app/features/order/presentation/widgets/order_payment_dialog.dart';
import '../../helpers/auth_fakes.dart';
import 'order_fakes.dart';

const _permissions = {
  ...orderPermissions,
  'PAYMENT_CREATE',
  'PAYMENT_CONFIRM',
  'ORDER_COMPLETE',
  'TABLE_CLOSE',
};

OrderDetail _order({
  bool paid = false,
  String status = 'SERVED',
  String lineStatus = 'SERVED',
  int version = 5,
}) => OrderDto.detail(
  orderJson(
      status: status,
      confirmed: true,
      lineStatus: lineStatus,
      version: version,
    )
    ..['paymentStatus'] = paid ? 'PAID' : 'UNPAID'
    ..['paidAmount'] = paid ? 100000 : 0
    ..['completedAt'] = status == 'COMPLETED' ? '2026-10-17T00:00:00Z' : null,
);

OrderPayment _receipt(FakeOrders orders) {
  final call = orders.paymentCalls.last;
  return OrderPayment(
    id: 'payment1',
    orderId: call.$1,
    paymentCode: 'PAY-TEST',
    amount: call.$2.amount,
    currencyCode: 'VND',
    paymentMethod: call.$2.paymentMethod,
    confirmationSource: PaymentConfirmationSource.staffManual,
    provider: null,
    status: PaymentRecordStatus.success,
    referenceNo: call.$2.normalizedReferenceNo,
    requestedAt: DateTime.utc(2026, 10, 17),
    paidAt: DateTime.utc(2026, 10, 17),
    createdBy: 'u1',
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeOrders orders, {
  Set<String> permissions = _permissions,
  double scale = 1,
  bool screen = false,
}) async {
  final auth = makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(
        makeEntitlement(features: {...orderFeatures, 'PAYMENT_MANAGEMENT'}),
      ),
  );
  await auth.login(
    const LoginCredentials(email: 'a@b.com', password: 'password'),
  );
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      orderRepositoryProvider.overrideWithValue(orders),
      orderKeyGeneratorProvider.overrideWithValue(TestKeys()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: screen
              ? const OrderDetailScreen(id: 'o1')
              : Consumer(
                  builder: (context, ref, _) {
                    final detail = ref.watch(orderDetailProvider('o1'));
                    return detail.order == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.all(16),
                            child: OrderSettlementActions(order: detail.order!),
                          );
                  },
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _payCash(WidgetTester tester) async {
  await tester.tap(find.text('Thanh toán hóa đơn'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(Checkbox));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Xác nhận đã nhận tiền'));
  await tester.tap(find.text('Xác nhận đã nhận tiền'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'verified payment changes action and complete uses refreshed version',
    (tester) async {
      final orders = FakeOrders()..current = _order();
      orders.onRecordPayment = () async {
        orders.current = _order(paid: true, version: 6);
        return Success(_receipt(orders));
      };
      orders.onComplete = () async {
        orders.current = _order(paid: true, status: 'COMPLETED', version: 7);
        return Success(orders.current);
      };
      await _pump(tester, orders);
      await _payCash(tester);
      expect(find.byType(OrderPaymentDialog), findsNothing);
      expect(find.text('Thanh toán hóa đơn'), findsNothing);
      expect(find.text('Hoàn tất đơn'), findsOneWidget);
      expect(orders.paymentCalls.single.$2.expectedOrderVersion, 5);
      expect(orders.paymentCalls.single.$2.amount.minorUnits, 10000000);
      await tester.tap(find.text('Hoàn tất đơn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận hoàn tất'));
      await tester.pumpAndSettle();
      expect(orders.completes, [('o1', 6)]);
      expect(find.text('Đã hoàn tất'), findsOneWidget);
      expect(find.text('Hoàn tất đơn'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'transfer requires reconciled reference and received-money checkbox',
    (tester) async {
      final orders = FakeOrders()..current = _order();
      orders.onRecordPayment = () async {
        orders.current = _order(paid: true, version: 6);
        return Success(_receipt(orders));
      };
      await _pump(tester, orders);
      await tester.tap(find.text('Thanh toán hóa đơn'));
      await tester.pumpAndSettle();
      final confirm = find.widgetWithText(
        FilledButton,
        'Xác nhận đã nhận tiền',
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.tap(
        find.byType(DropdownButtonFormField<OrderPaymentMethod>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chuyển khoản').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(
        find.text('Vui lòng nhập mã tham chiếu đã đối soát.'),
        findsOneWidget,
      );
      expect(orders.paymentCalls, isEmpty);
      await tester.enterText(find.byType(TextFormField), ' BANK-123 ');
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(
        orders.paymentCalls.single.$2.paymentMethod,
        OrderPaymentMethod.transfer,
      );
      expect(orders.paymentCalls.single.$2.referenceNo, 'BANK-123');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recorded payment with failed order readback never posts payment again',
    (tester) async {
      final orders = FakeOrders()..current = _order();
      orders.onRecordPayment = () async {
        orders.current = _order(paid: true, version: 6);
        orders.onDetail = () async => const Error(networkFailure);
        return Success(_receipt(orders));
      };
      await _pump(tester, orders);
      await _payCash(tester);
      expect(find.textContaining('Đã ghi nhận thanh toán.'), findsOneWidget);
      expect(find.text('Xác nhận đã nhận tiền'), findsNothing);
      expect(find.text('Kiểm tra lại lần thanh toán'), findsNothing);
      expect(orders.paymentCalls.length, 1);
      orders.onDetail = null;
      await tester.tap(find.text('Tải lại đơn để đối chiếu'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderPaymentDialog), findsNothing);
      expect(find.text('Hoàn tất đơn'), findsOneWidget);
      expect(orders.paymentCalls.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown payment locks form and retry uses original exact intent',
    (tester) async {
      final orders = FakeOrders()
        ..current = _order()
        ..onRecordPayment = () async => const Error(networkFailure);
      await _pump(tester, orders);
      await _payCash(tester);
      expect(
        find.textContaining('Chưa xác định kết quả thanh toán.'),
        findsOneWidget,
      );
      final original = orders.paymentCalls.single;
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
      orders.onRecordPayment = () async {
        orders.current = _order(paid: true, version: 6);
        return Success(_receipt(orders));
      };
      await tester.tap(find.text('Kiểm tra lại lần thanh toán'));
      await tester.pumpAndSettle();
      expect(orders.paymentCalls.length, 2);
      expect(orders.paymentCalls.last.$3, original.$3);
      expect(identical(orders.paymentCalls.last.$2, original.$2), isTrue);
      expect(find.text('Hoàn tất đơn'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing payment rights hides payment action', (tester) async {
    final orders = FakeOrders()..current = _order();
    await _pump(tester, orders, permissions: {'ORDER_VIEW'});
    expect(find.text('Thanh toán hóa đơn'), findsNothing);
    expect(orders.paymentCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('terminal readback keeps unknown payment recovery reachable', (
    tester,
  ) async {
    final orders = FakeOrders()
      ..current = _order()
      ..onRecordPayment = () async => const Error(networkFailure);
    await _pump(tester, orders);
    await _payCash(tester);
    final original = orders.paymentCalls.single;
    orders.current = _order(paid: true, status: 'COMPLETED', version: 7);
    await tester.tap(find.text('Tải lại đơn để đối chiếu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    expect(find.text('Kiểm tra thanh toán'), findsOneWidget);
    await tester.tap(find.text('Kiểm tra thanh toán'));
    await tester.pumpAndSettle();
    orders.onRecordPayment = () async => Success(_receipt(orders));
    await tester.ensureVisible(find.text('Kiểm tra lại lần thanh toán'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kiểm tra lại lần thanh toán'));
    await tester.pumpAndSettle();
    expect(orders.paymentCalls.last.$3, original.$3);
    expect(identical(orders.paymentCalls.last.$2, original.$2), isTrue);
    expect(find.text('Đã hoàn tất'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unserved lines require bulk serving permission to complete', (
    tester,
  ) async {
    final orders = FakeOrders()
      ..current = _order(paid: true, lineStatus: 'READY');
    final container = await _pump(tester, orders);
    expect(
      container.read(orderDetailProvider('o1')).order!.summary.paymentStatus,
      OrderPaymentStatus.paid,
    );
    expect(find.text('Hoàn tất đơn'), findsOneWidget);
    final complete = find.ancestor(
      of: find.text('Hoàn tất đơn'),
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    expect(tester.widget<ButtonStyleButton>(complete).onPressed, isNull);
    expect(find.text('Còn 1 dòng món chưa đánh dấu phục vụ.'), findsOneWidget);
    expect(orders.completes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 800.0]) {
    testWidgets('bill footer and payment form fit width $width at text 200%', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final orders = FakeOrders()..current = _order();
      await _pump(tester, orders, scale: 2, screen: true);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Thanh toán hóa đơn'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderPaymentDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<OrderPaymentMethod>),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(DropdownButtonFormField<OrderPaymentMethod>),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chuyển khoản').last);
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final field = find.byType(TextFormField);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'REF-TEST');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(orders.paymentCalls, isEmpty);
    });
  }
}
