import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_cost_estimate.dart';
import 'package:pos_saas_app/features/menu/domain/use_cases/recipe_use_cases.dart';
import 'package:pos_saas_app/features/menu/domain/use_cases/menu_item_use_cases.dart';
import 'package:pos_saas_app/features/menu/presentation/controllers/menu_catalog_events.dart';
import 'package:pos_saas_app/features/menu/presentation/controllers/recipe_cost_controller.dart';
import '../../helpers/auth_fakes.dart';
import 'menu_fakes.dart';
import 'recipe_cost_fakes.dart';
import 'recipe_ui_fakes.dart';

void main() {
  test(
    'busy reads deduplicate and refresh failure clearly marks retained estimate stale',
    () async {
      final repository = CostRecipes();
      final pending = Completer<Result<RecipeCostEstimate>>();
      repository.onCost = (_, _) => pending.future;
      final events = MenuCatalogEvents();
      addTearDown(events.dispose);
      final controller = RecipeCostController(
        menuItemId: 'i1',
        recipeId: 'r7',
        session: () => makeAppSession(
          permissions: {'RECIPE_VIEW'},
          features: {'RECIPE_MANAGEMENT'},
        ),
        get: GetRecipeCostEstimate(repository),
        events: events,
      );
      addTearDown(controller.dispose);
      final read = controller.load();
      await controller.load();
      expect(repository.costCalls, hasLength(1));
      expect(controller.loading, isTrue);
      pending.complete(Success(estimateForRecipe(uiRecipe())));
      await read;
      repository.onCost = (_, _) async => const Error(networkFailure);
      await controller.load();
      expect(controller.value, isNotNull);
      expect(controller.stale, isTrue);
      expect(controller.failure, networkFailure);
      expect(repository.versions, isEmpty);
    },
  );

  test(
    'a relevant price change invalidates an in-flight estimate but unrelated events do not',
    () async {
      final repository = CostRecipes();
      final events = MenuCatalogEvents();
      addTearDown(events.dispose);
      final controller = RecipeCostController(
        menuItemId: 'i1',
        recipeId: 'r7',
        session: () => makeAppSession(
          permissions: {'RECIPE_VIEW'},
          features: {'RECIPE_MANAGEMENT'},
        ),
        get: GetRecipeCostEstimate(repository),
        events: events,
      );
      addTearDown(controller.dispose);
      await controller.load();
      events.ingredientChanged('unrelated');
      expect(controller.stale, isFalse);
      final pending = Completer<Result<RecipeCostEstimate>>();
      repository.onCost = (_, _) => pending.future;
      final load = controller.load();
      events.ingredientChanged('ingredient-1');
      expect(controller.stale, isTrue);
      expect(controller.loading, isFalse);
      pending.complete(Success(estimateForRecipe(uiRecipe(id: 'wrong'))));
      await load;
      expect(controller.value!.recipeId, 'r7');
      repository.onCost = null;
      await controller.load();
      expect(controller.stale, isFalse);
      events.recipeChanged('i1');
      expect(controller.stale, isTrue);
    },
  );

  test(
    'token rotation preserves state while logout rejects late old-scope responses',
    () async {
      var session = makeAppSession(
        permissions: {'RECIPE_VIEW'},
        features: {'RECIPE_MANAGEMENT'},
      );
      final repository = CostRecipes();
      final events = MenuCatalogEvents();
      addTearDown(events.dispose);
      final controller = RecipeCostController(
        menuItemId: 'i1',
        recipeId: 'r7',
        session: () => session,
        get: GetRecipeCostEstimate(repository),
        events: events,
      );
      addTearDown(controller.dispose);
      await controller.load();
      final refreshed = makeAuthSession(
        permissions: {'RECIPE_VIEW'},
        tokens: makeTokens(accessToken: 'rotated'),
      );
      session = session.copyWithAuth(
        user: refreshed.user,
        tokens: refreshed.tokens,
      );
      expect(controller.current, isTrue);
      expect(controller.value, isNotNull);
      final pending = Completer<Result<RecipeCostEstimate>>();
      repository.onCost = (_, _) => pending.future;
      final read = controller.load();
      session = makeAppSession(
        restaurantId: 'restaurant-2',
        permissions: {'RECIPE_VIEW'},
        features: {'RECIPE_MANAGEMENT'},
      );
      pending.complete(Success(estimateForRecipe(uiRecipe())));
      await read;
      expect(controller.current, isFalse);
      expect(controller.value, isNull);
      await controller.load();
      expect(repository.costCalls, hasLength(2));
    },
  );

  test(
    'menu price requests need MENU_VIEW independently of recipe read rights',
    () async {
      var session = makeAppSession(
        permissions: {'RECIPE_VIEW'},
        features: {'RECIPE_MANAGEMENT'},
      );
      final repository = FakeMenuItems();
      final events = MenuCatalogEvents();
      addTearDown(events.dispose);
      final controller = RecipeMenuPriceController(
        menuItemId: 'i1',
        session: () => session,
        get: GetMenuItemDetail(repository),
        events: events,
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(repository.detailCalls, 0);
      expect(controller.menu, isNull);
      session = makeAppSession(
        permissions: {'RECIPE_VIEW', 'MENU_VIEW'},
        features: {'RECIPE_MANAGEMENT', 'MENU_MANAGEMENT'},
      );
      expect(controller.current, isFalse);
      await controller.load();
      expect(repository.detailCalls, 0);
      final current = RecipeMenuPriceController(
        menuItemId: 'i1',
        session: () => session,
        get: GetMenuItemDetail(repository),
        events: events,
      );
      addTearDown(current.dispose);
      await current.load();
      expect(current.menu, isNotNull);
      events.itemChanged('other');
      expect(current.stale, isFalse);
      events.itemChanged('i1');
      expect(current.stale, isTrue);
      repository.onDetail = () async => const Error(networkFailure);
      await current.load();
      expect(current.menu, isNull);
      expect(current.failure, networkFailure);
    },
  );
}
