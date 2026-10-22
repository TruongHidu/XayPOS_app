import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_audit_dto.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_quantity.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_audit.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_audit_queries.dart';
import 'package:pos_saas_app/features/inventory/domain/use_cases/inventory_use_cases.dart';
import 'package:pos_saas_app/features/inventory/domain/use_cases/stock_audit_use_cases.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_events.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/stock_audit_create_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/stock_audit_detail_controller.dart';
import '../../helpers/auth_fakes.dart';
import 'inventory_fakes.dart';
import 'stock_audit_fakes.dart';
import 'stock_fakes.dart';

AppSession _session({
  Set<String> permissions = stockAuditPermissions,
  Set<String> features = stockAuditFeatures,
}) => makeAppSession(permissions: permissions, features: features);
const _concurrent = Failure(
  type: FailureType.conflict,
  code: 'CONCURRENT_STOCK_AUDIT_UPDATE',
  message: 'Phiên đã thay đổi',
);
StockAuditDetailController _controller(
  FakeStockAudits repo,
  InventoryEvents events, {
  AppSession? Function()? session,
}) => StockAuditDetailController(
  id: 'a1',
  session: session ?? () => _session(),
  events: events,
  get: GetStockAudit(repo),
  getItems: GetStockAuditItems(repo),
  updateNote: UpdateStockAuditNote(repo),
  start: StartStockAudit(repo),
  updateCounts: UpdateStockAuditCounts(repo),
  confirm: ConfirmStockAudit(repo),
  cancel: CancelStockAudit(repo),
);
Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'a definite replay conflict requires review then permits a new explicit command',
    () async {
      final repo = FakeStockAudits()..value = stockAuditJson(counted: 2),
          events = InventoryEvents();
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      repo.onConfirm = (_, _) async => const Error(networkFailure);
      await c.post();
      repo.value = {...repo.value, 'version': 5};
      await c.verify();
      repo.onConfirm = (_, _) async => const Error(_concurrent);
      await c.retryPendingTransition();
      expect(repo.versions, [2, 2]);
      expect(c.pendingCommand, isNull);
      expect(c.requiresReview, true);
      await c.verify();
      c.acknowledgeReview();
      expect(c.canPost, true);
      repo.onConfirm = null;
      await c.post();
      expect(repo.versions, [2, 2, 5]);
    },
  );

  test(
    'refresh updates untouched field epoch but preserves dirty raw input',
    () async {
      final repo = FakeStockAudits(), events = InventoryEvents();
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      repo.rows[0] = stockAuditItemJson(counted: 9, note: 'New note');
      repo.value = {...repo.value, 'version': 3};
      await c.load();
      expect(c.epoch('ai1'), 1);
      expect(c.requiresReview, false);
      c.edit(c.rows.first, rawQuantity: '7');
      repo.rows[0] = stockAuditItemJson(counted: 6, note: 'Another note');
      repo.value = {...repo.value, 'version': 4};
      await c.load();
      expect(c.epoch('ai1'), 1);
      expect(c.draft('ai1')!.rawQuantity, '7');
      expect(c.rows.first.countedQuantity, InventoryQuantity.parse('6'));
      expect(c.requiresReview, true);
    },
  );
  test(
    'ordinary refresh with dirty rows and new version requires explicit comparison',
    () async {
      final repo = FakeStockAudits(), events = InventoryEvents();
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      c.edit(c.rows.first, rawQuantity: '9');
      repo.value = {...repo.value, 'version': 3};
      repo.rows[0] = stockAuditItemJson(counted: 7);
      await c.load();
      expect(c.requiresReview, true);
      expect(c.editable, false);
      expect(
        c.draft('ai1')!.baseline.countedQuantity,
        InventoryQuantity.parse('8'),
      );
      expect(c.draft('ai1')!.rawQuantity, '9');
      expect(c.rows.first.countedQuantity, InventoryQuantity.parse('7'));
      expect(await c.saveCounts(), isA<Error>());
      expect(repo.savedBatches, isEmpty);
      await c.verify();
      c.acknowledgeReview();
      await c.saveCounts();
      expect(repo.savedBatches.single.expectedVersion, 3);
    },
  );

  test(
    'pre-command items response cannot replace accepted count or newer filtered page',
    () async {
      final repo = FakeStockAudits(),
          events = InventoryEvents(),
          late = Completer<Result<InventoryPage<StockAuditItem>>>();
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      final previous = inventoryPage(c.rows);
      repo.onItems = (_, _) => late.future;
      final oldRead = c.loadItems();
      c.edit(c.rows.first, rawQuantity: '9');
      repo.onItems = null;
      await c.saveCounts();
      expect(c.rows.first.countedQuantity, InventoryQuantity.parse('9'));
      late.complete(Success(previous));
      await oldRead;
      expect(c.rows.first.countedQuantity, InventoryQuantity.parse('9'));
      expect(c.requiresReview, false);
    },
  );

  test(
    'header note draft remains after rejected save and ordinary refresh conflict',
    () async {
      final repo = FakeStockAudits(), events = InventoryEvents();
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      repo.onUpdateNote = (_, _) async => const Error(_concurrent);
      await c.saveNote('Nháp ghi chú');
      expect(c.headerNoteDraft, 'Nháp ghi chú');
      expect(c.dirty, true);
      expect(c.requiresReview, true);
      await c.verify();
      c.acknowledgeReview();
      repo.onUpdateNote = null;
      await c.saveDrafts();
      expect(c.headerNoteDraft, isNull);
      expect(c.audit!.note, 'Nháp ghi chú');
      expect(c.dirty, false);
    },
  );
  test(
    'draft has no implicit items read; start reads paged snapshot',
    () async {
      final repo = FakeStockAudits()
            ..value = stockAuditJson(status: 'DRAFT', version: 0),
          events = InventoryEvents();
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      expect(c.audit!.status, StockAuditStatus.draft);
      expect(repo.itemQueries, isEmpty);
      await c.startCounting();
      expect(repo.starts, 1);
      expect(repo.versions, [0]);
      expect(c.audit!.status, StockAuditStatus.counting);
      expect(repo.itemQueries.single.page, 0);
      expect(c.rows, hasLength(2));
    },
  );

  test(
    'null differs from zero and raw drafts survive pages and filters',
    () async {
      final repo = FakeStockAudits(), events = InventoryEvents();
      final sheet = _controller(repo, events);
      addTearDown(sheet.dispose);
      addTearDown(events.dispose);
      sheet.query = const StockAuditItemQuery(size: 1);
      await sheet.load();
      sheet.edit(sheet.rows.single, rawQuantity: '0');
      expect(sheet.draft('ai1')!.quantity, InventoryQuantity.zero);
      sheet.page(1);
      await _tick();
      expect(sheet.rows.single.countedQuantity, isNull);
      sheet.edit(sheet.rows.single, rawQuantity: '0,001');
      sheet.filter(sheet.query.copyWith(counted: () => true));
      await _tick();
      expect(sheet.dirtyCount, 2);
      expect(sheet.draft('ai2')!.rawQuantity, '0,001');
      expect(sheet.canPost, false);
      await sheet.saveCounts();
      expect(repo.savedBatches.single.items.map((e) => e.auditItemId), [
        'ai1',
        'ai2',
      ]);
      expect(
        repo.savedBatches.single.items.first.countedQuantity,
        InventoryQuantity.zero,
      );
      expect(sheet.dirty, false);
    },
  );

  test(
    'invalid raw input persists and blank never resets saved count',
    () async {
      final repo = FakeStockAudits(), events = InventoryEvents();
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      c.edit(c.rows.last, rawQuantity: '0.0001');
      expect(c.draft('ai2')!.error, isNotNull);
      c.edit(c.rows.first, rawQuantity: '');
      expect(c.draft('ai1')!.error, contains('không xóa'));
      expect(await c.saveCounts(), isA<Error>());
      expect(repo.savedBatches, isEmpty);
      expect(c.dirtyCount, 2);
    },
  );

  test(
    '201 dirty rows save sequential batches using actual no-op versions',
    () async {
      final repo = FakeStockAudits()
            ..rows = [
              for (var i = 0; i < 201; i++)
                stockAuditItemJson(id: 'a$i', ingredient: 'i$i', counted: null),
            ],
          events = InventoryEvents();
      repo.value = stockAuditJson(
        itemCount: 201,
        counted: 0,
        changed: 0,
        version: 7,
      );
      var active = 0, maximum = 0;
      repo.onUpdateCounts = (_, input) async {
        active++;
        if (active > maximum) maximum = active;
        await _tick();
        active--;
        // No-op for the first batch: the next request must still use 7.
        final next = repo.savedBatches.length == 1
            ? 7
            : input.expectedVersion + 1;
        repo.value = {...repo.value, 'version': next};
        return Success(StockAuditDto.detail(repo.value));
      };
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      for (final raw in repo.rows) {
        c.edit(StockAuditDto.item(raw), rawQuantity: '8');
      }
      expect(await c.saveCounts(), isA<Success>());
      expect(repo.savedBatches.map((b) => b.items.length), [100, 100, 1]);
      expect(repo.versions, [7, 7, 8]);
      expect(maximum, 1);
      expect(c.dirty, false);
    },
  );

  test(
    'middle batch failure keeps saved rows clear and unsent raw drafts',
    () async {
      final repo = FakeStockAudits()
            ..rows = [
              for (var i = 0; i < 205; i++)
                stockAuditItemJson(id: 'a$i', ingredient: 'i$i', counted: null),
            ],
          events = InventoryEvents();
      repo.value = stockAuditJson(itemCount: 205, counted: 0, changed: 0);
      repo.onUpdateCounts = (_, input) async {
        if (repo.savedBatches.length == 2) return const Error(_concurrent);
        repo.value = {...repo.value, 'version': input.expectedVersion + 1};
        return Success(StockAuditDto.detail(repo.value));
      };
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      for (final raw in repo.rows) {
        c.edit(StockAuditDto.item(raw), rawQuantity: '9');
      }
      expect(await c.saveCounts(), isA<Error>());
      expect(c.savedInLastRun, 100);
      expect(c.dirtyCount, 105);
      expect(c.draft('a0'), isNull);
      expect(c.draft('a204')!.rawQuantity, '9');
      expect(repo.savedBatches, hasLength(2));
      expect(c.requiresReview, true);
      await c.verify();
      expect(c.hasCompared, true);
      expect(c.editable, false);
      c.acknowledgeReview();
      expect(c.editable, true);
      expect(c.dirtyCount, 105);
    },
  );

  test(
    'whole audit lock blocks note and new edits until save resolves',
    () async {
      final repo = FakeStockAudits(),
          events = InventoryEvents(),
          gate = Completer<Result<StockAuditDetail>>();
      repo.onUpdateCounts = (_, _) => gate.future;
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      c.edit(c.rows.first, rawQuantity: '9');
      final pending = c.saveCounts();
      expect(c.busy, true);
      c.edit(c.rows.first, rawQuantity: '11');
      expect(c.draft('ai1')!.rawQuantity, '9');
      expect(await c.saveNote('racing note'), isA<Error>());
      expect(repo.notes, 0);
      gate.complete(Success(stockAudit(version: 3)));
      await pending;
      expect(c.busy, false);
    },
  );

  test(
    'manage and confirm are independent; missing feature makes no reads',
    () async {
      final repo = FakeStockAudits()..value = stockAuditJson(counted: 2),
          events = InventoryEvents();
      var session = _session(
        permissions: {'INVENTORY_VIEW', 'STOCK_AUDIT_CONFIRM'},
      );
      final c = _controller(repo, events, session: () => session);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      expect(c.editable, false);
      expect(c.canPost, true);
      expect(await c.post(), isA<Success>());
      expect(repo.confirms, 1);
      session = _session(features: {'INVENTORY_MANAGEMENT'});
      final denied = _controller(repo, events, session: () => session);
      addTearDown(denied.dispose);
      final before = repo.details;
      await denied.load();
      expect(repo.details, before);
      expect(await denied.startCounting(), isA<Error>());
    },
  );

  test(
    'create timeout freezes body/key and replays through retained controller',
    () async {
      final repo = FakeStockAudits(),
          events = InventoryEvents(),
          keys = FakeStockKeys();
      final c = StockAuditCreateController(
        session: () => _session(),
        events: events,
        create: CreateStockAudit(repo),
        getWarehouse: GetWarehouse(FakeWarehouses()),
        keys: keys,
      );
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      c.selectWarehouse(warehouse());
      c.setNote('Cuối ca');
      repo.onCreate = (_, _) async => const Error(networkFailure);
      await c.save();
      expect(c.uncertain, true);
      c.setNote('Changed');
      c.selectWarehouse(warehouse(id: 'w2'));
      c.begin();
      expect(c.note, 'Cuối ca');
      expect(c.warehouse!.id, 'w1');
      repo.onCreate = null;
      await c.save();
      expect(repo.sentKeys, hasLength(2));
      expect(repo.sentKeys[0], repo.sentKeys[1]);
      expect(identical(repo.sentInputs[0], repo.sentInputs[1]), true);
      expect(c.result!.id, 'created-audit');
      expect(c.uncertain, false);
    },
  );

  test(
    'uncertain saved counts verify every pending row and clear only after match',
    () async {
      final repo = FakeStockAudits(), events = InventoryEvents();
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      c.edit(c.rows.first, rawQuantity: '9');
      repo.onUpdateCounts = (_, _) async {
        repo.rows[0] = stockAuditItemJson(counted: 9);
        repo.value = {...repo.value, 'version': 3};
        return const Error(networkFailure);
      };
      await c.saveCounts();
      expect(c.pendingCommand!.kind, StockAuditCommand.counts);
      expect(c.dirty, true);
      await c.verify();
      expect(c.pendingCommand, isNull);
      expect(c.dirty, false);
      expect(c.requiresReview, false);
      expect(c.rows.first.countedQuantity, InventoryQuantity.parse('9'));
      expect(repo.savedBatches, hasLength(1));
    },
  );

  test(
    'uncertain PATCH with failed compare stays frozen; mismatch needs explicit acknowledgement',
    () async {
      final repo = FakeStockAudits(), events = InventoryEvents();
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      c.edit(c.rows.first, rawQuantity: '9');
      repo.onUpdateCounts = (_, _) async => const Error(networkFailure);
      await c.saveCounts();
      repo.onItems = (_, _) async => const Error(networkFailure);
      await c.verify();
      expect(c.hasCompared, false);
      c.acknowledgeUnappliedPatch();
      expect(c.pendingCommand, isNotNull);
      repo.onItems = null;
      await c.verify();
      expect(c.hasCompared, true);
      expect(c.editable, false);
      expect(repo.savedBatches, hasLength(1));
      c.acknowledgeUnappliedPatch();
      expect(c.editable, true);
      expect(c.dirty, true);
    },
  );

  for (final scenario in [
    (
      label: 'quantity-only PATCH preserves a newer server note',
      note: null,
      serverNote: 'Ghi chú từ thiết bị khác',
      applied: true,
    ),
    (
      label: 'edited note must match the server',
      note: 'Ghi chú đã sửa',
      serverNote: 'Ghi chú từ thiết bị khác',
      applied: false,
    ),
    (
      label: 'edited note matches after trimming',
      note: '  Ghi chú đã sửa  ',
      serverNote: 'Ghi chú đã sửa',
      applied: true,
    ),
    (
      label: 'explicit note clearing matches a null server note',
      note: '   ',
      serverNote: null,
      applied: true,
    ),
    (
      label: 'explicit note clearing rejects an unchanged server note',
      note: '',
      serverNote: 'Đếm thực tế',
      applied: false,
    ),
  ]) {
    test('uncertain count verification: ${scenario.label}', () async {
      final repo = FakeStockAudits(), events = InventoryEvents();
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      c.edit(c.rows.first, rawQuantity: '9', note: scenario.note);
      repo.onUpdateCounts = (_, _) async {
        repo.rows[0] = stockAuditItemJson(
          counted: 9,
          note: scenario.serverNote,
        );
        repo.value = {...repo.value, 'version': 4};
        return const Error(networkFailure);
      };
      await c.saveCounts();
      expect(repo.savedBatches.single.items.single.note, scenario.note);
      expect(c.pendingCommand, isNotNull);
      await c.verify();
      expect(c.hasCompared, true);
      expect(c.pendingCommand == null, scenario.applied);
      expect(c.dirty, !scenario.applied);
      expect(c.requiresReview, !scenario.applied);
      expect(c.rows.first.note, scenario.serverNote);
      expect(repo.savedBatches, hasLength(1));
    });
  }

  test(
    'confirm timeout replays original version and never creates an adjustment manually',
    () async {
      final repo = FakeStockAudits()..value = stockAuditJson(counted: 2),
          events = InventoryEvents();
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      repo.onConfirm = (_, _) async => const Error(networkFailure);
      await c.post();
      expect(c.requiresReview, true);
      repo.value = {...repo.value, 'version': 5};
      await c.verify();
      expect(c.pendingCommand, isNotNull);
      repo.onConfirm = (_, input) async =>
          Success(stockAudit(status: 'CONFIRMED', version: 6, counted: 2));
      await c.retryPendingTransition();
      expect(repo.versions, [2, 2]);
      expect(c.audit!.status, StockAuditStatus.confirmed);
      expect(c.audit!.adjustmentDocumentId, 'adjustment-a1');
      expect(repo.sentKeys, isEmpty);
    },
  );

  test(
    'stock signals never rebase or declare stale; server stale blocks confirm but allows cancel',
    () async {
      final repo = FakeStockAudits()..value = stockAuditJson(counted: 2),
          events = InventoryEvents();
      final c = _controller(repo, events);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      final baseline = c.rows.first.systemQuantity;
      events.emit(
        const InventoryChange(
          InventoryChangeKind.orderStock,
          null,
          orderId: 'o1',
        ),
      );
      expect(c.stockMayHaveChanged, true);
      expect(c.snapshotStale, false);
      expect(c.canPost, true);
      expect(c.rows.first.systemQuantity, baseline);
      repo.onConfirm = (_, _) async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'STOCK_AUDIT_SNAPSHOT_STALE',
          message: 'Biến động vật lý',
        ),
      );
      await c.post();
      expect(c.snapshotStale, true);
      expect(c.audit!.status, StockAuditStatus.counting);
      await c.verify();
      c.acknowledgeReview();
      expect(c.canPost, false);
      expect(c.headerEditable, true);
      await c.cancelAudit(null);
      expect(c.audit!.status, StockAuditStatus.cancelled);
    },
  );

  test(
    'no-difference confirm emits only audit; actual adjustment emits document and balance',
    () async {
      for (final changed in [0, 1]) {
        final repo = FakeStockAudits()
              ..value = stockAuditJson(counted: 2, changed: changed),
            events = InventoryEvents();
        final c = _controller(repo, events);
        final seen = <InventoryChangeKind>[];
        var revision = 0;
        events.addListener(() {
          if (revision != events.revision) {
            revision = events.revision;
            seen.add(events.change!.kind);
          }
        });
        await c.load();
        await c.post();
        expect(
          seen,
          changed == 0
              ? [InventoryChangeKind.audit]
              : [
                  InventoryChangeKind.audit,
                  InventoryChangeKind.document,
                  InventoryChangeKind.balance,
                ],
        );
        c.dispose();
        events.dispose();
      }
    },
  );

  test(
    'late reads and mutations cannot publish into changed tenant scope',
    () async {
      final repo = FakeStockAudits(),
          events = InventoryEvents(),
          gate = Completer<Result<StockAuditDetail>>();
      AppSession? session = _session();
      repo.onGet = (_) => gate.future;
      final c = _controller(repo, events, session: () => session);
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      final read = c.load();
      session = makeAppSession(
        restaurantId: 'other',
        permissions: stockAuditPermissions,
        features: stockAuditFeatures,
      );
      gate.complete(Success(stockAudit()));
      await read;
      expect(c.audit, isNull);
      expect(repo.itemQueries, isEmpty);
      expect(await c.saveNote('wrong tenant'), isA<Error>());
      expect(repo.notes, 0);
    },
  );
}
