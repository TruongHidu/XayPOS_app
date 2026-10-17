import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/app/router/app_routes.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/auth/presentation/controllers/auth_controller.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_page.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_amount.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_query.dart';
import 'package:pos_saas_app/features/menu/domain/repositories/recipe_repository.dart';
import 'package:pos_saas_app/features/menu/presentation/providers/recipe_providers.dart';
import 'package:pos_saas_app/features/menu/presentation/screens/recipe_management_screen.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/ingredient_dialogs.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/ingredient_form.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/menu_dialogs.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/menu_item_form.dart';
import '../../helpers/auth_fakes.dart';
import 'ingredient_fakes.dart';
import 'menu_fakes.dart';

Recipe _recipe() => Recipe(
  id: 'recipe-1',
  menuItemId: 'i1',
  recipeVersion: 3,
  yieldQuantity: RecipeQuantity.parse('10'),
  yieldUnit: 'tô',
  active: true,
  ingredients: [
    RecipeIngredient(
      id: 'line-1',
      ingredientId: 'ingredient-1',
      sku: 'NL-OLD',
      name: 'Tên nguyên liệu lịch sử',
      unit: 'g',
      quantity: RecipeQuantity.parse('1200'),
      wastePercent: RecipeWastePercent.zero,
    ),
  ],
  version: 7,
  createdAt: DateTime.utc(2026, 10, 16),
  updatedAt: DateTime.utc(2026, 10, 16),
);

class _RecipeRepository implements RecipeRepository {
  int activeCalls = 0, historyCalls = 0, detailCalls = 0, writes = 0;
  @override
  Future<Result<Recipe>> active(String menuItemId) async {
    activeCalls++;
    return Success(_recipe());
  }

  @override
  Future<Result<MenuPage<RecipeSummary>>> history(
    String menuItemId,
    RecipeQuery query,
  ) async {
    historyCalls++;
    return Success(
      MenuPage(
        content: const [],
        page: query.page,
        size: query.size,
        totalElements: 0,
        totalPages: 0,
      ),
    );
  }

  @override
  Future<Result<Recipe>> detail(String menuItemId, String recipeId) async {
    detailCalls++;
    return Success(_recipe());
  }

  @override
  Future<Result<Recipe>> create(String menuItemId, RecipeInput input) async {
    writes++;
    return Success(_recipe());
  }

  @override
  Future<Result<Recipe>> createVersion(
    String menuItemId,
    String activeRecipeId,
    CreateRecipeVersionInput input,
  ) async {
    writes++;
    return Success(_recipe());
  }

  @override
  Future<Result<void>> deactivate(
    String menuItemId,
    String recipeId,
    int expectedVersion,
  ) async {
    writes++;
    return const Success(null);
  }
}

Future<AuthController> _auth({
  required Set<String> permissions,
  required Set<String> features,
}) async {
  final auth = makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: features)),
  );
  await auth.login(
    const LoginCredentials(email: 'recipe@example.com', password: 'password'),
  );
  return auth;
}

