import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/inventory/data/dto/inventory_alert_dto.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_alert.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_alert_query.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/inventory/domain/use_cases/inventory_alert_use_cases.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_alert_realtime_coordinator.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_alert_list_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_alert_detail_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_events.dart';
import '../../helpers/auth_fakes.dart';
import 'inventory_alert_fakes.dart';
import 'inventory_fakes.dart';

String alertEvent({
  String eventId = 'event-1',
  String id = 'a1',
  int version = 1,
  String status = 'ACKNOWLEDGED',
  int schema = 1,
  String type = 'INVENTORY_LOW_STOCK_ALERT_CHANGED',
}) => jsonEncode({
  'eventId': eventId,
  'type': type,
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
  for (final status in ['OPEN', 'ACKNOWLEDGED', 'RESOLVED']) {
    test(
      '$status invalidates mounted list and matching detail, preserving filters',
      () {
        fakeAsync((clock) {
          final scope = _Scope();
          scope.list.query = const InventoryAlertQuery(
            status: null,
            q: 'bò',
            page: 2,
            direction: 'asc',
          );
          scope.load(clock);
          final query = scope.list.query;
          scope.repo.rows = [inventoryAlert(status: status, version: 3)];
          scope.coordinator.receive(alertEvent(status: status, version: 3));
          clock.elapse(const Duration(milliseconds: 399));
          expect(scope.repo.queries.length, 1);
          clock.elapse(const Duration(milliseconds: 1));
          clock.flushMicrotasks();
          expect(scope.repo.queries.length, 2);
          expect(scope.repo.detailIds, ['a1', 'a1']);
          expect(identical(scope.list.query, query), true);
          expect(scope.detail.value!.status.code, status);
          expect(scope.repo.acknowledgements, isEmpty);
          scope.dispose();
        });
      },
    );
  }

  test('malformed JSON and unknown schema/type are ignored safely', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.load(clock);
      for (final body in [
        'bad-json',
        '[]',
        '{}',
        alertEvent(schema: 2),
        alertEvent(type: 'ORDER_CHANGED'),
        alertEvent(status: 'INVALID'),
      ]) {
        scope.coordinator.receive(body);
      }
      clock.elapse(const Duration(seconds: 2));
      expect(scope.repo.queries.length, 1);
      expect(scope.coordinator.cachedEventCount, 0);
      scope.dispose();
    });
  });

  test(
    'event dedupe and versions are per alert, not per ingredient or timestamp',
    () {
      fakeAsync((clock) {
        final scope = _Scope();
        scope.load(clock);
        scope.coordinator.receive(alertEvent(version: 99));
        clock.elapse(const Duration(milliseconds: 400));
        scope.coordinator.receive(alertEvent(version: 100)); // same eventId
        scope.coordinator.receive(alertEvent(eventId: 'old-event', version: 1));
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.repo.queries.length, 2);
        scope.coordinator.receive(
          alertEvent(
            eventId: 'new-episode',
            id: 'a2',
            version: 0,
            status: 'OPEN',
          ),
        );
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.repo.queries.length, 3);
        expect(
          scope.repo.detailIds.length,
          2,
        ); // a1 detail does not reload for a2.
        scope.dispose();
      });
    },
  );

  test(
    'burst coalesces and event during GET causes exactly one trailing refresh',
    () {
      fakeAsync((clock) {
        final scope = _Scope();
        scope.load(clock);
        final listRead = Completer<Result<InventoryPage<InventoryAlert>>>();
        final detailRead = Completer<Result<InventoryAlert>>();
        scope.repo.onList = (_) => listRead.future;
        scope.repo.onDetail = (_) => detailRead.future;
        for (var i = 1; i <= 20; i++) {
          scope.coordinator.receive(alertEvent(eventId: 'e$i', version: i));
        }
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.repo.queries.length, 2);
        expect(scope.repo.detailIds.length, 2);
        scope.coordinator.receive(
          alertEvent(eventId: 'during-read', version: 21),
        );
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.repo.queries.length, 2);
        expect(scope.repo.detailIds.length, 2);
        scope.repo.onList = null;
        scope.repo.onDetail = null;
        listRead.complete(Success(inventoryPage([inventoryAlert()])));
        detailRead.complete(Success(inventoryAlert()));
        clock.flushMicrotasks();
        expect(scope.repo.queries.length, 3);
        expect(scope.repo.detailIds.length, 3);
        expect(scope.list.loading, false);
        expect(scope.detail.loading, false);
        scope.dispose();
      });
    },
  );

  test(
    'failed GET preserves existing data and reconnect/resume resync bypasses dedupe',
    () {
      fakeAsync((clock) {
        final scope = _Scope();
        scope.list.query = const InventoryAlertQuery(status: null);
        scope.load(clock);
        scope.repo.onList = (_) async => const Error(networkFailure);
        scope.coordinator.receive(alertEvent());
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.list.failure, isNotNull);
        expect(scope.list.rows.single.id, 'a1');
        scope.repo.onList = null;
        scope.repo.rows = [inventoryAlert(status: 'RESOLVED', version: 2)];
        scope.coordinator.channel.resync();
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.list.failure, isNull);
        expect(scope.list.rows.single.status, InventoryAlertStatus.resolved);
        scope.dispose();
      });
    },
  );

  for (final socketFirst in [false, true]) {
    test(
      'REST ACK and socket event coalesce without duplicate POST, socketFirst=$socketFirst',
      () {
        fakeAsync((clock) {
          final scope = _Scope();
          scope.load(clock);
          if (socketFirst) scope.coordinator.receive(alertEvent());
          unawaited(scope.detail.acknowledge());
          clock.flushMicrotasks();
          if (!socketFirst) scope.coordinator.receive(alertEvent());
          clock.elapse(const Duration(milliseconds: 400));
          expect(scope.repo.acknowledgements, hasLength(1));
          expect(scope.repo.queries, hasLength(2));
          expect(scope.repo.detailIds, hasLength(1));
          expect(scope.detail.value!.status, InventoryAlertStatus.acknowledged);
          expect(scope.list.rows, isEmpty); // Default list filters OPEN.
          scope.dispose();
        });
      },
    );
  }

  test(
    'same REST version accepts changed current metrics and retains null semantics',
    () {
      fakeAsync((clock) {
        final scope = _Scope();
        scope.load(clock);
        scope.repo.rows = [
          InventoryAlertDto.parse(inventoryAlertJson(current: 100)),
        ];
        scope.coordinator.resync();
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.detail.value!.version, 0);
        expect(scope.detail.value!.currentQuantity.toString(), '100');
        scope.repo.rows = [inventoryAlert(comparable: false)];
        scope.coordinator.resync();
        clock.elapse(const Duration(milliseconds: 400));
        expect(scope.detail.value!.currentQuantity, isNull);
        expect(scope.detail.value!.availableQuantity, isNull);
        scope.dispose();
      });
    },
  );

  test(
    'cache is bounded, expires, cancels on background/dispose and clears per scope',
    () {
      fakeAsync((clock) {
        final events = InventoryEvents();
        final coordinator = InventoryAlertRealtimeCoordinator(
          events,
          capacity: 4,
          now: () => DateTime.utc(2026).add(clock.elapsed),
        );
        for (var i = 0; i < 20; i++) {
          coordinator.receive(alertEvent(eventId: 'e$i', id: 'a$i'));
        }
        expect(coordinator.cachedEventCount, 4);
        expect(coordinator.cachedResourceCount, 4);
        coordinator.setForeground(false);
        clock.elapse(const Duration(minutes: 11));
        expect(events.revision, 0);
        coordinator.setForeground(true);
        coordinator.receive(alertEvent(eventId: 'after-ttl'));
        expect(coordinator.cachedEventCount, 1);
        coordinator.dispose();
        coordinator.dispose();
        clock.elapse(const Duration(seconds: 2));
        expect(events.revision, 0);
        expect(coordinator.cachedEventCount, 0);
        expect(clock.pendingTimers, isEmpty);
        events.dispose();
      });
    },
  );

  test(
    'read-only staff can refresh but cannot ACK and old tenant responses are ignored',
    () {
      fakeAsync((clock) {
        final scope = _Scope(permissions: {'INVENTORY_VIEW'});
        scope.load(clock);
        expect(scope.detail.canAcknowledge, false);
        final late = Completer<Result<InventoryAlert>>();
        scope.repo.onDetail = (_) => late.future;
        scope.coordinator.receive(alertEvent());
        clock.elapse(const Duration(milliseconds: 400));
        scope.session = makeAppSession(
          restaurantId: 'new-tenant',
          permissions: alertPermissions,
          features: alertFeatures,
        );
        late.complete(Success(inventoryAlert(version: 3)));
        clock.flushMicrotasks();
        expect(scope.detail.value, isNull);
        expect(scope.repo.acknowledgements, isEmpty);
        scope.dispose();
      });
    },
  );
}

class _Scope {
  _Scope({Set<String> permissions = alertPermissions}) {
    session = makeAppSession(permissions: permissions, features: alertFeatures);
    list = InventoryAlertListController(
      session: () => session,
      events: events,
      get: GetInventoryAlerts(repo),
    );
    detail = InventoryAlertDetailController(
      session: () => session,
      events: events,
      id: 'a1',
      get: GetInventoryAlert(repo),
      ack: AcknowledgeInventoryAlert(repo),
    );
    coordinator = InventoryAlertRealtimeCoordinator(events);
  }
  late AppSession session;
  final repo = FakeInventoryAlerts(), events = InventoryEvents();
  late final InventoryAlertListController list;
  late final InventoryAlertDetailController detail;
  late final InventoryAlertRealtimeCoordinator coordinator;
  void load(FakeAsync clock) {
    unawaited(list.load());
    unawaited(detail.load());
    clock.flushMicrotasks();
  }

  void dispose() {
    coordinator.dispose();
    list.dispose();
    detail.dispose();
    events.dispose();
  }
}
