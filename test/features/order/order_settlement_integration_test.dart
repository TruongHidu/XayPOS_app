import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_payment.dart';
import 'package:pos_saas_app/features/order/domain/policies/order_access_policy.dart';
import 'package:pos_saas_app/features/tables/presentation/controllers/table_events.dart';

import '../../helpers/auth_fakes.dart';
import 'order_fakes.dart';

const _permissions = {
  'ORDER_VIEW',
  'ORDER_COMPLETE',
  'PAYMENT_CREATE',
  'PAYMENT_CONFIRM',
  'TABLE_CLOSE',
};
const _features = {
  'ORDER_MANAGEMENT',
  'PAYMENT_MANAGEMENT',
  'TABLE_MANAGEMENT',
};

OrderDetail _order({
  bool paid = false,
  bool completed = false,
  int version = 5,
}) => OrderDto.detail(
  orderJson(
      version: version,
      status: completed ? 'COMPLETED' : 'SERVED',
      confirmed: true,
      lineStatus: 'SERVED',
    )
    ..['serviceType'] = 'DINE_IN'
    ..['tableSessionId'] = sessionId
    ..['paymentStatus'] = paid ? 'PAID' : 'UNPAID'
    ..['paidAmount'] = paid ? 100000 : 0
    ..['completedAt'] = completed ? '2026-10-17T10:00:00Z' : null,
);

OrderPayment _receipt() => OrderPayment(
  id: 'payment-1',
  orderId: 'o1',
  paymentCode: 'PAY-1',
  amount: _order().summary.totalAmount,
  currencyCode: 'VND',
  paymentMethod: OrderPaymentMethod.cash,
  confirmationSource: PaymentConfirmationSource.staffManual,
  provider: null,
  status: PaymentRecordStatus.success,
  referenceNo: null,
  requestedAt: DateTime.utc(2026, 10, 17),
  paidAt: DateTime.utc(2026, 10, 17),
  createdBy: 'u1',
);

Future<AuthController> _auth() async {
  final auth = makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: _permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: _features)),
  );
  await auth.login(
    const LoginCredentials(
      email: 'settlement@example.com',
      password: 'password',
    ),
  );
  return auth;
}

