import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/menu/data/dto/ingredient_dto.dart';
import 'package:pos_saas_app/features/menu/data/dto/ingredient_requests.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_requests.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/ingredient_form.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/menu_item_form.dart';
import '../../helpers/auth_fakes.dart';
import 'ingredient_fakes.dart';
import 'menu_fakes.dart';

class _Rig {
  final items = FakeMenuItems();
  final ingredients = FakeIngredients();
}

Future<_Rig> _pump(
  WidgetTester tester, {
  required bool menu,
  bool creating = false,
  bool configured = true,
  bool storedZero = false,
  bool recipeEnabled = false,
  bool recipeFeature = true,
  double width = 800,
  double scale = 1,
  bool keyboard = false,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1;
  if (keyboard) tester.view.viewInsets = const FakeViewPadding(bottom: 280);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final auth = makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(
        makeAuthSession(
          permissions: {...menuPermissions, ...ingredientPermissions},
        ),
      ),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(
        makeEntitlement(
          features: {
            'MENU_MANAGEMENT',
            'INVENTORY_MANAGEMENT',
            if (recipeFeature) 'RECIPE_MANAGEMENT',
          },
        ),
      ),
  );
  await auth.login(
    const LoginCredentials(
      email: 'reference@example.com',
      password: 'password',
    ),
  );
  final rig = _Rig();
  rig.items.current = MenuItemDto.fromJson(
    itemJson(costConfigured: configured, recipeEnabled: recipeEnabled)
      ..['costPrice'] = storedZero ? 0 : 12500,
  ).toEntity();
  rig.ingredients.current = IngredientDto.fromJson(
    ingredientJson(costConfigured: configured)
      ..['costPrice'] = storedZero ? 0 : 250.25,
  ).toEntity();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((_) => auth),
        menuItemRepositoryProvider.overrideWithValue(rig.items),
        menuGroupRepositoryProvider.overrideWithValue(FakeMenuGroups()),
        ingredientRepositoryProvider.overrideWithValue(rig.ingredients),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => menu
                    ? MenuItemForm(initial: creating ? null : rig.items.current)
                    : IngredientForm(
                        initial: creating ? null : rig.ingredients.current,
                      ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return rig;
}

Finder _field(bool menu, String field) =>
    find.byKey(ValueKey('${menu ? 'menu-item' : 'ingredient'}-$field'));
String _submit(bool menu, bool creating) =>
    creating ? (menu ? 'Tạo món' : 'Tạo nguyên liệu') : 'Lưu thay đổi';
Future<void> _tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _fillCreate(WidgetTester tester, bool menu) async {
  await tester.enterText(_field(menu, 'name'), 'Dữ liệu mới');
  await tester.enterText(_field(menu, 'baseUnit'), 'g');
  if (menu) await tester.enterText(_field(menu, 'salePrice'), '50000');
}

Map<String, dynamic> _createBody(_Rig rig, bool menu) => menu
    ? MenuRequests.createItem(rig.items.lastCreate!)
    : IngredientRequests.create(rig.ingredients.lastCreate!);
Map<String, dynamic> _patchBody(_Rig rig, bool menu) => menu
    ? MenuRequests.updateItem(rig.items.lastUpdate!)
    : IngredientRequests.update(rig.ingredients.lastUpdate!);

void main() {
  for (final menu in [true, false]) {
    for (final explicitZero in [false, true]) {
      testWidgets(
        '${menu ? 'menu' : 'ingredient'} create distinguishes untouched price from explicit zero ($explicitZero)',
        (tester) async {
          final rig = await _pump(tester, menu: menu, creating: true);
          expect(
            tester
                .widget<TextFormField>(_field(menu, 'costPrice'))
                .controller!
                .text,
            '',
          );
          expect(find.text('Chưa cấu hình giá vốn'), findsOneWidget);
          await _fillCreate(tester, menu);
          if (menu) {
            final toggle = tester.widget<SwitchListTile>(
              find.byKey(const ValueKey('menu-item-recipeEnabled')),
            );
            expect(toggle.value, false);
            expect(toggle.onChanged, null);
          }
          if (explicitZero) {
            await tester.enterText(_field(menu, 'costPrice'), '0');
          }
          await _tap(tester, find.text(_submit(menu, true)));
          final body = _createBody(rig, menu);
          expect(body.containsKey('costPrice'), explicitZero);
          if (explicitZero) expect(body['costPrice'], 0);
          expect(body.containsKey('costConfigured'), false);
          if (menu) expect(body['recipeEnabled'], false);
          expect(tester.takeException(), null);
        },
      );
    }
    testWidgets(
      '${menu ? 'menu' : 'ingredient'} metadata edit omits both cost fields',
      (tester) async {
        final rig = await _pump(tester, menu: menu);
        await tester.enterText(_field(menu, 'name'), 'Tên mới');
        await _tap(tester, find.text(_submit(menu, false)));
        final body = _patchBody(rig, menu);
        expect(body, {'name': 'Tên mới', 'expectedVersion': menu ? 9 : 4});
        expect(tester.takeException(), null);
      },
    );
    testWidgets(
      '${menu ? 'menu' : 'ingredient'} stored unconfigured zero requires explicit flag-only confirmation',
      (tester) async {
        final rig = await _pump(
          tester,
          menu: menu,
          configured: false,
          storedZero: true,
        );
        expect(find.text('Chưa cấu hình giá vốn'), findsOneWidget);
        expect(
          tester
              .widget<TextFormField>(_field(menu, 'costPrice'))
              .controller!
              .text,
          '',
        );
        await _tap(
          tester,
          find.byKey(
            ValueKey(
              '${menu ? 'menu-item' : 'ingredient'}-costPrice-confirm-zero',
            ),
          ),
        );
        await _tap(tester, find.text(_submit(menu, false)));
        expect(_patchBody(rig, menu), {
          'costConfigured': true,
          'expectedVersion': menu ? 9 : 4,
        });
        expect(tester.takeException(), null);
      },
    );
    testWidgets(
      '${menu ? 'menu' : 'ingredient'} clear asks confirmation and sends false without a numeric placeholder',
      (tester) async {
        final rig = await _pump(tester, menu: menu);
        final clear = find.byKey(
          ValueKey('${menu ? 'menu-item' : 'ingredient'}-costPrice-clear'),
        );
        await _tap(tester, clear);
        expect(find.text('Xóa cấu hình giá vốn?'), findsOneWidget);
        await _tap(tester, find.text('Giữ giá vốn'));
        expect(
          tester
              .widget<TextFormField>(_field(menu, 'costPrice'))
              .controller!
              .text,
          menu ? '12500.00' : '250.25',
        );
        expect(rig.items.lastUpdate, null);
        expect(rig.ingredients.lastUpdate, null);
        await _tap(tester, clear);
        await _tap(tester, find.text('Xóa cấu hình'));
        await _tap(tester, find.text(_submit(menu, false)));
        expect(_patchBody(rig, menu), {
          'costConfigured': false,
          'expectedVersion': menu ? 9 : 4,
        });
        expect(tester.takeException(), null);
      },
    );
    testWidgets(
      '${menu ? 'menu' : 'ingredient'} deleting input text does not silently configure zero',
      (tester) async {
        final rig = await _pump(tester, menu: menu);
        await tester.enterText(_field(menu, 'costPrice'), '');
        await _tap(tester, find.text(_submit(menu, false)));
        expect(
          find.text('Nhập giá hoặc chọn “Xóa cấu hình giá vốn”.'),
          findsOneWidget,
        );
        expect(rig.items.lastUpdate, null);
        expect(rig.ingredients.lastUpdate, null);
        expect(tester.takeException(), null);
      },
    );
    for (final width in [320.0, 600.0, 800.0, 1200.0]) {
      testWidgets(
        '${menu ? 'menu' : 'ingredient'} configured cost form fits width $width, text200 and keyboard',
        (tester) async {
          final rig = await _pump(
            tester,
            menu: menu,
            configured: false,
            storedZero: true,
            width: width,
            scale: 2,
            keyboard: true,
          );
          expect(tester.takeException(), null);
          await _tap(
            tester,
            find.byKey(
              ValueKey(
                '${menu ? 'menu-item' : 'ingredient'}-costPrice-confirm-zero',
              ),
            ),
          );
          expect(tester.takeException(), null);
          await _tap(tester, find.text(_submit(menu, false)));
          expect(_patchBody(rig, menu)['costConfigured'], true);
          expect(tester.takeException(), null);
        },
      );
    }
  }
  testWidgets(
    'menu application can be disabled after recipe package loss using menu update alone',
    (tester) async {
      final rig = await _pump(
        tester,
        menu: true,
        recipeEnabled: true,
        recipeFeature: false,
      );
      final finder = find.byKey(const ValueKey('menu-item-recipeEnabled'));
      final toggle = tester.widget<SwitchListTile>(finder);
      expect(toggle.value, true);
      expect(toggle.onChanged, isNotNull);
      await _tap(tester, finder);
      expect(tester.widget<SwitchListTile>(finder).value, false);
      expect(tester.widget<SwitchListTile>(finder).onChanged, null);
      await _tap(tester, find.text('Lưu thay đổi'));
      expect(_patchBody(rig, true), {
        'recipeEnabled': false,
        'expectedVersion': 9,
      });
      expect(tester.takeException(), null);
    },
  );
  testWidgets('menu application cannot be enabled without recipe feature', (
    tester,
  ) async {
    final rig = await _pump(tester, menu: true, recipeFeature: false);
    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('menu-item-recipeEnabled')),
    );
    expect(toggle.value, false);
    expect(toggle.onChanged, null);
    expect(rig.items.lastUpdate, null);
    expect(tester.takeException(), null);
  });
}
