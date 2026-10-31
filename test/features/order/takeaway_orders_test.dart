import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/ui/sidebar/app_sidebar_registry.dart';
import 'package:pos_saas_app/core/ui/sidebar/sidebar_filter.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_submission.dart';
import 'package:pos_saas_app/features/order/domain/policies/order_table_policy.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_create_screen.dart';
import 'package:pos_saas_app/features/order/presentation/screens/takeaway_orders_screen.dart';
import 'package:pos_saas_app/features/order/presentation/widgets/order_menu_picker.dart';
import 'package:pos_saas_app/features/order/presentation/widgets/order_payment_dialog.dart';
import 'package:pos_saas_app/features/order/presentation/widgets/takeaway_order_card.dart';
import 'order_fakes.dart';
import 'order_widget_test.dart' show pumpOrder;

const _permissions = {
  ...orderPermissions,
  'PAYMENT_CREATE',
  'PAYMENT_CONFIRM',
  'ORDER_COMPLETE',
};
const _features = {...orderFeatures, 'PAYMENT_MANAGEMENT'};

OrderDetail _order(
  String id, {
  String status = 'OPEN',
  bool paid = false,
  String? customer,
  String createdAt = '2026-10-08T00:00:00Z',
}) => OrderDto.detail(
  orderJson(status: status, confirmed: status != 'OPEN')
    ..['id'] = id
    ..['orderCode'] = 'OD-$id'
    ..['customerName'] = customer
    ..['createdAt'] = createdAt
    ..['paymentStatus'] = paid ? 'PAID' : 'UNPAID'
    ..['paidAmount'] = paid ? 100000 : 0,
);

/// Serves each order only for its own status, like the real list endpoint.
FakeOrders _board(List<OrderDetail> rows) {
  final orders = FakeOrders();
  orders.onList = (q) async => Success(
    OrderPage(
      content: [
        for (final row in rows)
          if (row.summary.status == q.status &&
              row.summary.serviceType == q.serviceType)
            row.summary,
      ],
      page: q.page,
      size: q.size,
      totalElements: 1,
      totalPages: 1,
    ),
  );
  return orders;
}

