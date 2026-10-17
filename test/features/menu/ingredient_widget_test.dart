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
import 'package:pos_saas_app/features/menu/data/dto/ingredient_requests.dart';
import 'package:pos_saas_app/features/menu/domain/entities/ingredient.dart';
import 'package:pos_saas_app/features/menu/domain/entities/item_type.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_price.dart';
import 'package:pos_saas_app/features/menu/presentation/screens/menu_management_screen.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/catalog_create_dialog.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/ingredient_details.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/ingredient_dialogs.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/ingredient_form.dart';
import '../../helpers/auth_fakes.dart';
import 'ingredient_fakes.dart';
import 'menu_fakes.dart';

Future<AuthController> _auth({
  bool both = false,
  bool readOnly = false,
  SessionEvents? events,
}) async {
  final auth = makeController(
    sessionEvents: events,
    authRepository: FakeAuthRepository()
      ..loginResult = Success(
        makeAuthSession(
          permissions: {
            if (readOnly) 'INGREDIENT_VIEW' else ...ingredientPermissions,
            if (both) ...menuPermissions,
          },
        ),
      ),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(
        makeEntitlement(
          features: {'RECIPE_MANAGEMENT', if (both) 'MENU_MANAGEMENT'},
        ),
      ),
  );
  await auth.login(
    const LoginCredentials(
      email: 'ingredient@example.com',
      password: 'password',
    ),
  );
  return auth;
}

