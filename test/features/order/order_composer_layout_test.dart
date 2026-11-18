import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_create_screen.dart';
import 'order_fakes.dart';
import 'order_table_workspace_test.dart' show tableId, tableData;
import 'order_widget_test.dart' show pumpOrder;
import '../tables/table_fakes.dart';

void _size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('a dish shows only + until it is in the cart, then − n +', (
    tester,
  ) async {
    _size(tester, const Size(390, 800));
    await pumpOrder(tester, child: const OrderCreateScreen(takeaway: true));
    expect(find.byTooltip('Thêm Trà đào'), findsOneWidget);
    expect(find.byTooltip('Bớt Trà đào'), findsNothing);

    await tester.tap(find.byTooltip('Thêm Trà đào'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Bớt Trà đào'), findsOneWidget);
    expect(cartCount(1), findsOneWidget);
    // The count is a small pill beside "Giỏ", never stretched by the tab.
    final pill = tester.getSize(find.byKey(const ValueKey('cart-count')));
    expect(pill.height, 20);
    expect(pill.width, 20);

    // Back to zero: the card returns to a single +, the cart empties.
    await tester.tap(find.byTooltip('Bớt Trà đào'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Bớt Trà đào'), findsNothing);
    expect(cartCount(0), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('customer details fold away but stay in the form', (
    tester,
  ) async {
    _size(tester, const Size(390, 800));
    await pumpOrder(
      tester,
      tables: TableServer()..table = tableData(occupied: false),
      child: const OrderCreateScreen(tableId: tableId),
    );
    await tester.tap(find.widgetWithText(Tab, 'Giỏ'));
    await tester.pumpAndSettle();

    final name = find.widgetWithText(
      TextFormField,
      'Tên khách (không bắt buộc)',
    );
    expect(find.text('Thông tin khách'), findsOneWidget);
    expect(find.textContaining('Không bắt buộc'), findsOneWidget);
    // Folded, yet mounted so the form still checks the fields.
    expect(name, findsNothing);
    expect(
      find.widgetWithText(
        TextFormField,
        'Tên khách (không bắt buộc)',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Ghi chú đơn'), findsOneWidget);

    await tester.tap(find.text('Thông tin khách'));
    await tester.pumpAndSettle();
    expect(name, findsOneWidget);
    await tester.enterText(name, 'Anh Nam');
    await tester.pumpAndSettle();
    // The folded row names who the order is for.
    expect(find.textContaining('Anh Nam'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('beside the menu, the cart pane holds the total and Gửi đơn', (
    tester,
  ) async {
    _size(tester, const Size(1280, 800));
    await pumpOrder(tester, child: const OrderCreateScreen(takeaway: true));
    const pane = ValueKey('order-cart-pane');
    expect(
      find.descendant(of: find.byKey(pane), matching: find.text('Gửi đơn')),
      findsOneWidget,
    );
    expect(find.text('Xem đơn'), findsNothing);
    await tester.tap(find.byTooltip('Thêm Trà đào'));
    await tester.pumpAndSettle();
    expect(cartCount(1), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(pane),
        matching: find.byKey(const ValueKey('order-cart-total')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
