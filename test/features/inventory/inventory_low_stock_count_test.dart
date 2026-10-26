import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_queries.dart';
import 'package:pos_saas_app/features/inventory/domain/use_cases/inventory_use_cases.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_events.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_low_stock_count_controller.dart';

import '../../helpers/auth_fakes.dart';
import 'inventory_fakes.dart';

AppSession _session({
  String tenant = 'restaurant-1',
  Set<String> permissions = const {'INVENTORY_VIEW'},
  Set<String> features = inventoryFeatures,
  UserRole role = UserRole.manager,
}) => makeAppSession(
  restaurantId: tenant,
  permissions: permissions,
  features: features,
  role: role,
);

InventoryPage<InventoryBalance> _page(int total) => inventoryPage(
  total == 0 ? <InventoryBalance>[] : [balance()],
  size: 1,
  total: total,
  pages: total,
);

class _CountRepository extends FakeBalances {
  final requests = <LowStockQuery>[];
  Future<Result<InventoryPage<InventoryBalance>>> Function(LowStockQuery)?
  respond;

  @override
  Future<Result<InventoryPage<InventoryBalance>>> lowStock(
    LowStockQuery query,
  ) {
    requests.add(query);
    return respond?.call(query) ?? Future.value(Success(_page(0)));
  }
}

class _Scope {
  _Scope({
    AppSession? initial,
    bool foreground = true,
    Future<void> Function(Failure)? onAccessDenied,
  }) {
    session = initial ?? _session();
    controller = InventoryLowStockCountController(
      session: () => session,
      events: events,
      get: GetLowStockBalances(repository),
      foreground: foreground,
      onAccessDenied: onAccessDenied,
    );
    addTearDown(dispose);
  }

  AppSession? session;
  final repository = _CountRepository();
  final events = InventoryEvents();
  late final InventoryLowStockCountController controller;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
    events.dispose();
  }
}