Future<void> _pump(
  WidgetTester tester, {
  required AuthController auth,
  required FakeIngredients ingredients,
  FakeMenuItems? items,
  FakeMenuGroups? groups,
  Widget? dialog,
  String permission = 'INGREDIENT_UPDATE',
  bool catalog = false,
  double width = 1200,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth),
        ingredientRepositoryProvider.overrideWithValue(ingredients),
        menuItemRepositoryProvider.overrideWithValue(items ?? FakeMenuItems()),
        menuGroupRepositoryProvider.overrideWithValue(
          groups ?? FakeMenuGroups(),
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: dialog == null && !catalog
              ? const MenuManagementScreen()
              : Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: () {
                      if (catalog) {
                        showCatalogCreateDialog(
                          context,
                          ref,
                          defaultType: ItemType.ingredient,
                        );
                      } else {
                        showIngredientDialog<void>(
                          context,
                          ref,
                          permission: permission,
                          child: dialog!,
                        );
                      }
                    },
                    child: const Text('Open'),
                  ),
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (dialog != null || catalog) {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}

Finder _field(String name) => find.byKey(ValueKey('ingredient-$name'));
String _value(WidgetTester tester, Finder field) =>
    tester.widget<TextFormField>(field).controller!.text;
Future<void> _tap(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

void main() {
  testWidgets('ingredient-only user opens workspace without menu requests', (
    tester,
  ) async {
    final items = FakeMenuItems();
    final groups = FakeMenuGroups();
    await _pump(
      tester,
      auth: await _auth(),
      ingredients: FakeIngredients(),
      items: items,
      groups: groups,
    );
    expect(find.text('Quản lý nguyên liệu'), findsOneWidget);
    expect(find.text('Thịt bò'), findsOneWidget);
    expect(items.queries, isEmpty);
    expect(groups.queries, isEmpty);
    expect(find.text('Món bán'), findsNothing);
    await _tap(tester, find.text('Thêm nguyên liệu'));
    await tester.pumpAndSettle();
    expect(_field('name'), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-item-salePrice')), findsNothing);
    expect(find.byKey(const ValueKey('ingredient-active')), findsOneWidget);
  });

  testWidgets(
    'switching item types retains separate drafts and creates only ingredient',
    (tester) async {
      final ingredients = FakeIngredients();
      final items = FakeMenuItems();
      await _pump(
        tester,
        auth: await _auth(both: true),
        ingredients: ingredients,
        items: items,
        catalog: true,
      );
      expect(items.queries, isEmpty);
      await tester.enterText(_field('name'), 'Bò Úc');
      await tester.enterText(_field('baseUnit'), 'kg');
      await tester.enterText(_field('sku'), ' nl-bo-uc ');
      await _tap(tester, find.byKey(const ValueKey('create-type-MENU_ITEM')));
      await tester.pumpAndSettle();
      final menuName = find.byKey(const ValueKey('menu-item-name'));
      await tester.enterText(menuName, 'Trà đào mới');
      await _tap(tester, find.byKey(const ValueKey('create-type-INGREDIENT')));
      expect(_value(tester, _field('name')), 'Bò Úc');
      await _tap(tester, find.byKey(const ValueKey('create-type-MENU_ITEM')));
      expect(_value(tester, menuName), 'Trà đào mới');
      await _tap(tester, find.byKey(const ValueKey('create-type-INGREDIENT')));
      await _tap(tester, find.text('Tạo nguyên liệu'));
      await tester.pumpAndSettle();
      expect(ingredients.lastCreate!.name, 'Bò Úc');
      expect(IngredientRequests.create(ingredients.lastCreate!), {
        'name': 'Bò Úc',
        'baseUnit': 'kg',
        'sku': 'NL-BO-UC',
        'costPrice': 0,
        'trackInventory': false,
        'active': true,
      });
      expect(items.lastCreate, isNull);
      expect(find.byType(IngredientForm), findsNothing);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(_value(tester, _field('name')), '');
    },
  );

  testWidgets('menu item remains creatable after visiting ingredient draft', (
    tester,
  ) async {
    final ingredients = FakeIngredients();
    final items = FakeMenuItems();
    await _pump(
      tester,
      auth: await _auth(both: true),
      ingredients: ingredients,
      items: items,
      catalog: true,
    );
    await tester.enterText(_field('name'), 'Bản nháp nguyên liệu');
    await _tap(tester, find.byKey(const ValueKey('create-type-MENU_ITEM')));
    await tester.pumpAndSettle();
    for (final entry in {
      'name': 'Trà đào',
      'baseUnit': 'ly',
      'salePrice': '35000.50',
    }.entries) {
      await tester.enterText(
        find.byKey(ValueKey('menu-item-${entry.key}')),
        entry.value,
      );
    }
    await _tap(tester, find.text('Tạo món'));
    await tester.pumpAndSettle();
    expect(items.lastCreate!.salePrice, MenuPrice.parse('35000.50'));
    expect(ingredients.writes, isEmpty);
  });

  testWidgets('type switching and double submit are disabled during creation', (
    tester,
  ) async {
    final pending = Completer<Result<Ingredient>>();
    final ingredients = FakeIngredients()..onWrite = () => pending.future;
    await _pump(
      tester,
      auth: await _auth(both: true),
      ingredients: ingredients,
      catalog: true,
    );
    await tester.enterText(_field('name'), 'Bò');
    await tester.enterText(_field('baseUnit'), 'g');
    await _tap(tester, find.text('Tạo nguyên liệu'));
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('create-type-MENU_ITEM')),
          )
          .onSelected,
      isNull,
    );
    expect(ingredients.writes.length, 1);
    pending.complete(Success(ingredient()));
    await tester.pumpAndSettle();
  });

  for (final clearCost in [false, true]) {
    testWidgets(
      'ingredient edit omits unchanged price or explicitly resets to zero: $clearCost',
      (tester) async {
        final ingredients = FakeIngredients();
        await _pump(
          tester,
          auth: await _auth(),
          ingredients: ingredients,
          dialog: IngredientForm(initial: ingredients.current),
        );
        expect(find.byKey(const ValueKey('ingredient-active')), findsNothing);
        expect(
          find.byKey(const ValueKey('create-type-MENU_ITEM')),
          findsNothing,
        );
        await tester.enterText(_field('name'), 'Tên mới');
        await tester.enterText(_field('sku'), '');
        await tester.enterText(_field('description'), '');
        if (clearCost) await tester.enterText(_field('costPrice'), '');
        await _tap(tester, find.text('Lưu thay đổi'));
        await tester.pumpAndSettle();
        final body = IngredientRequests.update(ingredients.lastUpdate!);
        expect(body['expectedVersion'], 4);
        expect(body['sku'], '');
        expect(body['description'], '');
        expect(body.containsKey('active'), isFalse);
        expect(body.containsKey('costPrice'), clearCost);
        if (clearCost) expect(body['costPrice'], 0);
      },
    );
  }

  testWidgets('SKU collision stays on form and attaches a field error', (
    tester,
  ) async {
    final ingredients = FakeIngredients()
      ..onWrite = () async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'SKU_EXISTS',
          message: 'SKU đã được sử dụng',
        ),
      );
    await _pump(
      tester,
      auth: await _auth(),
      ingredients: ingredients,
      dialog: const IngredientForm(),
      permission: 'INGREDIENT_CREATE',
    );
    await tester.enterText(_field('name'), 'Bò');
    await tester.enterText(_field('baseUnit'), 'g');
    await tester.enterText(_field('sku'), 'duplicate');
    await _tap(tester, find.text('Tạo nguyên liệu'));
    await tester.pumpAndSettle();
    expect(_value(tester, _field('sku')), 'duplicate');
    expect(
      tester.widget<TextFormField>(_field('sku')).forceErrorText,
      contains('SKU'),
    );
    expect(ingredients.writes.length, 1);
  });

  testWidgets(
    'version conflict preserves draft until explicit reload gets a new baseline',
    (tester) async {
      final ingredients = FakeIngredients()
        ..onWrite = () async => const Error(
          Failure(
            type: FailureType.conflict,
            code: 'CONCURRENT_INGREDIENT_UPDATE',
            message: 'Dữ liệu đã thay đổi',
          ),
        );
      await _pump(
        tester,
        auth: await _auth(),
        ingredients: ingredients,
        dialog: IngredientForm(initial: ingredients.current),
      );
      await tester.enterText(_field('name'), 'Bản nháp');
      await _tap(tester, find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(_value(tester, _field('name')), 'Bản nháp');
      expect(ingredients.writes.length, 1);
      ingredients.current = ingredient(version: 8, name: 'Dữ liệu máy chủ');
      await _tap(tester, find.text('Tải lại dữ liệu'));
      await tester.pumpAndSettle();
      expect(_value(tester, _field('name')), 'Bản nháp');
      await _tap(tester, find.text('Thay thế bản nháp'));
      await tester.pumpAndSettle();
      expect(_value(tester, _field('name')), 'Dữ liệu máy chủ');
      ingredients.onWrite = null;
      await tester.enterText(_field('name'), 'Sửa sau tải lại');
      await _tap(tester, find.text('Lưu thay đổi'));
      await tester.pumpAndSettle();
      expect(ingredients.lastUpdate!.expectedVersion, 8);
    },
  );

  for (final deleting in [false, true]) {
    testWidgets(
      'ingredient ${deleting ? 'delete' : 'status'} requires confirmation and uses baseline version',
      (tester) async {
        final ingredients = FakeIngredients();
        await _pump(tester, auth: await _auth(), ingredients: ingredients);
        await _tap(tester, find.byTooltip('Thao tác nguyên liệu'));
        await tester.pumpAndSettle();
        await _tap(
          tester,
          find.text(deleting ? 'Xóa nguyên liệu' : 'Ngừng sử dụng'),
        );
        await tester.pumpAndSettle();
        expect(ingredients.writes, isEmpty);
        expect(find.byType(IngredientConfirmDialog), findsOneWidget);
        if (deleting) ingredients.rows = [];
        await _tap(
          tester,
          find.widgetWithText(
            FilledButton,
            deleting ? 'Xóa nguyên liệu' : 'Xác nhận',
          ),
        );
        await tester.pumpAndSettle();
        expect(ingredients.writes, [(deleting ? 'delete' : 'status', 4)]);
        expect(find.byType(IngredientConfirmDialog), findsNothing);
        if (deleting) expect(find.text('Thịt bò'), findsNothing);
      },
    );
  }

  testWidgets('read-only user sees details without write actions', (
    tester,
  ) async {
    final ingredients = FakeIngredients();
    await _pump(
      tester,
      auth: await _auth(readOnly: true),
      ingredients: ingredients,
    );
    expect(find.text('Thêm nguyên liệu'), findsNothing);
    await _tap(tester, find.byTooltip('Thao tác nguyên liệu'));
    await tester.pumpAndSettle();
    expect(find.text('Chi tiết'), findsOneWidget);
    expect(find.text('Sửa thông tin'), findsNothing);
    expect(find.text('Xóa nguyên liệu'), findsNothing);
    expect(ingredients.writes, isEmpty);
  });

  testWidgets(
    'scope change closes both drafts and ignores a pending mutation result',
    (tester) async {
      final events = SessionEvents();
      addTearDown(events.dispose);
      final pending = Completer<Result<Ingredient>>();
      final ingredients = FakeIngredients()..onWrite = () => pending.future;
      await _pump(
        tester,
        auth: await _auth(both: true, events: events),
        ingredients: ingredients,
        catalog: true,
      );
      await tester.enterText(_field('name'), 'Bản nháp cũ');
      await tester.enterText(_field('baseUnit'), 'g');
      await _tap(tester, find.text('Tạo nguyên liệu'));
      events.refreshed(
        makeAuthSession(
          restaurantId: 'new-tenant',
          permissions: {...menuPermissions, ...ingredientPermissions},
        ),
      );
      await tester.pump();
      pending.complete(Success(ingredient()));
      await tester.pumpAndSettle();
      expect(find.byType(IngredientForm), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 800.0, 1200.0]) {
    testWidgets(
      'ingredient list, create/edit/details fit width $width at 200% text size',
      (tester) async {
        final ingredients = FakeIngredients();
        await _pump(
          tester,
          auth: await _auth(both: true),
          ingredients: ingredients,
          width: width,
          scale: 2,
        );
        await _tap(tester, find.byKey(const ValueKey('menu-tab-ingredients')));
        await tester.pumpAndSettle();
        // Build the lazy list content below the header too.
        await tester.scrollUntilVisible(
          find.text('Thịt bò'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Thịt bò'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.scrollUntilVisible(
          find.text('Thêm nguyên liệu'),
          -300,
          scrollable: find.byType(Scrollable).first,
        );
        await _tap(tester, find.text('Thêm nguyên liệu'));
        await tester.pumpAndSettle();
        await tester.enterText(_field('name'), 'Bò');
        await _tap(tester, find.byKey(const ValueKey('create-type-MENU_ITEM')));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('Đóng').last);
        await tester.pumpAndSettle();
        tester.view.resetViewInsets();

        await tester.pumpWidget(const SizedBox.shrink());
        await _pump(
          tester,
          auth: await _auth(),
          ingredients: ingredients,
          width: width,
          scale: 2,
          dialog: IngredientForm(initial: ingredient()),
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('Đóng').last);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
        await _pump(
          tester,
          auth: await _auth(),
          ingredients: ingredients,
          width: width,
          scale: 2,
          dialog: IngredientDetailsDialog(initial: ingredient()),
          permission: 'INGREDIENT_VIEW',
        );
        expect(find.text('Giá vốn: 250.25 / g'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
