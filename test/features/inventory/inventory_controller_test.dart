import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/ui/sidebar/app_sidebar_registry.dart';
import 'package:pos_saas_app/core/ui/sidebar/sidebar_filter.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_inputs.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_quantity.dart';
import 'package:pos_saas_app/features/inventory/domain/use_cases/inventory_use_cases.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_balance_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_balance_detail_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_events.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/warehouse_list_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/warehouse_selector_controller.dart';
import '../../helpers/auth_fakes.dart';
import 'inventory_fakes.dart';

AppSession _session({
  Set<String> permissions = inventoryPermissions,
  Set<String> features = inventoryFeatures,
  UserRole role = UserRole.manager,
  String tenant = 'restaurant-1',
}) => makeAppSession(
  permissions: permissions,
  features: features,
  role: role,
  restaurantId: tenant,
);
const _conflict = Failure(
  type: FailureType.conflict,
  code: 'CONCURRENT_INVENTORY_UPDATE',
  message: 'Đã thay đổi',
);
WarehouseListController _warehouses(
  FakeWarehouses repo,
  InventoryEvents events,
  AppSession? Function() session,
) => WarehouseListController(
  session: session,
  events: events,
  get: GetWarehouses(repo),
  getDetail: GetWarehouse(repo),
  createWarehouse: CreateWarehouse(repo),
  updateWarehouse: UpdateWarehouse(repo),
  setStatus: SetWarehouseStatus(repo),
  makeDefault: MakeDefaultWarehouse(repo),
  deleteWarehouse: DeleteWarehouse(repo),
);
InventoryBalanceController _list(
  FakeBalances repo,
  InventoryEvents events,
  AppSession? Function() session, {
  String? id = 'w1',
  bool low = false,
}) => InventoryBalanceController(
  session: session,
  events: events,
  warehouseId: id,
  lowStock: low,
  get: GetInventoryBalances(repo),
  getLowStock: GetLowStockBalances(repo),
);
InventoryBalanceDetailController _detail(
  FakeBalances repo,
  FakeWarehouses wh,
  InventoryEvents events,
  AppSession? Function() session, {
  String ingredient = 'i2',
}) => InventoryBalanceDetailController(
  session: session,
  events: events,
  warehouseId: 'w1',
  ingredientId: ingredient,
  getBalance: GetInventoryBalance(repo),
  getWarehouse: GetWarehouse(wh),
  updateThreshold: UpdateInventoryThreshold(repo),
);
Future<void> _tick() => Future<void>.delayed(Duration.zero);