Future<void> _pump(
  WidgetTester tester,
  FakeOrders orders, {
  double width = 1200,
  double scale = 1,
  Set<String> permissions = _permissions,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await pumpOrder(
    tester,
    child: const TakeawayOrdersScreen(),
    orders: orders,
    permissions: permissions,
    features: _features,
    scale: scale,
  );
}

void main() {
  testWidgets('reads takeaway orders once per active status', (tester) async {
    final orders = _board([]);
    await _pump(tester, orders);
    expect(orders.queries.map((q) => (q.serviceType, q.status)).toSet(), {
      for (final status in OrderTablePolicy.servingStatuses)
        (ServiceType.takeaway, status),
    });
    expect(find.text('Chưa có đơn mang đi nào đang xử lý.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('orders land in their column, oldest first, with actions', (
    tester,
  ) async {
    await _pump(
      tester,
      _board([
        _order('a', customer: 'Anh Nam'),
        _order('b', status: 'PREPARING', createdAt: '2026-10-08T00:05:00Z'),
        _order('c', status: 'CONFIRMED', createdAt: '2026-10-08T00:01:00Z'),
        _order('d', status: 'READY', paid: true, customer: 'Chị Lan'),
      ]),
    );
    expect(find.text('Chờ xác nhận (1)'), findsOneWidget);
    expect(find.text('Đang làm (2)'), findsOneWidget);
    expect(find.text('Chờ giao / thanh toán (1)'), findsOneWidget);
    expect(find.text('Anh Nam'), findsOneWidget);
    expect(find.text('Khách lẻ'), findsNWidgets(2));
    // Within "Đang làm" the earlier order (c) comes first.
    expect(
      tester.getTopLeft(find.text('OD-c')).dy,
      lessThan(tester.getTopLeft(find.text('OD-b')).dy),
    );

    Finder inCard(String id, String text) => find.descendant(
      of: find.byKey(ValueKey('takeaway-order-$id')),
      matching: find.text(text),
    );
    expect(inCard('a', 'Xác nhận'), findsOneWidget);
    expect(inCard('a', 'Gọi thêm'), findsOneWidget);
    expect(inCard('a', 'Thanh toán'), findsNothing);
    expect(inCard('c', 'Thanh toán'), findsOneWidget);
    expect(inCard('d', 'Giao khách & hoàn tất'), findsOneWidget);
    expect(inCard('d', 'Thanh toán'), findsNothing);
    expect(inCard('d', 'Gọi thêm'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shortcuts follow permissions', (tester) async {
    await _pump(
      tester,
      _board([_order('c', status: 'CONFIRMED')]),
      permissions: {'ORDER_VIEW'},
    );
    expect(find.text('OD-c'), findsOneWidget);
    for (final action in TakeawayQuickAction.values) {
      expect(find.text(action.label), findsNothing);
    }
    expect(find.text('Tạo đơn mang đi'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pay shortcut loads the full order and opens payment', (
    tester,
  ) async {
    final order = _order('c', status: 'CONFIRMED');
    final orders = _board([order])..current = order;
    await _pump(tester, orders);
    await tester.tap(find.text('Thanh toán'));
    await tester.pumpAndSettle();
    expect(orders.detailCalls, greaterThan(0));
    expect(find.byType(OrderPaymentDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale shortcut explains instead of opening a dialog', (
    tester,
  ) async {
    final orders = _board([_order('c', status: 'CONFIRMED')])
      // Paid elsewhere since the board loaded.
      ..current = _order('c', status: 'CONFIRMED', paid: true);
    await _pump(tester, orders);
    await tester.tap(find.text('Thanh toán'));
    await tester.pumpAndSettle();
    expect(find.byType(OrderPaymentDialog), findsNothing);
    expect(
      find.text('Đơn không còn ở trạng thái chờ thanh toán.'),
      findsOneWidget,
    );
  });

  testWidgets('an order event reloads the board', (tester) async {
    final orders = _board([]);
    await _pump(tester, orders);
    final before = orders.queries.length;
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TakeawayOrdersScreen)),
    );
    container.read(orderEventsProvider).emit('o9', null);
    await tester.pumpAndSettle();
    expect(orders.queries.length, before + 5);
    // A local change to a dine-in session cannot be a takeaway order.
    container.read(orderEventsProvider).emit('o9', sessionId);
    await tester.pumpAndSettle();
    expect(orders.queries.length, before + 5);
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets('board fits $width px at 200% text', (tester) async {
      await _pump(
        tester,
        _board([
          _order('a', customer: 'Khách có tên rất dài để kiểm tra xuống dòng'),
          _order('d', status: 'READY', paid: true),
        ]),
        width: width,
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(TakeawayOrderCard), findsWidgets);
    });
  }

  group('quick takeaway composer', () {
    Future<FakeOrders> pumpComposer(
      WidgetTester tester, {
      double width = 800,
      double scale = 1,
      Set<String> permissions = _permissions,
    }) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final orders = FakeOrders();
      await pumpOrder(
        tester,
        orders: orders,
        permissions: permissions,
        features: _features,
        scale: scale,
        child: const OrderCreateScreen(takeaway: true),
      );
      return orders;
    }

    testWidgets('name sits above the menu; no guest count or draft button', (
      tester,
    ) async {
      final orders = await pumpComposer(tester);
      expect(
        find.byKey(const ValueKey('takeaway-customer-name')),
        findsOneWidget,
      );
      expect(find.text('Chưa gửi đơn'), findsNothing);
      expect(find.text('Tạo nháp'), findsNothing);
      await tester.tap(find.text('Xem đơn'));
      await tester.pumpAndSettle();
      expect(find.text('Số khách'), findsNothing);
      await tester.tap(find.text('Chọn món'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('takeaway-customer-name')),
        'Anh Nam',
      );
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi đơn'));
      await tester.pumpAndSettle();
      final sent = orders.creates.single.$1;
      expect(sent.customerName, 'Anh Nam');
      expect(sent.submissionMode, OrderSubmissionMode.submit);
      expect(tester.takeException(), isNull);
    });

    testWidgets('draft stays reachable from the overflow menu', (tester) async {
      final orders = await pumpComposer(tester);
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thao tác khác'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu nháp (chưa gửi bếp)'));
      await tester.pumpAndSettle();
      expect(
        orders.creates.single.$1.submissionMode,
        OrderSubmissionMode.draft,
      );
      expect(find.text('Đã tạo đơn nháp'), findsOneWidget);
      expect(find.text('Thanh toán ngay'), findsNothing);
    });

    testWidgets('after sending: pay now, then start the next order', (
      tester,
    ) async {
      final orders = await pumpComposer(tester);
      await tester.enterText(
        find.byKey(const ValueKey('takeaway-customer-name')),
        'Chị Lan',
      );
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi đơn'));
      await tester.pumpAndSettle();
      expect(find.text('Đã gửi đơn xuống bếp'), findsOneWidget);
      expect(find.text('OD-TEST'), findsOneWidget);
      expect(orders.creates, hasLength(1));

      await tester.tap(find.text('Thanh toán ngay'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderPaymentDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(OrderPaymentDialog))).pop();
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Tạo đơn khác'));
      await tester.tap(find.text('Tạo đơn khác'));
      await tester.pumpAndSettle();
      expect(find.text('Giỏ (0)'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('takeaway-customer-name')),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });

    for (final width in [320.0, 800.0]) {
      testWidgets('composer and confirmation fit $width px at 200% text', (
        tester,
      ) async {
        await pumpComposer(tester, width: width, scale: 2);
        await tester.tap(find.byTooltip('Thêm SĐT, ghi chú'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Ẩn SĐT và ghi chú'));
        await tester.pumpAndSettle();
        // Large text makes the menu card tall; scroll until "+" is on screen.
        await tester.scrollUntilVisible(
          find.byTooltip('Thêm Trà đào'),
          60,
          scrollable: find
              .descendant(
                of: find.byType(OrderMenuPicker),
                matching: find.byType(Scrollable),
              )
              .last,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Thêm Trà đào'));
        await tester.pumpAndSettle();
        expect(find.text('Giỏ (1)'), findsOneWidget);
        await tester.ensureVisible(find.text('Gửi đơn'));
        await tester.tap(find.text('Gửi đơn'));
        await tester.pumpAndSettle();
        expect(find.text('Đã gửi đơn xuống bếp'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('waited time reads naturally', () {
    final start = DateTime(2026, 10, 8, 8);
    expect(takeawayWaited(start, start), 'Vừa đặt');
    expect(
      takeawayWaited(start, start.add(const Duration(minutes: 5))),
      '5 phút',
    );
    expect(takeawayWaited(start, start.add(const Duration(hours: 1))), '1 giờ');
    expect(
      takeawayWaited(start, start.add(const Duration(minutes: 70))),
      '1 giờ 10 phút',
    );
  });

  test('route and sidebar follow order view access', () {
    final viewer = orderSession(permissions: {'ORDER_VIEW'});
    final nobody = orderSession(permissions: {'MENU_VIEW'});
    expect(AccessPolicy.canOpenRoute(viewer, '/app/takeaway'), isTrue);
    expect(AccessPolicy.canOpenRoute(viewer, '/app/takeaway/o1'), isTrue);
    expect(AccessPolicy.canOpenRoute(nobody, '/app/takeaway'), isFalse);
    bool visible(AppSession session) => filterCategories(
      session,
      AppSidebarRegistry.categories,
    ).expand((c) => c.items).any((i) => i.id == 'takeaway-orders');
    expect(visible(viewer), isTrue);
    expect(visible(nobody), isFalse);
  });
}
