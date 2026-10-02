import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/staff/presentation/screens/staff_management_screen.dart';
import 'package:pos_saas_app/features/staff/presentation/widgets/staff_permission_dialog.dart';
import '../../helpers/auth_fakes.dart';
import 'staff_fakes.dart';
import 'package:pos_saas_app/features/staff/presentation/widgets/edit_staff_dialog.dart';

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

  testWidgets(
    'phone list, filters, create/edit/status and permission dialog do not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
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
          child: const MaterialApp(home: StaffManagementScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Alice'), findsOneWidget);
      await tester.tap(find.text('Bộ lọc và sắp xếp'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Bộ lọc và sắp xếp'));
      await tester.pumpAndSettle();
      for (final label in [
        'Thêm nhân viên',
        'Sửa',
        'Vô hiệu hóa',
        'Phân quyền',
      ]) {
        await tester.ensureVisible(find.text(label).first);
        await tester.tap(find.text(label).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
        final dialog = find.byType(Dialog);
        expect(dialog, findsOneWidget, reason: label);
        Navigator.of(tester.element(dialog)).pop();
        await tester.pumpAndSettle();
      }
    },
  );
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