void main() {
  test(
    'count uses all-warehouse totals rather than the one-row sample',
    () async {
      final scope = _Scope();
      scope.repository.respond = (_) async => Success(_page(123));
      expect(scope.controller.count, isNull);

      await scope.controller.load();

      expect(scope.controller.count, 123);
      final query = scope.repository.requests.single;
      expect(query.warehouseId, isNull);
      expect(query.filters.q, isEmpty);
      expect(query.filters.ingredientActive, isNull);
      expect(query.filters.page, 0);
      expect(query.filters.size, 1);
      expect(scope.events.revision, 0);

      scope.repository.respond = (_) async => Success(_page(0));
      await scope.controller.load();
      expect(scope.controller.count, 0);
      expect(scope.controller.failure, isNull);
    },
  );

  test(
    'in-flight inventory bursts discard stale totals and make one follow-up GET',
    () {
      fakeAsync((clock) {
        final scope = _Scope();
        final first = Completer<Result<InventoryPage<InventoryBalance>>>();
        final next = Completer<Result<InventoryPage<InventoryBalance>>>();
        scope.repository.respond = (_) =>
            scope.repository.requests.length == 1 ? first.future : next.future;
        final observed = <int?>[];
        scope.controller.addListener(
          () => observed.add(scope.controller.count),
        );
        var completed = false;
        scope.controller.load().then((_) => completed = true);
        expect(scope.repository.requests, hasLength(1));

        for (final kind in [
          InventoryChangeKind.balance,
          InventoryChangeKind.orderStock,
          InventoryChangeKind.alertSync,
          InventoryChangeKind.warehouse,
        ]) {
          scope.events.emit(InventoryChange(kind, null));
        }
        clock.flushMicrotasks();
        expect(scope.repository.requests, hasLength(1));
        first.complete(Success(_page(99)));
        clock.flushMicrotasks();
        expect(scope.repository.requests, hasLength(2));
        expect(scope.controller.count, isNull);
        expect(completed, isFalse);

        next.complete(Success(_page(4)));
        clock.flushMicrotasks();
        expect(scope.controller.count, 4);
        expect(completed, isTrue);
        expect(observed, isNot(contains(99)));
        expect(scope.controller.loading, isFalse);
        expect(scope.repository.requests, hasLength(2));
      });
    },
  );

  test(
    'lock changes and local ACK do not reload; stock hints coalesce without polling',
    () {
      fakeAsync((clock) {
        final scope = _Scope();
        scope.repository.respond = (_) async => Success(_page(3));
        scope.controller.load();
        clock.flushMicrotasks();
        scope.events.lock('balance:w1:i1');
        scope.events.unlock('balance:w1:i1');
        scope.events.emit(
          const InventoryChange(InventoryChangeKind.alert, null, alertId: 'a1'),
        );
        clock.flushMicrotasks();
        expect(scope.repository.requests, hasLength(1));

        scope.events.emit(
          const InventoryChange(InventoryChangeKind.balance, 'w1'),
        );
        scope.events.emit(
          const InventoryChange(InventoryChangeKind.balance, 'w2'),
        );
        scope.events.emit(
          const InventoryChange(InventoryChangeKind.alertSync, null),
        );
        clock.flushMicrotasks();
        expect(scope.repository.requests, hasLength(2));
        expect(scope.controller.count, 3);

        clock.elapse(const Duration(minutes: 5));
        expect(scope.repository.requests, hasLength(2));
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test(
    'background ignores reads and stale responses; resume reloads current totals',
    () {
      fakeAsync((clock) {
        final scope = _Scope(foreground: false);
        final first = Completer<Result<InventoryPage<InventoryBalance>>>();
        scope.repository.respond = (_) => scope.repository.requests.length == 1
            ? first.future
            : Future.value(Success(_page(6)));
        scope.controller.load();
        clock.flushMicrotasks();
        expect(scope.repository.requests, isEmpty);

        scope.controller.setForeground(true);
        expect(scope.repository.requests, hasLength(1));
        scope.controller.setForeground(false);
        first.complete(Success(_page(2)));
        clock.flushMicrotasks();
        scope.events.emit(
          const InventoryChange(InventoryChangeKind.balance, 'w1'),
        );
        clock.elapse(const Duration(minutes: 1));
        expect(scope.repository.requests, hasLength(1));
        expect(scope.controller.count, isNull);

        scope.controller.setForeground(true);
        clock.flushMicrotasks();
        expect(scope.repository.requests, hasLength(2));
        expect(scope.controller.count, 6);
        clock.elapse(const Duration(minutes: 1));
        expect(scope.repository.requests, hasLength(2));
      });
    },
  );

  for (final dispose in [false, true]) {
    test(
      '${dispose ? 'disposal' : 'tenant change'} fences late totals and further GETs',
      () {
        fakeAsync((clock) {
          final scope = _Scope();
          scope.repository.respond = (_) async => Success(_page(2));
          scope.controller.load();
          clock.flushMicrotasks();
          expect(scope.controller.count, 2);
          final pending = Completer<Result<InventoryPage<InventoryBalance>>>();
          scope.repository.respond = (_) => pending.future;
          scope.controller.load();
          if (dispose) {
            scope.dispose();
          } else {
            scope.session = _session(tenant: 'restaurant-2');
          }
          expect(scope.controller.count, isNull);
          pending.complete(Success(_page(70)));
          clock.flushMicrotasks();
          scope.controller.load();
          clock.flushMicrotasks();
          expect(scope.controller.count, isNull);
          expect(scope.repository.requests, hasLength(2));
        });
      },
    );
  }

  test('missing inventory capability never fetches a badge count', () async {
    for (final session in [
      _session(permissions: {}),
      _session(features: {'INVENTORY_MANAGEMENT'}),
      _session(features: {'LOW_STOCK_ALERT'}),
      _session(role: UserRole.cashier),
    ]) {
      final scope = _Scope(initial: session);
      await scope.controller.load();
      expect(scope.repository.requests, isEmpty);
      expect(scope.controller.count, isNull);
      scope.dispose();
    }
  });

  for (final failure in [
    networkFailure,
    const Failure(
      type: FailureType.forbidden,
      code: 'FORBIDDEN',
      message: 'Không có quyền.',
    ),
  ]) {
    test(
      '${failure.type.name} leaves count unknown and never automatically retries',
      () {
        fakeAsync((clock) {
          var recoveries = 0;
          final scope = _Scope(
            onAccessDenied: (_) async {
              recoveries++;
            },
          );
          scope.repository.respond = (_) async => Success(_page(5));
          scope.controller.load();
          clock.flushMicrotasks();
          expect(scope.controller.count, 5);

          scope.repository.respond = (_) async => Error(failure);
          scope.controller.load();
          clock.flushMicrotasks();
          expect(scope.controller.count, isNull);
          expect(scope.controller.failure, same(failure));
          expect(recoveries, failure.type == FailureType.forbidden ? 1 : 0);
          scope.events.lock('count-recovery');
          scope.events.unlock('count-recovery');
          clock.elapse(const Duration(minutes: 2));
          expect(scope.repository.requests, hasLength(2));
          expect(clock.pendingTimers, isEmpty);

          scope.repository.respond = (_) async => Success(_page(0));
          scope.controller.load();
          clock.flushMicrotasks();
          expect(scope.controller.count, 0);
          expect(scope.controller.failure, isNull);
        });
      },
    );
  }
}
