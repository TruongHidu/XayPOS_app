import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_payment.dart';
import 'package:pos_saas_app/features/order/domain/use_cases/order_use_cases.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_detail_controller.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_events.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_settlement_controller.dart';

import '../../helpers/auth_fakes.dart';
import 'order_fakes.dart';

const _permissions = {
  'ORDER_VIEW',
  'PAYMENT_CREATE',
  'PAYMENT_CONFIRM',
  'ORDER_COMPLETE',
  'TABLE_CLOSE',
};
const _features = {
  'ORDER_MANAGEMENT',
  'PAYMENT_MANAGEMENT',
  'TABLE_MANAGEMENT',
};
const _conflict = Failure(
  type: FailureType.conflict,
  code: 'CONCURRENT_ORDER_UPDATE',
  message: 'Đơn đã thay đổi.',
);

AppSession _session({
  Set<String> permissions = _permissions,
  Set<String> features = _features,
  String restaurantId = 'restaurant-1',
}) => makeAppSession(
  permissions: permissions,
  features: features,
  restaurantId: restaurantId,
);

OrderDetail _order({
  int version = 5,
  String status = 'SERVED',
  String lineStatus = 'SERVED',
  bool paid = false,
  bool dineIn = false,
}) => OrderDto.detail(
  orderJson(
      version: version,
      status: status,
      confirmed: true,
      lineStatus: lineStatus,
    )
    ..['paymentStatus'] = paid ? 'PAID' : 'UNPAID'
    ..['paidAmount'] = paid ? 100000 : 0
    ..['serviceType'] = dineIn ? 'DINE_IN' : 'TAKEAWAY'
    ..['tableSessionId'] = dineIn ? sessionId : null
    ..['completedAt'] = status == 'COMPLETED' ? '2026-10-17T00:00:00Z' : null,
);

OrderPayment _receipt(RecordOrderPaymentInput input) => OrderPayment(
  id: 'payment1',
  orderId: 'o1',
  paymentCode: 'PAY-TEST',
  amount: input.amount,
  currencyCode: 'VND',
  paymentMethod: input.paymentMethod,
  confirmationSource: PaymentConfirmationSource.staffManual,
  provider: null,
  status: PaymentRecordStatus.success,
  referenceNo: input.normalizedReferenceNo,
  requestedAt: DateTime.utc(2026, 10, 17),
  paidAt: DateTime.utc(2026, 10, 17),
  createdBy: 'u1',
);

class _Harness {
  _Harness({AppSession? session, OrderDetail? initial}) {
    who = session ?? _session();
    repo.current = initial ?? _order();
    read = detail(repo, () => who, events: events);
    settlement = OrderSettlementController(
      id: 'o1',
      session: () => who,
      events: events,
      getOrder: GetOrderDetail(repo),
      recordPayment: RecordOrderPayment(repo),
      completeOrder: CompleteOrder(repo),
      keys: keys,
      root: () => read.order,
      beforeSend: read.beginSubmission,
      onApplied: read.applySubmission,
      appliedSource: () => read,
      externalBlocked: () => externallyBlocked,
      onCompleted: (order) => completions.add(order),
    );
  }

  final repo = FakeOrders();
  final keys = TestKeys();
  final events = OrderEvents();
  final completions = <OrderDetail>[];
  late AppSession? who;
  late OrderDetailController read;
  late OrderSettlementController settlement;
  bool externallyBlocked = false;

  void close() {
    settlement.dispose();
    read.dispose();
    events.dispose();
  }
}