void main() {
  test(
    'view needs inventory permission/feature only; route and sidebar agree',
    () {
      final s = _session(
        permissions: {'INVENTORY_VIEW'},
        features: {'INVENTORY_MANAGEMENT'},
      );
      expect(AccessPolicy.canInventory(s, 'INVENTORY_VIEW'), true);
      expect(AccessPolicy.canOpenRoute(s, '/app/inventory'), true);
      expect(
        filterMenuItems(
          s,
          AppSidebarRegistry.categories.expand((c) => c.items).toList(),
        ).any((i) => i.id == 'inventory'),
        true,
      );
      expect(AccessPolicy.canInventory(s, 'WAREHOUSE_CREATE'), false);
      expect(
        AccessPolicy.canInventory(_session(features: {}), 'INVENTORY_VIEW'),
        false,
      );
      for (final role in [UserRole.cashier, UserRole.superAdmin]) {
        expect(
          AccessPolicy.canInventory(_session(role: role), 'INVENTORY_VIEW'),
          false,
        );
      }
      expect(
        AccessPolicy.canInventory(
          _session(role: UserRole.owner, permissions: {}),
          'INVENTORY_VIEW',
        ),
        false,
      );
    },
  );

  test(
    'no LOW_STOCK_ALERT never calls low API; threshold still works',
    () async {
      final s = _session(features: {'INVENTORY_MANAGEMENT'}),
          repo = FakeBalances(),
          wh = FakeWarehouses(),
          events = InventoryEvents();
      final low = _list(repo, events, () => s, low: true, id: null),
          normal = _list(repo, events, () => s);
      final detail = _detail(repo, wh, events, () => s);
      addTearDown(() {
        low.dispose();
        normal.dispose();
        detail.dispose();
        events.dispose();
      });
      await low.load();
      await normal.load();
      await detail.load();
      expect(repo.lowCalls, 0);
      expect(normal.rows, hasLength(3));
      expect(detail.canSave, true);
      final old = detail.balance!;
      expect(
        await detail.save(
          old,
          const UpdateInventoryThresholdInput(null, InventoryQuantity.zero),
        ),
        isA<Success>(),
      );
      expect(repo.lastInput!.expectedVersion, isNull);
      expect(detail.balance!.version, isNull);
      expect(detail.balance!.configured, false);
    },
  );

  test(
    'read-only controller cannot mutate and never calls repositories',
    () async {
      final s = _session(permissions: {'INVENTORY_VIEW'}),
          wh = FakeWarehouses(),
          repo = FakeBalances(),
          events = InventoryEvents();
      final c = _warehouses(wh, events, () => s),
          d = _detail(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        d.dispose();
        events.dispose();
      });
      await d.load();
      expect(
        await c.create(const CreateWarehouseInput(code: 'A', name: 'A')),
        isA<Error>(),
      );
      expect(
        await c.act(
          warehouse(id: 'w2', isDefault: false),
          WarehouseAction.delete,
        ),
        isA<Error>(),
      );
      expect(
        await d.save(
          d.balance!,
          const UpdateInventoryThresholdInput(null, InventoryQuantity.zero),
        ),
        isA<Error>(),
      );
      expect([wh.creates, wh.deletes, repo.saves], [0, 0, 0]);
    },
  );

  test(
    'default lifecycle guarded; backend stock failure and no-op versions preserved',
    () async {
      final s = _session(), wh = FakeWarehouses(), events = InventoryEvents();
      final c = _warehouses(wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      expect(await c.act(warehouse(), WarehouseAction.disable), isA<Error>());
      expect(await c.act(warehouse(), WarehouseAction.delete), isA<Error>());
      expect(
        await c.act(
          warehouse(id: 'w2', isDefault: false, active: false),
          WarehouseAction.makeDefault,
        ),
        isA<Error>(),
      );
      expect([wh.statuses, wh.deletes, wh.defaults], [0, 0, 0]);
      wh.statusResult = const Error(
        Failure(
          type: FailureType.conflict,
          code: 'WAREHOUSE_HAS_STOCK',
          message: 'Còn tồn',
        ),
      );
      expect(
        await c.act(
          warehouse(id: 'w2', isDefault: false),
          WarehouseAction.disable,
        ),
        isA<Error>(),
      );
      expect(c.events.change, isNull);
      wh.statusResult = Success(
        warehouse(id: 'w2', isDefault: false, version: 7),
      );
      final noop =
          await c.act(
                warehouse(id: 'w2', isDefault: false, version: 7),
                WarehouseAction.enable,
              )
              as Success;
      expect(noop.value.version, 7);
      await _tick();
    },
  );

  test(
    'threshold conflict locks resubmit until fresh baseline; null not substituted by zero',
    () async {
      final s = _session(),
          wh = FakeWarehouses(),
          repo = FakeBalances(),
          events = InventoryEvents();
      final c = _detail(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      await c.load();
      final old = c.balance!;
      repo.onSave = (w, i, input) async => const Error(_conflict);
      await c.save(
        old,
        UpdateInventoryThresholdInput(null, InventoryQuantity.parse('2')),
      );
      expect(c.balance, same(old));
      expect(c.requiresReview, true);
      await c.save(
        old,
        UpdateInventoryThresholdInput(null, InventoryQuantity.parse('2')),
      );
      expect(repo.saves, 1);
      repo.onDetail = (w, i) async =>
          Success(balance(i: i, min: 5, version: 3));
      await c.load();
      expect(c.requiresReview, false);
      expect(
        await c.save(
          old,
          const UpdateInventoryThresholdInput(null, InventoryQuantity.zero),
        ),
        isA<Error>(),
      );
      expect(repo.saves, 1);
      repo.onSave = (w, i, input) async =>
          Success(balance(i: i, min: 0, version: 4));
      await c.save(
        c.balance!,
        const UpdateInventoryThresholdInput(3, InventoryQuantity.zero),
      );
      expect(repo.lastInput!.expectedVersion, 3);
      expect(c.balance!.lowStock, false);
    },
  );

  test(
    'unknown result + readback 404 unlocks close without recreating a balance',
    () async {
      final s = _session(),
          wh = FakeWarehouses(),
          repo = FakeBalances(),
          events = InventoryEvents();
      final c = _detail(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      await c.load();
      repo.onSave = (w, i, input) async => const Error(networkFailure);
      await c.save(
        c.balance!,
        const UpdateInventoryThresholdInput(null, InventoryQuantity.zero),
      );
      repo.onDetail = (w, i) async =>
          const Error(Failure(type: FailureType.notFound, message: 'Đã xóa'));
      await c.load();
      expect(c.requiresReview, false);
      expect(c.balance, isNull);
      expect(c.canSave, false);
      expect(repo.saves, 1);
    },
  );

  test(
    'inactive warehouse disallows threshold while balances stay readable',
    () async {
      final s = _session(),
          wh = FakeWarehouses(),
          repo = FakeBalances(),
          events = InventoryEvents();
      wh.onDetail = (id) async =>
          Success(warehouse(active: false, isDefault: false));
      final c = _detail(repo, wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      await c.load();
      expect(c.balance, isNotNull);
      expect(c.canSave, false);
      await c.save(
        c.balance!,
        const UpdateInventoryThresholdInput(null, InventoryQuantity.zero),
      );
      expect(repo.saves, 0);
    },
  );

  test(
    'duplicate taps are locked across controllers for same entity',
    () async {
      final s = _session(),
          repo = FakeBalances(),
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
      final pending = Completer<Result<InventoryBalance>>();
      repo.onSave = (w, i, input) => pending.future;
      final first = a.save(
        a.balance!,
        const UpdateInventoryThresholdInput(null, InventoryQuantity.zero),
      );
      await b.save(
        b.balance!,
        const UpdateInventoryThresholdInput(null, InventoryQuantity.zero),
      );
      expect(repo.saves, 1);
      pending.complete(Success(balance(i: 'i2', configured: false)));
      await first;
    },
  );

  test(
    'timeout create inspects original code without automatic POST retry',
    () async {
      final s = _session(), wh = FakeWarehouses(), events = InventoryEvents();
      final c = _warehouses(wh, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      wh.onCreate = (input) async => const Error(networkFailure);
      const draft = CreateWarehouseInput(code: ' KHO-w1 ', name: 'Kho mới');
      await c.create(draft);
      await c.create(draft);
      expect(wh.creates, 1);
      expect(c.pendingCreate, same(draft));
      final matches = await c.inspectCreation('KHO-w1') as Success;
      expect(matches.value, hasLength(1));
      expect(wh.queries.last.q, 'KHO-W1');
      expect(wh.creates, 1);
      expect(events.verification(InventoryEvents.createKey), isNotNull);
      c.acknowledgeCreation();
      expect(c.pendingCreate, isNull);
    },
  );

  test(
    'response from an old query or tenant cannot replace current rows',
    () async {
      AppSession? s = _session();
      final repo = FakeBalances(), events = InventoryEvents();
      final c = _list(repo, events, () => s);
      addTearDown(() {
        c.dispose();
        events.dispose();
      });
      final pending = Completer<Result<InventoryPage<InventoryBalance>>>();
      repo.onList = (w, q) => pending.future;
      final old = c.load();
      c.search('mới');
      repo.onList = (w, q) async => Success(inventoryPage([balance(i: 'new')]));
      await c.load();
      pending.complete(Success(inventoryPage([balance(i: 'old')])));
      await old;
      expect(c.rows.single.ingredientId, 'new');
      final late = Completer<Result<InventoryPage<InventoryBalance>>>();
      repo.onList = (w, q) => late.future;
      final load = c.load();
      s = _session(tenant: 'different-tenant');
      late.complete(Success(inventoryPage([balance(i: 'wrong-tenant')])));
      await load;
      expect(c.rows.single.ingredientId, 'new');
    },
  );

  test('switching warehouse discards disposed controller response', () async {
    final s = _session(), repo = FakeBalances(), events = InventoryEvents();
    final old = Completer<Result<InventoryPage<InventoryBalance>>>();
    repo.onList = (w, q) => w == 'w1'
        ? old.future
        : Future.value(Success(inventoryPage([balance(w: w)])));
    final a = _list(repo, events, () => s),
        b = _list(repo, events, () => s, id: 'w2');
    final first = a.load();
    a.dispose();
    await b.load();
    old.complete(Success(inventoryPage([balance(w: 'w1')])));
    await first;
    expect(b.rows.single.warehouseId, 'w2');
    b.dispose();
    events.dispose();
  });

  test(
    'selector preserves selected warehouse across pages; default change refreshes both',
    () async {
      final s = _session(), wh = FakeWarehouses(), events = InventoryEvents();
      final c = WarehouseSelectorController(
        session: () => s,
        events: events,
        get: GetWarehouses(wh),
        detail: GetWarehouse(wh),
      );
      final actions = _warehouses(wh, events, () => s);
      addTearDown(() {
        c.dispose();
        actions.dispose();
        events.dispose();
      });
      await c.load();
      expect(c.selected!.id, 'w1');
      wh.onList = (q) async => Success(
        inventoryPage([wh.rows.last], total: 41, pages: 3, page: q.page),
      );
      await c.load();
      c.page(1);
      await _tick();
      expect(c.selected!.id, 'w1');
      expect(c.totalElements, 41);
      await actions.act(wh.rows.last, WarehouseAction.makeDefault);
      await _tick();
      await _tick();
      expect(c.selected!.isDefault, false);
      expect(c.rows.single.isDefault, true);
      expect(wh.defaults, 1);
      await actions.act(c.selected!, WarehouseAction.delete);
      await _tick();
      await _tick();
      expect(c.selected, isNull);
    },
  );

  test('last empty page moves to a valid server page', () async {
    final s = _session(), repo = FakeWarehouses(), events = InventoryEvents();
    final c = _warehouses(repo, events, () => s);
    addTearDown(() {
      c.dispose();
      events.dispose();
    });
    repo.onList = (q) async => Success(
      inventoryPage(
        q.page == 0 ? [warehouse()] : [],
        page: q.page,
        total: 1,
        pages: 1,
      ),
    );
    c.totalPages = 2;
    c.page(1);
    await _tick();
    await _tick();
    expect(repo.queries.map((q) => q.page), [1, 0]);
    expect(c.rows, hasLength(1));
    expect(c.query.page, 0);
  });

  test(
    'balance events invalidate only matching warehouse and allowed low stock',
    () async {
      final s = _session(), repo = FakeBalances(), events = InventoryEvents();
      final a = _list(repo, events, () => s),
          b = _list(repo, events, () => s, id: 'w2');
      final low = _list(repo, events, () => s, low: true, id: null);
      addTearDown(() {
        a.dispose();
        b.dispose();
        low.dispose();
        events.dispose();
      });
      events.emit(
        const InventoryChange(
          InventoryChangeKind.balance,
          'w1',
          ingredientId: 'i1',
        ),
      );
      await _tick();
      expect(repo.queries.map((q) => q.w), ['w1']);
      expect(repo.lowCalls, 1);
    },
  );
}
