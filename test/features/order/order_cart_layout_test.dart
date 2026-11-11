import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_append_screen.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_create_screen.dart';
import 'order_fakes.dart';
import 'order_widget_test.dart' show pumpOrder;

const _cartPane = ValueKey('order-cart-pane');
const _undo = ValueKey('cart-undo-remove');

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _inCart(Finder finder) =>
    find.descendant(of: find.byKey(_cartPane), matching: finder);

void main() {
  testWidgets('wide screen keeps the cart beside the menu', (tester) async {
    _size(tester, const Size(1280, 800));
    final orders = FakeOrders();
    await pumpOrder(
      tester,
      orders: orders,
      child: const OrderCreateScreen(takeaway: true),
    );
    expect(find.byKey(_cartPane), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Xem đơn'), findsNothing);
    expect(_inCart(find.text('Chưa chọn món nào.')), findsOneWidget);

    await tester.tap(find.byTooltip('Thêm Trà đào'));
    await tester.pumpAndSettle();
    expect(find.text('Giỏ (1)'), findsOneWidget);
    expect(_inCart(find.text('Trà đào')), findsOneWidget);

    await tester.tap(find.text('Gửi đơn'));
    await tester.pumpAndSettle();
    expect(orders.creates.single.$1.items.single.quantity.milliUnits, 1000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow screen keeps the tabs', (tester) async {
    _size(tester, const Size(400, 800));
    await pumpOrder(tester, child: const OrderCreateScreen(takeaway: true));
    expect(find.byKey(_cartPane), findsNothing);
    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Xem đơn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a removed line can be put back with its quantity', (
    tester,
  ) async {
    _size(tester, const Size(1280, 800));
    final orders = FakeOrders();
    await pumpOrder(
      tester,
      orders: orders,
      child: const OrderCreateScreen(takeaway: true),
    );
    await tester.tap(find.byTooltip('Thêm Trà đào'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Thêm Trà đào'));
    await tester.pumpAndSettle();
    expect(_inCart(find.textContaining('2 ')), findsOneWidget);

    await tester.tap(_inCart(find.text('Bỏ món')));
    await tester.pumpAndSettle();
    expect(find.text('Giỏ (0)'), findsOneWidget);
    expect(find.text('Đã bỏ Trà đào'), findsOneWidget);
    // The undo stands in for the line, so the empty-cart text stays away.
    expect(_inCart(find.text('Chưa chọn món nào.')), findsNothing);

    await tester.tap(find.byKey(_undo));
    await tester.pumpAndSettle();
    expect(find.text('Giỏ (1)'), findsOneWidget);
    expect(find.byKey(_undo), findsNothing);

    await tester.tap(find.text('Gửi đơn'));
    await tester.pumpAndSettle();
    expect(orders.creates.single.$1.items.single.quantity.milliUnits, 2000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the undo goes away on its own', (tester) async {
    _size(tester, const Size(1280, 800));
    await pumpOrder(tester, child: const OrderCreateScreen(takeaway: true));
    await tester.tap(find.byTooltip('Thêm Trà đào'));
    await tester.pumpAndSettle();
    await tester.tap(_inCart(find.text('Bỏ món')));
    await tester.pumpAndSettle();
    expect(find.byKey(_undo), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.byKey(_undo), findsNothing);
    expect(_inCart(find.text('Chưa chọn món nào.')), findsOneWidget);
  });

  testWidgets('swiping a line away on a phone offers the same undo', (
    tester,
  ) async {
    _size(tester, const Size(400, 800));
    await pumpOrder(tester, child: const OrderCreateScreen(takeaway: true));
    await tester.tap(find.byTooltip('Thêm Trà đào'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xem đơn'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Trà đào').last, const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Giỏ (0)'), findsOneWidget);
    await tester.tap(find.byKey(_undo));
    await tester.pumpAndSettle();
    expect(find.text('Giỏ (1)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding to a served order gets the same side cart and undo', (
    tester,
  ) async {
    _size(tester, const Size(1280, 800));
    final orders = FakeOrders()
      ..current = OrderDto.detail(
        orderJson(status: 'CONFIRMED', confirmed: true),
      );
    await pumpOrder(
      tester,
      orders: orders,
      child: const OrderAppendScreen(orderId: 'o1', tableName: 'Bàn 1'),
    );
    expect(find.byKey(_cartPane), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.text('Xem món gọi thêm'), findsNothing);

    await tester.tap(find.byTooltip('Thêm Trà đào'));
    await tester.pumpAndSettle();
    expect(_inCart(find.text('Trà đào')), findsOneWidget);
    await tester.tap(_inCart(find.text('Bỏ món')));
    await tester.pumpAndSettle();
    expect(_inCart(find.text('Trà đào')), findsNothing);
    expect(find.text('Đã bỏ Trà đào'), findsOneWidget);
    await tester.tap(find.byKey(_undo));
    await tester.pumpAndSettle();
    expect(_inCart(find.text('Trà đào')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
