import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/realtime/realtime_envelope.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/data/dto/order_realtime_payload.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_change_kind.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/policies/order_table_policy.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_invalidation.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_realtime_coordinator.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_list_screen.dart';
import '../../helpers/order_realtime_fakes.dart';
import '../tables/table_fakes.dart';
import 'order_fakes.dart';
import 'order_widget_test.dart' show pumpOrder;

String _event(int n, List<String> changes) =>
    jsonEncode(orderEventJson(n: n, version: n, changes: changes));

void main() {
  group('which order changes touch the table board', () {
    test('only kitchen progress leaves table cards alone', () {
      expect(
        OrderTablePolicy.affectedBy({OrderChangeKind.itemStatusChanged}),
        isFalse,
      );
      for (final kind in OrderChangeKind.values) {
        if (kind == OrderChangeKind.itemStatusChanged) continue;
        expect(OrderTablePolicy.affectedBy({kind}), isTrue, reason: '$kind');
        expect(
          OrderTablePolicy.affectedBy({
            OrderChangeKind.itemStatusChanged,
            kind,
          }),
          isTrue,
          reason: 'mixed with $kind',
        );
      }
      expect(OrderTablePolicy.affectedBy(const {}), isTrue);
    });

    test('every change the server sends maps to a domain kind', () {
      final payload = OrderRealtimePayload.parse(
        RealtimeEnvelope.parse(
          _event(1, OrderRealtimePayload.kindsByCode.keys.toList()),
        )!,
      )!;
      expect(payload.kinds, OrderChangeKind.values.toSet());
    });

    test('a batch of kitchen progress is marked as not touching tables', () {
      fakeAsync((async) {
        final hints = <OrderInvalidation>[];
        final coordinator = OrderRealtimeCoordinator(invalidate: hints.add);
        coordinator.receive(_event(1, ['ITEM_STATUS_CHANGED']));
        coordinator.receive(_event(2, ['ITEM_STATUS_CHANGED']));
        async.elapse(const Duration(seconds: 1));
        expect(hints.single.affectsTables, isFalse);

        coordinator.receive(_event(3, ['ITEM_STATUS_CHANGED']));
        coordinator.receive(_event(4, ['ITEMS_ADDED']));
        async.elapse(const Duration(seconds: 1));
        expect(hints.last.affectsTables, isTrue);

        coordinator.receive(_event(5, ['ITEM_STATUS_CHANGED']));
        coordinator.resync();
        async.elapse(const Duration(seconds: 1));
        expect(hints.last.affectsTables, isTrue);
        coordinator.dispose();
      });
    });
  });

  testWidgets('the table board ignores kitchen progress from elsewhere', (
    tester,
  ) async {
    final tables = TableServer()..table = tableJson(occupied: true);
    final container = await pumpOrder(tester, tables: tables);
    final events = container.read(orderEventsProvider);

    tables.requests.clear();
    events.invalidateRemote(
      OrderInvalidation(orderIds: {'o1'}, affectsTables: false),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tables.requests, isEmpty);

    events.invalidateRemote(OrderInvalidation(orderIds: {'o1'}));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tables.requests, isNotEmpty);

    // This device's own changes always refresh.
    tables.requests.clear();
    events.emit('o1', null);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tables.requests, isNotEmpty);
  });

  testWidgets('the order list builds only the cards on screen', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const total = 40;
    final rows = [
      for (var i = 0; i < total; i++)
        OrderDto.summary(
          orderJson()
            ..['id'] = 'order-$i'
            ..['orderCode'] = 'OD-${i.toString().padLeft(3, '0')}',
        ),
    ];
    final orders = FakeOrders()
      ..onList = (q) async => Success(
        OrderPage(
          content: rows,
          page: 0,
          size: total,
          totalElements: total,
          totalPages: 1,
        ),
      );
    await pumpOrder(tester, orders: orders, child: const OrderListScreen());

    Finder cards() => find.byWidgetPredicate(
      (w) =>
          w is KeyedSubtree &&
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('order-card-'),
    );
    expect(cards(), findsWidgets);
    expect(cards().evaluate().length, lessThan(total ~/ 2));

    await tester.scrollUntilVisible(
      find.text('OD-039'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('OD-039'), findsOneWidget);
    expect(find.text('OD-000'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