Failure _guardFailure(String code) => ApiErrorMapper.fromException(
  DioException(
    requestOptions: RequestOptions(path: '/menu'),
    response: Response(
      requestOptions: RequestOptions(path: '/menu'),
      statusCode: 409,
      data: {
        'code': code,
        'message': 'raw backend',
        'fieldErrors': <String, String>{},
      },
    ),
    type: DioExceptionType.badResponse,
  ),
);

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'recipe permission and feature remain independent from menu and inventory',
    () {
      for (final role in UserRole.values) {
        final session = makeAppSession(
          role: role,
          permissions: {'RECIPE_VIEW'},
          features: {'RECIPE_MANAGEMENT'},
        );
        final restaurantRole = const {
          UserRole.owner,
          UserRole.manager,
          UserRole.waiter,
          UserRole.kitchen,
        }.contains(role);
        expect(AccessPolicy.canRecipe(session, 'RECIPE_VIEW'), restaurantRole);
        expect(AccessPolicy.canRecipe(session, 'RECIPE_UPDATE'), isFalse);
        expect(AccessPolicy.canMenuWorkspace(session), isFalse);
        expect(
          AccessPolicy.canOpenRoute(session, AppRoutes.recipeFor('i1')),
          restaurantRole,
        );
        if (restaurantRole) {
          expect(AccessPolicy.initialRouteFor(session), AppRoutes.appHome);
        }
      }
      final inventoryOnly = makeAppSession(
        permissions: {'RECIPE_VIEW'},
        features: {'INVENTORY_MANAGEMENT'},
      );
      expect(AccessPolicy.canRecipe(inventoryOnly, 'RECIPE_VIEW'), isFalse);
      final noPermission = makeAppSession(
        features: {'RECIPE_MANAGEMENT'},
        permissions: {},
      );
      expect(AccessPolicy.canRecipe(noPermission, 'RECIPE_VIEW'), isFalse);
    },
  );

  test(
    'recipe errors remain distinguishable and unit guards target baseUnit',
    () {
      for (final code in [
        'ACTIVE_RECIPE_NOT_FOUND',
        'RECIPE_NOT_FOUND',
        'ACTIVE_RECIPE_ALREADY_EXISTS',
        'RECIPE_NOT_ACTIVE',
        'DUPLICATE_RECIPE_INGREDIENT',
        'INGREDIENT_INACTIVE',
        'SAME_RECIPE_VERSION_NOT_ALLOWED',
        'CONCURRENT_RECIPE_UPDATE',
        'MENU_ITEM_UNIT_IN_USE',
        'MENU_ITEM_HAS_ACTIVE_RECIPE',
        'INGREDIENT_USED_BY_ACTIVE_RECIPE',
        'INGREDIENT_UNIT_IN_USE',
      ]) {
        final failure = _guardFailure(code);
        expect(failure.code, code);
        expect(failure.message, isNot('raw backend'));
        if (code == 'MENU_ITEM_UNIT_IN_USE' ||
            code == 'INGREDIENT_UNIT_IN_USE') {
          expect(failure.fieldErrors['baseUnit'], isNotEmpty);
        }
      }
    },
  );

  testWidgets(
    'known recipe route renders snapshots without catalog rights or sidebar items',
    (tester) async {
      final recipes = _RecipeRepository();
      final items = FakeMenuItems();
      final ingredients = FakeIngredients();
      final auth = await _auth(
        permissions: {'RECIPE_VIEW'},
        features: {'RECIPE_MANAGEMENT'},
      );
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          recipeRepositoryProvider.overrideWithValue(recipes),
          menuItemRepositoryProvider.overrideWithValue(items),
          menuGroupRepositoryProvider.overrideWithValue(FakeMenuGroups()),
          ingredientRepositoryProvider.overrideWithValue(ingredients),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      router.go(AppRoutes.recipeFor('i1'));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(RecipeManagementScreen), findsOneWidget);
      expect(find.text('Tên nguyên liệu lịch sử'), findsOneWidget);
      expect(recipes.activeCalls, 1);
      expect(items.queries, isEmpty);
      expect(items.detailCalls, 0);
      expect(ingredients.queries, isEmpty);
      expect(ingredients.detailCalls, 0);
      expect(recipes.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'menu recipe action works for view-only staff without fetching recipes per card',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final recipes = _RecipeRepository();
      final items = FakeMenuItems()..rows = [item()];
      final auth = await _auth(
        permissions: {'MENU_VIEW', 'RECIPE_VIEW'},
        features: {'MENU_MANAGEMENT', 'RECIPE_MANAGEMENT'},
      );
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          recipeRepositoryProvider.overrideWithValue(recipes),
          menuItemRepositoryProvider.overrideWithValue(items),
          menuGroupRepositoryProvider.overrideWithValue(FakeMenuGroups()),
          ingredientRepositoryProvider.overrideWithValue(FakeIngredients()),
        ],
      );
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider)..go(AppRoutes.menu);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(recipes.activeCalls, 0);
      final actions = find.byTooltip('Thao tác');
      await _tapVisible(tester, actions);
      expect(find.text('Công thức'), findsOneWidget);
      expect(find.text('Sửa thông tin'), findsNothing);
      await tester.tap(find.text('Công thức'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeManagementScreen), findsOneWidget);
      expect(recipes.activeCalls, 1);
      expect(items.writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final isIngredient in [false, true]) {
    testWidgets(
      '${isIngredient ? 'ingredient' : 'menu'} unit guard keeps draft and allows correction',
      (tester) async {
        final items = FakeMenuItems()
          ..onWrite = () async => Error(_guardFailure('MENU_ITEM_UNIT_IN_USE'));
        final ingredients = FakeIngredients()
          ..onWrite = () async =>
              Error(_guardFailure('INGREDIENT_UNIT_IN_USE'));
        final auth = await _auth(
          permissions: {...menuPermissions, ...ingredientPermissions},
          features: {'MENU_MANAGEMENT', 'RECIPE_MANAGEMENT'},
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith((ref) => auth),
              menuItemRepositoryProvider.overrideWithValue(items),
              menuGroupRepositoryProvider.overrideWithValue(FakeMenuGroups()),
              ingredientRepositoryProvider.overrideWithValue(ingredients),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: () {
                      if (isIngredient) {
                        showIngredientDialog<void>(
                          context,
                          ref,
                          permission: 'INGREDIENT_UPDATE',
                          child: IngredientForm(initial: ingredients.current),
                        );
                      } else {
                        showMenuDialog<void>(
                          context,
                          ref,
                          permission: 'MENU_UPDATE',
                          child: MenuItemForm(initial: items.current),
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
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final prefix = isIngredient ? 'ingredient' : 'menu-item';
        final name = find.byKey(ValueKey('$prefix-name'));
        final unit = find.byKey(ValueKey('$prefix-baseUnit'));
        await tester.enterText(name, 'Tên đang sửa');
        await tester.enterText(unit, 'kg');
        await _tapVisible(tester, find.text('Lưu thay đổi'));
        expect(
          tester.widget<TextFormField>(name).controller!.text,
          'Tên đang sửa',
        );
        expect(tester.widget<TextFormField>(unit).forceErrorText, isNotEmpty);
        if (isIngredient) {
          ingredients.onWrite = null;
        } else {
          items.onWrite = null;
        }
        await tester.enterText(unit, isIngredient ? 'g' : 'ly');
        await _tapVisible(tester, find.text('Lưu thay đổi'));
        expect(
          isIngredient ? ingredients.writes.length : items.writes.length,
          2,
        );
      },
    );
  }
}