void main() {
  test('payment needs both effective permissions and its own feature', () {
    for (final permissions in [
      <String>{},
      {'PAYMENT_CREATE'},
      {'PAYMENT_CONFIRM'},
    ]) {
      expect(
        AccessPolicy.canRecordOrderPayment(
          makeAppSession(permissions: permissions, features: _features),
        ),
        false,
      );
    }
    expect(
      AccessPolicy.canRecordOrderPayment(
        makeAppSession(
          permissions: _permissions,
          features: {'ORDER_MANAGEMENT'},
        ),
      ),
      false,
    );
    expect(
      AccessPolicy.canRecordOrderPayment(
        makeAppSession(
          permissions: _permissions,
          features: {'PAYMENT_MANAGEMENT'},
        ),
      ),
      true,
    );
    for (final role in [UserRole.cashier, UserRole.superAdmin]) {
      expect(
        AccessPolicy.canRecordOrderPayment(
          makeAppSession(
            role: role,
            permissions: _permissions,
            features: _features,
          ),
        ),
        false,
      );
    }
  });

  test(
    'dine-in completion requires TABLE_CLOSE; takeaway needs only order feature',
    () {
      final noClose = makeAppSession(
        permissions: {'ORDER_COMPLETE'},
        features: _features,
      );
      expect(AccessPolicy.canCompleteOrder(noClose, takeaway: false), false);
      expect(
        AccessPolicy.canCompleteOrder(
          makeAppSession(
            permissions: {'ORDER_COMPLETE'},
            features: {'ORDER_MANAGEMENT'},
          ),
          takeaway: true,
        ),
        true,
      );
      expect(
        AccessPolicy.canCompleteOrder(
          makeAppSession(
            permissions: {'ORDER_COMPLETE', 'TABLE_CLOSE'},
            features: _features,
          ),
          takeaway: false,
        ),
        true,
      );
    },
  );

  test(
    'completion requires exact full payment and nonempty served live items',
    () {
      expect(OrderAccessPolicy.canComplete(_order(paid: true), true), true);
      expect(OrderAccessPolicy.canComplete(_order(), true), false);
      expect(
        OrderAccessPolicy.canComplete(
          _order(paid: true, completed: true),
          true,
        ),
        false,
      );
      for (final status in ['PENDING', 'COOKING', 'READY', 'CANCELLED']) {
        final data = orderJson(status: 'SERVED', lineStatus: status)
          ..['paymentStatus'] = 'PAID'
          ..['paidAmount'] = 100000;
        expect(
          OrderAccessPolicy.canComplete(OrderDto.detail(data), true),
          false,
        );
      }
      final underpaid = orderJson(status: 'SERVED', lineStatus: 'SERVED')
        ..['paymentStatus'] = 'PAID'
        ..['paidAmount'] = 99999;
      expect(
        OrderAccessPolicy.canComplete(OrderDto.detail(underpaid), true),
        false,
      );
      final zero = orderJson(status: 'SERVED', lineStatus: 'SERVED')
        ..['totalAmount'] = 0
        ..['paidAmount'] = 0;
      expect(OrderAccessPolicy.canPay(OrderDto.detail(zero), true), false);
    },
  );

  test(
    'provider applies payment readback then completes with new order version and refreshes tables',
    () async {
      final orders = FakeOrders()..current = _order();
      orders.onRecordPayment = () async {
        orders.current = _order(paid: true, version: 6);
        return Success(_receipt());
      };
      orders.onComplete = () async => Success(
        orders.current = _order(paid: true, completed: true, version: 7),
      );
      final auth = await _auth();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          orderRepositoryProvider.overrideWithValue(orders),
          orderKeyGeneratorProvider.overrideWithValue(TestKeys()),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        orderSettlementProvider('o1'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.pump();
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      final controller = container.read(orderSettlementProvider('o1'));
      final detail = container.read(orderDetailProvider('o1'));
      expect(controller.canPay, true);
      expect(
        await controller.pay(detail.order!, OrderPaymentMethod.cash),
        isA<Success<OrderDetail>>(),
      );
      expect(detail.order!.summary.paymentStatus, OrderPaymentStatus.paid);
      expect(detail.order!.version, 6);
      expect(controller.canComplete, true);
      expect(
        await controller.complete(detail.order!),
        isA<Success<OrderDetail>>(),
      );
      expect(orders.completes.single, ('o1', 6));
      expect(detail.order!.summary.status, OrderStatus.completed);
      final tableChange = container.read(tableEventsProvider).change!;
      expect(tableChange.kind, TableChangeKind.refresh);
      expect(tableChange.sessionId, sessionId);
      expect(controller.canPay, false);
      expect(controller.canComplete, false);
    },
  );

  test(
    'known receipt keeps provider alive until order readback succeeds without another payment',
    () async {
      final orders = FakeOrders()..current = _order();
      final auth = await _auth();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          orderRepositoryProvider.overrideWithValue(orders),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        orderSettlementProvider('o1'),
        (_, _) {},
      );
      await container.pump();
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      final controller = container.read(orderSettlementProvider('o1'));
      final baseline = container.read(orderDetailProvider('o1')).order!;
      orders.onRecordPayment = () async {
        orders.current = _order(paid: true, version: 6);
        return Success(_receipt());
      };
      orders.onDetail = () async =>
          const Error(Failure(type: FailureType.network, message: 'Mất mạng'));
      expect(
        await controller.pay(baseline, OrderPaymentMethod.cash),
        isA<Error<OrderDetail>>(),
      );
      expect(controller.paymentRecordedAwaitingRefresh, true);
      subscription.close();
      await container.pump();
      expect(
        identical(controller, container.read(orderSettlementProvider('o1'))),
        true,
      );
      orders.onDetail = null;
      final reopened = container.listen(
        orderSettlementProvider('o1'),
        (_, _) {},
      );
      addTearDown(reopened.close);
      expect(await controller.refresh(), isA<Success<OrderDetail>>());
      expect(controller.paymentRecordedAwaitingRefresh, false);
      expect(orders.paymentCalls, hasLength(1));
    },
  );

  test(
    'late payment after logout ignores old scope and disposed order event stream',
    () async {
      final reportedErrors = <FlutterErrorDetails>[];
      final originalErrorHandler = FlutterError.onError;
      FlutterError.onError = reportedErrors.add;
      addTearDown(() => FlutterError.onError = originalErrorHandler);
      final orders = FakeOrders()..current = _order();
      final auth = await _auth();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          orderRepositoryProvider.overrideWithValue(orders),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        orderSettlementProvider('o1'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container.pump();
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      final controller = container.read(orderSettlementProvider('o1'));
      final response = Completer<Result<OrderPayment>>();
      orders.onRecordPayment = () => response.future;
      final pending = controller.pay(
        container.read(orderDetailProvider('o1')).order!,
        OrderPaymentMethod.cash,
      );
      await container.pump();
      await auth.logout();
      await container.pump();
      response.complete(Success(_receipt()));
      expect(await pending, isA<Error<OrderDetail>>());
      expect(controller.current, false);
      expect(reportedErrors, isEmpty);
    },
  );
}
