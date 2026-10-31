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
import 'package:pos_saas_app/features/menu/domain/entities/menu_query.dart';
import 'package:pos_saas_app/features/menu/presentation/screens/menu_management_screen.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/menu_actions.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/menu_dialogs.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/menu_filter_panel.dart';
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
    expect(find.text('Đồ uống (ngừng hoạt động)'), findsOneWidget);
    expect(find.text('Chưa thể bán'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MenuItemDetails)),
    );
    items.current = item();
    container.read(menuCatalogEventsProvider).groupsChanged();
    await tester.pumpAndSettle();
    expect(items.detailCalls, 1);
    expect(find.text('Có thể bán'), findsOneWidget);
    expect(find.text('Đồ uống'), findsOneWidget);
  });

  testWidgets('tapping a card opens every item detail', (tester) async {
    final row = MenuItemDto.fromJson(
      itemJson(costConfigured: true, recipeEnabled: true)
        ..['costPrice'] = 12500
        ..['description'] = 'Trà ủ lạnh',
    ).toEntity();
    final items = FakeMenuItems()
      ..rows = [row]
      ..current = row;
    await _pump(tester, await _auth(), items, FakeMenuGroups());
    await tester.pumpAndSettle();
    expect(find.textContaining('35.000,50 đ'), findsOneWidget);
    expect(find.text('TEA'), findsNothing);

    await tester.tap(find.text(row.name));
    await tester.pumpAndSettle();
    final details = find.byType(MenuItemDetails);
    expect(details, findsOneWidget);
    for (final text in [
      '35.000,50 đ / ly',
      '12.500 đ / ly',
      'Trà ủ lạnh',
      'TEA',
      'Đồ uống',
      'ly',
      menuDate(row.createdAt),
      'Sử dụng công thức',
      'Có thể bán',
      'Đang kinh doanh',
      'Còn hàng',
    ]) {
      expect(
        find.descendant(of: details, matching: find.text(text)),
        findsWidgets,
        reason: text,
      );
    }
    expect(tester.takeException(), isNull);
  });

  // ── Endless list ──
  MenuItem row(int index) => MenuItemDto.fromJson(
    itemJson()
      ..['id'] = 'i$index'
      ..['name'] = 'Món $index',
  ).toEntity();
  List<MenuItem> rowsOf(int page) => [
    for (var i = 0; i < 12; i++) row(page * 12 + i),
  ];

  Future<FakeMenuItems> pumpList(
    WidgetTester tester, {
    int pages = 3,
    Future<Result<MenuPage<MenuItem>>> Function(MenuQuery)? onList,
  }) async {
    final items = FakeMenuItems()
      ..onList =
          onList ??
          ((q) async =>
              Success(page(rowsOf(q.page), index: q.page, pages: pages)));
    await _pump(tester, await _auth(), items, FakeMenuGroups());
    await tester.pumpAndSettle();
    return items;
  }

  Future<void> scrollToEnd(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -6000));
    await tester.pumpAndSettle();
  }

  testWidgets('scrolling appends pages until the end, without paging UI', (
    tester,
  ) async {
    final items = await pumpList(tester);
    expect(find.byTooltip('Trang sau'), findsNothing);
    expect(find.text('Mỗi trang'), findsNothing);
    expect(items.queries.map((q) => q.page), [0]);

    await scrollToEnd(tester);
    await scrollToEnd(tester);
    await scrollToEnd(tester);
    expect(items.queries.map((q) => q.page), [0, 1, 2]);
    expect(find.textContaining('Đã hiển thị tất cả'), findsOneWidget);
    expect(find.text('Món 35'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a refresh keeps every page already scrolled', (tester) async {
    final items = await pumpList(tester);
    await scrollToEnd(tester);
    expect(items.queries.map((q) => q.page), [0, 1]);
    final controller = ProviderScope.containerOf(
      tester.element(find.byType(MenuManagementScreen)),
    ).read(menuItemControllerProvider);
    items.queries.clear();
    await controller.load();
    await tester.pump();
    expect(items.queries.map((q) => q.page), [0, 1]);
    expect(controller.state.rows, hasLength(24));
    expect(controller.state.query.page, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('failed page keeps rows and retries from the footer', (
    tester,
  ) async {
    var fail = true;
    final items = await pumpList(
      tester,
      onList: (q) async => q.page == 1 && fail
          ? const Error(networkFailure)
          : Success(page(rowsOf(q.page), index: q.page, pages: 2)),
    );
    await scrollToEnd(tester);
    expect(find.text(networkFailure.message), findsOneWidget);
    expect(find.text('Món 0'), findsWidgets);
    fail = false;
    await _tapVisible(tester, find.text('Thử lại'));
    await tester.pumpAndSettle();
    expect(items.queries.map((q) => q.page), [0, 1, 1]);
    expect(find.text(networkFailure.message), findsNothing);
    await scrollToEnd(tester);
    expect(find.textContaining('Đã hiển thị tất cả'), findsOneWidget);
  });

  testWidgets('pull to refresh reloads the list', (tester) async {
    final items = await pumpList(tester, pages: 1);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(items.queries.map((q) => q.page), [0, 0]);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 412.0, 900.0]) {
    testWidgets('cards and details fit width $width at large text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final row = MenuItemDto.fromJson(
        itemJson(sellable: false, active: false)
          ..['name'] =
              'Trà sữa trân châu hoàng kim phô mai tươi cỡ lớn đặc biệt',
      ).toEntity();
      final items = FakeMenuItems()
        ..rows = [row, row]
        ..current = row;
      await _pump(tester, await _auth(), items, FakeMenuGroups());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(row.name).first);
      await tester.pumpAndSettle();
      expect(find.byType(MenuItemDetails), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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
  testWidgets('app bar filter overlay follows the tab and filters items', (
    tester,
  ) async {
    final items = FakeMenuItems()..rows = [item()];
    final auth = await _auth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          menuItemRepositoryProvider.overrideWithValue(items),
          menuGroupRepositoryProvider.overrideWithValue(FakeMenuGroups()),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: const [MenuFilterAction()]),
            body: const MenuManagementScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tất cả tình trạng'), findsNothing);

    await tester.tap(find.byTooltip('Bộ lọc'));
    await tester.pumpAndSettle();
    expect(find.text('Bộ lọc món bán'), findsOneWidget);
    await tester.tap(find.text('Tất cả tình trạng'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hết hàng').last);
    await tester.pumpAndSettle();
    expect(
      items.queries.last.availabilityStatus,
      AvailabilityStatus.outOfStock,
    );
    await tester.tap(find.text('Xong'));
    await tester.pumpAndSettle();
    expect(find.text('Bộ lọc món bán'), findsNothing);
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('menu-tab-menuGroups')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Bộ lọc'));
    await tester.pumpAndSettle();
    expect(find.text('Bộ lọc nhóm món'), findsOneWidget);
    expect(find.text('Tất cả tình trạng'), findsNothing);
    expect(tester.takeException(), isNull);
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
      await tester.tap(find.byTooltip('Thêm mới'));
      await tester.pumpAndSettle();
      expect(find.text('Thêm nhóm món'), findsOneWidget);
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
