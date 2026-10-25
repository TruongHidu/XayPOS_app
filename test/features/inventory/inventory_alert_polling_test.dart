import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/inventory/data/dto/inventory_alert_dto.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_alert.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_alert_query.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/inventory/domain/use_cases/inventory_alert_use_cases.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_alert_notice.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_alert_polling_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_events.dart';

import '../../helpers/auth_fakes.dart';
import 'inventory_alert_fakes.dart';
import 'inventory_fakes.dart';

InventoryAlert _alert(
  int number, {
  String status = 'OPEN',
  int version = 0,
  DateTime? triggeredAt,
}) => InventoryAlertDto.parse({
  ...inventoryAlertJson(id: 'a$number', status: status, version: version),
  'triggeredAt':
      (triggeredAt ?? DateTime.utc(2026, 10, 23).add(Duration(seconds: number)))
          .toIso8601String(),
});

List<InventoryAlert> _rows(int newest, int oldest) => [
  for (var value = newest; value >= oldest; value--) _alert(value),
];

InventoryPage<InventoryAlert> _page(
  List<InventoryAlert> rows,
  InventoryAlertQuery query,
) => inventoryPage(
  rows.skip(query.page * query.size).take(query.size).toList(),
  page: query.page,
  size: query.size,
  total: rows.length,
  pages: (rows.length / query.size).ceil(),
);

class _Scope {
  _Scope({Future<void> Function(Failure)? onAccessDenied}) {
    repository.onList = (query) async => Success(_page(repository.rows, query));
    controller = InventoryAlertPollingController(
      get: GetInventoryAlerts(repository),
      events: events,
      session: () => session,
      onAccessDenied: onAccessDenied,
    );
    controller.addNoticeListener(notices.add);
  }

  AppSession? session = makeAppSession(
    permissions: alertPermissions,
    features: alertFeatures,
  );
  final repository = FakeInventoryAlerts();
  final events = InventoryEvents();
  final notices = <InventoryAlertNotice>[];
  late final InventoryAlertPollingController controller;

  void start() => controller.configure(enabled: true, foreground: true);
  void dispose() {
    controller.dispose();
    events.dispose();
  }
}

