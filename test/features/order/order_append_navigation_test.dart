import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_append_screen.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_detail_screen.dart';
import 'package:pos_saas_app/features/order/presentation/widgets/order_append_navigation.dart';
import '../../helpers/auth_fakes.dart';
import 'order_fakes.dart';
import 'order_widget_test.dart' show pumpOrder;

void main() {
  test('"Gọi thêm món" opens under the section it came from', () {
    expect(
      orderAppendLocation('/app/orders/o1', 'o1'),
      '/app/orders/o1/add-items',
    );
    expect(
      orderAppendLocation('/app/takeaway', 'o1'),
      '/app/takeaway/o1/add-items',
    );
    expect(
      orderAppendLocation(
        '/app/order-create/bill/o1',
        'o1',
        tableName: 'Bàn 1',
      ),
      '/app/order-create/bill/o1/add-items?tableName=B%C3%A0n+1',
    );
  });

  test('adding items needs the same rights from every section', () {
    final staff = makeAppSession(
      permissions: {'ORDER_VIEW', 'ORDER_UPDATE', 'MENU_VIEW'},
      features: orderFeatures,
    );
    final viewer = makeAppSession(
      permissions: {'ORDER_VIEW', 'MENU_VIEW'},
      features: orderFeatures,
    );
    for (final path in [
      '/app/orders/o1/add-items',
      '/app/order-create/bill/o1/add-items',
    ]) {
      expect(AccessPolicy.canOpenRoute(staff, path), isTrue, reason: path);
      expect(AccessPolicy.canOpenRoute(viewer, path), isFalse, reason: path);
    }
    expect(
      AccessPolicy.canOpenRoute(viewer, '/app/orders/o1'),
      isTrue,
      reason: 'viewing the order itself stays allowed',
    );
  });

  testWidgets('from Đơn hàng the full append screen opens and goes back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final orders = FakeOrders()
      ..current = OrderDto.detail(
        orderJson(status: 'CONFIRMED', confirmed: true),
      );
    final container = await pumpOrder(tester, orders: orders, useRouter: true);
    final router = container.read(appRouterProvider);
    router.go('/app/orders/o1');
    await tester.pumpAndSettle();
    expect(find.byType(OrderDetailScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Gọi thêm món'));
    await tester.pumpAndSettle();
    expect(find.byType(OrderAppendScreen), findsOneWidget);
    // Pushed onto the order's page, under the Đơn hàng section.
    expect(
      GoRouterState.of(tester.element(find.byType(OrderAppendScreen))).uri.path,
      '/app/orders/o1/add-items',
    );
    // Full screen: no popup frame around it.
    expect(find.byType(Dialog), findsNothing);

    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.byType(OrderAppendScreen), findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/app/orders/o1',
    );
    expect(tester.takeException(), isNull);
  });
}
