import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/menu/domain/entities/ingredient.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_page.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_query.dart';
import 'package:pos_saas_app/features/menu/domain/use_cases/ingredient_use_cases.dart';
import 'package:pos_saas_app/features/menu/domain/use_cases/recipe_use_cases.dart';
import 'package:pos_saas_app/features/menu/presentation/controllers/menu_catalog_events.dart';
import 'package:pos_saas_app/features/menu/presentation/controllers/recipe_controller.dart';
import 'package:pos_saas_app/features/menu/presentation/controllers/recipe_ingredient_selector_controller.dart';
import 'package:pos_saas_app/features/menu/presentation/providers/recipe_providers.dart';

import '../../helpers/auth_fakes.dart';
import 'ingredient_fakes.dart';
import 'recipe_state_fakes.dart';

AppSession _session({Set<String> permissions = recipePermissions}) =>
    makeAppSession(permissions: permissions, features: {'RECIPE_MANAGEMENT'});

RecipeController _controller(
  FakeRecipeStateRepository repository, {
  AppSession? Function()? session,
  MenuCatalogEvents? events,
  Future<void> Function(Failure)? onAccessDenied,
}) {
  final catalog = events ?? MenuCatalogEvents();
  if (events == null) addTearDown(catalog.dispose);
  final controller = RecipeController(
    menuItemId: 'item-1',
    session: session ?? () => _session(),
    active: GetActiveRecipe(repository),
    history: GetRecipeHistory(repository),
    detail: GetRecipeDetail(repository),
    create: CreateRecipe(repository),
    createVersion: CreateRecipeVersion(repository),
    deactivate: DeactivateRecipe(repository),
    events: catalog,
    onAccessDenied: onAccessDenied,
  );
  addTearDown(controller.dispose);
  return controller;
}

RecipeIngredientSelectorController _selector(
  FakeIngredients repository, {
  AppSession? Function()? session,
}) {
  final controller = RecipeIngredientSelectorController(
    menuItemId: 'item-1',
    session: session ?? () => _session(permissions: {'INGREDIENT_VIEW'}),
    list: GetIngredients(repository),
    detail: GetIngredientDetail(repository),
  );
  addTearDown(controller.dispose);
  return controller;
}

const _notFound = Failure(
  type: FailureType.notFound,
  code: 'ACTIVE_RECIPE_NOT_FOUND',
  message: 'Chưa có công thức',
);