void main() {
  test('OFF and missing effective permissions never start a GET', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.controller.configure(enabled: false, foreground: true);
      clock.elapse(const Duration(minutes: 1));
      expect(scope.repository.queries, isEmpty);
      expect(scope.controller.state, InventoryAlertPollingState.stopped);
      scope.session = makeAppSession();
      scope.start();
      clock.elapse(const Duration(minutes: 1));
      expect(scope.repository.queries, isEmpty);
      expect(clock.pendingTimers, isEmpty);
      scope.dispose();
    });
  });

  test('first successful all-status recent page is a silent baseline', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.repository.rows = [
        _alert(3),
        _alert(2, status: 'ACKNOWLEDGED'),
        _alert(1, status: 'RESOLVED'),
      ];
      scope.start();
      expect(scope.controller.state, InventoryAlertPollingState.checking);
      clock.flushMicrotasks();
      expect(scope.controller.state, InventoryAlertPollingState.active);
      expect(scope.controller.failure, isNull);
      expect(scope.notices, isEmpty);
      final query = scope.repository.queries.single;
      expect(query.status, isNull);
      expect(query.page, 0);
      expect(query.size, 100);
      expect(query.sortBy, 'triggeredAt');
      expect(query.direction, 'desc');
      expect(scope.events.change!.kind, InventoryChangeKind.alertSync);
      expect(scope.events.change!.alertIds, isEmpty);
      expect(scope.events.revision, 1);
      clock.elapse(const Duration(seconds: 20));
      expect(scope.repository.queries, hasLength(2));
      expect(
        scope.events.revision,
        2,
      ); // Refresh balances even without versions.
      expect(scope.notices, isEmpty);
      scope.dispose();
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('only new OPEN episodes notify; ACK, resolved and updates do not', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.repository.rows = [_alert(1)];
      scope.start();
      clock.flushMicrotasks();
      scope.repository.rows = [
        _alert(4, status: 'RESOLVED'),
        _alert(3, status: 'ACKNOWLEDGED'),
        _alert(2),
        _alert(1, status: 'ACKNOWLEDGED', version: 1),
      ];
      clock.elapse(const Duration(seconds: 20));
      expect(scope.notices.single.alertIds, {'a2'});
      expect(scope.notices.single.hasMore, false);
      scope.repository.rows = [_alert(4), _alert(3), _alert(2, version: 2)];
      clock.elapse(const Duration(seconds: 20));
      expect(scope.notices, hasLength(1));
      scope.dispose();
    });
  });

  test('scans beyond first overlap to the last retained head ID', () {
    fakeAsync((clock) {
      final scope = _Scope();
      final timestamp = DateTime.utc(2026, 10, 23);
      scope.repository.rows = [
        for (var i = 0; i < 200; i++) _alert(i, triggeredAt: timestamp),
      ];
      scope.start();
      clock.flushMicrotasks();
      // All sort keys tie; the new ID is inserted inside the retained prefix.
      scope.repository.rows.insert(50, _alert(300, triggeredAt: timestamp));
      clock.elapse(const Duration(seconds: 20));
      expect(scope.repository.queries.map((q) => q.page), [0, 0, 1]);
      expect(scope.notices.single.alertIds, {'a300'});
      // a100..a199 are historical tail, not new alerts.
      clock.elapse(const Duration(seconds: 20));
      expect(scope.notices, hasLength(1));
      scope.dispose();
    });
  });

  test('a complete 100-row baseline detects same-time IDs after its tail', () {
    fakeAsync((clock) {
      final scope = _Scope();
      final timestamp = DateTime.utc(2026, 10, 23);
      scope.repository.rows = [
        for (var i = 0; i < 100; i++) _alert(i, triggeredAt: timestamp),
      ];
      scope.start();
      clock.flushMicrotasks();
      scope.repository.rows.add(_alert(100, triggeredAt: timestamp));
      clock.elapse(const Duration(seconds: 20));
      expect(scope.repository.queries.map((q) => q.page), [0, 0, 1]);
      expect(scope.notices.single.alertIds, {'a100'});
      scope.dispose();
    });
  });

  test('new bursts across multiple pages are grouped and IDs deduplicated', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.repository.rows = _rows(200, 1);
      scope.start();
      clock.flushMicrotasks();
      scope.repository.rows = _rows(350, 1);
      // Offset pagination may repeat a row while new alerts are being inserted.
      scope.repository.onList = (query) async {
        final data = _page(scope.repository.rows, query);
        return Success(
          query.page == 1
              ? inventoryPage(
                  [scope.repository.rows.first, ...data.content],
                  page: 1,
                  size: 100,
                  total: 350,
                  pages: 4,
                )
              : data,
        );
      };
      clock.elapse(const Duration(seconds: 20));
      expect(scope.repository.queries.map((q) => q.page), [0, 0, 1, 2]);
      expect(scope.notices.single.alertIds, hasLength(150));
      expect(
        scope.notices.single.alertIds,
        _rows(350, 201).map((a) => a.id).toSet(),
      );
      expect(scope.notices.single.hasMore, false);
      scope.dispose();
    });
  });

  test('pagination errors never partially advance the successful baseline', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.repository.rows = _rows(200, 1);
      scope.start();
      clock.flushMicrotasks();
      scope.repository.rows = _rows(350, 1);
      scope.repository.onList = (query) async => query.page == 1
          ? const Error(networkFailure)
          : Success(_page(scope.repository.rows, query));
      clock.elapse(const Duration(seconds: 20));
      expect(scope.controller.state, InventoryAlertPollingState.error);
      expect(scope.controller.failure, networkFailure);
      expect(scope.notices, isEmpty);
      expect(scope.events.revision, 1);
      scope.repository.onList = (query) async =>
          Success(_page(scope.repository.rows, query));
      clock.elapse(const Duration(seconds: 20));
      expect(scope.notices.single.alertIds, hasLength(150));
      expect(scope.events.revision, 2);
      expect(scope.controller.failure, isNull);
      scope.dispose();
    });
  });

  test(
    'large gaps scan at most ten pages and flag a bounded best-effort notice',
    () {
      fakeAsync((clock) {
        final scope = _Scope();
        scope.repository.rows = _rows(200, 1);
        scope.start();
        clock.flushMicrotasks();
        scope.repository.rows = _rows(1400, 1);
        clock.elapse(const Duration(seconds: 20));
        expect(
          scope.repository.queries,
          hasLength(11),
        ); // Baseline + ten pages.
        expect(scope.notices.single.alertIds, hasLength(1000));
        expect(scope.notices.single.hasMore, true);
        expect(scope.notices.single.singleAlertId, isNull);
        clock.elapse(const Duration(seconds: 20));
        expect(scope.notices, hasLength(1));
        expect(scope.repository.queries, hasLength(12));
        scope.dispose();
      });
    },
  );

  test('a missing boundary does not toast ambiguous tied historical rows', () {
    fakeAsync((clock) {
      final scope = _Scope();
      final timestamp = DateTime.utc(2026, 10, 23);
      scope.repository.rows = [
        for (var i = 0; i < 200; i++) _alert(i, triggeredAt: timestamp),
      ];
      scope.start();
      clock.flushMicrotasks();
      scope.repository.rows = [
        for (var i = 200; i < 1400; i++) _alert(i, triggeredAt: timestamp),
      ];
      clock.elapse(const Duration(seconds: 20));
      expect(scope.repository.queries, hasLength(11));
      expect(scope.notices, isEmpty);
      expect(scope.events.revision, 2);
      scope.dispose();
    });
  });

  test('an empty complete baseline can discover its first new episodes', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.repository.rows = [];
      scope.start();
      clock.flushMicrotasks();
      scope.repository.rows = _rows(110, 1);
      clock.elapse(const Duration(seconds: 20));
      expect(scope.notices.single.alertIds, hasLength(110));
      expect(scope.notices.single.hasMore, false);
      scope.dispose();
    });
  });

  test('local mutations debounce refresh and own alertSync never loops', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.start();
      clock.flushMicrotasks();
      for (final kind in [
        InventoryChangeKind.balance,
        InventoryChangeKind.document,
        InventoryChangeKind.audit,
        InventoryChangeKind.orderStock,
      ]) {
        scope.events.emit(InventoryChange(kind, 'w1'));
      }
      scope.events.lock('unrelated');
      scope.events.unlock('unrelated');
      clock.elapse(const Duration(milliseconds: 399));
      expect(scope.repository.queries, hasLength(1));
      clock.elapse(const Duration(milliseconds: 1));
      expect(scope.repository.queries, hasLength(2));
      scope.events.emit(
        const InventoryChange(InventoryChangeKind.alertSync, null),
      );
      clock.elapse(const Duration(seconds: 1));
      expect(scope.repository.queries, hasLength(2));
      scope.dispose();
    });
  });

  test('local ACK during a pending GET suppresses a stale OPEN notice', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.repository.rows = [_alert(1)];
      scope.start();
      clock.flushMicrotasks();
      final pending = Completer<Result<InventoryPage<InventoryAlert>>>();
      scope.repository.onList = (_) => pending.future;
      scope.controller.refresh();
      scope.events.emit(
        const InventoryChange(
          InventoryChangeKind.alert,
          'w1',
          alertId: 'a2',
          resourceVersion: 1,
        ),
      );
      pending.complete(
        Success(_page([_alert(2), _alert(1)], const InventoryAlertQuery())),
      );
      clock.flushMicrotasks();
      expect(scope.notices, isEmpty);
      scope.dispose();
    });
  });

  test(
    'slow GETs never overlap; repeated refreshes coalesce one trailing GET',
    () {
      fakeAsync((clock) {
        final scope = _Scope();
        final pending = Completer<Result<InventoryPage<InventoryAlert>>>();
        scope.repository.onList = (_) => pending.future;
        scope.start();
        scope.controller.refresh();
        scope.controller.refresh();
        clock.elapse(const Duration(minutes: 2));
        expect(scope.repository.queries, hasLength(1));
        scope.repository.onList = (query) async =>
            Success(_page([_alert(2)], query));
        pending.complete(
          Success(_page([_alert(1)], const InventoryAlertQuery())),
        );
        clock.flushMicrotasks();
        expect(scope.repository.queries, hasLength(2));
        expect(scope.notices.single.alertIds, {'a2'});
        expect(scope.controller.state, InventoryAlertPollingState.active);
        scope.dispose();
      });
    },
  );

  test(
    'network retries back off and return to the regular interval after success',
    () {
      fakeAsync((clock) {
        final scope = _Scope();
        scope.repository.onList = (_) async => const Error(networkFailure);
        scope.start();
        clock.flushMicrotasks();
        expect(scope.controller.state, InventoryAlertPollingState.error);
        clock.elapse(const Duration(seconds: 20));
        expect(scope.repository.queries, hasLength(2));
        clock.elapse(const Duration(seconds: 39));
        expect(scope.repository.queries, hasLength(2));
        scope.repository.onList = (query) async =>
            Success(_page([_alert(1)], query));
        clock.elapse(const Duration(seconds: 1));
        expect(scope.repository.queries, hasLength(3));
        expect(scope.controller.state, InventoryAlertPollingState.active);
        expect(
          scope.notices,
          isEmpty,
        ); // First successful response is baseline.
        clock.elapse(const Duration(seconds: 20));
        expect(scope.repository.queries, hasLength(4));
        scope.dispose();
      });
    },
  );

  test('permission denials report once and do not retry in the same run', () {
    fakeAsync((clock) {
      var deniedCalls = 0;
      final scope = _Scope(
        onAccessDenied: (_) async {
          deniedCalls++;
          throw StateError('Recovery is unavailable');
        },
      );
      const denied = Failure(type: FailureType.forbidden, message: 'Denied');
      scope.repository.onList = (_) async => const Error(denied);
      scope.start();
      clock.flushMicrotasks();
      expect(scope.controller.state, InventoryAlertPollingState.error);
      expect(scope.controller.failure, denied);
      expect(deniedCalls, 1);
      scope.controller.refresh();
      clock.elapse(const Duration(minutes: 10));
      expect(scope.repository.queries, hasLength(1));
      expect(clock.pendingTimers, isEmpty);
      scope.dispose();
    });
  });

  test('a denied run can resume with a fresh silent baseline', () {
    fakeAsync((clock) {
      var deniedCalls = 0;
      final scope = _Scope(
        onAccessDenied: (_) async {
          deniedCalls++;
        },
      );
      const denied = Failure(type: FailureType.forbidden, message: 'Denied');
      scope.repository.onList = (_) async => const Error(denied);
      scope.start();
      clock.flushMicrotasks();
      clock.elapse(const Duration(minutes: 1));
      expect(scope.repository.queries, hasLength(1));
      expect(deniedCalls, 1);

      scope.controller.configure(enabled: true, foreground: false);
      expect(scope.controller.state, InventoryAlertPollingState.stopped);
      scope.repository.onList = (query) async =>
          Success(_page([_alert(2), _alert(1)], query));
      scope.controller.configure(enabled: true, foreground: true);
      clock.flushMicrotasks();
      expect(scope.repository.queries, hasLength(2));
      expect(scope.controller.state, InventoryAlertPollingState.active);
      expect(scope.controller.failure, isNull);
      expect(scope.notices, isEmpty);
      expect(deniedCalls, 1);
      scope.dispose();
    });
  });

  test('unexpected repository exceptions become retryable failures', () {
    fakeAsync((clock) {
      final scope = _Scope();
      scope.repository.onList = (_) => throw StateError('Unparseable data');
      scope.start();
      clock.flushMicrotasks();
      expect(scope.controller.state, InventoryAlertPollingState.error);
      expect(scope.controller.failure!.type, FailureType.internal);
      clock.elapse(const Duration(seconds: 20));
      expect(scope.repository.queries, hasLength(2));
      expect(scope.notices, isEmpty);
      scope.dispose();
    });
  });

  for (final pause in ['OFF', 'background']) {
    test('$pause drops pending work and resumes with a silent baseline', () {
      fakeAsync((clock) {
        final scope = _Scope();
        scope.repository.rows = [_alert(1)];
        scope.start();
        clock.flushMicrotasks();
        final pending = Completer<Result<InventoryPage<InventoryAlert>>>();
        scope.repository.onList = (_) => pending.future;
        scope.controller.refresh();
        scope.controller.configure(
          enabled: pause != 'OFF',
          foreground: pause != 'background',
        );
        expect(scope.controller.state, InventoryAlertPollingState.stopped);
        scope.controller.configure(enabled: true, foreground: true);
        clock.flushMicrotasks();
        expect(
          scope.repository.queries,
          hasLength(2),
        ); // Old physical read still in flight.
        scope.repository.onList = (query) async =>
            Success(_page([_alert(3), _alert(1)], query));
        pending.complete(
          Success(_page([_alert(2), _alert(1)], const InventoryAlertQuery())),
        );
        clock.flushMicrotasks();
        expect(scope.repository.queries, hasLength(3));
        expect(scope.notices, isEmpty);
        expect(scope.events.revision, 2); // Late pre-pause response is ignored.
        scope.repository.rows = [_alert(4), _alert(3), _alert(1)];
        scope.repository.onList = (query) async =>
            Success(_page(scope.repository.rows, query));
        clock.elapse(const Duration(seconds: 20));
        expect(scope.notices.single.alertIds, {'a4'});
        scope.dispose();
      });
    });
  }

  for (final change in ['logout', 'tenant', 'permission', 'dispose']) {
    test('$change fences late responses, notices and timers', () {
      fakeAsync((clock) {
        final scope = _Scope();
        final pending = Completer<Result<InventoryPage<InventoryAlert>>>();
        scope.repository.onList = (_) => pending.future;
        scope.start();
        switch (change) {
          case 'logout':
            scope.session = null;
          case 'tenant':
            scope.session = makeAppSession(
              restaurantId: 'other',
              permissions: alertPermissions,
              features: alertFeatures,
            );
          case 'permission':
            scope.session = makeAppSession();
          case 'dispose':
            scope.controller.dispose();
        }
        pending.complete(
          Success(_page([_alert(2)], const InventoryAlertQuery())),
        );
        clock.elapse(const Duration(minutes: 1));
        expect(scope.notices, isEmpty);
        expect(scope.events.revision, 0);
        expect(scope.repository.queries, hasLength(1));
        expect(clock.pendingTimers, isEmpty);
        if (change != 'dispose') {
          expect(scope.controller.state, InventoryAlertPollingState.stopped);
        }
        scope.dispose();
      });
    });
  }

  test('bootstrap stop can avoid provider notifications', () {
    fakeAsync((clock) {
      final scope = _Scope();
      var notifications = 0;
      scope.controller.addListener(() => notifications++);
      scope.start();
      clock.flushMicrotasks();
      final before = notifications;
      scope.controller.configure(
        enabled: false,
        foreground: false,
        notify: false,
      );
      expect(scope.controller.state, InventoryAlertPollingState.stopped);
      expect(notifications, before);
      expect(clock.pendingTimers, isEmpty);
      scope.dispose();
    });
  });
}
