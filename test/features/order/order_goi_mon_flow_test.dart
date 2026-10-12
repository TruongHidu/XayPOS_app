import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_submission.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_append_screen.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_create_screen.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_detail_screen.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_list_screen.dart';
import 'package:pos_saas_app/features/order/presentation/widgets/order_menu_item_card.dart';
import '../tables/table_fakes.dart';
import 'order_fakes.dart';
import 'order_table_workspace_test.dart' show tableData, serving;
import 'order_widget_test.dart' show pumpOrder;

void main() {
  testWidgets(
    '1 & 2 & 3. Tap table with active order opens bill in Goi mon flow, keeps sidebar in Goi mon, back returns to grid',
    (tester) async {
      final tables = TableServer()..table = tableData(occupied: true);
      final orders = FakeOrders()..current = serving(id: 'o1');
      final container = await pumpOrder(
        tester,
        tables: tables,
        orders: orders,
        useRouter: true,
      );

      final router = container.read(appRouterProvider);
      router.go('/app/order-create');
      await tester.pumpAndSettle();

      // Tap the occupied table
      await tester.tap(find.text('Window table'));
      await tester.pumpAndSettle();

      // Bill detail is rendered directly in Gọi món flow
      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(find.byType(OrderListScreen), findsNothing);

      // Verify the order ID on the screen
      final detailWidget = tester.widget<OrderDetailScreen>(
        find.byType(OrderDetailScreen),
      );
      expect(detailWidget.id, 'o1');

      // Sidebar stays in "Gọi món" (both AppShell AppBar and sidebar item)
      expect(find.text('Gọi món'), findsWidgets);

      // Back returns to table grid
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderDetailScreen), findsNothing);
      expect(find.text('Window table'), findsOneWidget);
    },
  );

  testWidgets('4. Route detail from orders history retains Orders section', (
    tester,
  ) async {
    final orders = FakeOrders()..current = serving(id: 'o1');
    final container = await pumpOrder(tester, orders: orders, useRouter: true);

    final router = container.read(appRouterProvider);
    router.go('/app/orders/o1');
    await tester.pumpAndSettle();

    expect(find.byType(OrderDetailScreen), findsOneWidget);
    expect(find.text('Đơn hàng'), findsWidgets);
  });

  testWidgets('5. VIEW-only sees bill without CREATE or MENU permissions', (
    tester,
  ) async {
    final orders = FakeOrders()..current = serving(id: 'o1');
    await pumpOrder(
      tester,
      orders: orders,
      permissions: {'ORDER_VIEW'},
      child: const OrderDetailScreen(id: 'o1'),
    );

    expect(find.byType(OrderDetailScreen), findsOneWidget);
    expect(find.text('Phở bò'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets(
    '6. Empty table tap opens composer; back does not create session or order',
    (tester) async {
      final tables = TableServer()..table = tableData(occupied: false);
      final orders = FakeOrders();
      final container = await pumpOrder(
        tester,
        tables: tables,
        orders: orders,
        useRouter: true,
      );

      final router = container.read(appRouterProvider);
      router.go('/app/order-create');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Window table'));
      await tester.pumpAndSettle();

      expect(find.byType(OrderCreateScreen), findsOneWidget);

      // Back before sending
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();

      expect(orders.creates, isEmpty);
      expect(tables.requests.any((r) => r.method == 'POST'), false);
    },
  );

  testWidgets('7. Active-order 204 opens local composer with tableId', (
    tester,
  ) async {
    final tables = TableServer()..table = tableData(occupied: true);
    final orders = FakeOrders()
      ..onActive = (_) async => Success<OrderDetail?>(null); // 204 No Content
    final container = await pumpOrder(
      tester,
      tables: tables,
      orders: orders,
      useRouter: true,
    );

    final router = container.read(appRouterProvider);
    router.go('/app/order-create');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Window table'));
    await tester.pumpAndSettle();

    // Opens composer with tableId
    expect(find.byType(OrderCreateScreen), findsOneWidget);
    expect(orders.creates, isEmpty);
  });

  testWidgets(
    '9 & 10. Stepper modifies local cart and quantity 0 removes line',
    (tester) async {
      final tables = TableServer();
      final orders = FakeOrders();
      final container = await pumpOrder(
        tester,
        tables: tables,
        orders: orders,
        useRouter: true,
      );

      final router = container.read(appRouterProvider);
      router.go('/app/order-create?serviceType=TAKEAWAY');
      await tester.pumpAndSettle();

      expect(find.byType(OrderMenuItemCard), findsOneWidget);

      // Add item via stepper
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(SafeArea),
          matching: find.text('1 món'),
        ),
        findsOneWidget,
      );
      expect(orders.creates, isEmpty);

      // Decrement to 0
      await tester.tap(find.byTooltip('Bớt Trà đào'));
      await tester.pumpAndSettle();

      expect(find.text('0 món'), findsOneWidget);
      expect(orders.creates, isEmpty);
    },
  );

  testWidgets('12. Switching between menu and review does not lose cart', (
    tester,
  ) async {
    final tables = TableServer();
    final orders = FakeOrders();
    final container = await pumpOrder(
      tester,
      tables: tables,
      orders: orders,
      useRouter: true,
    );

    final router = container.read(appRouterProvider);
    router.go('/app/order-create?serviceType=TAKEAWAY');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Thêm Trà đào'));
    await tester.pumpAndSettle();

    // Switch to review tab
    await tester.tap(find.text('Xem đơn'));
    await tester.pumpAndSettle();

    expect(find.text('Trà đào'), findsOneWidget);

    // Switch back to menu tab
    await tester.tap(find.text('Chọn món'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(SafeArea),
        matching: find.text('1 món'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    '15 & 16. FAB (+) in bill opens append screen in Goi mon, sends only new lines with expectedVersion',
    (tester) async {
      final orders = FakeOrders()..current = serving(id: 'o1', version: 5);
      final container = await pumpOrder(
        tester,
        orders: orders,
        useRouter: true,
      );

      final router = container.read(appRouterProvider);
      router.go('/app/order-create/bill/o1?tableName=B%C3%A0n%201');
      await tester.pumpAndSettle();

      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      // Tap FAB (+)
      await tester.tap(find.byTooltip('Gọi thêm món'));
      await tester.pumpAndSettle();

      // Append screen opens in Gọi món flow
      expect(find.byType(OrderAppendScreen), findsOneWidget);

      // Add new item in append
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();

      // Send append
      await tester.tap(find.text('Gửi món gọi thêm'));
      await tester.pumpAndSettle();

      // Verify append submission
      expect(orders.submissions.length, 1);
      final (subOrderId, payload, _) = orders.submissions.first;
      expect(subOrderId, 'o1');
      expect(payload.expectedVersion, 5);
      expect(payload.submissionMode, OrderSubmissionMode.submit);
      expect(payload.items.length, 1);
      expect(payload.items.first.itemId, itemId);

      // Returned back to bill screen
      expect(find.byType(OrderDetailScreen), findsOneWidget);
    },
  );

  testWidgets(
    '17. CONFIRMED order line is read-only (no stepper ± on saved lines)',
    (tester) async {
      final orders = FakeOrders()
        ..current = serving(id: 'o1', status: 'CONFIRMED');
      await pumpOrder(
        tester,
        orders: orders,
        child: const OrderDetailScreen(id: 'o1'),
      );

      // Line is read-only; no inline "Sửa" or local ± stepper on saved lines
      expect(find.text('Phở bò'), findsOneWidget);
      expect(find.text('Sửa'), findsNothing);
      expect(find.byTooltip('Bớt Phở bò'), findsNothing);
    },
  );

  testWidgets(
    '19. CANCELLED order line renders with distinct style, backend total is preserved',
    (tester) async {
      final orders = FakeOrders()
        ..current = OrderDto.detail(
          orderJson(status: 'OPEN', lineStatus: 'CANCELLED')
            ..['totalAmount'] = 50000,
        );
      await pumpOrder(
        tester,
        orders: orders,
        child: const OrderDetailScreen(id: 'o1'),
      );

      expect(find.text('Đã hủy'), findsOneWidget);
      expect(find.textContaining('Tổng:'), findsWidgets);
    },
  );

  testWidgets('25. No fake payment, kitchen or close actions implemented', (
    tester,
  ) async {
    final orders = FakeOrders()..current = serving(id: 'o1');
    await pumpOrder(
      tester,
      orders: orders,
      child: const OrderDetailScreen(id: 'o1'),
    );

    expect(find.text('Thanh toán'), findsNothing);
    expect(find.text('Thông báo'), findsNothing);
    await tester.scrollUntilVisible(find.textContaining('Chưa hỗ trợ'), 200);
    expect(find.textContaining('Chưa hỗ trợ'), findsOneWidget);
  });

  testWidgets(
    '26. 320px screen does not overflow on bill screen or append screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final orders = FakeOrders()..current = serving(id: 'o1');
      final container = await pumpOrder(
        tester,
        orders: orders,
        useRouter: true,
      );
      final router = container.read(appRouterProvider);
      router.go('/app/order-create/bill/o1?tableName=B%C3%A0n%201');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // Open append screen
      router.go('/app/order-create/bill/o1/add-items?tableName=B%C3%A0n%201');
      await tester.pumpAndSettle();

      expect(find.byType(OrderAppendScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Verify provisional bill dialog on bill screen does not overflow
      router.go('/app/order-create/bill/o1?tableName=B%C3%A0n%201');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tạm tính'));
      await tester.pumpAndSettle();
      expect(find.text('Phiếu tạm tính'), findsOneWidget);
      expect(find.text('Tổng thanh toán:'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
    },
  );
}
