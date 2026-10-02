import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'staff_fakes.dart';

void main() {
  test('latest filter wins even if previous request completes later', () async {
    final r = FakeStaffRepository()..delayedList = true;
    final c = listController(r);
    addTearDown(c.dispose);
    final first = c.loadStaffList();
    c.setRoleFilter('WAITER');
    r.lists[1].complete(Success(page('B')));
    await Future<void>.delayed(Duration.zero);
    r.lists[0].complete(Success(page('A')));
    await first;
    expect(c.state.staffList.single.id, 'B');
    expect(r.queries.last['roleCode'], 'WAITER');
  });
  testWidgets('search debounce invalidates response immediately', (
    tester,
  ) async {
    final r = FakeStaffRepository()..delayedList = true;
    final c = listController(r);
    addTearDown(c.dispose);
    final first = c.loadStaffList();
    c.setSearchQuery('a');
    c.setSearchQuery('alice');
    r.lists[0].complete(Success(page('old')));
    await tester.pump();
    await first;
    expect(c.state.staffList, isEmpty);
    await tester.pump(const Duration(milliseconds: 350));
    expect(r.queries.length, 2);
    expect(r.queries.last['q'], 'alice');
    r.lists[1].complete(Success(page('new')));
    await tester.pump();
    expect(c.state.staffList.single.id, 'new');
  });
  test(
    'filters reset pagination and enforce supported sort and size',
    () async {
      final r = FakeStaffRepository();
      final c = listController(r);
      addTearDown(c.dispose);
      await c.loadInitial();
      c.setPage(1);
      await Future<void>.delayed(Duration.zero);
      expect(r.queries.last['page'], 1);
      c.setStatusFilter(false);
      await Future<void>.delayed(Duration.zero);
      expect(r.queries.last['page'], 0);
      expect(r.queries.last['active'], false);
      c.setSorting('email', 'asc');
      await Future<void>.delayed(Duration.zero);
      expect(r.queries.last['sortBy'], 'email');
      final count = r.queries.length;
      c.setSorting('phone', 'asc');
      c.setSize(101);
      expect(r.queries.length, count);
      c.setSize(50);
      await Future<void>.delayed(Duration.zero);
      expect(r.queries.last['size'], 50);
    },
  );
  test(
    'create/update/status validation, empty patch and clear phone',
    () async {
      final r = FakeStaffRepository();
      final c = listController(r);
      addTearDown(c.dispose);
      await c.loadInitial();
      expect(
        await c.addStaff(
          name: 'Alice',
          email: 'a@b.com',
          roleCode: 'WAITER',
          initialPassword: '12345678',
        ),
        isNull,
      );
      expect(r.creates, 1);
      expect(
        await c.addStaff(
          name: 'Alice',
          email: 'a@b.com',
          roleCode: 'OWNER',
          initialPassword: '12345678',
        ),
        isNotNull,
      );
      expect(r.creates, 1);
      expect(await c.editStaff(staffId: 'A'), isNotNull);
      expect(r.updates, 0);
      expect(await c.editStaff(staffId: 'A', phone: ''), isNull);
      expect(r.patch!['phone'], '');
      expect(r.patch!['name'], isNull);
      expect(await c.toggleStatus(staffId: 'A', active: false), isNotNull);
      expect(r.statuses, 0);
      expect(
        await c.toggleStatus(staffId: 'A', active: false, reason: 'Left'),
        isNull,
      );
      expect(await c.toggleStatus(staffId: 'A', active: true), isNull);
      expect(r.statuses, 2);
    },
  );
  test(
    'dispose ignores outstanding responses and rejects old form saves',
    () async {
      final r = FakeStaffRepository()..delayedList = true;
      final c = listController(r);
      final request = c.loadStaffList();
      c.dispose();
      r.lists.single.complete(Success(page('old')));
      await request;
      expect(await c.toggleStatus(staffId: 'A', active: true), isNotNull);
      expect(r.statuses, 0);
    },
  );
  test('A cannot overwrite B, and saves require matching staff id', () async {
    final r = FakeStaffRepository()..delayedPermissions = true;
    final c = permissionController(r);
    addTearDown(c.dispose);
    final a = c.load('A');
    await Future<void>.delayed(Duration.zero);
    final b = c.load('B');
    await Future<void>.delayed(Duration.zero);
    expect(c.state.config, isNull);
    expect(c.canSave, isFalse);
    r.configs['B']!.complete(Success(config('B', grants: ['ORDER_CANCEL'])));
    await b;
    r.configs['A']!.complete(Success(config('A')));
    await a;
    expect(c.state.config!.staffId, 'B');
    expect(c.state.localGrants, {'ORDER_CANCEL'});
    expect(await c.saveOverrides('A'), isNotNull);
    expect(r.savedId, isNull);
  });
  test(
    'catalog or config failure clears previous overrides and disables save',
    () async {
      final r = FakeStaffRepository();
      final c = permissionController(r);
      addTearDown(c.dispose);
      await c.load('A');
      c.setPermissionState('ORDER_CANCEL', 'grant');
      r.catalog = const Error(
        Failure(type: FailureType.network, message: 'offline'),
      );
      await c.load('B');
      expect(c.state.config, isNull);
      expect(c.state.localGrants, isEmpty);
      expect(c.canSave, isFalse);
      expect(await c.saveOverrides('B'), isNotNull);
      expect(r.savedId, isNull);
      r.catalog = const Success([]);
      r.delayedPermissions = true;
      final b = c.load('B');
      await Future<void>.delayed(Duration.zero);
      r.configs['B']!.complete(
        const Error(Failure(type: FailureType.network, message: 'offline')),
      );
      await b;
      expect(c.canSave, isFalse);
    },
  );
  test(
    'PUT replaces both arrays; failure never changes confirmed effective permissions',
    () async {
      final r = FakeStaffRepository();
      final c = permissionController(r);
      addTearDown(c.dispose);
      await c.load('A');
      c.setPermissionState('ORDER_CANCEL', 'grant');
      c.setPermissionState('ORDER_VIEW', 'deny');
      r.putResult = const Error(
        Failure(type: FailureType.conflict, message: 'conflict'),
      );
      expect(await c.saveOverrides('A'), 'conflict');
      expect(c.state.config!.effectivePermissions, ['ORDER_VIEW']);
      expect(c.state.successMessage, isNull);
      expect(r.savedGrants, ['ORDER_CANCEL']);
      expect(r.savedDenies, ['ORDER_VIEW']);
      r.putResult = null;
      expect(await c.saveOverrides('A'), isNull);
      expect(c.state.config!.effectivePermissions, ['ORDER_CANCEL']);
      c.resetAllOverrides();
      expect(await c.saveOverrides('A'), isNull);
      expect(r.savedGrants, isEmpty);
      expect(r.savedDenies, isEmpty);
    },
  );
}
