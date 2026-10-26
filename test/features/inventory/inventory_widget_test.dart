import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/warehouse_list_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_balances_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_warehouses_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_low_stock_screen.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/inventory_threshold_dialog.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/inventory_widgets.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/warehouse_action_dialog.dart';
import 'package:pos_saas_app/features/inventory/presentation/widgets/warehouse_form.dart';
import '../../helpers/auth_fakes.dart';
import 'inventory_fakes.dart';

Future<AuthController> _auth({
  Set<String> permissions = inventoryPermissions,
  Set<String> features = inventoryFeatures,
  SessionEvents? events,
}) async {
  final auth = makeController(
    sessionEvents: events,
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: features)),
  );
  await auth.login(
    const LoginCredentials(
      email: 'inventory@example.com',
      password: 'password',
    ),
  );
  return auth;
}

Future<void> _pump(
  WidgetTester tester, {
  FakeWarehouses? wh,
  FakeBalances? balances,
  AuthController? auth,
  Widget? dialog,
  Widget screen = const InventoryBalancesScreen(),
  double width = 1200,
  double scale = 1,
  bool keyboard = false,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  if (keyboard) tester.view.viewInsets = const FakeViewPadding(bottom: 300);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.view.resetViewInsets);
  auth ??= await _auth();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth!),
        warehouseRepositoryProvider.overrideWithValue(wh ?? FakeWarehouses()),
        inventoryBalanceRepositoryProvider.overrideWithValue(
          balances ?? FakeBalances(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: dialog == null
              ? RepaintBoundary(
                  key: const ValueKey('inventory-preview'),
                  child: screen,
                )
              : Consumer(
                  builder: (context, ref, _) => Center(
                    child: TextButton(
                      onPressed: () => showInventoryDialog<void>(
                        context,
                        ref,
                        child: dialog,
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (dialog != null) {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

TextField _field(WidgetTester tester, String label) => tester.widget<TextField>(
  find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  ),
);
Finder _findField(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);

void main() {
  testWidgets(
    'token rotation keeps filter/draft; permission change clears scoped state',
    (tester) async {
      final events = SessionEvents();
      final auth = await _auth(events: events);
      await _pump(tester, auth: auth, dialog: const WarehouseForm());
      final container = ProviderScope.containerOf(
        tester.element(find.byType(WarehouseForm)),
      );
      final controller = container.read(warehouseListProvider);
      controller.search('Kho chính');
      await tester.enterText(_findField('Mã kho'), 'DRAFT');
      events.refreshed(
        makeAuthSession(
          permissions: inventoryPermissions,
          tokens: makeTokens(accessToken: 'rotated'),
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(warehouseListProvider), same(controller));
      expect(controller.query.q, 'Kho chính');
      expect(_field(tester, 'Mã kho').controller!.text, 'DRAFT');
      events.refreshed(
        makeAuthSession(
          permissions: {'INVENTORY_VIEW'},
          tokens: makeTokens(accessToken: 'new-permissions'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WarehouseForm), findsNothing);
      expect(container.read(warehouseListProvider), isNot(same(controller)));
      expect(container.read(warehouseListProvider).query.q, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      events.dispose();
    },
  );
  for (final width in [320.0, 600.0, 800.0, 1200.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'independent stock screens fit width $width with system text $scale',
        (tester) async {
          final wh = FakeWarehouses()
            ..rows = [
              warehouse(
                name:
                    'Kho nguyên liệu chính tại khu vực phía sau nhà hàng với tên dài',
              ),
            ];
          final balances = FakeBalances()
            ..rows = [
              balance(
                name:
                    'Nguyên liệu tên rất dài dùng để kiểm tra bố cục khi phóng chữ hệ thống',
                quantity: 99999999999.999,
                min: 0,
              ),
              balance(i: 'i2', configured: false),
              balance(i: 'i3', active: false),
            ];
          await _pump(
            tester,
            wh: wh,
            balances: balances,
            width: width,
            scale: scale,
          );
          expect(find.text('Tồn kho'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('Chưa cấu hình'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Chưa cấu hình'), findsOneWidget);
          expect(balances.details, 0); // no N+1 detail requests
          expect(tester.takeException(), isNull);
          if (find.byType(ExpansionTile).evaluate().isNotEmpty) {
            await _tap(tester, find.text('Lọc và sắp xếp'));
            expect(
              find.byType(DropdownButtonFormField<String>),
              findsNWidgets(4),
            );
            expect(tester.takeException(), isNull);
          }
          await _pump(
            tester,
            wh: wh,
            balances: balances,
            width: width,
            scale: scale,
            screen: const InventoryWarehousesScreen(),
          );
          expect(find.text('Quản lý kho'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('Mặc định'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Mặc định'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _pump(
            tester,
            wh: wh,
            balances: balances,
            width: width,
            scale: scale,
            screen: const InventoryLowStockScreen(),
          );
          expect(find.text('Tồn thấp hiện tại'), findsOneWidget);
          expect(balances.lowCalls, 1);
          expect(find.textContaining('KHO-W1'), findsWidgets);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'read-only without low-stock feature has no write actions or low request',
    (tester) async {
      final balances = FakeBalances();
      await _pump(
        tester,
        auth: await _auth(
          permissions: {'INVENTORY_VIEW'},
          features: {'INVENTORY_MANAGEMENT'},
        ),
        balances: balances,
      );
      expect(find.text('Tồn thấp hiện tại'), findsNothing);
      expect(find.text('Thêm kho'), findsNothing);
      expect(find.text('Sửa ngưỡng'), findsNothing);
      expect(find.text('Chi tiết'), findsWidgets);
      expect(balances.lowCalls, 0);
    },
  );

  testWidgets('create normalizes code, keeps duplicate draft then saves', (
    tester,
  ) async {
    final wh = FakeWarehouses();
    wh.onCreate = (input) async => const Error(
      Failure(
        type: FailureType.conflict,
        code: 'WAREHOUSE_CODE_EXISTS',
        message: 'Mã đã dùng',
        fieldErrors: {'code': 'Mã đã dùng'},
      ),
    );
    await _pump(tester, wh: wh, dialog: const WarehouseForm());
    await tester.enterText(_findField('Mã kho'), ' kho-new ');
    await tester.enterText(_findField('Tên kho'), ' Kho mới ');
    await _tap(tester, find.text('Tạo kho'));
    expect(_field(tester, 'Tên kho').controller!.text, ' Kho mới ');
    expect(_field(tester, 'Mã kho').decoration!.errorText, 'Mã đã dùng');
    expect(wh.lastCreate!.code, 'KHO-NEW');
    wh.onCreate = null;
    await _tap(tester, find.text('Tạo kho'));
    expect(find.byType(WarehouseForm), findsNothing);
  });

  testWidgets(
    'edit conflict preserves draft; reload requires explicit discard confirmation',
    (tester) async {
      final wh = FakeWarehouses();
      wh.onUpdate = (id, input) async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'CONCURRENT_WAREHOUSE_UPDATE',
          message: 'Kho đã thay đổi',
        ),
      );
      await _pump(
        tester,
        wh: wh,
        dialog: const WarehouseForm(id: 'w2'),
      );
      await tester.enterText(_findField('Tên kho'), 'Bản nháp của tôi');
      await _tap(tester, find.text('Lưu thay đổi'));
      expect(_field(tester, 'Tên kho').controller!.text, 'Bản nháp của tôi');
      expect(wh.lastUpdate!.code, isNull);
      expect(wh.lastUpdate!.expectedVersion, 0);
      await _tap(tester, find.text('Tải lại để đối chiếu'));
      await _tap(tester, find.text('Giữ bản nháp'));
      expect(_field(tester, 'Tên kho').controller!.text, 'Bản nháp của tôi');
      wh.onDetail = (id) async => Success(
        warehouse(id: id, isDefault: false, version: 3, name: 'Dữ liệu server'),
      );
      await _tap(tester, find.text('Tải lại để đối chiếu'));
      await _tap(tester, find.text('Tải dữ liệu mới'));
      expect(_field(tester, 'Tên kho').controller!.text, 'Dữ liệu server');
      wh.onUpdate = null;
      await tester.enterText(_findField('Tên kho'), 'Tên mới');
      await _tap(tester, find.text('Lưu thay đổi'));
      expect(wh.lastUpdate!.expectedVersion, 3);
    },
  );

  testWidgets(
    'threshold accepts logical zero and rejects excess precision before HTTP',
    (tester) async {
      final repo = FakeBalances();
      await _pump(
        tester,
        balances: repo,
        dialog: const InventoryThresholdDialog(
          warehouseId: 'w1',
          ingredientId: 'i2',
          edit: true,
        ),
      );
      expect(find.text('Chưa cấu hình'), findsOneWidget);
      await tester.enterText(_findField('Ngưỡng tối thiểu'), '1.0001');
      await _tap(tester, find.text('Lưu ngưỡng'));
      expect(repo.saves, 0);
      expect(
        _field(tester, 'Ngưỡng tối thiểu').decoration!.errorText,
        isNotNull,
      );
      await tester.enterText(_findField('Ngưỡng tối thiểu'), '0');
      await _tap(tester, find.text('Lưu ngưỡng'));
      expect(repo.lastInput!.expectedVersion, isNull);
      expect(repo.lastInput!.minQuantity.scaled, 0);
      expect(find.byType(InventoryThresholdDialog), findsNothing);
    },
  );

  testWidgets(
    'threshold conflict retains input and uses confirmed refreshed version',
    (tester) async {
      final repo = FakeBalances();
      repo.onSave = (w, i, input) async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'CONCURRENT_INVENTORY_UPDATE',
          message: 'Số dư đã đổi',
        ),
      );
      await _pump(
        tester,
        balances: repo,
        dialog: const InventoryThresholdDialog(
          warehouseId: 'w1',
          ingredientId: 'i1',
          edit: true,
        ),
      );
      await tester.enterText(_findField('Ngưỡng tối thiểu'), '7.125');
      await _tap(tester, find.text('Lưu ngưỡng'));
      expect(_field(tester, 'Ngưỡng tối thiểu').controller!.text, '7.125');
      repo.onDetail = (w, i) async => Success(balance(min: 5, version: 9));
      await _tap(tester, find.text('Tải lại để đối chiếu'));
      await _tap(tester, find.text('Tải dữ liệu mới'));
      expect(_field(tester, 'Ngưỡng tối thiểu').controller!.text, '5');
      repo.onSave = (w, i, input) async =>
          Success(balance(min: 7, version: 10));
      await tester.enterText(_findField('Ngưỡng tối thiểu'), '7');
      await _tap(tester, find.text('Lưu ngưỡng'));
      expect(repo.lastInput!.expectedVersion, 9);
    },
  );

  for (final dialog in <Widget>[
    const WarehouseForm(),
    const InventoryThresholdDialog(
      warehouseId: 'w1',
      ingredientId: 'i2',
      edit: true,
    ),
    const WarehouseActionDialog(id: 'w2', action: WarehouseAction.delete),
  ]) {
    testWidgets(
      '${dialog.runtimeType} scrolls at 320px, 200% text and keyboard',
      (tester) async {
        await _pump(
          tester,
          dialog: dialog,
          width: 320,
          scale: 2,
          keyboard: true,
        );
        expect(tester.takeException(), isNull);
        final action = dialog is WarehouseForm
            ? 'Tạo kho'
            : dialog is InventoryThresholdDialog
            ? 'Lưu ngưỡng'
            : 'Xác nhận xóa kho';
        await tester.ensureVisible(find.text(action));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.text(action)).bottom, lessThan(700));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'scope change dismisses old dialog and ignores delayed creation',
    (tester) async {
      final auth = await _auth(), wh = FakeWarehouses();
      final pending = Completer<Result<Warehouse>>();
      wh.onCreate = (input) => pending.future;
      await _pump(tester, auth: auth, wh: wh, dialog: const WarehouseForm());
      await tester.enterText(_findField('Mã kho'), 'NEW');
      await tester.enterText(_findField('Tên kho'), 'Kho mới');
      await tester.tap(find.text('Tạo kho'));
      await tester.pump();
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.byType(WarehouseForm), findsNothing);
      pending.complete(Success(warehouse(id: 'new', isDefault: false)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final action in [
    WarehouseAction.makeDefault,
    WarehouseAction.disable,
    WarehouseAction.delete,
  ]) {
    testWidgets('warehouse ${action.name} uses fresh detail and confirmation', (
      tester,
    ) async {
      final wh = FakeWarehouses();
      await _pump(
        tester,
        wh: wh,
        dialog: WarehouseActionDialog(id: 'w2', action: action),
      );
      expect(wh.details, greaterThanOrEqualTo(1));
      expect([wh.defaults, wh.statuses, wh.deletes], [0, 0, 0]);
      await _tap(
        tester,
        find.text('Xác nhận ${warehouseActionLabel(action).toLowerCase()}'),
      );
      expect(wh.defaults + wh.statuses + wh.deletes, 1);
      expect(find.byType(WarehouseActionDialog), findsNothing);
    });
  }
}
