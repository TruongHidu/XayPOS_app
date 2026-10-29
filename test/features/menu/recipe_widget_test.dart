import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/menu/domain/entities/ingredient.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_price.dart';
import 'package:pos_saas_app/features/menu/presentation/providers/recipe_providers.dart';
import 'package:pos_saas_app/features/menu/presentation/screens/recipe_management_screen.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/recipe_dialogs.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/recipe_form.dart';
import '../../helpers/auth_fakes.dart';
import 'ingredient_fakes.dart';
import 'menu_fakes.dart';
import 'recipe_ui_fakes.dart';

Future<AuthController> _auth({
  Set<String> permissions = recipeUiPermissions,
}) async {
  final auth = makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(
        makeEntitlement(features: {'RECIPE_MANAGEMENT', 'MENU_MANAGEMENT'}),
      ),
  );
  await auth.login(
    const LoginCredentials(email: 'recipe@example.com', password: 'password'),
  );
  return auth;
}

Future<void> _pump(
  WidgetTester tester, {
  required UiRecipes recipes,
  AuthController? auth,
  FakeIngredients? ingredients,
  FakeMenuItems? items,
  Widget? form,
  double width = 1200,
  double scale = 1,
  bool keyboard = false,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => auth!),
        recipeRepositoryProvider.overrideWithValue(recipes),
        ingredientRepositoryProvider.overrideWithValue(
          ingredients ?? FakeIngredients(),
        ),
        menuItemRepositoryProvider.overrideWithValue(items ?? FakeMenuItems()),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: keyboard
                ? const EdgeInsets.only(bottom: 300)
                : EdgeInsets.zero,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: form == null
              ? const RecipeManagementScreen(menuItemId: 'i1')
              : Consumer(
                  builder: (context, ref, _) {
                    // Keep the active controller alive while the standalone form is open.
                    ref.watch(recipeControllerProvider('i1'));
                    return TextButton(
                      onPressed: () => showRecipeDialog<void>(
                        context,
                        ref,
                        permission: 'RECIPE_UPDATE',
                        child: form,
                      ),
                      child: const Text('Open'),
                    );
                  },
                ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (form != null) {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _value(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

Ingredient _ingredient(String id, {String unit = 'g', bool active = true}) =>
    Ingredient(
      id: id,
      sku: id,
      name: 'Hiện tại $id',
      baseUnit: unit,
      description: null,
      costPrice: MenuPrice.zero,
      trackInventory: false,
      active: active,
      version: 1,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  testWidgets(
    'save and use partial failure keeps saved definition and retries only application',
    (tester) async {
      final recipes = UiRecipes()..current = null;
      recipes.onWrite = () async {
        recipes.current = uiRecipe(unit: 'ly');
        return Success(recipes.current!);
      };
      final items = FakeMenuItems()
        ..onWrite = () async => const Error(networkFailure);
      await _pump(
        tester,
        recipes: recipes,
        items: items,
        auth: await _auth(
          permissions: {
            ...recipeUiPermissions,
            'MENU_VIEW',
            'MENU_UPDATE',
            'INGREDIENT_VIEW',
          },
        ),
      );
      await _tap(tester, find.text('Thiết lập công thức'));
      await tester.enterText(find.byKey(const ValueKey('recipe-yield')), '10');
      await _tap(tester, find.byKey(const ValueKey('recipe-add-ingredient')));
      await _tap(
        tester,
        find.byKey(const ValueKey('recipe-pick-ingredient-1')),
      );
      await _tap(tester, find.text('Thêm 1 nguyên liệu'));
      await tester.enterText(
        find.byKey(const ValueKey('recipe-quantity-0')),
        '1200',
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('recipe-submit-and-enable')),
      );
      expect(recipes.creates, hasLength(1));
      expect(items.writes, hasLength(1));
      expect(
        find.descendant(
          of: find.byType(RecipeForm),
          matching: find.textContaining('Đã lưu công thức, chưa bật sử dụng'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('recipe-submit')))
            .onPressed,
        null,
      );
      // The first PATCH may have reached the server despite a lost response.
      items.current = item(version: 12, recipeEnabled: true);
      await _tap(tester, find.text('Kiểm tra và bật sử dụng'));
      expect(recipes.creates, hasLength(1));
      expect(items.writes, hasLength(1));
      expect(find.byKey(const ValueKey('recipe-yield')), findsNothing);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'fresh create rechecks menu and selected ingredient units before saving',
    (tester) async {
      final recipes = UiRecipes()..current = null;
      final items = FakeMenuItems();
      final ingredients = FakeIngredients();
      await _pump(
        tester,
        auth: await _auth(
          permissions: {...recipeUiPermissions, 'MENU_VIEW', 'INGREDIENT_VIEW'},
        ),
        recipes: recipes,
        items: items,
        ingredients: ingredients,
      );
      await _tap(tester, find.text('Thiết lập công thức'));
      await tester.enterText(find.byKey(const ValueKey('recipe-yield')), '10');
      await _tap(tester, find.byKey(const ValueKey('recipe-add-ingredient')));
      await _tap(
        tester,
        find.byKey(const ValueKey('recipe-pick-ingredient-1')),
      );
      await _tap(tester, find.text('Thêm 1 nguyên liệu'));
      await tester.enterText(
        find.byKey(const ValueKey('recipe-quantity-0')),
        '1200',
      );
      items.current = MenuItemDto.fromJson({
        ...itemJson(),
        'baseUnit': 'tô',
      }).toEntity();
      ingredients.current = _ingredient('ingredient-1', unit: 'kg');
      await _tap(tester, find.byKey(const ValueKey('recipe-submit')));
      expect(recipes.creates, isEmpty);
      expect(_value(tester, 'recipe-yield'), '');
      expect(_value(tester, 'recipe-quantity-0'), '');
      expect(find.textContaining('Đơn vị món đã đổi'), findsOneWidget);
      expect(find.textContaining('Đơn vị đã đổi từ g sang kg'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('recipe-yield')),
        '10.000',
      );
      await tester.enterText(
        find.byKey(const ValueKey('recipe-quantity-0')),
        '1.200',
      );
      await _tap(tester, find.byKey(const ValueKey('recipe-submit')));
      expect(recipes.creates, hasLength(1));
      expect(recipes.creates.single.yieldQuantity.toString(), '10');
      expect(
        recipes.creates.single.ingredients.single.quantity.toString(),
        '1.2',
      );
      expect(recipes.versions, isEmpty);
    },
  );

  testWidgets('fresh create without readable current menu unit cannot submit', (
    tester,
  ) async {
    final recipes = UiRecipes()..current = null;
    final items = FakeMenuItems();
    await _pump(tester, auth: await _auth(), recipes: recipes, items: items);
    await _tap(tester, find.text('Thiết lập công thức'));
    expect(
      find.textContaining('Cần quyền xem món và dữ liệu đơn vị món hiện tại'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('recipe-submit')))
          .onPressed,
      isNull,
    );
    expect(items.detailCalls, 0);
    expect(recipes.creates, isEmpty);
  });

  testWidgets(
    'recipe-only reader sees snapshots without catalog reads or write actions',
    (tester) async {
      final items = FakeMenuItems();
      final ingredients = FakeIngredients();
      final recipes = UiRecipes();
      await _pump(
        tester,
        auth: await _auth(permissions: {'RECIPE_VIEW'}),
        recipes: recipes,
        items: items,
        ingredients: ingredients,
      );
      expect(find.text('Snapshot nguyên liệu 0'), findsOneWidget);
      expect(find.text('Phiên bản 7'), findsOneWidget);
      expect(
        find.text('Định lượng bên dưới dùng để tạo ra 10 tô'),
        findsOneWidget,
      );
      expect(items.detailCalls, 0);
      expect(items.queries, isEmpty);
      expect(ingredients.detailCalls, 0);
      expect(ingredients.queries, isEmpty);
      expect(find.text('Tạo phiên bản mới'), findsNothing);
      expect(find.byTooltip('Thao tác công thức'), findsNothing);
      await _tap(tester, find.text('Lịch sử'));
      expect(recipes.historyQueries.single.sortBy, 'recipeVersion');
      expect(recipes.detailCalls, 0);
      await _tap(tester, find.byKey(const ValueKey('recipe-history-r2')));
      expect(recipes.detailCalls, 1);
      expect(find.text('Snapshot nguyên liệu 0'), findsOneWidget);
      expect(ingredients.detailCalls, 0);
      expect(items.detailCalls, 0);
      expect(find.text('Dùng nội dung này tạo phiên bản mới'), findsNothing);
    },
  );

  testWidgets(
    'active edit uses snapshots without ingredient permission and normalized no-op does not write',
    (tester) async {
      final recipes = UiRecipes();
      final ingredients = FakeIngredients();
      await _pump(
        tester,
        auth: await _auth(),
        recipes: recipes,
        ingredients: ingredients,
      );
      await _tap(tester, find.text('Tạo phiên bản mới'));
      expect(_value(tester, 'recipe-quantity-0'), '1200');
      await tester.enterText(
        find.byKey(const ValueKey('recipe-quantity-0')),
        '1200.000',
      );
      await _tap(tester, find.byKey(const ValueKey('recipe-submit')));
      expect(find.text('Công thức chưa có thay đổi thực tế.'), findsOneWidget);
      expect(recipes.versions, isEmpty);
      expect(ingredients.detailCalls, 0);
      expect(ingredients.queries, isEmpty);
      expect(find.textContaining('Cần quyền xem nguyên liệu'), findsOneWidget);
    },
  );

  testWidgets(
    'conflict preserves draft and does not retry; reload replacement requires confirmation',
    (tester) async {
      final recipes = UiRecipes()
        ..onWrite = () async => const Error(
          Failure(
            type: FailureType.conflict,
            code: 'CONCURRENT_RECIPE_UPDATE',
            message: 'Có người vừa đổi công thức.',
          ),
        );
      await _pump(tester, auth: await _auth(), recipes: recipes);
      await _tap(tester, find.text('Tạo phiên bản mới'));
      await tester.enterText(
        find.byKey(const ValueKey('recipe-quantity-0')),
        '1300.125',
      );
      await _tap(tester, find.byKey(const ValueKey('recipe-submit')));
      expect(_value(tester, 'recipe-quantity-0'), '1300.125');
      expect(recipes.versions.single.$1, 'r7');
      expect(recipes.versions.single.$2.expectedVersion, 42);
      expect(recipes.versions.single.$2.expectedVersion, isNot(7));
      await _tap(tester, find.text('Tải lại bản nháp'));
      expect(find.text('Thay bản nháp'), findsOneWidget);
      await _tap(tester, find.text('Giữ bản nháp'));
      expect(_value(tester, 'recipe-quantity-0'), '1300.125');
      expect(recipes.versions, hasLength(1));
      await _tap(tester, find.text('Đóng'));
      expect(find.text('Bỏ bản nháp'), findsOneWidget);
      await _tap(tester, find.text('Giữ bản nháp'));
      expect(_value(tester, 'recipe-quantity-0'), '1300.125');
    },
  );

  testWidgets(
    'server row errors stay attached to stable draft rows after removing a prior row',
    (tester) async {
      final recipes = UiRecipes()
        ..current = uiRecipe(count: 2)
        ..onWrite = () async => const Error(
          Failure(
            type: FailureType.validation,
            message: 'Kiểm tra lượng dùng',
            fieldErrors: {'ingredients[1].quantity': 'Lỗi dòng thứ hai'},
          ),
        );
      await _pump(tester, auth: await _auth(), recipes: recipes);
      await _tap(tester, find.text('Tạo phiên bản mới'));
      await tester.enterText(
        find.byKey(const ValueKey('recipe-quantity-0')),
        '1300',
      );
      await _tap(tester, find.byKey(const ValueKey('recipe-submit')));
      expect(find.text('Lỗi dòng thứ hai'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('recipe-remove-0')));
      expect(_value(tester, 'recipe-quantity-1'), '1200');
      expect(find.text('Lỗi dòng thứ hai'), findsOneWidget);
      expect(find.byKey(const ValueKey('recipe-quantity-0')), findsNothing);
    },
  );

  testWidgets(
    'picker selection survives search and pages, accepts trackInventory false and keeps draft',
    (tester) async {
      final ingredients = FakeIngredients()
        ..onList = (query) async => Success(
          page(
            query.page == 0 ? [_ingredient('second')] : [_ingredient('third')],
            index: query.page,
            pages: 2,
          ),
        );
      final recipes = UiRecipes();
      await _pump(
        tester,
        auth: await _auth(
          permissions: {...recipeUiPermissions, 'INGREDIENT_VIEW'},
        ),
        recipes: recipes,
        ingredients: ingredients,
      );
      await _tap(tester, find.text('Tạo phiên bản mới'));
      await tester.enterText(
        find.byKey(const ValueKey('recipe-quantity-0')),
        '1500.001',
      );
      await _tap(tester, find.byKey(const ValueKey('recipe-add-ingredient')));
      await _tap(tester, find.byKey(const ValueKey('recipe-pick-second')));
      await tester.enterText(
        find.byKey(const ValueKey('recipe-picker-search')),
        'tìm',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await _tap(tester, find.byTooltip('Trang sau'));
      await _tap(tester, find.byKey(const ValueKey('recipe-pick-third')));
      await _tap(tester, find.text('Thêm 2 nguyên liệu'));
      expect(_value(tester, 'recipe-quantity-0'), '1500.001');
      expect(find.text('Hiện tại second'), findsOneWidget);
      expect(find.text('Hiện tại third'), findsOneWidget);
      expect(
        ingredients.queries.every(
          (query) => query.active == true && query.trackInventory == null,
        ),
        isTrue,
      );
    },
  );

  testWidgets(
    'history reuse uses current active lock baseline and requires explicit units reentry',
    (tester) async {
      final recipes = UiRecipes();
      final ingredients = FakeIngredients()
        ..onDetail = () async =>
            Success(_ingredient('ingredient-1', unit: 'kg'));
      final items =
          FakeMenuItems(); // current item unit ly differs from historical tô
      await _pump(
        tester,
        auth: await _auth(
          permissions: {...recipeUiPermissions, 'INGREDIENT_VIEW', 'MENU_VIEW'},
        ),
        recipes: recipes,
        ingredients: ingredients,
        items: items,
      );
      await _tap(tester, find.text('Lịch sử'));
      await _tap(tester, find.byKey(const ValueKey('recipe-history-r2')));
      expect(ingredients.detailCalls, 0);
      await _tap(tester, find.text('Dùng nội dung này tạo phiên bản mới'));
      expect(_value(tester, 'recipe-yield'), '');
      expect(_value(tester, 'recipe-quantity-0'), '');
      expect(find.textContaining('Đơn vị đã đổi từ g sang kg'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('recipe-yield')), '12');
      await tester.enterText(
        find.byKey(const ValueKey('recipe-quantity-0')),
        '1.25',
      );
      await _tap(tester, find.byKey(const ValueKey('recipe-submit')));
      expect(recipes.versions.single.$1, 'r7');
      expect(recipes.versions.single.$2.expectedVersion, 42);
      expect(recipes.creates, isEmpty);
    },
  );

  testWidgets(
    'unverifiable historical content remains visible but cannot be submitted',
    (tester) async {
      final recipes = UiRecipes();
      final ingredients = FakeIngredients();
      final items = FakeMenuItems();
      await _pump(
        tester,
        auth: await _auth(),
        recipes: recipes,
        ingredients: ingredients,
        items: items,
      );
      await _tap(tester, find.text('Lịch sử'));
      await _tap(tester, find.byKey(const ValueKey('recipe-history-r2')));
      await _tap(tester, find.text('Dùng nội dung này tạo phiên bản mới'));
      expect(
        find.textContaining('Cần quyền xem món và xem nguyên liệu'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('recipe-submit')))
            .onPressed,
        isNull,
      );
      expect(_value(tester, 'recipe-quantity-0'), '1200');
      expect(ingredients.detailCalls, 0);
      expect(items.detailCalls, 0);
    },
  );

  testWidgets(
    'inactive historical ingredient blocks saving until explicitly removed or replaced',
    (tester) async {
      final recipes = UiRecipes();
      final ingredients = FakeIngredients()
        ..onDetail = () async =>
            Success(_ingredient('ingredient-1', active: false));
      await _pump(
        tester,
        auth: await _auth(
          permissions: {...recipeUiPermissions, 'INGREDIENT_VIEW', 'MENU_VIEW'},
        ),
        recipes: recipes,
        ingredients: ingredients,
      );
      await _tap(tester, find.text('Lịch sử'));
      await _tap(tester, find.byKey(const ValueKey('recipe-history-r2')));
      await _tap(tester, find.text('Dùng nội dung này tạo phiên bản mới'));
      await tester.enterText(find.byKey(const ValueKey('recipe-yield')), '12');
      await _tap(tester, find.byKey(const ValueKey('recipe-submit')));
      expect(
        find.textContaining('Nguyên liệu không còn hoạt động'),
        findsWidgets,
      );
      expect(recipes.versions, isEmpty);
    },
  );

  testWidgets(
    'loading submit disables duplicates and network uncertainty requires an explicit check',
    (tester) async {
      final completion = Completer<Result<Never>>();
      final recipes = UiRecipes()..onWrite = () => completion.future;
      await _pump(tester, auth: await _auth(), recipes: recipes);
      await _tap(tester, find.text('Tạo phiên bản mới'));
      await tester.enterText(
        find.byKey(const ValueKey('recipe-quantity-0')),
        '1300',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('recipe-submit')));
      await tester.tap(find.byKey(const ValueKey('recipe-submit')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('recipe-submit')))
            .onPressed,
        isNull,
      );
      expect(recipes.versions, hasLength(1));
      completion.complete(
        const Error(Failure(type: FailureType.network, message: 'Mất mạng')),
      );
      await tester.pumpAndSettle();
      expect(_value(tester, 'recipe-quantity-0'), '1300');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('recipe-submit')))
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('Chưa xác định công thức đã được lưu'),
        findsOneWidget,
      );
    },
  );

  for (final width in [320.0, 800.0, 1200.0]) {
    testWidgets(
      'recipe screen and 100-row form fit width $width at 200 percent with keyboard',
      (tester) async {
        final recipes = UiRecipes()..current = uiRecipe(count: 100);
        await _pump(
          tester,
          auth: await _auth(),
          recipes: recipes,
          width: width,
          scale: 2,
          keyboard: true,
        );
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('Tạo phiên bản mới'));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('recipe-quantity-99')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('recipe-quantity-99')),
          '12.345',
        );
        expect(_value(tester, 'recipe-quantity-99'), '12.345');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
