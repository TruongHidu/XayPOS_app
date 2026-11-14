import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/ui/controllers/refresh_throttle.dart';
import 'package:pos_saas_app/features/order/domain/use_cases/order_use_cases.dart';
import 'package:pos_saas_app/features/order/domain/use_cases/order_workspace_use_cases.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_events.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_invalidation.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/takeaway_count_refresher.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/takeaway_orders_controller.dart';
import '../../helpers/auth_fakes.dart';
import 'order_fakes.dart';

void main() {
  test('freshness lasts its window and ends on a failure or change', () {
    var now = DateTime(2026, 11, 13, 9);
    final fresh = RefreshThrottle(now: () => now);
    expect(fresh.isFresh, isFalse);
    fresh.markLoaded();
    expect(fresh.isFresh, isTrue);
    now = now.add(const Duration(seconds: 29));
    expect(fresh.isFresh, isTrue);
    now = now.add(const Duration(seconds: 2));
    expect(fresh.isFresh, isFalse);
    fresh.markLoaded();
    fresh.markStale();
    expect(fresh.isFresh, isFalse);
  });

  group('takeaway badge', () {
    late DateTime now;
    late OrderEvents events;
    late List<int> published;
    late int reads;
    late int? next;
    late TakeawayCountRefresher refresher;

    setUp(() {
      now = DateTime(2026, 11, 13, 9);
      events = OrderEvents();
      published = [];
      reads = 0;
      next = 3;
      refresher = TakeawayCountRefresher(
        read: () async {
          reads++;
          return next;
        },
        publish: published.add,
        events: events,
        freshness: RefreshThrottle(now: () => now),
      );
      addTearDown(refresher.dispose);
    });

    test('opening the sidebar twice reads once', () async {
      await refresher.refreshIfStale();
      await refresher.refreshIfStale();
      expect(reads, 1);
      expect(published, [3]);
      now = now.add(const Duration(seconds: 31));
      await refresher.refreshIfStale();
      expect(reads, 2);
    });

    test('the board publishing its count counts as fresh', () async {
      refresher.record(7);
      await refresher.refreshIfStale();
      expect(reads, 0);
      expect(published, [7]);
    });

    test('a takeaway change made here makes the count stale', () async {
      await refresher.refreshIfStale();
      events.emit('dine-in-order', 'session-1');
      await refresher.refreshIfStale();
      expect(reads, 1, reason: 'a table order cannot change the badge');
      events.emit('takeaway-order', null);
      await refresher.refreshIfStale();
      expect(reads, 2);
      events.invalidateRemote(OrderInvalidation(orderIds: {'x'}));
      await refresher.refreshIfStale();
      expect(reads, 2, reason: 'remote hints wait for the time window');
    });

    test('a failed read is retried next time; refresh always asks', () async {
      next = null;
      await refresher.refreshIfStale();
      await refresher.refreshIfStale();
      expect(reads, 2);
      expect(published, isEmpty);
      next = 1;
      await refresher.refresh();
      await refresher.refresh();
      expect(reads, 4);
    });
  });

  test('the takeaway board polls slower while realtime is connected', () {
    fakeAsync((async) {
      final orders = FakeOrders();
      final controller = TakeawayOrdersController(
        session: () => makeAppSession(
          permissions: orderPermissions,
          features: orderFeatures,
        ),
        events: OrderEvents(),
        get: GetActiveTakeawayOrders(GetOrders(orders)),
      );
      controller.setRealtimeConnected(true);
      controller.setVisible(true);
      expect(
        controller.currentPollInterval,
        TakeawayOrdersController.connectedPollInterval,
      );
      async.elapse(const Duration(seconds: 59));
      expect(orders.queries, isEmpty);
      async.elapse(const Duration(seconds: 2));
      expect(orders.queries, isNotEmpty);

      // Realtime drops: back to the 30 s safety poll straight away.
      orders.queries.clear();
      controller.setRealtimeConnected(false);
      async.elapse(const Duration(seconds: 31));
      expect(orders.queries, isNotEmpty);

      controller.setVisible(false);
      orders.queries.clear();
      async.elapse(const Duration(minutes: 5));
      expect(orders.queries, isEmpty, reason: 'no polling while hidden');
      controller.dispose();
    });
  });
}
