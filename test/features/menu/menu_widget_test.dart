import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_item.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_price.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_page.dart';
import 'package:pos_saas_app/features/menu/presentation/screens/menu_management_screen.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/menu_actions.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/menu_dialogs.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/menu_details.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/menu_item_form.dart';
import 'menu_fakes.dart';
import '../../helpers/auth_fakes.dart';

const _credentials = LoginCredentials(
  email: 'menu@example.com',
  password: 'password',
);

Future<AuthController> _auth({
  Set<String> permissions = menuPermissions,
  SessionEvents? events,
}) async {
  final repo = FakeAuthRepository()
    ..loginResult = Success(makeAuthSession(permissions: permissions));
  final auth = makeController(authRepository: repo, sessionEvents: events);
  await auth.login(_credentials);
  return auth;
}

Future<void> _pump(
  WidgetTester tester,
  AuthController auth,
  FakeMenuItems items,
  FakeMenuGroups groups, {
  Widget? dialog,
  String permission = 'MENU_UPDATE',
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        menuItemRepositoryProvider.overrideWithValue(items),
        menuGroupRepositoryProvider.overrideWithValue(groups),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: dialog == null
              ? const MenuManagementScreen()
              : Consumer(
                  builder: (context, ref, child) => TextButton(
                    onPressed: () => showMenuDialog<void>(
                      context,
                      ref,
                      permission: permission,
                      child: dialog,
                    ),
                    child: const Text('Open'),
                  ),
                ),
        ),
      ),
    ),
  );
  await tester.pump();
  if (dialog != null) {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  for (final scenario in [
    (
      name: 'missing response cost untouched',
      original: null,
      edited: null,
      expected: null,
    ),
    (
      name: 'missing response cost explicitly reset',
      original: null,
      edited: '0',
      expected: '0',
    ),
    (
      name: 'known cost left unchanged',
      original: 12500.5,
      edited: null,
      expected: null,
    ),
    (
      name: 'known cost configuration explicitly cleared',
      original: 12500.5,
      edited: '',
      expected: null,
    ),
    (
      name: 'known cost changed to decimal',
      original: 12500.5,
      edited: '15000.01',
      expected: '15000.01',
    ),
  ]) {
    testWidgets('edit costPrice: ${scenario.name}', (tester) async {
      final json = itemJson(costConfigured: scenario.original != null);
      if (scenario.original != null) json['costPrice'] = scenario.original;
      final initial = MenuItemDto.fromJson(json).toEntity();
      final items = FakeMenuItems()..current = initial;
      await _pump(
        tester,
        await _auth(),
        items,
        FakeMenuGroups(),
        dialog: MenuItemForm(initial: initial),
      );
      final costField = find.byKey(const ValueKey('menu-item-costPrice'));
      expect(
        tester.widget<TextFormField>(costField).controller!.text,
        scenario.original == null ? '' : '12500.50',
      );
      await tester.enterText(
        find.byKey(const ValueKey('menu-item-name')),
        'Changed',
      );
      if (scenario.edited != null) {
        if (scenario.edited!.isEmpty) {
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('menu-item-costPrice-clear')),
          );
          await _tapVisible(tester, find.text('Xóa cấu hình'));
        } else {
          await tester.enterText(costField, scenario.edited!);
        }
      }
      await _tapVisible(tester, find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(
        items.lastUpdate?.costPrice,
        scenario.expected == null ? null : MenuPrice.parse(scenario.expected!),
      );
      expect(items.lastUpdate?.expectedVersion, initial.version);
      if (scenario.edited == '') {
        expect(items.lastUpdate?.costConfigured, false);
      }
      expect(items.writes, hasLength(1));
    });
  }
  testWidgets('create validates optional costPrice and saves decimal cost', (
    tester,
  ) async {
    final items = FakeMenuItems();
    await _pump(
      tester,
      await _auth(),
      items,
      FakeMenuGroups(),
      dialog: const MenuItemForm(),
      permission: 'MENU_CREATE',
    );
    await tester.enterText(find.byKey(const ValueKey('menu-item-name')), 'Tea');
    await tester.enterText(
      find.byKey(const ValueKey('menu-item-baseUnit')),
      'cup',
    );
    await tester.enterText(
      find.byKey(const ValueKey('menu-item-salePrice')),
      '35000.50',
    );
    final field = find.byKey(const ValueKey('menu-item-costPrice'));
    for (final invalid in ['-1', '1.001']) {
      await tester.enterText(field, invalid);
      await _tapVisible(tester, find.text('Tạo món'));
      await tester.pumpAndSettle();
      expect(items.writes, isEmpty);
      expect(tester.widget<TextFormField>(field).controller!.text, invalid);
    }
    await tester.enterText(field, '12500.50');
    await _tapVisible(tester, find.text('Tạo món'));
    await tester.pumpAndSettle();
    expect(items.lastCreate?.costPrice, MenuPrice.parse('12500.50'));
    expect(items.writes, hasLength(1));
  });
  testWidgets('detail uses server sellable and refreshes after group changes', (
    tester,
  ) async {
    final initial = MenuItemDto.fromJson(
      itemJson(sellable: false)
        ..['group'] = {'id': 'g1', 'name': 'Đồ uống', 'active': false},
    ).toEntity();
    final items = FakeMenuItems()..current = initial;
    await _pump(
      tester,
      await _auth(),
      items,
      FakeMenuGroups(),
      dialog: MenuItemDetails(initial: initial),
      permission: 'MENU_VIEW',
    );
    expect(find.text('Nhóm: Đồ uống (ngừng hoạt động)'), findsOneWidget);
    expect(find.text('Chưa thể bán'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MenuItemDetails)),
    );
    items.current = item();
    container.read(menuCatalogEventsProvider).groupsChanged();
    await tester.pumpAndSettle();
    expect(items.detailCalls, 1);
    expect(find.text('Có thể bán'), findsOneWidget);
    expect(find.text('Nhóm: Đồ uống'), findsOneWidget);
  });

  testWidgets('read-only menu shows server sellable and no mutation controls', (
    tester,
  ) async {
    final items = FakeMenuItems()..rows = [item()];
    await _pump(
      tester,
      await _auth(permissions: {'MENU_VIEW'}),
      items,
      FakeMenuGroups(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Thêm món'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Có thể bán'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Có thể bán'), findsOneWidget);
    expect(items.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('initial loading, failure retry and empty results', (
    tester,
  ) async {
    final pending = Completer<Result<MenuPage<MenuItem>>>();
    final items = FakeMenuItems()..onList = (_) => pending.future;
    await _pump(tester, await _auth(), items, FakeMenuGroups());
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.complete(const Error(networkFailure));
    await tester.pumpAndSettle();
    expect(find.text(networkFailure.message), findsOneWidget);
    items.onList = null;
    await _tapVisible(tester, find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa có món ăn.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'missing');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Không có kết quả phù hợp với bộ lọc.'), findsOneWidget);
  });
  testWidgets(
    'mobile screen and keyboard form scroll without overflow; decimal validation',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final items = FakeMenuItems();
      await _pump(tester, await _auth(), items, FakeMenuGroups());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Thêm món'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('menu-item-name')),
        'Tea',
      );
      await tester.enterText(
        find.byKey(const ValueKey('menu-item-baseUnit')),
        'cup',
      );
      await tester.enterText(
        find.byKey(const ValueKey('menu-item-salePrice')),
        '1.001',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Tạo món'));
      await tester.pumpAndSettle();
      expect(items.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const ValueKey('menu-item-salePrice')),
        '0',
      );
      await _tapVisible(tester, find.text('Tạo món'));
      await tester.pumpAndSettle();
      expect(items.lastCreate?.salePrice.minorUnits, 0);
      expect(
        items.lastCreate?.costPrice,
        isNull,
      ); // V37: untouched optional cost is omitted.
      expect(items.writes, hasLength(1));
      expect(find.byType(MenuItemForm), findsNothing);
    },
  );
  testWidgets(
    'edit keeps baseline across refresh and conflict retains draft until explicit replacement',
    (tester) async {
      final items = FakeMenuItems()..current = item(version: 20);
      items.onWrite = () async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'CONCURRENT_MENU_UPDATE',
          message: 'Conflict',
        ),
      );
      await _pump(
        tester,
        await _auth(),
        items,
        FakeMenuGroups(),
        dialog: MenuItemForm(initial: item(version: 4)),
      );
      final name = find.byKey(const ValueKey('menu-item-name'));
      await tester.enterText(name, 'My draft');
      await _tapVisible(tester, find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(items.lastUpdate?.expectedVersion, 4);
      expect(items.detailCalls, 0);
      expect(find.text('My draft'), findsOneWidget);
      expect(find.text('Conflict'), findsOneWidget);
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Lưu thay đổi'),
      );
      expect(save.onPressed, isNull);
      await _tapVisible(tester, find.text('Tải lại dữ liệu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Giữ bản nháp'));
      await tester.pumpAndSettle();
      expect(find.text('My draft'), findsOneWidget);
      expect(items.detailCalls, 0);
      await _tapVisible(tester, find.text('Tải lại dữ liệu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thay thế bản nháp'));
      await tester.pumpAndSettle();
      expect(items.detailCalls, 1);
      expect(find.text(item().name), findsOneWidget);
      items.onWrite = null;
      await tester.enterText(name, 'Replacement');
      await _tapVisible(tester, find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(items.lastUpdate?.expectedVersion, 20);
    },
  );
  testWidgets(
    'server field error clears when its field is edited; submit cannot duplicate',
    (tester) async {
      final items = FakeMenuItems();
      final pending = Completer<Result<MenuItem>>();
      items.onWrite = () => pending.future;
      await _pump(
        tester,
        await _auth(),
        items,
        FakeMenuGroups(),
        dialog: MenuItemForm(initial: item()),
      );
      await tester.enterText(
        find.byKey(const ValueKey('menu-item-name')),
        'New',
      );
      await _tapVisible(tester, find.text('Lưu thay đổi'));
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(items.writes, hasLength(1));
      pending.complete(
        const Error(
          Failure(
            type: FailureType.validation,
            code: 'VALIDATION_ERROR',
            message: 'Invalid',
            fieldErrors: {'name': 'Name taken'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Name taken'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('menu-item-name')),
        'Different',
      );
      await tester.pump();
      expect(find.text('Name taken'), findsNothing);
    },
  );
  testWidgets('token rotation preserves draft, permission loss closes dialog', (
    tester,
  ) async {
    final events = SessionEvents();
    addTearDown(events.dispose);
    final auth = await _auth(events: events);
    await _pump(
      tester,
      auth,
      FakeMenuItems(),
      FakeMenuGroups(),
      dialog: MenuItemForm(initial: item()),
    );
    await tester.enterText(
      find.byKey(const ValueKey('menu-item-name')),
      'Unsaved',
    );
    events.refreshed(
      makeAuthSession(
        permissions: menuPermissions,
        tokens: makeTokens(accessToken: 'new'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unsaved'), findsOneWidget);
    events.refreshed(makeAuthSession(permissions: {'MENU_VIEW'}));
    await tester.pumpAndSettle();
    expect(find.byType(MenuItemForm), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'inactive item disables availability action; delete requires confirmation',
    (tester) async {
      final items = FakeMenuItems()
        ..current = item(active: false)
        ..rows = [item(active: false)];
      await _pump(tester, await _auth(), items, FakeMenuGroups());
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      final disabled = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Bật món để đổi có hàng'),
      );
      expect(disabled.enabled, false);
      await tester.tap(find.text('Xóa món'));
      await tester.pumpAndSettle();
      expect(find.byType(MenuConfirmDialog<MenuItem>), findsOneWidget);
      expect(items.writes, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Xóa món'));
      await tester.pumpAndSettle();
      expect(items.writes.single, ('delete', 9));
    },
  );
  testWidgets(
    'ungroup assignment preserves current selection and sends null explicitly',
    (tester) async {
      final items = FakeMenuItems();
      await _pump(
        tester,
        await _auth(),
        items,
        FakeMenuGroups(),
        dialog: MenuMoveDialog(initial: item(version: 6)),
      );
      expect(find.text('Đồ uống'), findsOneWidget);
      await tester.tap(find.text('Đồ uống'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chưa phân nhóm'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(items.writes.single, ('group', 6));
      expect(items.lastGroup, isNull);
    },
  );
}
