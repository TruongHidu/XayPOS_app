import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/ui/shell/app_shell.dart';
import 'package:pos_saas_app/features/staff/domain/entities/staff_permission_config.dart';
import 'package:pos_saas_app/features/staff/presentation/controllers/staff_permission_controller.dart';
import 'package:pos_saas_app/features/staff/presentation/widgets/staff_permission_dialog.dart';
import '../../helpers/auth_fakes.dart';
import 'staff_fakes.dart';
import 'package:pos_saas_app/features/staff/presentation/widgets/edit_staff_dialog.dart';
import 'package:pos_saas_app/features/staff/presentation/widgets/create_staff_dialog.dart';
import 'package:pos_saas_app/features/staff/presentation/widgets/staff_member_card.dart';

void main() {
  testWidgets('server field errors clear on editing and allow resubmission', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EditStaffDialog(
            staff: member(),
            roles: const [waiterRole],
            fieldErrors: () => {'email': 'Email already used'},
            onSubmit: ({required staffId, name, email, phone, roleCode}) async {
              calls++;
              return 'Server rejected update';
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField).first, 'Alice Updated');
    await tester.ensureVisible(find.text('Lưu thay đổi'));
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Email already used'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(1), 'new@example.com');
    await tester.pump();
    await tester.ensureVisible(find.text('Lưu thay đổi'));
    await tester.tap(find.text('Lưu thay đổi'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(320, 700),
    const Size(800, 900),
    const Size(1440, 900),
  ]) {
    testWidgets(
      'staff list, filters and dialogs use available width at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final auth = makeController(
          authRepository: FakeAuthRepository()
            ..restoreResult = Success(
              makeAuthSession(permissions: staffPermissions),
            ),
          entitlementRepository: FakeEntitlementRepository()
            ..result = Success(makeEntitlement(features: staffFeatures)),
        );
        await auth.restore();
        final repo = FakeStaffRepository();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith((ref) => auth),
              staffRepositoryProvider.overrideWithValue(repo),
            ],
            child: const MaterialApp(home: AppShell(initialSection: 'staff')),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Alice'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Alice'), findsOneWidget);
        expect(
          tester.getSize(find.byType(StaffMemberCard).first).width,
          closeTo(size.width - 32, 0.1),
        );
        if (size.width >= 1440) {
          expect(
            tester.getTopLeft(find.text('Đăng nhập cuối')).dy,
            closeTo(
              tester.getTopLeft(find.text('Vai trò & trạng thái')).dy,
              0.1,
            ),
          );
          expect(
            tester.getTopLeft(find.text('Đăng nhập cuối')).dx,
            greaterThan(
              tester.getTopLeft(find.text('Vai trò & trạng thái')).dx,
            ),
          );
        }
        await tester.scrollUntilVisible(
          find.text('Bộ lọc và sắp xếp'),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bộ lọc và sắp xếp'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final roleFilter = find.byType(DropdownButtonFormField<String>).at(0);
        final statusFilter = find.byType(DropdownButtonFormField<String>).at(1);
        if (size.width >= 800) {
          expect(
            tester.getTopLeft(statusFilter).dy,
            closeTo(tester.getTopLeft(roleFilter).dy, 0.1),
          );
          expect(
            tester.getTopLeft(statusFilter).dx,
            greaterThan(tester.getTopLeft(roleFilter).dx),
          );
        }
        await tester.tap(find.text('Bộ lọc và sắp xếp'));
        await tester.pumpAndSettle();
        for (final label in [
          'Thêm nhân viên',
          'Chi tiết',
          'Sửa',
          'Vô hiệu hóa',
          'Phân quyền',
        ]) {
          await tester.scrollUntilVisible(
            find.text(label),
            label == 'Thêm nhân viên' ? -200 : 200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
          final dialog = find.byType(Dialog);
          expect(dialog, findsOneWidget, reason: label);
          final surface = find
              .descendant(of: dialog, matching: find.byType(Material))
              .first;
          expect(
            tester.getSize(surface).width,
            closeTo(size.width - 32, 0.1),
            reason: label,
          );
          if (label == 'Thêm nhân viên' && size.width >= 800) {
            final fields = find.descendant(
              of: find.byType(CreateStaffDialog),
              matching: find.byType(TextFormField),
            );
            expect(
              tester.getTopLeft(fields.at(1)).dy,
              closeTo(tester.getTopLeft(fields.first).dy, 0.1),
            );
            expect(
              tester.getTopLeft(fields.at(1)).dx,
              greaterThan(tester.getTopLeft(fields.first).dx),
            );
            await tester.enterText(fields.first, 'Unsaved name');
            tester.view.physicalSize = const Size(320, 700);
            await tester.pumpAndSettle();
            expect(find.text('Unsaved name'), findsOneWidget);
            expect(tester.takeException(), isNull);
            tester.view.physicalSize = size;
            await tester.pumpAndSettle();
          }
          Navigator.of(tester.element(dialog)).pop();
          await tester.pumpAndSettle();
        }
      },
    );
  }
  testWidgets(
    'permission dialog switches staff without reusing previous config',
    (tester) async {
      final repo = FakeStaffRepository()..delayedPermissions = true;
      final controller = permissionController(repo);
      final container = ProviderContainer(
        overrides: [
          staffPermissionControllerProvider.overrideWith((ref) => controller),
        ],
      );
      addTearDown(container.dispose);
      Widget app(String id) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: StaffPermissionDialog(staff: member(id))),
        ),
      );
      await tester.pumpWidget(app('A'));
      await tester.pump();
      repo.configs['A']!.complete(
        Success(config('A', grants: ['ORDER_CANCEL'])),
      );
      await tester.pump();
      await tester.pumpWidget(app('B'));
      await tester.pump();
      expect(controller.state.config, isNull);
      expect(controller.canSave, false);
      repo.configs['B']!.complete(Success(config('B')));
      await tester.pumpAndSettle();
      expect(controller.state.config!.staffId, 'B');
      expect(controller.state.localGrants, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  group('permission dialog', () {
    Future<StaffPermissionController> open(
      WidgetTester tester, {
      List<String> role = const ['ORDER_VIEW'],
      List<String> grants = const [],
      List<String> denies = const [],
      Set<String> actor = staffPermissions,
      double width = 800,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeStaffRepository()..delayedPermissions = true;
      final controller = permissionController(
        repo,
        session: () =>
            makeAppSession(permissions: actor, features: staffFeatures),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            staffPermissionControllerProvider.overrideWith((ref) => controller),
          ],
          child: MaterialApp(
            home: Scaffold(body: StaffPermissionDialog(staff: member('A'))),
          ),
        ),
      );
      await tester.pump();
      repo.configs['A']!.complete(
        Success(
          StaffPermissionConfig(
            staffId: 'A',
            roleCode: 'WAITER',
            rolePermissions: role,
            grants: grants,
            denies: denies,
            effectivePermissions: role,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    Finder toggle(String code) =>
        find.byKey(ValueKey('staff-permission-$code'));

    testWidgets('shows plain names grouped, without technical codes', (
      tester,
    ) async {
      await open(tester);
      expect(find.text('Đơn hàng'), findsOneWidget);
      expect(find.text('Xem đơn hàng'), findsOneWidget);
      expect(find.text('Hủy đơn hàng'), findsOneWidget);
      expect(find.text('ORDER_CANCEL'), findsNothing);
      expect(find.textContaining('override'), findsNothing);
      expect(find.textContaining('Đang có 1/2 quyền'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switches map to role, grant and deny and count changes', (
      tester,
    ) async {
      final c = await open(tester);
      expect(c.isEnabled('ORDER_VIEW'), true);

      await tester.tap(toggle('ORDER_CANCEL'));
      await tester.pumpAndSettle();
      expect(c.state.localGrants, {'ORDER_CANCEL'});
      expect(find.text('Thêm riêng cho nhân viên này'), findsOneWidget);

      await tester.tap(toggle('ORDER_VIEW'));
      await tester.pumpAndSettle();
      expect(c.state.localDenies, {'ORDER_VIEW'});
      expect(find.text('Đã tắt riêng cho nhân viên này'), findsOneWidget);
      expect(find.text('2 thay đổi chưa lưu'), findsOneWidget);

      await tester.tap(toggle('ORDER_VIEW'));
      await tester.pumpAndSettle();
      expect(c.state.localDenies, isEmpty);
      expect(find.text('1 thay đổi chưa lưu'), findsOneWidget);

      await tester.tap(find.text('Khôi phục theo vai trò'));
      await tester.pumpAndSettle();
      expect(c.state.localGrants, isEmpty);
      expect(find.textContaining('chưa lưu'), findsNothing);
    });

    testWidgets('a group switches together', (tester) async {
      final c = await open(tester);
      await tester.tap(find.text('Bật cả nhóm'));
      await tester.pumpAndSettle();
      expect(c.state.localGrants, {'ORDER_CANCEL'});
      await tester.tap(find.text('Tắt cả nhóm'));
      await tester.pumpAndSettle();
      expect(c.state.localGrants, isEmpty);
      expect(c.state.localDenies, {'ORDER_VIEW'});
    });

    testWidgets('a permission the actor lacks cannot be granted', (
      tester,
    ) async {
      final c = await open(
        tester,
        actor: staffPermissions.difference({'ORDER_CANCEL'}),
      );
      expect(c.canToggle('ORDER_CANCEL'), false);
      expect(c.canToggle('ORDER_VIEW'), true);
      expect(
        find.text('Bạn chưa có quyền này nên không thể cấp cho người khác.'),
        findsOneWidget,
      );
      await tester.tap(toggle('ORDER_CANCEL'));
      await tester.pumpAndSettle();
      expect(c.state.localGrants, isEmpty);
    });

    testWidgets('search narrows the list', (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('staff-permission-search')),
        'hủy',
      );
      await tester.pumpAndSettle();
      expect(find.text('Hủy đơn hàng'), findsOneWidget);
      expect(find.text('Xem đơn hàng'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('staff-permission-search')),
        'không có',
      );
      await tester.pumpAndSettle();
      expect(find.text('Không tìm thấy quyền phù hợp.'), findsOneWidget);
    });

    testWidgets('closing with unsaved changes asks first', (tester) async {
      await open(tester);
      await tester.tap(toggle('ORDER_CANCEL'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Đóng'));
      await tester.pumpAndSettle();
      expect(find.text('Bỏ thay đổi chưa lưu?'), findsOneWidget);
      await tester.tap(find.text('Tiếp tục sửa'));
      await tester.pumpAndSettle();
      expect(find.byType(StaffPermissionDialog), findsOneWidget);
    });

    for (final width in [320.0, 412.0]) {
      testWidgets('fits a $width phone at large text', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await open(tester, width: width);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
