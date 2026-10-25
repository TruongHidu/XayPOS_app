import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_alert_notice.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_alert_realtime_coordinator.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_events.dart';

String _event({
  String eventId = 'e1',
  String id = 'a1',
  int version = 0,
  String status = 'OPEN',
  int schema = 1,
}) => jsonEncode({
  'eventId': eventId,
  'type': 'INVENTORY_LOW_STOCK_ALERT_CHANGED',
  'schemaVersion': schema,
  'occurredAt': '2026-10-23T08:00:00Z',
  'resourceType': 'LOW_STOCK_ALERT',
  'resourceId': id,
  'resourceVersion': version,
  'payload': {
    'warehouseId': 'w1',
    'ingredientId': 'i1',
    'status': status,
    'resolutionReason': null,
  },
});

void main() {
  test('notice copies IDs and selects single or grouped wording', () {
    final ids = {'a1'};
    final single = InventoryAlertNotice(alertIds: ids);
    ids.add('a2');
    expect(single.alertIds, {'a1'});
    expect(single.singleAlertId, 'a1');
    expect(single.message, 'Có cảnh báo tồn thấp mới.');
    expect(() => single.alertIds.add('a2'), throwsUnsupportedError);

    final group = InventoryAlertNotice(alertIds: ids);
    expect(group.singleAlertId, isNull);
    expect(group.message, 'Có 2 cảnh báo tồn thấp mới.');
    final overflow = InventoryAlertNotice(alertIds: {'a1'}, hasMore: true);
    expect(overflow.singleAlertId, isNull);
    expect(overflow.message, 'Có nhiều cảnh báo tồn thấp mới.');
  });

  test(
    'new OPEN emits once with the coalesced REST invalidation at 400 ms',
    () {
      fakeAsync((clock) {
        final scope = _Scope();
        scope.coordinator.receive(_event());
        clock.elapse(const Duration(milliseconds: 399));
        expect(scope.notices, isEmpty);
        expect(scope.events.revision, 0);
        clock.elapse(const Duration(milliseconds: 1));
        expect(scope.notices.single.alertIds, {'a1'});
        expect(scope.events.change!.kind, InventoryChangeKind.alertSync);
        expect(scope.events.change!.alertIds, {'a1'});
        expect(scope.events.revision, 1);
        clock.elapse(const Duration(seconds: 2));
        expect(scope.notices, hasLength(1));
        scope.dispose();
      });
    },
  );

  test('burst groups distinct alert episodes even for the same ingredient', () {
    fakeAsync((clock) {
      final scope = _Scope();
      for (var i = 1; i <= 3; i++) {
        scope.coordinator.receive(_event(eventId: 'e$i', id: 'a$i'));
      }
      clock.elapse(const Duration(milliseconds: 400));
      expect(scope.notices.single.alertIds, {'a1', 'a2', 'a3'});
      expect(scope.notices.single.message, 'Có 3 cảnh báo tồn thấp mới.');
      expect(scope.notices.single.hasMore, false);
      expect(scope.events.revision, 1);
      scope.dispose();
    });
  });

  test('duplicate event, same version and later OPEN do not notify twice', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.coordinator.receive(_event());
      clock.elapse(const Duration(milliseconds: 400));
      scope.coordinator.receive(_event(version: 1)); // Duplicate event ID.
      scope.coordinator.receive(_event(eventId: 'same-version'));
      scope.coordinator.receive(_event(eventId: 'later-open', version: 2));
      clock.elapse(const Duration(milliseconds: 400));
      expect(scope.notices, hasLength(1));
      expect(scope.events.revision, 2); // Later OPEN still refreshes REST.
      scope.coordinator.receive(_event(eventId: 'new-episode', id: 'a2'));
      clock.elapse(const Duration(milliseconds: 400));
      expect(scope.notices, hasLength(2));
      expect(scope.notices.last.singleAlertId, 'a2');
      scope.dispose();
    });
  });

  for (final status in ['ACKNOWLEDGED', 'RESOLVED']) {
    test('$status never notifies and removes an OPEN pending before flush', () {
      fakeAsync((clock) {
        final scope = _Scope();
        scope.coordinator.receive(_event(status: status));
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.notices, isEmpty);
        scope.coordinator.receive(_event(eventId: 'open-2', id: 'a2'));
        scope.coordinator.receive(
          _event(eventId: 'close-2', id: 'a2', version: 1, status: status),
        );
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.notices, isEmpty);
        expect(scope.events.revision, 2);
        scope.dispose();
      });
    });
  }

  test('local REST ACK suppresses its pending OPEN, leaving other alerts', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.coordinator.receive(_event());
      scope.coordinator.receive(_event(eventId: 'e2', id: 'a2'));
      scope.events.emit(
        const InventoryChange(
          InventoryChangeKind.alert,
          'w1',
          alertId: 'a1',
          resourceVersion: 1,
        ),
      );
      clock.elapse(const Duration(milliseconds: 400));
      expect(scope.notices.single.alertIds, {'a2'});
      expect(scope.events.change!.alertIds, {'a2'});
      scope.dispose();
    });
  });

  test('local ACK before socket OPEN suppresses the old creation event', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.events.emit(
        const InventoryChange(
          InventoryChangeKind.alert,
          'w1',
          alertId: 'a1',
          resourceVersion: 1,
        ),
      );
      scope.coordinator.receive(_event());
      clock.elapse(const Duration(milliseconds: 400));
      expect(scope.notices, isEmpty);
      expect(scope.events.revision, 1);
      scope.dispose();
    });
  });

  test(
    'resync refreshes REST without notifying or replaying pending OPENs',
    () {
      fakeAsync((clock) {
        final scope = _Scope();
        scope.coordinator.resync();
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.notices, isEmpty);
        expect(scope.events.revision, 1);
        scope.coordinator.receive(_event());
        scope.coordinator.resync();
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.notices, isEmpty);
        expect(scope.events.revision, 2);
        scope.coordinator.receive(_event(eventId: 'e2', id: 'a2'));
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.notices.single.singleAlertId, 'a2');
        scope.dispose();
      });
    },
  );

  test('background drops pending notice and resume only resyncs REST', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.coordinator.receive(_event());
      scope.coordinator.setForeground(false);
      scope.coordinator.receive(_event(eventId: 'background', id: 'a2'));
      clock.elapse(const Duration(seconds: 1));
      expect(scope.notices, isEmpty);
      expect(scope.events.revision, 0);
      scope.coordinator.setForeground(true);
      clock.elapse(const Duration(milliseconds: 400));
      expect(scope.notices, isEmpty);
      expect(scope.events.revision, 1);
      scope.dispose();
    });
  });

  test('turning off cancels pending notice and REST invalidation', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.coordinator.receive(_event());
      scope.coordinator.cancelPending();
      clock.elapse(const Duration(seconds: 1));
      expect(scope.notices, isEmpty);
      expect(scope.events.revision, 0);
      scope.coordinator.resync();
      clock.elapse(const Duration(milliseconds: 400));
      expect(scope.notices, isEmpty);
      expect(scope.events.revision, 1);
      scope.dispose();
    });
  });

  test('dispose clears notices and timers without late callbacks', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.coordinator.receive(_event());
      scope.dispose();
      clock.elapse(const Duration(seconds: 1));
      expect(scope.notices, isEmpty);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test(
    'synchronous scope disposal during invalidation cannot publish notice',
    () {
      fakeAsync((clock) {
        final scope = _Scope();
        scope.events.addListener(scope.coordinator.dispose);
        scope.coordinator.receive(_event());
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.events.revision, 1);
        expect(scope.notices, isEmpty);
        scope.dispose();
      });
    },
  );

  test('notice listeners support add, remove and mutation during dispatch', () {
    fakeAsync((clock) {
      final scope = _Scope();
      final received = <String>[];
      void removed(InventoryAlertNotice notice) => received.add('removed');
      void added(InventoryAlertNotice notice) => received.add('added');
      void first(InventoryAlertNotice notice) {
        received.add('first');
        scope.coordinator.removeNoticeListener(removed);
        scope.coordinator.addNoticeListener(added);
      }

      scope.coordinator.addNoticeListener(first);
      scope.coordinator.addNoticeListener(first);
      scope.coordinator.addNoticeListener(removed);
      scope.coordinator.receive(_event());
      clock.elapse(const Duration(milliseconds: 400));
      expect(received, ['first']);
      expect(scope.notices, hasLength(1)); // Constructor callback is preserved.

      scope.coordinator.receive(_event(eventId: 'e2', id: 'a2'));
      clock.elapse(const Duration(milliseconds: 400));
      expect(received, ['first', 'first', 'added']);
      expect(scope.notices, hasLength(2));

      scope.coordinator.removeNoticeListener(first);
      scope.coordinator.removeNoticeListener(added);
      scope.coordinator.receive(_event(eventId: 'e3', id: 'a3'));
      clock.elapse(const Duration(milliseconds: 400));
      expect(received, ['first', 'first', 'added']);
      expect(scope.notices, hasLength(3));
      scope.dispose();
    });
  });

  test(
    'disposing during notice dispatch stops remaining and late listeners',
    () {
      fakeAsync((clock) {
        final scope = _Scope();
        var laterCalls = 0;
        scope.coordinator.addNoticeListener((_) => scope.coordinator.dispose());
        scope.coordinator.addNoticeListener((_) => laterCalls++);
        scope.coordinator.receive(_event());
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.notices, hasLength(1));
        expect(laterCalls, 0);

        scope.coordinator.addNoticeListener((_) => laterCalls++);
        scope.coordinator.receive(_event(eventId: 'late', id: 'a2'));
        clock.elapse(const Duration(seconds: 1));
        expect(scope.notices, hasLength(1));
        expect(laterCalls, 0);
        expect(clock.pendingTimers, isEmpty);
        scope.dispose();
      });
    },
  );

  test('overflow bounds retained IDs and uses generic group navigation', () {
    fakeAsync((clock) {
      final scope = _Scope(capacity: 3);
      for (var i = 0; i < 20; i++) {
        scope.coordinator.receive(_event(eventId: 'e$i', id: 'a$i'));
      }
      expect(scope.coordinator.cachedEventCount, 3);
      expect(scope.coordinator.cachedResourceCount, 3);
      clock.elapse(const Duration(milliseconds: 400));
      expect(scope.notices.single.alertIds, hasLength(3));
      expect(scope.notices.single.hasMore, true);
      expect(scope.notices.single.singleAlertId, isNull);
      expect(scope.notices.single.message, 'Có nhiều cảnh báo tồn thấp mới.');
      expect(scope.events.change!.alertIds, isEmpty); // Full REST resync.
      scope.dispose();
    });
  });

  test('overflow alone cannot notify after retained OPENs were superseded', () {
    fakeAsync((clock) {
      final scope = _Scope(capacity: 2);
      for (var i = 0; i < 4; i++) {
        scope.coordinator.receive(_event(eventId: 'e$i', id: 'a$i'));
      }
      for (var i = 0; i < 4; i++) {
        scope.coordinator.receive(
          _event(
            eventId: 'closed-$i',
            id: 'a$i',
            version: 1,
            status: 'RESOLVED',
          ),
        );
      }
      clock.elapse(const Duration(milliseconds: 400));
      expect(scope.notices, isEmpty);
      expect(scope.events.revision, 1);
      scope.dispose();
    });
  });

  test('unsupported and malformed messages cannot produce notice', () {
    fakeAsync((clock) {
      final scope = _Scope();
      for (final body in [
        'bad json',
        _event(schema: 2),
        _event(status: 'BAD'),
      ]) {
        scope.coordinator.receive(body);
      }
      clock.elapse(const Duration(seconds: 1));
      expect(scope.notices, isEmpty);
      expect(scope.events.revision, 0);
      scope.dispose();
    });
  });
}

class _Scope {
  _Scope({int capacity = 512}) {
    coordinator = InventoryAlertRealtimeCoordinator(
      events,
      capacity: capacity,
      onNewAlerts: notices.add,
    );
  }

  final events = InventoryEvents();
  final notices = <InventoryAlertNotice>[];
  late final InventoryAlertRealtimeCoordinator coordinator;

  void dispose() {
    coordinator.dispose();
    events.dispose();
  }
}
