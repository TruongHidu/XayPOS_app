import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/realtime/realtime_access_policy.dart';
import 'package:pos_saas_app/core/realtime/realtime_connection_service.dart';
import 'package:pos_saas_app/core/realtime/realtime_envelope.dart';
import 'package:pos_saas_app/core/realtime/realtime_event_window.dart';
import 'package:pos_saas_app/core/realtime/realtime_transport.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/order/data/dto/order_realtime_payload.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_realtime_coordinator.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_invalidation.dart';
import 'package:pos_saas_app/features/qr_order/data/dto/qr_realtime_payload.dart';
import 'package:pos_saas_app/features/qr_order/presentation/controllers/qr_events.dart';
import 'package:pos_saas_app/features/qr_order/presentation/controllers/qr_realtime_coordinator.dart';
import 'package:pos_saas_app/features/kitchen/presentation/controllers/kitchen_events.dart';
import 'package:pos_saas_app/features/kitchen/presentation/controllers/kitchen_realtime_coordinator.dart';
import '../../helpers/auth_fakes.dart';
import '../../helpers/order_realtime_fakes.dart';
import '../../helpers/realtime_fakes.dart';

void main() {
  test(
    'scope fence rejects a queued batch before provider disposal and suppresses notice after scope change',
    () {
      fakeAsync((clock) {
        var current = true, invalidations = 0, notices = 0;
        final order = OrderRealtimeCoordinator(
          isCurrent: () => current,
          invalidate: (_) {
            invalidations++;
            current = false;
          },
          onNewItems: (_) => notices++,
        );
        order.receive(orderEvent(fresh: true));
        current = false;
        clock.elapse(const Duration(milliseconds: 400));
        expect(invalidations, 0);
        current = true;
        order.receive(orderEvent(n: 2, fresh: true));
        clock.elapse(const Duration(milliseconds: 400));
        expect(invalidations, 1);
        expect(notices, 0);
        order.dispose();
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  test(
    'cashier reads order/QR without QR grants; kitchen needs no order/inventory',
    () {
      final cashier = makeAppSession(
        role: UserRole.cashier,
        permissions: {'ORDER_VIEW'},
        features: {'ORDER_MANAGEMENT'},
      );
      expect(RealtimeAccessPolicy.orders(cashier), true);
      expect(RealtimeAccessPolicy.inventory(cashier), false);
      expect(RealtimeAccessPolicy.kitchen(cashier), false);
      final kitchen = makeAppSession(
        role: UserRole.kitchen,
        permissions: {'KITCHEN_VIEW'},
        features: {'KITCHEN_DISPLAY'},
      );
      expect(RealtimeAccessPolicy.kitchen(kitchen), true);
      expect(RealtimeAccessPolicy.orders(kitchen), false);
      for (final role in [UserRole.superAdmin, UserRole.unsupported]) {
        expect(
          RealtimeAccessPolicy.orders(
            makeAppSession(
              role: role,
              permissions: {'ORDER_VIEW'},
              features: {'ORDER_MANAGEMENT'},
            ),
          ),
          false,
        );
      }
      expect(
        RealtimeAccessPolicy.orders(
          makeAppSession(
            restaurantId: null,
            permissions: {'ORDER_VIEW'},
            features: {'ORDER_MANAGEMENT'},
          ),
        ),
        false,
      );
      expect(
        RealtimeAccessPolicy.orders(
          makeAppSession(permissions: {}, features: {'ORDER_MANAGEMENT'}),
        ),
        false,
      );
      expect(
        RealtimeAccessPolicy.kitchen(
          makeAppSession(permissions: {'KITCHEN_VIEW'}, features: {}),
        ),
        false,
      );
    },
  );
  test(
    'payload validation, nullable context, unordered changes and nested freezing',
    () {
      final raw = orderEventJson(
        session: null,
        changes: ['SUBMITTED', 'CREATED', 'CREATED'],
      );
      (raw['payload'] as Map)['extra'] = {
        'nested': [
          1,
          {'safe': true},
        ],
      };
      final envelope = RealtimeEnvelope.parse(jsonEncode(raw))!;
      final payload = OrderRealtimePayload.parse(envelope)!;
      expect(payload.sessionId, null);
      expect(payload.changes, {'CREATED', 'SUBMITTED'});
      expect(() => payload.changes.add('UPDATED'), throwsUnsupportedError);
      expect(
        () => (envelope.payload['extra']['nested'] as List).add(2),
        throwsUnsupportedError,
      );
      expect(
        () => envelope.payload['extra']['nested'][1]['safe'] = false,
        throwsUnsupportedError,
      );
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (j) => j['schemaVersion'] = 2,
        (j) => j['type'] = 'UNKNOWN',
        (j) => j['resourceId'] = '../wrong',
        (j) => j['resourceVersion'] = 1.5,
        (j) => j['payload']['orderStatus'] = 'DRAFT',
        (j) => j['payload']['newKitchenItemIds'] = [123],
        (j) => j['payload']['tableSessionId'] = 'bad',
        (j) => j['payload']['changes'] = ['PAYMENT_SUCCESS'],
      ]) {
        final data = orderEventJson();
        mutate(data);
        final e = RealtimeEnvelope.parse(jsonEncode(data));
        expect(e == null ? null : OrderRealtimePayload.parse(e), null);
      }
      expect(RealtimeEnvelope.parse('{bad'), null);
      expect(RealtimeEnvelope.parse('x' * (256 * 1024 + 1)), null);
      final qr = QrRealtimePayload.parse(
        RealtimeEnvelope.parse(jsonEncode(qrEventJson(takeaway: true)))!,
      )!;
      expect(qr.tableId, null);
      expect(qr.entryType, 'RESTAURANT');
      final invalid = qrEventJson()..['payload']['status'] = 'APPROVED';
      expect(
        QrRealtimePayload.parse(RealtimeEnvelope.parse(jsonEncode(invalid))!),
        null,
      );
    },
  );
  test(
    'four channels share one connection, connected handshake gates subscriptions',
    () {
      fakeAsync((clock) {
        final factory = FakeRealtimeFactory();
        final service = RealtimeConnectionService(
          factory: factory.call,
          endpoint: () => Uri.parse('ws://example.test/ws'),
          refresh: (_) async {},
          recoverAccess: (_) async {},
        );
        final channels = [
          for (final id in [
            'inventory-alerts',
            'orders',
            'qr-order-requests',
            'kitchen-orders',
          ])
            testRealtimeChannel(id: id),
        ];
        service.configure(
          enabled: true,
          foreground: true,
          session: realtimeTestSession,
          channels: channels,
        );
        clock.flushMicrotasks();
        expect(factory.transports, hasLength(1));
        expect(factory.last.destinations, isEmpty);
        factory.last.connected();
        expect(factory.last.handlers, hasLength(4));
        service.configure(
          enabled: true,
          foreground: true,
          session: realtimeTestSession,
          channels: channels,
        );
        clock.flushMicrotasks();
        expect(factory.transports, hasLength(1));
        service.dispose();
        clock.flushMicrotasks();
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  test(
    'invalid subscription IDs/destination duplication fail closed without retry',
    () {
      fakeAsync((clock) {
        final factory = FakeRealtimeFactory();
        final service = RealtimeConnectionService(
          factory: factory.call,
          endpoint: () => Uri.parse('ws://example.test/ws'),
          refresh: (_) async {},
          recoverAccess: (_) async {},
        );
        service.configure(
          enabled: true,
          foreground: true,
          session: realtimeTestSession,
          channels: [testRealtimeChannel(id: 'bad\nid')],
        );
        clock.elapse(const Duration(hours: 1));
        expect(factory.transports, isEmpty);
        service.dispose();
      });
    },
  );
  test(
    'fan-out reaches order and kitchen; duplicates notify kitchen only once',
    () {
      fakeAsync((clock) {
        final orders = <OrderInvalidation>[], events = KitchenEvents();
        var notices = 0;
        final order = OrderRealtimeCoordinator(invalidate: orders.add);
        final kitchen = KitchenRealtimeCoordinator(
          events,
          onNewItems: (_) => notices++,
        );
        final body = orderEvent(fresh: true);
        order.receive(body);
        kitchen.receive(body);
        order.receive(body);
        kitchen.receive(body);
        clock.elapse(const Duration(milliseconds: 400));
        expect(orders, hasLength(1));
        expect(events.revision, 1);
        expect(notices, 1);
        kitchen.receive(orderEvent(n: 2, version: 5));
        clock.elapse(const Duration(milliseconds: 400));
        expect(notices, 1);
        kitchen.resync();
        clock.elapse(const Duration(milliseconds: 400));
        expect(notices, 1);
        order.dispose();
        kitchen.dispose();
        events.dispose();
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  test(
    'burst coalesces all IDs, overflow broadens and out-of-order resources stay independent',
    () {
      fakeAsync((clock) {
        final hints = <OrderInvalidation>[];
        final coordinator = OrderRealtimeCoordinator(
          invalidate: hints.add,
          capacity: 3,
        );
        for (var i = 1; i < 10; i++) {
          coordinator.receive(
            jsonEncode(
              orderEventJson(
                n: i,
                id: realtimeEventId(i + 50),
                version: 10 - i,
              ),
            ),
          );
        }
        expect(clock.pendingTimers, hasLength(1));
        clock.elapse(const Duration(milliseconds: 400));
        expect(hints.single.all, true);
        expect(coordinator.window.length, 3);
        coordinator.setActive(false);
        coordinator.receive(orderEvent(n: 40));
        clock.elapse(const Duration(seconds: 1));
        expect(hints, hasLength(1));
        coordinator.dispose();
        expect(coordinator.window.length, 0);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  test('event window is bounded by capacity and TTL', () {
    var now = DateTime.utc(2026);
    final window = RealtimeEventWindow(
      capacity: 2,
      ttl: const Duration(seconds: 1),
      now: () => now,
    );
    expect(window.accept('a'), true);
    expect(window.accept('a'), false);
    window.accept('b');
    window.accept('c');
    expect(window.length, 2);
    now = now.add(const Duration(seconds: 2));
    expect(window.accept('c'), true);
    expect(window.length, 1);
  });
  test(
    'QR processed in burst removes arrival notice, REST hint remains; restaurant explicit',
    () {
      fakeAsync((clock) {
        final events = QrEvents();
        final notices = <(int, int)>[];
        final qr = QrRealtimeCoordinator(
          events,
          onCreated: (a, b) => notices.add((a, b)),
        );
        qr.receive(jsonEncode(qrEventJson()));
        qr.receive(jsonEncode(qrEventJson(n: 2, kind: 'APPROVED')));
        clock.elapse(const Duration(milliseconds: 400));
        expect(events.revision, 1);
        expect(notices, isEmpty);
        qr.receive(jsonEncode(qrEventJson(n: 3, takeaway: true)));
        clock.elapse(const Duration(milliseconds: 400));
        expect(notices, [(0, 1)]);
        qr.resync();
        clock.elapse(const Duration(milliseconds: 400));
        expect(notices, hasLength(1));
        qr.dispose();
        events.dispose();
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  test('new stable errors are accepted without exposing arbitrary reasons', () {
    expect(
      RealtimeProblem.stableCode('REALTIME_SUBSCRIPTION_LIMIT'),
      isNotNull,
    );
    expect(RealtimeProblem.stableCode('REALTIME_SHUTDOWN'), isNotNull);
    expect(RealtimeProblem.stableCode('sensitive exception'), null);
  });
}
