import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_query.dart';
import 'package:pos_saas_app/features/menu/domain/use_cases/menu_group_use_cases.dart';
import 'package:pos_saas_app/features/menu/domain/use_cases/menu_item_use_cases.dart';
import 'package:pos_saas_app/features/menu/presentation/controllers/menu_catalog_events.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_inputs.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_quantity.dart';
import 'package:pos_saas_app/features/order/domain/policies/order_access_policy.dart';
import 'package:pos_saas_app/features/order/domain/use_cases/order_use_cases.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_events.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_list_controller.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_menu_picker_controller.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_table_workspace.dart';
import '../../helpers/auth_fakes.dart';
import '../menu/menu_fakes.dart';
import '../tables/table_fakes.dart';
import 'order_fakes.dart';

final saleItem = MenuItemDto.fromJson(itemJson()..['id'] = itemId).toEntity();
void main() {
  test(
    'permissions/features/tenant/subscription and platform policy without owner bypass',
    () {
      final noView = orderSession(
        permissions: {'ORDER_CREATE', 'MENU_VIEW'},
        features: {'ORDER_MANAGEMENT', 'POS_QUICK_ORDER', 'MENU_MANAGEMENT'},
      );
      expect(AccessPolicy.canCreateOrder(noView, takeaway: true), isTrue);
      expect(AccessPolicy.canTables(noView, 'TABLE_VIEW'), isFalse);
      expect(AccessPolicy.canCreateOrder(noView, takeaway: false), isFalse);
      expect(
        AccessPolicy.canOpenRoute(
          noView,
          '/app/order-create?serviceType=TAKEAWAY',
        ),
        isTrue,
      );
      expect(AccessPolicy.canOpenRoute(noView, '/app/orders/o1'), isFalse);
      for (final role in [
        UserRole.cashier,
        UserRole.superAdmin,
        UserRole.unsupported,
      ]) {
        expect(
          AccessPolicy.canOrders(
            makeAppSession(
              role: role,
              permissions: orderPermissions,
              features: orderFeatures,
            ),
            'ORDER_CREATE',
          ),
          isFalse,
        );
      }
      expect(
        AccessPolicy.canOrders(orderSession(permissions: {}), 'ORDER_CREATE'),
        isFalse,
      );
      expect(
        AccessPolicy.canOrders(orderSession(features: {}), 'ORDER_CREATE'),
        isFalse,
      );
      expect(
        AccessPolicy.canOrders(
          makeAppSession(
            restaurantId: null,
            permissions: orderPermissions,
            features: orderFeatures,
          ),
          'ORDER_VIEW',
        ),
        isFalse,
      );
    },
  );
  test(
    'takeaway draft succeeds without table/view permission and result keeps server state',
    () async {
      final repo = FakeOrders()
        ..current = OrderDto.detail(
          orderJson(version: 9, status: 'CONFIRMED', confirmed: true),
        );
      final c = draft(
        repo,
        () => orderSession(permissions: {'ORDER_CREATE', 'MENU_VIEW'}),
      );
      addTearDown(c.dispose);
      c.add(saleItem);
      final response = await c.submit();
      expect(response, isA<Success<OrderDetail>>());
      expect(repo.creates.single.$1.context.tableSessionId, isNull);
      expect(c.result!.version, 9);
      expect(c.result!.summary.status, OrderStatus.confirmed);
    },
  );
  test(
    'timeout freezes original key/payload; edit and double submit cannot change it',
    () async {
      final repo = FakeOrders();
      final pending = Completer<Result<OrderDetail>>();
      repo.onCreate = () => pending.future;
      final c = draft(repo, () => orderSession());
      addTearDown(c.dispose);
      c.add(saleItem);
      c.setFields(customerName: 'Khách');
      final first = c.submit();
      await c.submit();
      expect(repo.creates.length, 1);
      pending.complete(const Error(networkFailure));
      await first;
      expect(c.uncertain, isTrue);
      expect(c.lines.length, 1);
      c.add(saleItem);
      c.remove(c.lines.first.id);
      c.setFields(customerName: 'Tên khác');
      repo.onCreate = () => Future.value(Success(repo.current));
      await c.submit();
      expect(repo.creates.length, 2);
      expect(identical(repo.creates.first.$1, repo.creates.last.$1), isTrue);
      expect(repo.creates.first.$2, repo.creates.last.$2);
      expect(repo.creates.last.$1.customerName, 'Khách');
    },
  );
  test(
    'missing menu access prevents picker and create; invalid session prevents submission',
    () async {
      final repo = FakeOrders();
      final noMenu = draft(
        repo,
        () => orderSession(permissions: {'ORDER_CREATE'}),
      );
      addTearDown(noMenu.dispose);
      noMenu.add(saleItem);
      await noMenu.submit();
      expect(repo.creates, isEmpty);
      final invalid = draft(
        repo,
        () => orderSession(),
        context: const OrderCreationContext.dineIn(sessionId: 'fake'),
      );
      addTearDown(invalid.dispose);
      invalid.add(saleItem);
      await invalid.submit();
      expect(repo.creates, isEmpty);
    },
  );
  test(
    'exact HALF_UP preview uses BigInt, zero price and independent duplicate lines',
    () {
      final tiny = MenuItemDto.fromJson(
        itemJson()
          ..['id'] = itemId
          ..['salePrice'] = 0.05,
      ).toEntity();
      final c = draft(FakeOrders(), () => orderSession());
      addTearDown(c.dispose);
      c.add(tiny);
      c.edit(c.lines.first.id, OrderQuantity.parse('0.1'), 'A');
      c.add(tiny);
      c.edit(c.lines.last.id, OrderQuantity.parse('0.1'), 'B');
      expect(c.previewMinor, BigInt.from(2));
      expect(c.lines[0].id, isNot(c.lines[1].id));
      final zero = MenuItemDto.fromJson(
        itemJson()
          ..['id'] = itemId
          ..['salePrice'] = 0,
      ).toEntity();
      c.add(zero);
      expect(c.lines.last.previewMinor, BigInt.zero);
    },
  );
  test(
    'scope change rejects late create and token rotation preserves draft',
    () async {
      AppSession? session = orderSession();
      final repo = FakeOrders();
      final c = draft(repo, () => session);
      addTearDown(c.dispose);
      c.add(saleItem);
      final oldScope = AccessPolicy.orderScope(session);
      session = session.copyWithAuth(
        user: session.authenticatedUser,
        tokens: makeTokens(accessToken: 'rotated'),
      );
      expect(AccessPolicy.orderScope(session), oldScope);
      expect(c.lines.length, 1);
      final pending = Completer<Result<OrderDetail>>();
      repo.onCreate = () => pending.future;
      final request = c.submit();
      session = null;
      pending.complete(Success(repo.current));
      expect(await request, isA<Error<OrderDetail>>());
      expect(c.result, isNull);
    },
  );
  test('same-menu lines keep IDs/notes; validation and 100 limit', () async {
    final c = draft(FakeOrders(), () => orderSession());
    addTearDown(c.dispose);
    for (var i = 0; i < 101; i++) {
      c.add(saleItem);
    }
    expect(c.lines.length, 100);
    expect(c.failure?.type, FailureType.validation);
    c.setFields(guestCount: 0);
    expect(await c.submit(), isA<Error<OrderDetail>>());
  });
  test(
    'all detail mutations use returned root version and cancelled last line response',
    () async {
      final repo = FakeOrders();
      final c = detail(repo, () => orderSession());
      addTearDown(c.dispose);
      repo.current = OrderDto.detail(orderJson(version: 6));
      await c.editLine(
        'line1',
        const UpdateOrderLineInput(expectedVersion: 5, note: 'Mới'),
      );
      expect(repo.writes.last, ('line', 5));
      expect(c.order!.version, 6);
      repo.current = OrderDto.detail(orderJson(version: 7));
      await c.addItems(6, [
        CreateOrderLine(itemId: itemId, quantity: OrderQuantity.one),
      ]);
      expect(repo.writes.last, ('add', 6));
      expect(c.order!.version, 7);
      repo.current = OrderDto.detail(
        orderJson(version: 8, status: 'CANCELLED', lineStatus: 'CANCELLED'),
      );
      await c.cancelItem('line1', 7, 'Đổi món');
      expect(c.order!.summary.status, OrderStatus.cancelled);
      expect(c.editable, isFalse);
    },
  );
  test(
    'confirmed frozen; cancel line depends confirmedAt; other cooked line does not block pending target',
    () {
      final confirmed = OrderDto.detail(
        orderJson(status: 'CONFIRMED', confirmed: true),
      );
      expect(OrderAccessPolicy.canEdit(confirmed, true), isFalse);
      expect(OrderAccessPolicy.lineCancelPermission(confirmed), 'ORDER_CANCEL');
      expect(
        OrderAccessPolicy.canCancelLine(confirmed, confirmed.items.first, true),
        isTrue,
      );
      final cancelled = OrderDto.detail(
        orderJson(
          status: 'CANCELLED',
          confirmed: true,
          lineStatus: 'CANCELLED',
        ),
      );
      expect(OrderAccessPolicy.lineCancelPermission(cancelled), 'ORDER_CANCEL');
      expect(OrderAccessPolicy.canCancel(cancelled, true), isFalse);
    },
  );
  test(
    'confirmed needs ORDER_CANCEL, draft only ORDER_UPDATE; no fake cooking mutation',
    () async {
      final repo = FakeOrders();
      final c = detail(
        repo,
        () => orderSession(permissions: {'ORDER_VIEW', 'ORDER_UPDATE'}),
      );
      addTearDown(c.dispose);
      expect(c.lineCancellable(c.order!.items.first), isTrue);
      expect(c.cancellable, isFalse);
      repo.current = OrderDto.detail(
        orderJson(status: 'CONFIRMED', confirmed: true, version: 6),
      );
      await c.load();
      expect(c.lineCancellable(c.order!.items.first), isFalse);
      expect(c.editable, isFalse);
      await c.confirm(6);
      await c.addItems(6, []);
      expect(repo.writes, isEmpty);
    },
  );
  test(
    'conflict/network holds baseline and blocks mutation until explicit verification',
    () async {
      final repo = FakeOrders();
      final c = detail(repo, () => orderSession());
      addTearDown(c.dispose);
      repo.onWrite = () => Future.value(
        const Error(
          Failure(
            type: FailureType.conflict,
            code: 'CONCURRENT_ORDER_UPDATE',
            message: 'Conflict',
          ),
        ),
      );
      await c.update(const UpdateOrderInput(expectedVersion: 5, note: 'Draft'));
      expect(c.order!.version, 5);
      expect(c.requiresVerification, isTrue);
      await c.update(const UpdateOrderInput(expectedVersion: 6, note: 'Draft'));
      expect(repo.writes.length, 1);
      repo.current = OrderDto.detail(orderJson(version: 7));
      await c.load();
      expect(c.order!.version, 7);
      repo.onWrite = () => Future.value(const Error(networkFailure));
      await c.confirm(7);
      expect(c.requiresVerification, isTrue);
      expect(repo.writes.length, 2);
    },
  );
  test(
    'dialog baseline cannot silently follow background refresh; double mutation is locked',
    () async {
      final repo = FakeOrders();
      final c = detail(repo, () => orderSession());
      addTearDown(c.dispose);
      repo.current = OrderDto.detail(orderJson(version: 6));
      await c.load();
      await c.update(
        const UpdateOrderInput(expectedVersion: 5, note: 'Old draft'),
      );
      expect(repo.writes, isEmpty);
      final pending = Completer<Result<OrderDetail>>();
      repo.onWrite = () => pending.future;
      final first = c.confirm(6);
      await c.confirm(6);
      expect(repo.writes.length, 1);
      pending.complete(Success(repo.current));
      await first;
    },
  );
  test('older GET cannot overwrite mutation response', () async {
    final repo = FakeOrders();
    final c = detail(repo, () => orderSession());
    addTearDown(c.dispose);
    final pending = Completer<Result<OrderDetail>>();
    repo.onDetail = () => pending.future;
    final read = c.load();
    repo.current = OrderDto.detail(orderJson(version: 6));
    await c.update(const UpdateOrderInput(expectedVersion: 5, note: 'New'));
    pending.complete(Success(OrderDto.detail(orderJson(version: 5))));
    await read;
    expect(c.order!.version, 6);
  });
  test('server-side query/reset/debounce and stale responses', () async {
    final repo = FakeOrders();
    final c = OrderListController(
      session: () => orderSession(),
      events: OrderEvents(),
      get: GetOrders(repo),
      query: const OrderQuery(tableSessionId: sessionId),
    );
    addTearDown(c.dispose);
    final pending = Completer<Result<OrderPage>>();
    repo.onList = (_) => pending.future;
    final old = c.load();
    c.search('new');
    repo.onList = (q) => Future.value(
      Success(
        OrderPage(
          content: [],
          page: q.page,
          size: 20,
          totalElements: 0,
          totalPages: 0,
        ),
      ),
    );
    pending.complete(
      Success(
        OrderPage(
          content: [repo.current.summary],
          page: 0,
          size: 20,
          totalElements: 1,
          totalPages: 1,
        ),
      ),
    );
    await old;
    expect(c.page, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(repo.queries.last.q, 'new');
    expect(repo.queries.last.tableSessionId, sessionId);
    expect(c.page!.content, isEmpty);
  });
  test(
    'hub loads snapshot and filters occupancy locally without per-card requests',
    () async {
      final server = TableServer();
      addTearDown(server.close);
      final c = hub(server, () => orderSession());
      addTearDown(c.dispose);
      await c.load();
      await c.loadAreas();
      expect(
        server.requests.where((r) => r.path.endsWith('current-session')),
        isEmpty,
      );
      final calls = server.requests.length;
      await c.filter(occupied: true, areaId: 'a1');
      expect(server.requests.length, calls);
      expect(c.query.occupied, true);
      expect(c.tables, isEmpty);
      expect(server.requests.first.queryParameters['status'], 'AVAILABLE');
      expect(server.requests.first.queryParameters['size'], 100);
    },
  );
  test(
    'selecting a free table returns table target without opening any session',
    () async {
      final server = TableServer()
        ..table = tableJson(occupied: true, canOpen: false);
      addTearDown(server.close);
      final c = hub(server, () => orderSession());
      addTearDown(c.dispose);
      final prepared = await c.prepare('t1');
      expect((prepared as Success).value.occupied, isTrue);
      expect(server.requests.where((r) => r.method == 'POST'), isEmpty);
      server.table = tableJson(version: 23);
      final selected = await c.selectTable('t1');
      expect(
        (selected as Success<OrderTableSelection>).value,
        isA<ComposeTableOrder>(),
      );
      expect(server.requests.where((r) => r.method == 'POST'), isEmpty);
    },
  );
  test(
    'missing TABLE_OPEN never sends opening mutation; closed session rejected',
    () async {
      final server = TableServer()..session = sessionJson(status: 'CLOSED');
      addTearDown(server.close);
      final c = hub(
        server,
        () => orderSession(
          permissions: {'ORDER_CREATE', 'MENU_VIEW', 'TABLE_VIEW'},
        ),
      );
      addTearDown(c.dispose);
      expect(await c.selectTable('t1'), isA<Error<OrderTableSelection>>());
      expect(server.requests.where((r) => r.method == 'POST'), isEmpty);
      expect(
        await c.resolveSession(sessionId),
        isA<Error<OrderCreationContext>>(),
      );
    },
  );
  test(
    'picker independent query, no menu permission bypass, group page beyond first',
    () async {
      final items = FakeMenuItems();
      final groups = FakeMenuGroups();
      groups.onList = (q) => Future.value(
        Success(
          page(
            [
              groupJson(id: 'g${q.page}'),
            ].map((j) => MenuGroupDto.fromJson(j).toEntity()).toList(),
            index: q.page,
            pages: 2,
            total: 2,
          ),
        ),
      );
      final catalog = MenuCatalogEvents();
      final c = OrderMenuPickerController(
        session: () => orderSession(),
        events: OrderEvents(),
        itemsUseCase: GetMenuItems(items),
        groupsUseCase: GetMenuGroups(groups),
        catalog: catalog,
        permission: 'ORDER_CREATE',
      );
      addTearDown(c.dispose);
      await c.load();
      await c.loadGroups();
      await c.loadGroups();
      expect(c.groups.length, 2);
      expect(items.queries.single.sellable, true);
      expect(items.queries.single.active, true);
      expect(c.query, isA<MenuQuery>());
      final denied = OrderMenuPickerController(
        session: () => orderSession(permissions: {'ORDER_CREATE'}),
        events: OrderEvents(),
        itemsUseCase: GetMenuItems(items),
        groupsUseCase: GetMenuGroups(groups),
        catalog: catalog,
        permission: 'ORDER_CREATE',
      );
      addTearDown(denied.dispose);
      await denied.load();
      expect(items.queries.length, 1);
    },
  );
}
