import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_line_configuration.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_quantity.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_cart_lines.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_draft_controller.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_append_screen.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_create_screen.dart';
import '../menu/menu_fakes.dart' show itemJson;
import 'order_fakes.dart';
import 'order_widget_test.dart' show pumpOrder;

const _sheet = ValueKey('menu-item-sheet');
const _plus = ValueKey('menu-item-sheet-quantity-plus');
const _note = ValueKey('menu-item-sheet-note');
const _add = ValueKey('menu-item-sheet-add');

void _phone(WidgetTester tester, {Size size = const Size(400, 800)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _openDish(WidgetTester tester) async {
  await tester.tap(find.text('Trà đào').first);
  await tester.pumpAndSettle();
  expect(find.byKey(_sheet), findsOneWidget);
}

Future<void> _addFromSheet(
  WidgetTester tester, {
  int extra = 0,
  String note = '',
}) async {
  for (var i = 0; i < extra; i++) {
    await tester.tap(find.byKey(_plus));
    await tester.pump();
  }
  if (note.isNotEmpty) await tester.enterText(find.byKey(_note), note);
  await tester.tap(find.byKey(_add));
  await tester.pumpAndSettle();
  expect(find.byKey(_sheet), findsNothing);
}

void main() {
  group('line configuration', () {
    test('a blank or padded note is the same as none', () {
      expect(
        OrderLineConfiguration(menuItemId: 'i1', note: '  '),
        OrderLineConfiguration(menuItemId: 'i1'),
      );
      expect(
        OrderLineConfiguration(menuItemId: 'i1', note: ' ít cay '),
        OrderLineConfiguration(menuItemId: 'i1', note: 'ít cay'),
      );
      expect(
        OrderLineConfiguration(menuItemId: 'i1', note: 'ít cay'),
        isNot(OrderLineConfiguration(menuItemId: 'i1')),
      );
      expect(
        OrderLineConfiguration(menuItemId: 'i1'),
        isNot(OrderLineConfiguration(menuItemId: 'i2')),
      );
    });

    test('the same configuration grows, another one starts a line', () {
      final item = MenuItemDto.fromJson(itemJson()).toEntity();
      var ids = 0;
      String next() => 'line-${++ids}';
      final lines = <OrderDraftLine>[];
      expect(
        addToLines(lines, item, OrderQuantity.one, note: 'ít cay', newId: next),
        CartAddResult.added,
      );
      expect(
        addToLines(
          lines,
          item,
          OrderQuantity.one,
          note: ' ít cay',
          newId: next,
        ),
        CartAddResult.merged,
      );
      expect(
        addToLines(lines, item, OrderQuantity.one, newId: next),
        CartAddResult.added,
      );
      expect(lines.map((l) => (l.quantity.milliUnits, l.note)), [
        (2000, 'ít cay'),
        (1000, null),
      ]);
      expect(
        addToLines(lines, item, OrderQuantity.one, merge: false, newId: next),
        CartAddResult.added,
        reason: 'a plain quick add keeps its old "new line" behaviour',
      );
      final full = [
        for (var i = 0; i < 100; i++)
          OrderDraftLine('x$i', item, OrderQuantity.one, 'n$i'),
      ];
      expect(
        addToLines(full, item, OrderQuantity.one, note: 'new', newId: next),
        CartAddResult.full,
      );
    });
  });

  testWidgets('tapping a dish opens its sheet and never the cart', (
    tester,
  ) async {
    _phone(tester);
    await pumpOrder(tester, child: const OrderCreateScreen(takeaway: true));

    await _openDish(tester);
    // 1 + 2 = 3 portions, a little less spicy.
    await _addFromSheet(tester, extra: 2, note: 'ít cay');
    expect(find.text('Giỏ (1)'), findsOneWidget);
    // Still on the menu: its quick add button is on screen.
    expect(find.byTooltip('Thêm Trà đào'), findsOneWidget);

    // Same note again: the line grows instead of doubling.
    await _openDish(tester);
    expect(find.text('Đang có trong giỏ'), findsOneWidget);
    expect(find.text('ít cay'), findsOneWidget);
    await _addFromSheet(tester, note: 'ít cay');
    expect(find.text('Giỏ (1)'), findsOneWidget);

    // No note: a second line.
    await _openDish(tester);
    await _addFromSheet(tester);
    expect(find.text('Giỏ (2)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with several lines, + on the card opens the sheet', (
    tester,
  ) async {
    _phone(tester);
    await pumpOrder(tester, child: const OrderCreateScreen(takeaway: true));
    await _openDish(tester);
    await _addFromSheet(tester, note: 'ít đá');
    await _openDish(tester);
    await _addFromSheet(tester);
    expect(find.text('Giỏ (2)'), findsOneWidget);

    await tester.tap(find.byTooltip('Thêm Trà đào'));
    await tester.pumpAndSettle();
    expect(find.byKey(_sheet), findsOneWidget);
    expect(find.text('Giỏ (2)'), findsOneWidget);

    // Lines can be adjusted right there; dropping one can be undone.
    final plain = find.ancestor(
      of: find.text('Không ghi chú'),
      matching: find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith(
              'menu-item-sheet-line-',
            ),
      ),
    );
    await tester.tap(
      find.descendant(of: plain, matching: find.byTooltip('Bớt')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đã bỏ Trà đào'), findsOneWidget);
    await tester.tap(find.text('Hoàn tác'));
    await tester.pumpAndSettle();
    expect(find.text('Không ghi chú'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adding to a served order uses the same sheet', (tester) async {
    _phone(tester);
    final orders = FakeOrders()
      ..current = OrderDto.detail(
        orderJson(status: 'CONFIRMED', confirmed: true),
      );
    await pumpOrder(
      tester,
      orders: orders,
      child: const OrderAppendScreen(orderId: 'o1'),
    );
    await _openDish(tester);
    await _addFromSheet(tester, extra: 1, note: 'mang về');
    expect(find.text('Giỏ gọi thêm (1)'), findsWidgets);
    expect(find.byTooltip('Thêm Trà đào'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the sheet fits a 320px phone at 200% text', (tester) async {
    _phone(tester, size: const Size(320, 700));
    await pumpOrder(
      tester,
      scale: 2,
      child: const OrderCreateScreen(takeaway: true),
    );
    await _openDish(tester);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(_note));
    await tester.enterText(find.byKey(_note), 'ít cay');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