void main() {
  test('only active-not-found represents a missing active recipe', () async {
    final repository = FakeRecipeStateRepository()
      ..onActive = () async => const Error(_notFound);
    final controller = _controller(repository);
    await controller.loadActive();
    expect(controller.activeLoaded, isTrue);
    expect(controller.active, isNull);
    expect(controller.activeFailure, isNull);

    for (final failure in [
      networkFailure,
      const Failure(
        type: FailureType.notFound,
        code: 'MENU_ITEM_NOT_FOUND',
        message: 'Không tìm thấy món',
      ),
      const Failure(
        type: FailureType.forbidden,
        code: 'FORBIDDEN',
        message: 'Thiếu quyền',
      ),
    ]) {
      repository.onActive = () async => Error(failure);
      final isolated = _controller(repository);
      await isolated.loadActive();
      expect(isolated.activeLoaded, isFalse);
      expect(isolated.activeFailure, same(failure));
    }
  });

  test(
    'view-only snapshot reads need no menu or ingredient permission',
    () async {
      final repository = FakeRecipeStateRepository();
      final controller = _controller(
        repository,
        session: () => _session(permissions: {'RECIPE_VIEW'}),
      );
      await controller.loadActive();
      await controller.loadHistory();
      expect(await controller.detail('recipe-7'), isA<Success<Recipe>>());
      expect(controller.active!.ingredients.first.name, contains('snapshot'));
      expect(controller.history!.content.single.ingredientCount, 2);
      expect(await controller.create(stateInput()), isA<Error<Recipe>>());
      expect(
        await controller.createVersion(repository.current, stateInput()),
        isA<Error<Recipe>>(),
      );
      expect(
        await controller.deactivate(repository.current),
        isA<Error<void>>(),
      );
      expect(repository.creates, isEmpty);
      expect(repository.versions, isEmpty);
      expect(repository.deactivations, isEmpty);
      // History is summaries; the sole detail request came from explicit opening.
      expect(repository.detailIds, [('item-1', 'recipe-7')]);
    },
  );

  test('unentitled inventory session never starts recipe reads', () async {
    final repository = FakeRecipeStateRepository();
    final controller = _controller(
      repository,
      session: () => makeAppSession(
        permissions: recipePermissions,
        features: {'INVENTORY_MANAGEMENT'},
      ),
    );
    await controller.loadActive();
    await controller.loadHistory();
    await controller.detail('recipe-7');
    expect(repository.activeIds, isEmpty);
    expect(repository.historyQueries, isEmpty);
    expect(repository.detailIds, isEmpty);
  });

  test(
    'new version uses active id and lock version, never business version',
    () async {
      final repository = FakeRecipeStateRepository();
      final controller = _controller(repository);
      await controller.loadActive();
      await controller.createVersion(repository.current, stateInput());
      final call = repository.versions.single;
      expect(call.$1, 'item-1');
      expect(call.$2, 'recipe-7');
      expect(call.$3.expectedVersion, 2);
      expect(call.$3.expectedVersion, isNot(repository.current.recipeVersion));
    },
  );

  test('historical recipe cannot become an update baseline', () async {
    final repository = FakeRecipeStateRepository();
    final controller = _controller(repository);
    await controller.loadActive();
    final historical = stateRecipe(id: 'old', version: 1, active: false);
    final result = await controller.createVersion(historical, stateInput());
    expect((result as Error).failure.code, 'CONCURRENT_RECIPE_UPDATE');
    expect(repository.versions, isEmpty);
  });

  test(
    'row reordering and normalized quantities do not create a version',
    () async {
      final repository = FakeRecipeStateRepository();
      final controller = _controller(repository);
      await controller.loadActive();
      final result = await controller.createVersion(
        repository.current,
        stateInput(reversed: true, yieldQuantity: '10.000'),
      );
      expect((result as Error).failure.code, 'SAME_RECIPE_VERSION_NOT_ALLOWED');
      expect(repository.versions, isEmpty);
    },
  );

  test('duplicate ingredients are rejected before mutation', () async {
    final repository = FakeRecipeStateRepository();
    final controller = _controller(repository);
    final input = stateInput();
    final result = await controller.create(
      RecipeInput(
        yieldQuantity: input.yieldQuantity,
        ingredients: [input.ingredients.first, input.ingredients.first],
      ),
    );
    expect(
      (result as Error).failure.fieldErrors,
      contains('ingredients[1].ingredientId'),
    );
    expect(repository.creates, isEmpty);
  });

  test(
    'latest history query wins when requests complete out of order',
    () async {
      final first = Completer<Result<MenuPage<RecipeSummary>>>();
      final second = Completer<Result<MenuPage<RecipeSummary>>>();
      final repository = FakeRecipeStateRepository()
        ..onHistory = (query) => query.page == 0 ? first.future : second.future;
      final controller = _controller(repository);
      final initial = controller.loadHistory();
      controller.setHistoryQuery(const RecipeQuery(page: 1));
      second.complete(
        Success(recipeStatePage(page: 1, totalPages: 2, id: 'new')),
      );
      await Future<void>.delayed(Duration.zero);
      first.complete(Success(recipeStatePage(id: 'stale')));
      await initial;
      expect(controller.query.page, 1);
      expect(controller.query.sortBy, 'recipeVersion');
      expect(controller.history!.content.single.id, 'new');
    },
  );

  test(
    'changing history ordering resets page and pagination preserves ordering',
    () async {
      final repository = FakeRecipeStateRepository();
      final controller = _controller(repository);
      controller.setHistoryQuery(const RecipeQuery(page: 4));
      await Future<void>.delayed(Duration.zero);
      expect(controller.query.page, 4);
      controller.setHistoryQuery(
        const RecipeQuery(page: 4, sortBy: 'createdAt'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.query.page, 0);
      expect(repository.historyQueries.last.$2.sortBy, 'createdAt');
      controller.setHistoryQuery(
        const RecipeQuery(page: 2, sortBy: 'createdAt'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.query.page, 2);
      controller.setHistoryQuery(
        const RecipeQuery(page: 2, sortBy: 'createdAt', size: 50),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.query.page, 0);
    },
  );

  test(
    'scope changes discard in-flight reads and hide loaded snapshots',
    () async {
      AppSession? session = _session();
      final active = Completer<Result<Recipe>>();
      final repository = FakeRecipeStateRepository()
        ..onActive = () => active.future;
      final controller = _controller(repository, session: () => session);
      final request = controller.loadActive();
      session = makeAppSession(
        restaurantId: 'restaurant-2',
        permissions: recipePermissions,
        features: {'RECIPE_MANAGEMENT'},
      );
      active.complete(Success(repository.current));
      await request;
      expect(controller.isCurrent, isFalse);
      expect(controller.active, isNull);
      expect(controller.activeLoaded, isFalse);
      expect(controller.history, isNull);
    },
  );

  test(
    'late detail result is discarded independently for each recipe id',
    () async {
      final first = Completer<Result<Recipe>>();
      final second = Completer<Result<Recipe>>();
      final repository = FakeRecipeStateRepository();
      var count = 0;
      repository.onDetail = (_) => count++ == 0 ? first.future : second.future;
      final controller = _controller(repository);
      final oldRequest = controller.detail('recipe-7');
      final newRequest = controller.detail('recipe-7');
      second.complete(Success(repository.current));
      expect(await newRequest, isA<Success<Recipe>>());
      first.complete(Success(repository.current));
      expect((await oldRequest as Error).failure.code, 'RECIPE_SCOPE_CHANGED');
    },
  );

  test(
    'successful response is active and events never reload item catalog',
    () async {
      final repository = FakeRecipeStateRepository();
      final events = MenuCatalogEvents();
      addTearDown(events.dispose);
      final controller = _controller(repository, events: events);
      final response = stateRecipe(id: 'created', recipeVersion: 8, version: 0);
      repository.onCreate = () async => Success(response);
      expect(await controller.create(stateInput()), isA<Success<Recipe>>());
      expect(controller.active, same(response));
      expect(repository.activeIds, isEmpty);
      expect(events.recipeRevision, 1);
      expect(events.changedRecipeMenuItemId, 'item-1');
      expect(events.itemRevision, 0);
      expect(events.ingredientRevision, 0);
      expect(repository.historyQueries, isEmpty);
    },
  );

  test(
    'DELETE retry targets old id and reload keeps newer active recipe',
    () async {
      final repository = FakeRecipeStateRepository();
      final controller = _controller(repository);
      await controller.loadActive();
      await controller.loadHistory();
      final inactive = stateRecipe(
        id: 'old-inactive',
        active: false,
        version: 0,
      );
      repository.current = stateRecipe(
        id: 'new-active',
        recipeVersion: 8,
        version: 1,
      );
      expect(await controller.deactivate(inactive), isA<Success<void>>());
      expect(repository.deactivations.single, ('item-1', 'old-inactive', 0));
      expect(controller.active!.id, 'new-active');
      expect(repository.activeIds.length, 2);
      expect(repository.historyQueries.length, 2);
    },
  );

  test(
    'failed active reread after DELETE retains snapshot and exposes failure',
    () async {
      final repository = FakeRecipeStateRepository();
      final controller = _controller(repository);
      await controller.loadActive();
      final previous = controller.active;
      repository.onActive = () async => const Error(networkFailure);
      expect(
        await controller.deactivate(repository.current),
        isA<Success<void>>(),
      );
      expect(controller.active, same(previous));
      expect(controller.activeLoaded, isTrue);
      expect(controller.activeFailure, same(networkFailure));
      expect(controller.activeLoading, isFalse);
    },
  );

  test(
    'scope change during mutation discards result and emits no catalog event',
    () async {
      AppSession? session = _session();
      final pending = Completer<Result<Recipe>>();
      final repository = FakeRecipeStateRepository()
        ..onCreate = () => pending.future;
      final events = MenuCatalogEvents();
      addTearDown(events.dispose);
      final controller = _controller(
        repository,
        session: () => session,
        events: events,
      );
      final request = controller.create(stateInput());
      session = null;
      pending.complete(Success(repository.current));
      expect((await request as Error).failure.code, 'RECIPE_SCOPE_CHANGED');
      expect(controller.active, isNull);
      expect(controller.busy, isFalse);
      expect(events.recipeRevision, 0);
    },
  );

  test('mutation lock prevents duplicate writes while pending', () async {
    final pending = Completer<Result<Recipe>>();
    final repository = FakeRecipeStateRepository()
      ..onCreate = () => pending.future;
    final controller = _controller(repository);
    final first = controller.create(stateInput());
    expect(controller.busy, isTrue);
    final duplicate = await controller.create(stateInput());
    expect((duplicate as Error).failure.code, 'RECIPE_BUSY');
    expect(repository.creates.length, 1);
    pending.complete(Success(repository.current));
    await first;
    expect(controller.busy, isFalse);
  });

  test(
    'conflict invalidates baseline and never retries or switches endpoint',
    () async {
      const failure = Failure(
        type: FailureType.conflict,
        code: 'CONCURRENT_RECIPE_UPDATE',
        message: 'Đã thay đổi',
      );
      final repository = FakeRecipeStateRepository()
        ..onVersion = () async => const Error(failure);
      final controller = _controller(repository);
      await controller.loadActive();
      final draft = stateInput();
      final result = await controller.createVersion(repository.current, draft);
      expect((result as Error).failure, same(failure));
      expect(draft.ingredients.length, 2);
      expect(controller.baselineNeedsReload, isTrue);
      await controller.createVersion(repository.current, draft);
      expect(repository.versions.length, 1);
      expect(repository.creates, isEmpty);
      expect(repository.activeIds.length, 1);
      await controller.loadActive();
      expect(controller.baselineNeedsReload, isFalse);
    },
  );

  test(
    'active GET started before conflict cannot validate stale baseline',
    () async {
      const failure = Failure(
        type: FailureType.conflict,
        code: 'CONCURRENT_RECIPE_UPDATE',
        message: 'Đã thay đổi',
      );
      final repository = FakeRecipeStateRepository()
        ..onVersion = () async => const Error(failure);
      final controller = _controller(repository);
      await controller.loadActive();
      final beforeConflict = Completer<Result<Recipe>>();
      repository.onActive = () => beforeConflict.future;
      final staleRead = controller.loadActive();
      expect(controller.activeLoading, isTrue);
      await controller.createVersion(repository.current, stateInput());
      expect(controller.baselineNeedsReload, isTrue);
      expect(controller.activeLoading, isFalse);
      beforeConflict.complete(Success(repository.current));
      await staleRead;
      expect(controller.baselineNeedsReload, isTrue);
      await controller.createVersion(repository.current, stateInput());
      expect(repository.versions.length, 1);
      repository.onActive = null;
      await controller.loadActive();
      expect(controller.baselineNeedsReload, isFalse);
    },
  );

  test(
    'network mutation retains uncertain outcome and sends exactly once',
    () async {
      final repository = FakeRecipeStateRepository()
        ..onCreate = () async => const Error(networkFailure);
      final controller = _controller(repository);
      final result = await controller.create(stateInput());
      expect((result as Error).failure.message, contains('Chưa xác định'));
      expect(repository.creates.length, 1);
      expect(repository.versions, isEmpty);
      expect(repository.activeIds, isEmpty);
    },
  );

  test(
    'only recipe events for this item refresh the active aggregate',
    () async {
      final repository = FakeRecipeStateRepository();
      final events = MenuCatalogEvents();
      addTearDown(events.dispose);
      _controller(repository, events: events);
      events.itemChanged('item-1');
      events.ingredientChanged('ingredient-1');
      events.recipeChanged('item-2');
      await Future<void>.delayed(Duration.zero);
      expect(repository.activeIds, isEmpty);
      events.recipeChanged('item-1');
      await Future<void>.delayed(Duration.zero);
      expect(repository.activeIds, ['item-1']);
      expect(repository.historyQueries, isEmpty);
    },
  );

  test(
    'selector uses active catalog without inventory tracking restriction',
    () async {
      final repository = FakeIngredients();
      final current = repository.current;
      repository.rows = [
        Ingredient(
          id: current.id,
          sku: current.sku,
          name: current.name,
          baseUnit: current.baseUnit,
          description: current.description,
          costPrice: current.costPrice,
          trackInventory: false,
          active: true,
          version: current.version,
          createdAt: current.createdAt,
          updatedAt: current.updatedAt,
        ),
      ];
      final selector = _selector(repository);
      await selector.load();
      expect(repository.queries.single.active, isTrue);
      expect(repository.queries.single.trackInventory, isNull);
      expect(selector.rows.single.trackInventory, isFalse);
      expect(selector.rows.single.id, current.id);
    },
  );

  test(
    'recipe view permission never authorizes ingredient catalog reads',
    () async {
      final repository = FakeIngredients();
      final selector = _selector(repository, session: () => _session());
      expect(selector.canRead, isFalse);
      await selector.load();
      selector.search('bò');
      await selector.detail('ingredient-1');
      expect(repository.queries, isEmpty);
      expect(repository.detailCalls, 0);
    },
  );

  testWidgets(
    'selector search debounces and stale pages cannot replace results',
    (tester) async {
      final old = Completer<Result<MenuPage<Ingredient>>>();
      final repository = FakeIngredients();
      repository.onList = (query) async => query.q.isEmpty
          ? old.future
          : Success(
              MenuPage(
                content: [repository.current],
                page: query.page,
                size: 20,
                totalElements: 40,
                totalPages: 2,
              ),
            );
      final selector = _selector(repository);
      final initial = selector.load();
      selector.search('th');
      await tester.pump(const Duration(milliseconds: 200));
      selector.search('thịt bò');
      await tester.pump(const Duration(milliseconds: 349));
      expect(repository.queries.length, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.queries.length, 2);
      expect(selector.rows.single.id, repository.current.id);
      selector.setPage(1);
      await tester.pump();
      expect(selector.query.q, 'thịt bò');
      expect(selector.query.page, 1);
      old.complete(
        Success(
          MenuPage(
            content: [],
            page: 0,
            size: 20,
            totalElements: 0,
            totalPages: 0,
          ),
        ),
      );
      await initial;
      expect(selector.query.page, 1);
      expect(selector.rows, isNotEmpty);
    },
  );

  testWidgets(
    'disposing selector cancels search debounce on scope replacement',
    (tester) async {
      final repository = FakeIngredients();
      final selector = RecipeIngredientSelectorController(
        menuItemId: 'item-1',
        session: () => _session(permissions: {'INGREDIENT_VIEW'}),
        list: GetIngredients(repository),
        detail: GetIngredientDetail(repository),
      );
      selector.search('pending');
      selector.dispose();
      await tester.pump(const Duration(milliseconds: 400));
      expect(repository.queries, isEmpty);
      expect(selector.state.rows, isEmpty);
    },
  );

  test(
    'providers retain query on token rotation and reset on tenant change',
    () async {
      final permissions = {...recipePermissions, 'INGREDIENT_VIEW'};
      final events = SessionEvents();
      final auth = makeController(
        sessionEvents: events,
        authRepository: FakeAuthRepository()
          ..loginResult = Success(makeAuthSession(permissions: permissions)),
        entitlementRepository: FakeEntitlementRepository()
          ..result = Success(makeEntitlement(features: {'RECIPE_MANAGEMENT'})),
      );
      await auth.login(
        const LoginCredentials(
          email: 'recipe@example.com',
          password: 'password',
        ),
      );
      final repository = FakeRecipeStateRepository();
      final ingredients = FakeIngredients();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          recipeRepositoryProvider.overrideWithValue(repository),
          ingredientRepositoryProvider.overrideWithValue(ingredients),
        ],
      );
      addTearDown(events.dispose);
      addTearDown(container.dispose);
      final activeSubscription = container.listen(
        recipeControllerProvider('item-1'),
        (_, _) {},
      );
      final pickerSubscription = container.listen(
        recipeIngredientSelectorProvider('item-1'),
        (_, _) {},
      );
      addTearDown(activeSubscription.close);
      addTearDown(pickerSubscription.close);
      final first = container.read(recipeControllerProvider('item-1'));
      final firstSelector = container.read(
        recipeIngredientSelectorProvider('item-1'),
      );
      first.setHistoryQuery(
        const RecipeQuery(sortBy: 'updatedAt', direction: 'asc'),
      );
      firstSelector.search('draft');
      await Future<void>.delayed(Duration.zero);
      events.refreshed(
        makeAuthSession(
          permissions: permissions,
          tokens: makeTokens(accessToken: 'rotated'),
        ),
      );
      await container.pump();
      expect(container.read(recipeControllerProvider('item-1')), same(first));
      expect(
        container.read(recipeIngredientSelectorProvider('item-1')),
        same(firstSelector),
      );
      expect(first.query.sortBy, 'updatedAt');
      expect(firstSelector.query.q, 'draft');
      repository.current = stateRecipe(id: 'new-tenant');
      events.refreshed(
        makeAuthSession(permissions: permissions, restaurantId: 'restaurant-2'),
      );
      await container.pump();
      final second = container.read(recipeControllerProvider('item-1'));
      expect(second, isNot(same(first)));
      expect(first.isCurrent, isFalse);
      expect(first.active, isNull);
      expect(second.query.sortBy, 'recipeVersion');
      expect(
        container.read(recipeIngredientSelectorProvider('item-1')).query.q,
        '',
      );
      await auth.logout();
      await container.pump();
      expect(second.isCurrent, isFalse);
      expect(second.active, isNull);
    },
  );

  test('recipe access recovery restores only once per scope', () async {
    final repository = FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: recipePermissions))
      ..restoreResult = Success(
        makeAuthSession(permissions: recipePermissions),
      );
    final auth = makeController(
      authRepository: repository,
      entitlementRepository: FakeEntitlementRepository()
        ..result = Success(makeEntitlement(features: {'RECIPE_MANAGEMENT'})),
    );
    addTearDown(auth.dispose);
    await auth.login(
      const LoginCredentials(email: 'recipe@example.com', password: 'password'),
    );
    final recovery = RecipeAccessRecovery(auth, (_) {});
    const failure = Failure(
      type: FailureType.forbidden,
      message: 'Thiếu quyền',
    );
    await Future.wait([recovery.handle(failure), recovery.handle(failure)]);
    await recovery.handle(failure);
    expect(repository.restoreCalls, 1);
  });
}
