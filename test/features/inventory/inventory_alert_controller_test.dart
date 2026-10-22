import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_alert.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/inventory/domain/use_cases/inventory_alert_use_cases.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_alert_list_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_alert_detail_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_events.dart';
import '../../helpers/auth_fakes.dart';
import 'inventory_alert_fakes.dart';
import 'inventory_fakes.dart';

InventoryAlertListController _list(
  FakeInventoryAlerts repo,
  InventoryEvents events,
  AppSession? Function() session,
) => InventoryAlertListController(
  session: session,
  events: events,
  get: GetInventoryAlerts(repo),
);
InventoryAlertDetailController _detail(
  FakeInventoryAlerts repo,
  InventoryEvents events,
  AppSession? Function() session,
) => InventoryAlertDetailController(
  session: session,
  events: events,
  id: 'a1',
  get: GetInventoryAlert(repo),
  ack: AcknowledgeInventoryAlert(repo),
);
AppSession _session({
  Set<String> permissions = alertPermissions,
  Set<String> features = alertFeatures,
  String tenant = 'restaurant-1',
}) => makeAppSession(
  permissions: permissions,
  features: features,
  restaurantId: tenant,
);
Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'capability needs both features and effective view; owner has no implicit ACK',
    () async {
      for (final s in [
        _session(permissions: {}),
        _session(features: {'INVENTORY_MANAGEMENT'}),
        _session(features: {'LOW_STOCK_ALERT'}),
      ]) {
        final repo = FakeInventoryAlerts(), events = InventoryEvents();
        final a = _list(repo, events, () => s);
        final b = _detail(repo, events, () => s);
        await a.load();
        await b.load();
        await b.acknowledge();
        expect(repo.queries, isEmpty);
        expect(repo.detailIds, isEmpty);
        expect(repo.acknowledgements, isEmpty);
        expect(AccessPolicy.canViewInventoryAlerts(s), false);
        a.dispose();
        b.dispose();
        events.dispose();
      }
      final s = _session(permissions: {'INVENTORY_VIEW'}),
          repo = FakeInventoryAlerts(),
          events = InventoryEvents();
      final d = _detail(repo, events, () => s);
      await d.load();
      expect(d.value, isNotNull);
      expect(d.canAcknowledge, false);
      await d.acknowledge();
      expect(repo.acknowledgements, isEmpty);
      d.dispose();
      events.dispose();
    },
  );
  test(
    'ACK keeps server actor/version and emits alert only; list is full DTO no detail N+1',
    () async {
      final s = _session(),
          repo = FakeInventoryAlerts(),
          events = InventoryEvents();
      final a = _list(repo, events, () => s),
          b = _detail(repo, events, () => s);
      await a.load();
      expect(repo.detailIds, isEmpty);
      await b.load();
      expect(await b.acknowledge(), isA<Success>());
      await _tick();
      expect(repo.acknowledgements.single.input.expectedVersion, 0);
      expect(events.change!.kind, InventoryChangeKind.alert);
      expect(events.change!.alertId, 'a1');
      expect(b.value!.acknowledgedBy, 'user-ack');
      expect(b.value!.version, 1);
      expect(a.rows, isEmpty);
      expect(b.canAcknowledge, false);
      a.dispose();
      b.dispose();
      events.dispose();
    },
  );
  test(
    'shared ACK lock prevents duplicate calls across detail controllers',
    () async {
      final s = _session(),
          repo = FakeInventoryAlerts(),
          events = InventoryEvents();
      final a = _detail(repo, events, () => s),
          b = _detail(repo, events, () => s);
      await Future.wait([a.load(), b.load()]);
      final pending = Completer<Result<InventoryAlert>>();
      repo.onAcknowledge = (_, _) => pending.future;
      final command = a.acknowledge();
      await b.acknowledge();
      expect(repo.acknowledgements, hasLength(1));
      pending.complete(
        Success(inventoryAlert(status: 'ACKNOWLEDGED', version: 8)),
      );
      await command;
      await _tick();
      expect(a.value!.version, 8);
      a.dispose();
      b.dispose();
      events.dispose();
    },
  );
  test(
    'stale ACK requires fresh detail before another attempt; RESOLVED never ACKs',
    () async {
      final s = _session(),
          repo = FakeInventoryAlerts(),
          events = InventoryEvents();
      final c = _detail(repo, events, () => s);
      await c.load();
      repo.onAcknowledge = (_, _) async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'CONCURRENT_LOW_STOCK_ALERT_UPDATE',
          message: 'Tải lại',
        ),
      );
      await c.acknowledge();
      await c.acknowledge();
      expect(repo.acknowledgements, hasLength(1));
      expect(c.requiresReview, true);
      repo.rows = [inventoryAlert(status: 'RESOLVED')];
      await c.load();
      expect(c.requiresReview, false);
      expect(c.canAcknowledge, false);
      await c.acknowledge();
      expect(repo.acknowledgements, hasLength(1));
      c.dispose();
      events.dispose();
    },
  );
  test(
    'timeout ACK retains original state until authoritative readback without another POST',
    () async {
      final s = _session(),
          repo = FakeInventoryAlerts(),
          events = InventoryEvents();
      final c = _detail(repo, events, () => s);
      await c.load();
      repo.onAcknowledge = (_, _) async => const Error(networkFailure);
      await c.acknowledge();
      expect(c.value!.status, InventoryAlertStatus.open);
      expect(c.requiresReview, true);
      await c.acknowledge();
      expect(repo.acknowledgements, hasLength(1));
      repo.rows = [inventoryAlert(status: 'ACKNOWLEDGED', version: 9)];
      await c.load();
      expect(c.value!.version, 9);
      expect(c.value!.acknowledgedBy, 'user-ack');
      expect(c.requiresReview, false);
      expect(c.canAcknowledge, false);
      expect(repo.acknowledgements, hasLength(1));
      c.dispose();
      events.dispose();
    },
  );
  test(
    'relevant stock events coalesce; unrelated warehouse/doc and audit edits do not refresh',
    () async {
      final s = _session(),
          repo = FakeInventoryAlerts(),
          events = InventoryEvents();
      final a = _list(repo, events, () => s);
      a.query = a.query.copyWith(warehouseId: () => 'w1');
      await a.load();
      for (final kind in [
        InventoryChangeKind.document,
        InventoryChangeKind.audit,
      ]) {
        events.emit(InventoryChange(kind, 'w1'));
      }
      events.emit(const InventoryChange(InventoryChangeKind.balance, 'w2'));
      await _tick();
      expect(repo.queries, hasLength(1));
      events.emit(const InventoryChange(InventoryChangeKind.orderStock, null));
      events.emit(const InventoryChange(InventoryChangeKind.balance, 'w1'));
      await _tick();
      expect(repo.queries, hasLength(2));
      a.dispose();
      events.dispose();
    },
  );
  test(
    'late old query and tenant results cannot replace latest rows',
    () async {
      AppSession? s = _session();
      final repo = FakeInventoryAlerts(), events = InventoryEvents();
      final a = _list(repo, events, () => s),
          b = _detail(repo, events, () => s);
      final old = Completer<Result<InventoryPage<InventoryAlert>>>();
      repo.onList = (_) => old.future;
      final first = a.load();
      a.search('new');
      repo.onList = (_) async =>
          Success(inventoryPage([inventoryAlert(id: 'new')]));
      await a.load();
      old.complete(Success(inventoryPage([inventoryAlert(id: 'old')])));
      await first;
      expect(a.rows.single.id, 'new');
      final late = Completer<Result<InventoryAlert>>();
      repo.onDetail = (_) => late.future;
      final get = b.load();
      s = _session(tenant: 'other');
      late.complete(Success(inventoryAlert()));
      await get;
      expect(b.value, null);
      a.dispose();
      b.dispose();
      events.dispose();
    },
  );
}
