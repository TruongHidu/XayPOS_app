import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/ui/shell/app_shell.dart';
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
}