void main() {
  test(
    'payment readback supplies new version for completion and emits events',
    () async {
      final h = _Harness(initial: _order(dineIn: true));
      addTearDown(h.close);
      final c = h.settlement;
      h.repo.onDetail = () async =>
          Success(_order(version: 6, paid: true, dineIn: true));
      expect(c.canPay, true);
      expect(c.canComplete, false);
      expect(
        await c.pay(h.read.order!, OrderPaymentMethod.cash),
        isA<Success<OrderDetail>>(),
      );
      expect(h.repo.paymentCalls.single.$2.expectedOrderVersion, 5);
      expect(h.repo.detailCalls, 1);
      expect(h.read.order!.version, 6);
      expect(c.payment, isNotNull);
      expect(c.canPay, false);
      expect(c.canComplete, true);
      h.repo.onComplete = () async => Success(
        _order(version: 7, paid: true, status: 'COMPLETED', dineIn: true),
      );
      expect(await c.complete(h.read.order!), isA<Success<OrderDetail>>());
      expect(h.repo.completes.single, ('o1', 6));
      expect(h.read.order!.summary.status, OrderStatus.completed);
      expect(h.completions.single.summary.tableSessionId, sessionId);
      expect(h.events.revision, 2);
      expect(h.events.unresolved('o1'), false);
    },
  );

  test('double click creates one immutable payment intent', () async {
    final h = _Harness();
    addTearDown(h.close);
    final gate = Completer<Result<OrderPayment>>();
    h.repo.onRecordPayment = () => gate.future;
    h.repo.onDetail = () async => Success(_order(version: 6, paid: true));
    final first = h.settlement.pay(h.read.order!, OrderPaymentMethod.cash);
    expect(h.settlement.busy, true);
    expect(
      await h.settlement.pay(h.read.order!, OrderPaymentMethod.cash),
      isA<Error<OrderDetail>>(),
    );
    expect(h.repo.paymentCalls.length, 1);
    expect(h.keys.calls, 1);
    gate.complete(Success(_receipt(h.repo.paymentCalls.single.$2)));
    await first;
    expect(h.settlement.busy, false);
    expect(h.repo.detailCalls, 1);
  });

  test(
    'timeout retry retains exact key payload and original version after visible order changes',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      h.repo.onRecordPayment = () async => const Error(networkFailure);
      await h.settlement.pay(
        h.read.order!,
        OrderPaymentMethod.transfer,
        referenceNo: ' BANK-123 ',
      );
      final intent = h.repo.paymentCalls.single;
      expect(h.settlement.paymentOutcomeUnknown, true);
      expect(h.events.unresolved('o1'), true);
      expect(h.settlement.canPay, false);
      h.read.applySubmission(_order(version: 9, paid: true));
      h.repo.onRecordPayment = () async => Success(_receipt(intent.$2));
      h.repo.onDetail = () async => Success(_order(version: 9, paid: true));
      expect(h.settlement.canRetryPayment, true);
      await h.settlement.retryPayment();
      final replay = h.repo.paymentCalls.last;
      expect(identical(replay.$2, intent.$2), true);
      expect(replay.$3, intent.$3);
      expect(replay.$2.expectedOrderVersion, 5);
      expect(replay.$2.normalizedReferenceNo, 'BANK-123');
      expect(h.keys.calls, 1);
      expect(h.settlement.uncertain, false);
      expect(h.events.unresolved('o1'), false);
    },
  );

  test(
    'known receipt with failed GET permits only readback, never a second POST',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      h.repo.onDetail = () async => const Error(networkFailure);
      expect(
        await h.settlement.pay(h.read.order!, OrderPaymentMethod.cash),
        isA<Error<OrderDetail>>(),
      );
      expect(h.settlement.payment, isNotNull);
      expect(h.settlement.paymentRecordedAwaitingRefresh, true);
      expect(h.settlement.paymentOutcomeUnknown, false);
      expect(h.settlement.canRetryPayment, false);
      expect(await h.settlement.retryPayment(), isA<Error<OrderDetail>>());
      expect(
        await h.settlement.pay(h.read.order!, OrderPaymentMethod.cash),
        isA<Error<OrderDetail>>(),
      );
      h.repo.onDetail = () async => Success(_order(version: 6, paid: true));
      await h.settlement.refresh();
      expect(h.repo.paymentCalls.length, 1);
      expect(h.settlement.paymentRecordedAwaitingRefresh, false);
      expect(h.settlement.canComplete, true);
    },
  );

  test(
    'GET showing unpaid cannot resolve an unknown payment outcome',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      h.repo.onRecordPayment = () async => const Error(networkFailure);
      await h.settlement.pay(h.read.order!, OrderPaymentMethod.cash);
      expect(await h.settlement.check(), isA<Error<OrderDetail>>());
      expect(h.settlement.paymentOutcomeUnknown, true);
      expect(h.settlement.canRetryPayment, true);
      expect(h.settlement.canPay, false);
      h.repo.onDetail = () async => Success(_order(version: 6, paid: true));
      expect(await h.settlement.check(), isA<Error<OrderDetail>>());
      expect(h.settlement.paymentOutcomeUnknown, true);
      expect(h.settlement.pending, isNotNull);
      expect(h.read.order!.summary.paymentStatus, OrderPaymentStatus.paid);
      expect(h.repo.paymentCalls.length, 1);
    },
  );

  test(
    'reused payment key stays blocked after unverified GET changes displayed failure',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      h.repo.onRecordPayment = () async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'PAYMENT_IDEMPOTENCY_KEY_REUSED',
          message: 'Key conflict',
        ),
      );
      await h.settlement.pay(h.read.order!, OrderPaymentMethod.cash);
      expect(h.settlement.keyConflict, true);
      await h.settlement.refresh();
      expect(h.settlement.failure?.code, 'PAYMENT_AWAITING_VERIFICATION');
      expect(h.settlement.keyConflict, true);
      expect(h.settlement.canRetryPayment, false);
      await h.settlement.retryPayment();
      expect(h.repo.paymentCalls.length, 1);
    },
  );

  test(
    'transfer validation does not allocate an idempotency key or POST',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      await h.settlement.pay(
        h.read.order!,
        OrderPaymentMethod.transfer,
        referenceNo: '  ',
      );
      expect(h.settlement.failure!.fieldErrors, contains('referenceNo'));
      expect(h.repo.paymentCalls, isEmpty);
      expect(h.keys.calls, 0);
      expect(h.settlement.canPay, true);
    },
  );

  test(
    'conflict requires a fresh read and explicit review before new intent',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      h.repo.onRecordPayment = () async => const Error(_conflict);
      await h.settlement.pay(h.read.order!, OrderPaymentMethod.cash);
      expect(h.settlement.needsReview, true);
      expect(h.settlement.reviewCurrent(), false);
      await h.settlement.refresh();
      expect(
        h.settlement.reviewCurrent(),
        false,
        reason: 'Same-version read cannot acknowledge concurrent update',
      );
      h.repo.current = _order(version: 6);
      await h.settlement.refresh();
      expect(h.settlement.needsReview, true);
      expect(h.settlement.canPay, false);
      expect(h.settlement.reviewCurrent(), true);
      expect(h.settlement.canPay, true);
      h.repo.onRecordPayment = null;
      h.repo.onDetail = () async => Success(_order(version: 7, paid: true));
      await h.settlement.pay(h.read.order!, OrderPaymentMethod.cash);
      expect(h.repo.paymentCalls.last.$2.expectedOrderVersion, 6);
      expect(h.repo.paymentCalls.last.$3, 'key-2');
    },
  );

  test('stale dialog baseline is rejected before any HTTP', () async {
    final h = _Harness();
    addTearDown(h.close);
    final old = h.read.order!;
    h.read.applySubmission(_order(version: 6));
    await h.settlement.pay(old, OrderPaymentMethod.cash);
    expect(h.settlement.failure?.code, 'CONCURRENT_ORDER_UPDATE');
    expect(h.repo.paymentCalls, isEmpty);
    expect(h.settlement.needsReview, true);
  });

  test('payment command invalidates pre-command detail GET', () async {
    final h = _Harness();
    addTearDown(h.close);
    final oldGet = Completer<Result<OrderDetail>>();
    h.repo.onDetail = () => oldGet.future;
    final read = h.read.load();
    h.repo.onDetail = () async => Success(_order(version: 6, paid: true));
    await h.settlement.pay(h.read.order!, OrderPaymentMethod.cash);
    oldGet.complete(Success(_order()));
    await read;
    expect(h.read.order!.version, 6);
    expect(h.read.order!.summary.paymentStatus, OrderPaymentStatus.paid);
  });

  test(
    'tenant change discards late payment response and performs no old-scope GET',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      final gate = Completer<Result<OrderPayment>>();
      h.repo.onRecordPayment = () => gate.future;
      final send = h.settlement.pay(h.read.order!, OrderPaymentMethod.cash);
      h.who = _session(restaurantId: 'another-tenant');
      gate.complete(Success(_receipt(h.repo.paymentCalls.single.$2)));
      expect(await send, isA<Error<OrderDetail>>());
      expect(h.repo.detailCalls, 0);
      expect(h.settlement.payment, isNull);
      expect(h.events.revision, 0);
      expect(h.read.order!.version, 5);
    },
  );

  test('token rotation preserves pending intent and exact replay', () async {
    final h = _Harness();
    addTearDown(h.close);
    h.repo.onRecordPayment = () async => const Error(networkFailure);
    await h.settlement.pay(h.read.order!, OrderPaymentMethod.cash);
    h.who = h.who!.copyWithAuth(
      user: h.who!.authenticatedUser,
      tokens: makeTokens(accessToken: 'rotated'),
    );
    expect(h.settlement.current, true);
    expect(h.settlement.canRetryPayment, true);
    h.repo.onRecordPayment = null;
    h.repo.onDetail = () async => Success(_order(version: 6, paid: true));
    await h.settlement.retryPayment();
    expect(h.repo.paymentCalls.last.$3, h.repo.paymentCalls.first.$3);
  });

  test('compound payment permission and feature are both required', () async {
    for (final session in [
      _session(permissions: {..._permissions}..remove('PAYMENT_CONFIRM')),
      _session(features: {..._features}..remove('PAYMENT_MANAGEMENT')),
    ]) {
      final h = _Harness(session: session);
      expect(h.settlement.canPay, false);
      await h.settlement.pay(h.read.order!, OrderPaymentMethod.cash);
      expect(h.repo.paymentCalls, isEmpty);
      h.close();
    }
  });

  test(
    'known payment without ORDER_VIEW retains receipt and issues no GET',
    () async {
      final h = _Harness(
        session: _session(permissions: {..._permissions}..remove('ORDER_VIEW')),
      );
      addTearDown(h.close);
      await h.settlement.pay(h.read.order!, OrderPaymentMethod.cash);
      expect(h.repo.paymentCalls.length, 1);
      expect(h.repo.detailCalls, 0);
      expect(h.settlement.paymentRecordedAwaitingRefresh, true);
      expect(h.settlement.failure?.code, 'ORDER_VIEW_REQUIRED');
    },
  );

  test(
    'completion requires served lines and table-close authority for dine in',
    () async {
      final unserved = _Harness(
        initial: _order(paid: true, lineStatus: 'READY'),
      );
      final noClose = _Harness(
        initial: _order(paid: true, dineIn: true),
        session: _session(
          permissions: {..._permissions}..remove('TABLE_CLOSE'),
        ),
      );
      addTearDown(unserved.close);
      addTearDown(noClose.close);
      expect(unserved.settlement.canComplete, false);
      expect(noClose.settlement.canComplete, false);
      await unserved.settlement.complete(unserved.read.order!);
      await noClose.settlement.complete(noClose.read.order!);
      expect(unserved.repo.completes, isEmpty);
      expect(noClose.repo.completes, isEmpty);
    },
  );

  test(
    'unknown completion checks before allowing an explicitly reviewed new command',
    () async {
      final h = _Harness(initial: _order(paid: true));
      addTearDown(h.close);
      h.repo.onComplete = () async => const Error(networkFailure);
      await h.settlement.complete(h.read.order!);
      expect(h.settlement.completeOutcomeUnknown, true);
      expect(h.settlement.completionAttempt, true);
      expect(h.settlement.canComplete, false);
      await h.settlement.complete(h.read.order!);
      expect(h.repo.completes.length, 1);
      await h.settlement.check();
      expect(h.settlement.completeOutcomeUnknown, false);
      expect(h.settlement.needsReview, true);
      expect(h.settlement.reviewCurrent(), true);
      h.repo.onComplete = () async =>
          Success(_order(version: 6, paid: true, status: 'COMPLETED'));
      await h.settlement.complete(h.read.order!);
      expect(h.repo.completes.length, 2);
      expect(h.settlement.canComplete, false);
    },
  );

  test(
    'completion timeout resolved by GET completed does not POST again',
    () async {
      final h = _Harness(initial: _order(paid: true, dineIn: true));
      addTearDown(h.close);
      h.repo.onComplete = () async => const Error(networkFailure);
      await h.settlement.complete(h.read.order!);
      h.repo.onDetail = () async => Success(
        _order(version: 6, paid: true, dineIn: true, status: 'COMPLETED'),
      );
      await h.settlement.check();
      expect(h.repo.completes.length, 1);
      expect(h.settlement.ownsMutationBlock, false);
      expect(h.completions.length, 1);
      expect(h.read.order!.summary.status, OrderStatus.completed);
    },
  );

  test(
    'external verification or another order mutation blocks fresh requests',
    () async {
      final h = _Harness();
      addTearDown(h.close);
      h.externallyBlocked = true;
      expect(h.settlement.canPay, false);
      h.externallyBlocked = false;
      h.events.lock('o1');
      await h.settlement.pay(h.read.order!, OrderPaymentMethod.cash);
      expect(h.repo.paymentCalls, isEmpty);
      h.events.unlock('o1');
      expect(h.settlement.canPay, true);
    },
  );

  test('paid readback must advance the payment baseline version', () async {
    final h = _Harness();
    addTearDown(h.close);
    h.repo.onDetail = () async => Success(_order(paid: true));
    await h.settlement.pay(h.read.order!, OrderPaymentMethod.cash);
    expect(h.settlement.paymentRecordedAwaitingRefresh, true);
    expect(h.read.order!.summary.paymentStatus, OrderPaymentStatus.unpaid);
    expect(h.settlement.canComplete, false);
    h.repo.onDetail = () async => Success(_order(version: 6, paid: true));
    await h.settlement.refresh();
    expect(h.settlement.paymentRecordedAwaitingRefresh, false);
    expect(h.repo.paymentCalls.length, 1);
    expect(h.read.order!.version, 6);
  });

  test(
    'invalid completed response stays unresolved until a verified GET',
    () async {
      final h = _Harness(initial: _order(paid: true));
      addTearDown(h.close);
      h.repo.onComplete = () async =>
          Success(_order(version: 6, status: 'COMPLETED'));
      await h.settlement.complete(h.read.order!);
      expect(h.settlement.completeOutcomeUnknown, true);
      expect(h.completions, isEmpty);
      h.repo.onDetail = () async => Success(
        _order(
          version: 6,
          paid: true,
          status: 'COMPLETED',
          lineStatus: 'READY',
        ),
      );
      await h.settlement.refresh();
      expect(h.settlement.completeOutcomeUnknown, true);
      expect(h.completions, isEmpty);
      h.repo.onDetail = () async =>
          Success(_order(version: 6, paid: true, status: 'COMPLETED'));
      await h.settlement.refresh();
      expect(h.settlement.completeOutcomeUnknown, false);
      expect(h.repo.completes.length, 1);
      expect(h.completions.length, 1);
    },
  );

  test('stale completion retains completion recovery origin', () async {
    final h = _Harness(initial: _order(paid: true));
    addTearDown(h.close);
    final old = h.read.order!;
    h.read.applySubmission(_order(version: 6, paid: true));
    await h.settlement.complete(old);
    expect(h.settlement.needsReview, true);
    expect(h.settlement.completionAttempt, true);
    expect(h.repo.completes, isEmpty);
  });
}
