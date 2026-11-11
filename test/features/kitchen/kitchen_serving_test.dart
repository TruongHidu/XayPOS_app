import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/features/kitchen/data/dto/kitchen_dto.dart';
import 'package:pos_saas_app/features/kitchen/domain/entities/kitchen_queue.dart';
import 'package:pos_saas_app/features/kitchen/presentation/widgets/kitchen_cards.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'kitchen_fakes.dart';
import 'kitchen_widget_test.dart' show pumpKitchen, tapKitchen;

/// One dish still to cook (o1) and one fully ready order (o2).
FakeKitchen _repo() => FakeKitchen()
  ..rows = [
    KitchenDto.item(kitchenJson()),
    KitchenDto.item(
      kitchenJson(
        orderId: 'o2',
        itemId: 'i2',
        status: 'READY',
        name: 'Coca',
        unit: 'lon',
        quantity: 3,
        table: 'Bàn 2',
      ),
    ),
  ];

const _servers = {...kitchenPermissions, 'ORDER_MARK_SERVED'};
const _features = {'KITCHEN_DISPLAY', 'ORDER_MANAGEMENT'};

void main() {
  test('waiting time reads in minutes, hours or days', () {
    expect(kitchenWaited(const Duration(seconds: 20)), 'Vừa vào');
    expect(kitchenWaited(const Duration(minutes: 12)), '12 phút');
    expect(kitchenWaited(const Duration(minutes: 70)), '1 giờ 10 phút');
    expect(kitchenWaited(const Duration(hours: 3)), '3 giờ');
    expect(kitchenWaited(const Duration(minutes: 3523)), '2 ngày 10 giờ');
    expect(kitchenWaited(const Duration(days: 2)), '2 ngày');
  });

  test('to-do view hides ready dishes and lists them for serving', () async {
    final rig = KitchenRig(repository: _repo());
    addTearDown(rig.dispose);
    await rig.display.refresh();
    expect(rig.display.todoOnly, isTrue);
    expect(rig.display.visibleItems.map((r) => r.orderId), ['o1']);
    expect(rig.display.servingOrders.map((o) => o.first.orderId), ['o2']);
    rig.display.setFilter(null);
    expect(rig.display.visibleItems, hasLength(2));
    rig.display.setFilter(OrderItemStatus.ready);
    expect(rig.display.visibleItems.map((r) => r.orderId), ['o2']);
    rig.display.showTodo();
    expect(rig.display.visibleItems.map((r) => r.orderId), ['o1']);
    // Kitchen grants alone can't hand dishes over.
    expect(rig.actions.canServeOrder('o2'), isFalse);
  });

  testWidgets('ready dishes wait under Chờ phục vụ and Đã giao serves them', (
    tester,
  ) async {
    final repo = _repo();
    await pumpKitchen(tester, repo, permissions: _servers, features: _features);
    expect(find.text('Cần làm (1)'), findsOneWidget);
    expect(find.byKey(const ValueKey('kitchen-item-o2/i2')), findsNothing);
    expect(find.text('Chờ phục vụ · 1 món, 1 đơn'), findsOneWidget);
    expect(find.text('3 lon Coca'), findsOneWidget);
    await tapKitchen(tester, find.byKey(const ValueKey('serve-row-o2')));
    await tester.pumpAndSettle();
    expect(repo.writes.single.action, KitchenAction.markServed);
    expect(repo.writes.single.orderItemId, 'i2');
    expect(find.textContaining('Chờ phục vụ'), findsNothing);
    expect(find.text('Đã giao món cho Bàn 2 · B01.'), findsOneWidget);
  });

  testWidgets('without the serving grant the list only informs', (
    tester,
  ) async {
    final repo = _repo();
    await pumpKitchen(tester, repo, features: _features);
    expect(find.text('Chờ phục vụ · 1 món, 1 đơn'), findsOneWidget);
    expect(find.byKey(const ValueKey('serve-row-o2')), findsNothing);
    await tapKitchen(
      tester,
      find.byKey(const ValueKey('kitchen-serving-toggle')),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 lon Coca'), findsNothing);
  });

  testWidgets('a fully ready order card offers Đã giao, not Ready cả đơn', (
    tester,
  ) async {
    final repo = _repo();
    await pumpKitchen(tester, repo, permissions: _servers, features: _features);
    await tapKitchen(tester, find.text('Tất cả (2)'));
    await tapKitchen(tester, find.text('Theo đơn'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('serve-order-o2')), findsOneWidget);
    expect(find.byKey(const ValueKey('ready-order-o2')), findsNothing);
    // Pending dishes block "Ready cả đơn", so no dead button either.
    expect(find.byKey(const ValueKey('ready-order-o1')), findsNothing);
    expect(find.textContaining('Chờ phục vụ ·'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
