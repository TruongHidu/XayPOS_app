import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_document.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_queries.dart';
import 'package:pos_saas_app/features/inventory/domain/use_cases/stock_document_use_cases.dart';
import 'package:pos_saas_app/features/inventory/domain/use_cases/inventory_use_cases.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/stock_document_create_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/stock_document_detail_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/stock_document_list_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_transaction_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_balance_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_events.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_balance_detail_controller.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_inputs.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_quantity.dart';
import '../../helpers/auth_fakes.dart';
import 'stock_fakes.dart';
import 'inventory_fakes.dart';

AppSession _session({
  Set<String> permissions = stockPermissions,
  String tenant = 'restaurant-1',
}) => makeAppSession(
  permissions: permissions,
  features: {'INVENTORY_MANAGEMENT'},
  restaurantId: tenant,
);
StockDocumentCreateController _create(
  FakeStockDocuments repo,
  FakeWarehouses wh,
  InventoryEvents events,
  AppSession? Function() session, {
  FakeStockKeys? keys,
}) => StockDocumentCreateController(
  session: session,
  events: events,
  create: CreateStockDocument(repo),
  getWarehouse: GetWarehouse(wh),
  keys: keys ?? FakeStockKeys(),
);
StockDocumentDetailController _detail(
  FakeStockDocuments repo,
  FakeWarehouses wh,
  InventoryEvents events,
  AppSession? Function() session,
) => StockDocumentDetailController(
  session: session,
  events: events,
  id: 'd1',
  get: GetStockDocument(repo),
  update: UpdateStockDocument(repo),
  addItem: AddStockDocumentItem(repo),
  updateItem: UpdateStockDocumentItem(repo),
  removeItem: RemoveStockDocumentItem(repo),
  confirm: ConfirmStockDocument(repo),
  cancel: CancelStockDocument(repo),
  getWarehouse: GetWarehouse(wh),
);
Future<void> _tick() => Future<void>.delayed(Duration.zero);
void main() {
  test(
    'ingredient becomes inactive after selection: conflict requires readback before another attempt',
    () async {
      final s = _session(),
          repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          events = InventoryEvents(),
          c = _detail(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      await c.load();
      final before = c.document!;
      repo.onAdd = (id, input) async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'INGREDIENT_INACTIVE_FOR_RECEIPT',
          message: 'Inactive',
        ),
      );
      await c.saveLine(before, stockLine(id: 'i2'));
      expect(c.requiresReview, true);
      expect(c.document, same(before));
      await c.saveLine(before, stockLine(id: 'i2'));
      expect(repo.adds, 1);
      await c.load();
      expect(c.requiresReview, false);
      expect(repo.adds, 1);
    },
  );
  test(
    'posting invalidates open threshold baseline without overwriting its snapshot',
    () async {
      final s = _session(),
          wh = FakeWarehouses(),
          repo = FakeBalances(),
          events = InventoryEvents();
      final c = InventoryBalanceDetailController(
        session: () => s,
        events: events,
        warehouseId: 'w1',
        ingredientId: 'i1',
        getBalance: GetInventoryBalance(repo),
        getWarehouse: GetWarehouse(wh),
        updateThreshold: UpdateInventoryThreshold(repo),
      );
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      await c.load();
      final before = c.balance!;
      events.emit(
        const InventoryChange(
          InventoryChangeKind.balance,
          'w1',
          documentId: 'posted',
        ),
      );
      expect(c.balance, same(before));
      expect(c.canSave, false);
      expect(c.failure!.type, FailureType.conflict);
      expect(
        await c.save(
          before,
          UpdateInventoryThresholdInput(before.version, InventoryQuantity.zero),
        ),
        isA<Error>(),
      );
      expect(repo.saves, 0);
      repo.onDetail = (w, i) async =>
          Success(balance(quantity: 50, version: 7));
      await c.load();
      expect(c.canSave, true);
      expect(c.balance!.version, 7);
    },
  );
  test(
    'inventory route and type permissions are independent of menu and low stock',
    () {
      final viewer = _session(permissions: {'INVENTORY_VIEW'}),
          receiver = _session(
            permissions: {'INVENTORY_VIEW', 'INVENTORY_RECEIVE'},
          );
      expect(
        AccessPolicy.canOpenRoute(viewer, '/app/inventory/stock-documents/d1'),
        true,
      );
      expect(
        AccessPolicy.canOpenRoute(
          viewer,
          '/app/inventory/transactions?documentId=d1',
        ),
        true,
      );
      expect(
        AccessPolicy.canOpenRoute(viewer, '/app/inventory/stock-documents/new'),
        false,
      );
      expect(
        AccessPolicy.canOpenRoute(
          receiver,
          '/app/inventory/stock-documents/new',
        ),
        true,
      );
      expect(AccessPolicy.canInventory(receiver, 'INVENTORY_ISSUE'), false);
    },
  );
  test(
    'empty draft allowed; create does not post or request low stock',
    () async {
      final s = _session(),
          repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          events = InventoryEvents();
      final c = _create(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      c.selectWarehouse(warehouse());
      expect(await c.save(), isA<Success>());
      expect(repo.sentInputs.single.items, isEmpty);
      expect(repo.confirms, 0);
      expect(events.change!.kind, InventoryChangeKind.document);
      expect(c.result!.status, StockDocumentStatus.draft);
      expect(c.intent, isNull);
      c.begin(StockDocumentType.issue);
      expect(c.editable, true);
      expect(c.uncertain, false);
    },
  );
  test(
    'receipt logical zero accepted; inactive receipt excluded but inactive adjustment increase allowed',
    () {
      final s = _session(),
          repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          events = InventoryEvents();
      final c = _create(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      c.selectWarehouse(warehouse());
      expect(c.put(balance(configured: false), stockLine()), isA<Success>());
      expect(
        c.put(balance(i: 'i2', active: false), stockLine(id: 'i2')),
        isA<Error>(),
      );
      expect(c.put(balance(configured: false), stockLine()), isA<Error>());
      c.setType(StockDocumentType.adjustment);
      expect(c.lines, isEmpty);
      expect(
        c.put(
          balance(i: 'i2', active: false),
          stockLine(id: 'i2', direction: AdjustmentDirection.increase),
        ),
        isA<Success>(),
      );
    },
  );
  test('known invalid inputs never allocate a key or send a create', () async {
    final s = _session(),
        repo = FakeStockDocuments(),
        wh = FakeWarehouses(),
        events = InventoryEvents(),
        keys = FakeStockKeys();
    final c = _create(repo, wh, events, () => s, keys: keys);
    addTearDown(() {
      c.dispose();
      events.dispose();
    });
    expect(await c.save(), isA<Error>());
    expect(keys.calls, 0);
    expect(repo.sentKeys, isEmpty);
    c.selectWarehouse(warehouse());
    expect(
      c.put(balance(), stockLine(quantity: '0.001', cost: '0.01')),
      isA<Error>(),
    );
    expect(c.lines, isEmpty);
  });
  test(
    'timeout freezes creation intent and replays same key/payload even when draft fields are touched',
    () async {
      final s = _session(),
          repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          events = InventoryEvents(),
          keys = FakeStockKeys();
      final c = _create(repo, wh, events, () => s, keys: keys);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      c.selectWarehouse(warehouse());
      c.setNote('Gốc');
      c.put(balance(), stockLine());
      repo.onCreate = (key, input) async => const Error(networkFailure);
      await c.save();
      final frozen = c.intent!;
      c.setNote('Không được thay');
      c.setType(StockDocumentType.issue);
      c.remove(0);
      await _tick();
      expect(repo.sentKeys, hasLength(1));
      expect(c.note, 'Gốc');
      expect(c.lines, hasLength(1));
      expect(c.editable, false);
      repo.onCreate = (key, input) async => Success(
        stockDocument(id: 'existing', status: 'CONFIRMED', version: 11),
      );
      final result = await c.save() as Success;
      expect(repo.sentKeys, [frozen.key, frozen.key]);
      expect(repo.sentInputs.last, same(frozen.input));
      expect(keys.calls, 1);
      expect(result.value.status, StockDocumentStatus.confirmed);
      expect(c.result!.version, 11);
      expect(events.change!.kind, InventoryChangeKind.balance);
    },
  );
  test(
    'checking warehouse and create request both resist duplicate taps',
    () async {
      final s = _session(),
          repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          events = InventoryEvents();
      final c = _create(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      c.selectWarehouse(warehouse());
      final pending = Completer<Result<Warehouse>>();
      wh.onDetail = (id) => pending.future;
      final first = c.save();
      await c.save();
      expect(repo.sentKeys, isEmpty);
      pending.complete(Success(warehouse()));
      await first;
      expect(repo.sentKeys, hasLength(1));
      c.begin(StockDocumentType.receipt);
      c.selectWarehouse(warehouse());
      wh.onDetail = null;
      final creation = Completer<Result<StockDocumentDetail>>();
      repo.onCreate = (key, input) => creation.future;
      final second = c.save();
      await _tick();
      await c.save();
      expect(repo.sentKeys, hasLength(2));
      creation.complete(Success(stockDocument()));
      await second;
    },
  );
  test(
    'idempotency conflict never silently rotates key; explicit acknowledgement required',
    () async {
      final s = _session(),
          repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          events = InventoryEvents(),
          keys = FakeStockKeys();
      final c = _create(repo, wh, events, () => s, keys: keys);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      c.selectWarehouse(warehouse());
      repo.onCreate = (key, input) async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'IDEMPOTENCY_KEY_REUSED',
          message: 'Conflict',
        ),
      );
      await c.save();
      await c.save();
      expect(repo.sentKeys.toSet(), hasLength(1));
      expect(keys.calls, 1);
      expect(c.uncertain, true);
      c.acknowledgeKeyConflict();
      expect(c.editable, true);
      expect(c.intent, isNull);
      expect(keys.calls, 1);
    },
  );
  test(
    'late create response from old tenant is discarded and cannot post events',
    () async {
      AppSession? s = _session();
      final repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          events = InventoryEvents();
      final c = _create(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      c.selectWarehouse(warehouse());
      final pending = Completer<Result<StockDocumentDetail>>();
      repo.onCreate = (key, input) => pending.future;
      final task = c.save();
      await _tick();
      s = _session(tenant: 'other');
      pending.complete(Success(stockDocument(status: 'CONFIRMED')));
      await task;
      expect(c.result, isNull);
      expect(events.change, isNull);
    },
  );
  test('read-only or wrong document type permission cannot mutate', () async {
    final repo = FakeStockDocuments()..value = stockDetailJson(type: 'ISSUE'),
        wh = FakeWarehouses(),
        events = InventoryEvents();
    final s = _session(permissions: {'INVENTORY_VIEW', 'INVENTORY_RECEIVE'}),
        c = _detail(repo, wh, events, () => s);
    addTearDown(() {
      c.dispose();
      events.dispose();
    });
    await c.load();
    final d = c.document!;
    expect(await c.saveNote(d, 'note'), isA<Error>());
    expect(await c.saveLine(d, stockLine(id: 'i2')), isA<Error>());
    expect(await c.deleteLine(d, 'si1'), isA<Error>());
    expect(await c.transition(d, posting: false), isA<Error>());
    expect([repo.updates, repo.adds, repo.deletes, repo.cancels], [0, 0, 0, 0]);
    expect(wh.details, 0);
  });
  test(
    'line operations use aggregate version and refuse stale baseline or changed ingredient',
    () async {
      final s = _session(),
          repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          events = InventoryEvents(),
          c = _detail(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      await c.load();
      final old = c.document!;
      expect(
        await c.saveLine(old, stockLine(quantity: '3'), itemId: 'si1'),
        isA<Success>(),
      );
      expect(repo.lastVersion, 3);
      expect(c.document!.version, 4);
      expect(await c.saveNote(old, 'stale'), isA<Error>());
      expect(repo.updates, 0);
      expect(
        await c.saveLine(
          c.document!,
          stockLine(id: 'different'),
          itemId: 'si1',
        ),
        isA<Error>(),
      );
      expect(repo.edits, 1);
      expect(
        await c.saveLine(c.document!, stockLine(id: 'i2')),
        isA<Success>(),
      );
      expect(repo.lastVersion, 4);
    },
  );
  test(
    'delete 204 fetches fresh document; GET failure blocks all following mutations',
    () async {
      final s = _session(),
          repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          events = InventoryEvents(),
          c = _detail(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      await c.load();
      final old = c.document!;
      repo.onDetail = (id) async => const Error(networkFailure);
      expect(await c.deleteLine(old, 'si1'), isA<Success>());
      expect(repo.lastVersion, 3);
      expect(c.document!.version, 3);
      expect(c.needsRead, true);
      expect(c.editable, false);
      expect(await c.saveNote(old, 'no guessed version'), isA<Error>());
      expect(repo.updates, 0);
      repo.onDetail = null;
      await c.load();
      expect(c.document!.version, 4);
      expect(c.document!.items, isEmpty);
      expect(c.needsRead, false);
      await c.saveNote(c.document!, 'new');
      expect(repo.lastVersion, 4);
    },
  );
  test(
    'mutations are locked by document across different line/note controllers',
    () async {
      final s = _session(),
          repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          events = InventoryEvents();
      final a = _detail(repo, wh, events, () => s),
          b = _detail(repo, wh, events, () => s);
      addTearDown(() {
        a.dispose();
        b.dispose();
        events.dispose();
      });
      await Future.wait([a.load(), b.load()]);
      final pending = Completer<Result<StockDocumentDetail>>();
      repo.onUpdate = (id, input) => pending.future;
      final first = a.saveNote(a.document!, 'pending');
      expect(await b.saveLine(b.document!, stockLine(id: 'i2')), isA<Error>());
      expect(repo.adds, 0);
      pending.complete(Success(stockDocument(version: 4)));
      await first;
      expect(repo.updates, 1);
    },
  );
  test(
    'conflict preserves baseline and never silently replaces expectedVersion',
    () async {
      final s = _session(),
          repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          events = InventoryEvents(),
          c = _detail(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      await c.load();
      final old = c.document!;
      repo.onUpdate = (id, input) async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'CONCURRENT_STOCK_DOCUMENT_UPDATE',
          message: 'Changed',
        ),
      );
      await c.saveNote(old, 'local draft');
      expect(c.document, same(old));
      expect(c.requiresReview, true);
      await c.saveNote(old, 'local draft');
      expect(repo.updates, 1);
      repo.value = stockDetailJson(version: 9);
      repo.onUpdate = null;
      await c.load();
      expect(c.requiresReview, false);
      expect(await c.saveNote(old, 'stale'), isA<Error>());
      expect(repo.updates, 1);
      await c.saveNote(c.document!, 'reviewed');
      expect(repo.lastVersion, 9);
    },
  );
  test(
    'inactive warehouse blocks create/confirm but permits existing note edits and cancel',
    () async {
      final s = _session(),
          repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          events = InventoryEvents();
      wh.onDetail = (id) async =>
          Success(warehouse(active: false, isDefault: false));
      final c = _detail(repo, wh, events, () => s),
          draft = _create(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        draft.dispose();
        events.dispose();
      });
      draft.selectWarehouse(warehouse());
      expect(await draft.save(), isA<Error>());
      expect(repo.sentKeys, isEmpty);
      await c.load();
      expect(await c.transition(c.document!, posting: true), isA<Error>());
      expect(repo.confirms, 0);
      expect(await c.saveNote(c.document!, 'Allowed'), isA<Success>());
      expect(await c.transition(c.document!, posting: false), isA<Success>());
      expect(repo.cancels, 1);
    },
  );
  test(
    'confirm insufficient stock retains draft and emits no stock event',
    () async {
      final s = _session(),
          repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          events = InventoryEvents(),
          c = _detail(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      await c.load();
      final old = c.document!;
      repo.onConfirm = (id, input) async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'INSUFFICIENT_STOCK',
          message: 'No stock',
        ),
      );
      expect(await c.transition(old, posting: true), isA<Error>());
      expect(c.document, same(old));
      expect(events.change, isNull);
      expect(c.requiresReview, true);
      await c.transition(old, posting: true);
      expect(repo.confirms, 1);
    },
  );
  test(
    'confirm no-op version accepted; terminal documents immutable; timeout readback publishes actual posted state',
    () async {
      final s = _session(),
          repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          events = InventoryEvents(),
          c = _detail(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      await c.load();
      repo.onConfirm = (id, input) async => const Error(networkFailure);
      await c.transition(c.document!, posting: true);
      expect(c.requiresReview, true);
      expect(events.change, isNull);
      repo.value = stockDetailJson(status: 'CONFIRMED', version: 3);
      await c.load();
      expect(c.document!.version, 3);
      expect(events.change!.kind, InventoryChangeKind.balance);
      expect(await c.saveNote(c.document!, 'immutable'), isA<Error>());
      expect(await c.transition(c.document!, posting: false), isA<Error>());
      expect(repo.cancels, 0);
    },
  );
  test(
    'draft events refresh documents only; posting refreshes matching balances and ledger, not unrelated warehouse or low stock',
    () async {
      final s = _session(),
          repo = FakeStockDocuments(),
          wh = FakeWarehouses(),
          balances = FakeBalances(),
          ledger = FakeStockTransactions(),
          events = InventoryEvents();
      final docs = StockDocumentListController(
        session: () => s,
        events: events,
        get: GetStockDocuments(repo),
      );
      final tx = InventoryTransactionController(
        session: () => s,
        events: events,
        get: GetInventoryTransactions(ledger),
      );
      InventoryBalanceController list(String w, {bool low = false}) =>
          InventoryBalanceController(
            session: () => s,
            events: events,
            warehouseId: w,
            lowStock: low,
            get: GetInventoryBalances(balances),
            getLowStock: GetLowStockBalances(balances),
          );
      final a = list('w1'),
          b = list('w2'),
          low = list('w1', low: true),
          c = _detail(repo, wh, events, () => s);
      addTearDown(() {
        docs.dispose();
        tx.dispose();
        a.dispose();
        b.dispose();
        low.dispose();
        c.dispose();
        events.dispose();
      });
      await c.load();
      await c.saveNote(c.document!, 'draft');
      await _tick();
      expect(repo.queries, hasLength(1));
      expect(balances.queries, isEmpty);
      expect(ledger.queries, isEmpty);
      await c.transition(c.document!, posting: true);
      await _tick();
      expect(balances.queries.map((r) => r.w), ['w1']);
      expect(ledger.queries, hasLength(1));
      expect(balances.lowCalls, 0);
    },
  );
  test(
    'late document and transaction queries never replace newer query/scope',
    () async {
      AppSession? s = _session();
      final repo = FakeStockDocuments(),
          ledger = FakeStockTransactions(),
          events = InventoryEvents();
      final docs = StockDocumentListController(
            session: () => s,
            events: events,
            get: GetStockDocuments(repo),
          ),
          tx = InventoryTransactionController(
            session: () => s,
            events: events,
            get: GetInventoryTransactions(ledger),
          );
      addTearDown(() {
        docs.dispose();
        tx.dispose();
        events.dispose();
      });
      final old = Completer<Result<InventoryPage<StockDocumentSummary>>>();
      repo.onList = (q) => old.future;
      final first = docs.load();
      docs.search('new');
      repo.onList = (q) async =>
          Success(inventoryPage([stockDocument(id: 'new')]));
      await docs.load();
      old.complete(Success(inventoryPage([stockDocument(id: 'old')])));
      await first;
      expect(docs.rows.single.id, 'new');
      final late = Completer<Result<InventoryPage<InventoryTransaction>>>();
      ledger.onList = (q) => late.future;
      final second = tx.load();
      s = _session(tenant: 'other');
      late.complete(Success(inventoryPage(ledger.rows)));
      await second;
      expect(tx.rows, isEmpty);
    },
  );
  test('inclusive local day range and query allowlists match API', () {
    final from = DateTime(2026, 10, 1),
        to = DateTime(2026, 10, 18),
        range = StockDateRange.days(from, to);
    expect(range.from, DateTime(2026, 10, 1).toUtc());
    expect(
      range.to,
      DateTime(2026, 10, 19).toUtc().subtract(const Duration(microseconds: 1)),
    );
    expect(
      StockDocumentQuery(
        dates: StockDateRange(from: to, to: from),
      ).valid,
      false,
    );
    expect(const StockDocumentQuery(sortBy: 'ingredientName').valid, false);
    expect(const InventoryTransactionQuery(sortBy: 'quantity').valid, false);
    expect(const StockDocumentQuery(size: 101).valid, false);
  });
}
