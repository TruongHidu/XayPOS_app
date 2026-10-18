import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_item_action.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_detail_screen.dart';
import '../../helpers/auth_fakes.dart';
import 'order_fakes.dart';

const _rights = {
  'ORDER_VIEW',
  'ORDER_CANCEL',
  'ORDER_COMPLETE',
  'ORDER_MARK_SERVED',
  'KITCHEN_START_COOKING',
  'KITCHEN_MARK_READY',
};
OrderDetail _order({
  String line = 'PENDING',
  bool paid = false,
  int version = 5,
  String status = 'PREPARING',
}) => OrderDto.detail(
  orderJson(status: status, confirmed: true, lineStatus: line, version: version)
    ..['paymentStatus'] = paid ? 'PAID' : 'UNPAID'
    ..['paidAmount'] = paid ? 100000 : 0
    ..['completedAt'] = status == 'COMPLETED' ? '2026-10-18T00:00:00Z' : null,
);

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeOrders orders, {
  Set<String> rights = _rights,
  Set<String> features = const {'ORDER_MANAGEMENT', 'KITCHEN_DISPLAY'},
  double width = 1200,
  double scale = 1,
  bool keyboard = false,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  if (keyboard) tester.view.viewInsets = const FakeViewPadding(bottom: 280);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final auth = makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: rights)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: features)),
  );
  await auth.login(
    const LoginCredentials(email: 'items@example.com', password: 'password'),
  );
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      orderRepositoryProvider.overrideWithValue(orders),
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
        home: const Scaffold(body: OrderDetailScreen(id: 'o1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final action in OrderItemAction.values) {
    testWidgets(
      'tap ${action.source.code} offers exactly the next transition',
      (tester) async {
        final orders = FakeOrders()..current = _order(line: action.source.code);
        orders.onTransition = () async => Success(
          orders.current = _order(line: action.target.code, version: 7),
        );
        final container = await _pump(tester, orders);
        await _tap(
          tester,
          find.byKey(const ValueKey('order-line-actions-line1')),
        );
        expect(orders.itemTransitions, isEmpty);
        expect(find.text(action.label), findsOneWidget);
        await _tap(tester, find.text(action.label));
        expect(orders.itemTransitions.single, ('o1', 'line1', 5, action));
        expect(
          container.read(orderDetailProvider('o1')).order!.items.single.status,
          action.target,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'pending on PREPARING can cancel through the existing reason form',
    (tester) async {
      final orders = FakeOrders()..current = _order();
      orders.onWrite = () async => Success(
        orders.current = _order(
          line: 'CANCELLED',
          version: 7,
          status: 'CANCELLED',
        ),
      );
      await _pump(tester, orders);
      await _tap(
        tester,
        find.byKey(const ValueKey('order-line-actions-line1')),
      );
      await _tap(tester, find.widgetWithText(TextButton, 'Hủy món').last);
      await tester.enterText(find.byType(TextFormField).last, 'Khách đổi món');
      await _tap(tester, find.text('Xác nhận'));
      expect(orders.writes.single, ('cancelLine', 5));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('cooking has no cancel action and view-only cannot advance', (
    tester,
  ) async {
    final orders = FakeOrders()..current = _order(line: 'COOKING');
    await _pump(tester, orders, rights: {'ORDER_VIEW'});
    await _tap(tester, find.byKey(const ValueKey('order-line-actions-line1')));
    expect(find.text('Hủy món'), findsNothing);
    final next = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Đã chế biến xong'),
    );
    expect(next.onPressed, isNull);
    expect(orders.itemTransitions, isEmpty);
  });
  testWidgets(
    'paid pending order confirms served-all then completes without kitchen feature',
    (tester) async {
      final orders = FakeOrders()..current = _order(paid: true);
      orders.onMarkAllServed = () async => Success(
        orders.current = _order(
          line: 'SERVED',
          paid: true,
          version: 8,
          status: 'SERVED',
        ),
      );
      orders.onComplete = () async => Success(
        orders.current = _order(
          line: 'SERVED',
          paid: true,
          version: 10,
          status: 'COMPLETED',
        ),
      );
      await _pump(
        tester,
        orders,
        rights: {'ORDER_VIEW', 'ORDER_COMPLETE', 'ORDER_MARK_SERVED'},
        features: {'ORDER_MANAGEMENT'},
      );
      await _tap(tester, find.text('Hoàn tất đơn'));
      expect(orders.servedBatches, isEmpty);
      expect(orders.completes, isEmpty);
      expect(
        find.textContaining('Bạn xác nhận đã phục vụ thực tế tất cả món'),
        findsOneWidget,
      );
      await _tap(tester, find.text('Xác nhận hoàn tất'));
      expect(orders.servedBatches.single, ('o1', 5));
      expect(orders.completes.single, ('o1', 8));
      expect(find.text('Đã hoàn tất'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'partial failure shows that service succeeded and preserves that state',
    (tester) async {
      final orders = FakeOrders()..current = _order(paid: true);
      orders.onMarkAllServed = () async => Success(
        orders.current = _order(
          line: 'SERVED',
          paid: true,
          version: 8,
          status: 'SERVED',
        ),
      );
      orders.onComplete = () async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'CONCURRENT_ORDER_UPDATE',
          message: 'Đơn đã thay đổi',
        ),
      );
      final container = await _pump(tester, orders);
      await _tap(tester, find.text('Hoàn tất đơn'));
      await _tap(tester, find.text('Xác nhận hoàn tất'));
      expect(
        find.textContaining('Các món đã được đánh dấu phục vụ.'),
        findsOneWidget,
      );
      expect(
        container.read(orderDetailProvider('o1')).order!.items.single.status,
        OrderItemStatus.served,
      );
      expect(orders.servedBatches, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'missing bulk permission keeps completion disabled for unserved items',
    (tester) async {
      final orders = FakeOrders()..current = _order(paid: true);
      await _pump(tester, orders, rights: {'ORDER_VIEW', 'ORDER_COMPLETE'});
      final button = tester.widget<FilledButton>(
        find
            .ancestor(
              of: find.text('Hoàn tất đơn'),
              matching: find.byWidgetPredicate(
                (widget) => widget is FilledButton,
              ),
            )
            .first,
      );
      expect(button.onPressed, isNull);
      expect(orders.servedBatches, isEmpty);
    },
  );
  for (final width in [320.0, 800.0]) {
    testWidgets(
      'line and completion dialogs fit $width px, text200 and keyboard',
      (tester) async {
        final orders = FakeOrders()..current = _order(paid: true);
        await _pump(tester, orders, width: width, scale: 2, keyboard: true);
        await _tap(tester, find.text('Phở bò'));
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('Đóng'));
        await _tap(tester, find.text('Hoàn tất đơn'));
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('Đóng'));
        expect(orders.servedBatches, isEmpty);
        expect(orders.completes, isEmpty);
      },
    );
  }
}
