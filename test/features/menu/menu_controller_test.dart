import 'dart:async';
import 'package:flutter_test/flutter_test.dart' hide group;
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_item.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_group.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_page.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_query.dart';
import 'package:pos_saas_app/features/menu/domain/use_cases/menu_item_use_cases.dart';
import 'package:pos_saas_app/features/menu/domain/use_cases/menu_group_use_cases.dart';
import 'package:pos_saas_app/features/menu/presentation/controllers/menu_catalog_events.dart';
import 'package:pos_saas_app/features/menu/presentation/controllers/menu_item_controller.dart';
import 'package:pos_saas_app/features/menu/presentation/controllers/menu_group_controller.dart';
import 'package:pos_saas_app/features/menu/presentation/controllers/menu_group_selector_controller.dart';
import 'package:pos_saas_app/features/subscription/domain/entities/entitlement.dart';
import '../../helpers/auth_fakes.dart';
import 'menu_fakes.dart';

void main() {
  late AppSession? session;
  late FakeMenuItems items;
  late FakeMenuGroups groups;
  late MenuCatalogEvents events;
  late MenuItemController controller;
  late MenuGroupController groupController;
  setUp(() {
    session = makeAppSession(permissions: menuPermissions);
    items = FakeMenuItems();
    groups = FakeMenuGroups();
    events = MenuCatalogEvents();
    controller = MenuItemController(
      session: () => session,
      list: GetMenuItems(items),
      detail: GetMenuItemDetail(items),
      create: CreateMenuItem(items),
      update: UpdateMenuItem(items),
      status: SetMenuItemStatus(items),
      availability: SetMenuItemAvailability(items),
      group: SetMenuItemGroup(items),
      delete: DeleteMenuItem(items),
      events: events,
    );
    groupController = MenuGroupController(
      session: () => session,
      list: GetMenuGroups(groups),
      detail: GetMenuGroupDetail(groups),
      create: CreateMenuGroup(groups),
      update: UpdateMenuGroup(groups),
      status: SetMenuGroupStatus(groups),
      delete: DeleteMenuGroup(groups),
      events: events,
    );
  });
  tearDown(() {
    controller.dispose();
    groupController.dispose();
    events.dispose();
  });

  test(
    'all allowed roles need exact permissions, feature, tenant and active subscription',
    () {
      for (final role in [
        UserRole.owner,
        UserRole.manager,
        UserRole.waiter,
        UserRole.kitchen,
      ]) {
        expect(
          AccessPolicy.canMenu(makeAppSession(role: role), 'MENU_VIEW'),
          true,
        );
        expect(
          AccessPolicy.canMenu(makeAppSession(role: role), 'MENU_UPDATE'),
          false,
        );
      }
      for (final role in [
        UserRole.cashier,
        UserRole.superAdmin,
        UserRole.unsupported,
      ]) {
        expect(
          AccessPolicy.canMenu(
            makeAppSession(role: role, permissions: menuPermissions),
            'MENU_VIEW',
          ),
          false,
        );
      }
      for (final invalid in [
        makeAppSession(features: {}),
        makeAppSession(restaurantId: null),
        makeAppSession(status: SubscriptionStatus.inactive),
        makeAppSession(permissions: {}),
      ]) {
        expect(AccessPolicy.canOpenRoute(invalid, '/app/menu'), false);
      }
    },
  );
  test(
    'scope ignores token and set ordering but includes all authorization boundaries',
    () {
      final a = makeAppSession(permissions: menuPermissions);
      final rotated = AppSession.fromEntitlement(
        user: a.authenticatedUser,
        tokens: makeTokens(accessToken: 'new'),
        entitlement: makeEntitlement(),
      );
      expect(AccessPolicy.menuScope(a), AccessPolicy.menuScope(rotated));
      expect(
        AccessPolicy.menuScope(a),
        AccessPolicy.menuScope(
          makeAppSession(
            permissions: menuPermissions.toList().reversed.toSet(),
          ),
        ),
      );
      for (final changed in [
        makeAppSession(permissions: {'MENU_VIEW'}),
        makeAppSession(restaurantId: 'other'),
        makeAppSession(role: UserRole.waiter),
        makeAppSession(features: {}),
        makeAppSession(status: SubscriptionStatus.inactive),
      ]) {
        expect(
          AccessPolicy.menuScope(a),
          isNot(AccessPolicy.menuScope(changed)),
        );
      }
    },
  );
  testWidgets(
    'search invalidates in-flight request immediately, debounces and resets page',
    (tester) async {
      final pending = <Completer<Result<MenuPage<MenuItem>>>>[];
      items.onList = (_) {
        final c = Completer<Result<MenuPage<MenuItem>>>();
        pending.add(c);
        return c.future;
      };
      final first = controller.load();
      controller.search(' old ');
      pending[0].complete(Success(page([item()])));
      await first;
      expect(controller.state.rows, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      controller.search(' new ');
      await tester.pump(const Duration(milliseconds: 349));
      expect(items.queries.length, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(items.queries.last.q, 'new');
      pending[1].complete(Success(page([item(version: 22)], pages: 3)));
      await tester.pump();
      expect(controller.state.rows.single.version, 22);
      controller.setPage(2);
      expect(items.queries.last.page, 2);
      pending[2].complete(Success(page([item()], index: 2, pages: 3)));
      await tester.pump();
      controller.setQuery(controller.state.query.copyWith(active: () => false));
      expect(items.queries.last.page, 0);
      pending[3].complete(Success(page([])));
      await tester.pump();
    },
  );
  test(
    'refresh retains rows and out-of-order responses cannot overwrite newest',
    () async {
      items.rows = [item()];
      await controller.load();
      final older = Completer<Result<MenuPage<MenuItem>>>();
      final newer = Completer<Result<MenuPage<MenuItem>>>();
      items.onList = (_) => older.future;
      final first = controller.load();
      expect(controller.state.rows, hasLength(1));
      items.onList = (_) => newer.future;
      final second = controller.load();
      newer.complete(Success(page([item(version: 12)])));
      await second;
      older.complete(Success(page([item(version: 10)])));
      await first;
      expect(controller.state.rows.single.version, 12);
    },
  );
  test(
    'mutation uses displayed version, locks duplicates, reloads list and never fetches detail',
    () async {
      final pending = Completer<Result<MenuItem>>();
      items.onWrite = () => pending.future;
      final write = controller.setStatus(item(version: 3), false);
      expect(controller.isPending('i1'), true);
      expect(await controller.delete(item()), isA<Error<void>>());
      expect(items.writes, [('status', 3)]);
      expect(items.detailCalls, 0);
      pending.complete(Success(item(version: 19)));
      expect(await write, isA<Success<MenuItem>>());
      expect(events.itemRevision, 1);
      expect(items.queries, hasLength(1));
      expect(controller.isPending('i1'), false);
    },
  );
  test('conflict, timeout and no-op never retry or advance baseline', () async {
    const conflict = Failure(
      type: FailureType.conflict,
      code: 'CONCURRENT_MENU_UPDATE',
      message: 'Conflict',
    );
    items.onWrite = () async => const Error(conflict);
    expect(
      await controller.update(
        'i1',
        const UpdateMenuItemInput(expectedVersion: 4, name: 'New'),
      ),
      isA<Error<MenuItem>>(),
    );
    expect(items.writes, [('update', 4)]);
    expect(items.queries, isEmpty);
    expect(items.detailCalls, 0);
    expect(
      await controller.update(
        'i1',
        const UpdateMenuItemInput(expectedVersion: 4),
      ),
      isA<Error<MenuItem>>(),
    );
    expect(items.writes, hasLength(1));
    items.onWrite = () async => const Error(networkFailure);
    final failure =
        await controller.setStatus(item(), false) as Error<MenuItem>;
    expect(failure.failure.message, contains('Chưa xác định'));
    expect(items.writes, hasLength(2));
    expect(items.detailCalls, 0);
  });
  test(
    'inactive items reject availability; inactive groups reject assignment',
    () async {
      expect(
        await controller.setAvailability(
          item(active: false),
          AvailabilityStatus.outOfStock,
        ),
        isA<Error<MenuItem>>(),
      );
      expect(
        await controller.setGroup(
          item(),
          const MenuItemGroupSummary(id: 'g2', name: 'Closed', active: false),
        ),
        isA<Error<MenuItem>>(),
      );
      expect(items.writes, isEmpty);
      await controller.setGroup(item(version: 8), null);
      expect(items.lastGroup, isNull);
      expect(items.writes.single, ('group', 8));
    },
  );
  test(
    'group deletion clears item filter and refreshes items and selector',
    () async {
      final selector = MenuGroupSelectorController(
        session: () => session,
        list: GetMenuGroups(groups),
        activeOnly: true,
        events: events,
      );
      addTearDown(selector.dispose);
      controller.setQuery(const MenuQuery(groupId: 'g1'));
      await Future<void>.delayed(Duration.zero);
      await selector.load();
      final requests = groups.queries.length;
      await groupController.delete(group(version: 2));
      await Future<void>.delayed(Duration.zero);
      expect(groups.writes, [('delete', 2)]);
      expect(controller.state.query.groupId, isNull);
      expect(items.queries.last.groupId, isNull);
      expect(groups.queries.length, greaterThan(requests));
      expect(groups.queries.where((q) => q.active == true), isNotEmpty);
    },
  );
  test(
    'selector enforces active-only across pages; filter selector may include inactive',
    () async {
      groups.onList = (query) async =>
          Success(page([group()], index: query.page, pages: 4));
      final selector = MenuGroupSelectorController(
        session: () => session,
        list: GetMenuGroups(groups),
        activeOnly: true,
        events: events,
      );
      addTearDown(selector.dispose);
      await selector.load();
      selector.setPage(2);
      await Future<void>.delayed(Duration.zero);
      expect(groups.queries.last.page, 2);
      expect(groups.queries.last.active, true);
      selector.setQuery(const MenuQuery(active: false));
      await Future<void>.delayed(Duration.zero);
      expect(groups.queries.last.active, true);
      expect(groups.queries.last.page, 0);
      final filter = MenuGroupSelectorController(
        session: () => session,
        list: GetMenuGroups(groups),
        activeOnly: false,
        events: events,
      );
      addTearDown(filter.dispose);
      await filter.load();
      expect(groups.queries.last.active, isNull);
    },
  );
  test('empty final page falls back after deletion', () async {
    items.onList = (q) async =>
        Success(page([item()], index: q.page, pages: 2));
    await controller.load();
    controller.setPage(1);
    await Future<void>.delayed(Duration.zero);
    items.onList = (q) async =>
        Success(page(q.page == 0 ? [item()] : [], index: q.page, pages: 1));
    await controller.delete(item());
    expect(controller.state.query.page, 0);
    expect(controller.state.rows, hasLength(1));
  });
  test(
    'scope changes drop reads and writes and reject stale controller operations',
    () async {
      final read = Completer<Result<MenuPage<MenuItem>>>();
      items.onList = (_) => read.future;
      final loading = controller.load();
      final write = Completer<Result<MenuItem>>();
      items.onWrite = () => write.future;
      final saving = controller.setStatus(item(), false);
      session = makeAppSession(
        restaurantId: 'restaurant-2',
        permissions: menuPermissions,
      );
      read.complete(Success(page([item()])));
      write.complete(Success(item()));
      await loading;
      expect(await saving, isA<Error<MenuItem>>());
      expect(controller.state.rows, isEmpty);
      expect(events.itemRevision, 0);
      await controller.delete(item());
      expect(items.writes, hasLength(1));
    },
  );
  test(
    'token rotation keeps controller requests and filters current',
    () async {
      controller.setQuery(const MenuQuery(q: 'tea'));
      await Future<void>.delayed(Duration.zero);
      session = AppSession.fromEntitlement(
        user: session!.authenticatedUser,
        tokens: makeTokens(accessToken: 'rotated'),
        entitlement: makeEntitlement(),
      );
      expect(controller.isCurrent, true);
      expect(controller.state.query.q, 'tea');
      await controller.setStatus(item(), false);
      expect(items.writes, hasLength(1));
    },
  );
  test('disposed selector ignores completion', () async {
    final pending = Completer<Result<MenuPage<MenuGroup>>>();
    groups.onList = (_) => pending.future;
    final selector = MenuGroupSelectorController(
      session: () => session,
      list: GetMenuGroups(groups),
      activeOnly: true,
      events: events,
    );
    final loading = selector.load();
    selector.dispose();
    pending.complete(Success(page([group()])));
    await loading;
    expect(selector.state.rows, isEmpty);
  });
}
