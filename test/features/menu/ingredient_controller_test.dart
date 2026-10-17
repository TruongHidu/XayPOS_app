import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/ui/sidebar/app_sidebar_registry.dart';
import 'package:pos_saas_app/core/ui/sidebar/sidebar_filter.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import 'package:pos_saas_app/features/menu/domain/entities/ingredient.dart';
import 'package:pos_saas_app/features/menu/domain/entities/ingredient_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/ingredient_query.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_page.dart';
import 'package:pos_saas_app/features/menu/domain/use_cases/ingredient_use_cases.dart';
import 'package:pos_saas_app/features/menu/presentation/controllers/ingredient_controller.dart';
import 'package:pos_saas_app/features/menu/presentation/controllers/menu_catalog_events.dart';
import 'ingredient_fakes.dart';
import 'menu_fakes.dart' show page;
import '../../helpers/auth_fakes.dart';

AppSession _session({Set<String> permissions = ingredientPermissions}) =>
    makeAppSession(permissions: permissions, features: {'RECIPE_MANAGEMENT'});

IngredientController _controller(
  FakeIngredients repository, {
  AppSession? Function()? session,
  MenuCatalogEvents? events,
}) {
  final catalogEvents = events ?? MenuCatalogEvents();
  if (events == null) addTearDown(catalogEvents.dispose);
  final controller = IngredientController(
    session: session ?? () => _session(),
    list: GetIngredients(repository),
    detail: GetIngredientDetail(repository),
    create: CreateIngredient(repository),
    update: UpdateIngredient(repository),
    status: SetIngredientStatus(repository),
    delete: DeleteIngredient(repository),
    events: catalogEvents,
  );
  addTearDown(controller.dispose);
  return controller;
}

void main() {
  test(
    'ingredient-only access reaches workspace with either entitled feature',
    () {
      for (final role in UserRole.values) {
        for (final feature in ['RECIPE_MANAGEMENT', 'INVENTORY_MANAGEMENT']) {
          final session = makeAppSession(
            role: role,
            permissions: ingredientPermissions,
            features: {feature},
          );
          final allowed = const {
            UserRole.owner,
            UserRole.manager,
            UserRole.waiter,
            UserRole.kitchen,
          }.contains(role);
          expect(
            AccessPolicy.canIngredient(session, 'INGREDIENT_VIEW'),
            allowed,
          );
          expect(AccessPolicy.canMenu(session, 'MENU_VIEW'), isFalse);
          expect(
            AccessPolicy.canOpenRoute(session, '/app/menu?source=test'),
            allowed,
          );
          expect(
            filterCategories(
              session,
              AppSidebarRegistry.categories,
            ).expand((c) => c.items).any((i) => i.id == 'menu'),
            allowed,
          );
          if (allowed) {
            expect(AccessPolicy.initialRouteFor(session), '/app/home');
            expect(AccessPolicy.canOpenRoute(session, '/app/home'), isTrue);
          }
        }
      }
      expect(
        AccessPolicy.canIngredient(
          makeAppSession(features: {'RECIPE_MANAGEMENT'}),
          'INGREDIENT_VIEW',
        ),
        isFalse,
      );
      expect(
        AccessPolicy.canIngredient(
          makeAppSession(permissions: ingredientPermissions),
          'INGREDIENT_VIEW',
        ),
        isFalse,
      );
    },
  );

  test(
    'read-only ingredient controller cannot mutate even for OWNER',
    () async {
      final repository = FakeIngredients();
      final controller = _controller(
        repository,
        session: () => _session(permissions: {'INGREDIENT_VIEW'}),
      );
      await controller.create(
        const CreateIngredientInput(name: 'Bò', baseUnit: 'g'),
      );
      await controller.update(
        'ingredient-1',
        const UpdateIngredientInput(expectedVersion: 4, name: 'Mới'),
      );
      await controller.setStatus(ingredient(), false);
      await controller.delete(ingredient());
      expect(repository.writes, isEmpty);
      await controller.load();
      expect(controller.state.rows.single.name, 'Thịt bò');
    },
  );

  test(
    'empty patches do not issue writes and status uses server version unchanged',
    () async {
      final repository = FakeIngredients();
      final events = MenuCatalogEvents();
      addTearDown(events.dispose);
      final controller = _controller(repository, events: events);
      await controller.update(
        'ingredient-1',
        const UpdateIngredientInput(expectedVersion: 4),
      );
      expect(repository.writes, isEmpty);
      final result = await controller.setStatus(ingredient(version: 1), true);
      expect((result as Success<Ingredient>).value.version, 4);
      expect(repository.writes, [('status', 1)]);
      expect(repository.queries.length, 1);
      expect(events.ingredientRevision, 1);
      expect(events.itemRevision, 0);
    },
  );

  test(
    'concurrent update is returned without retrying and without replacing baseline',
    () async {
      const conflict = Failure(
        type: FailureType.conflict,
        code: 'CONCURRENT_INGREDIENT_UPDATE',
        message: 'Tải lại',
      );
      final repository = FakeIngredients()
        ..onWrite = () async => const Error(conflict);
      final controller = _controller(repository);
      final result = await controller.update(
        'ingredient-1',
        const UpdateIngredientInput(expectedVersion: 4, name: 'Mới'),
      );
      expect((result as Error).failure.code, conflict.code);
      expect(repository.writes, [('update', 4)]);
      expect(repository.detailCalls, 0);
    },
  );

  test(
    'same-row mutations are blocked while in flight and late results are discarded',
    () async {
      final pending = Completer<Result<Ingredient>>();
      final repository = FakeIngredients()..onWrite = () => pending.future;
      AppSession? session = _session();
      final controller = _controller(repository, session: () => session);
      final first = controller.setStatus(ingredient(), false);
      final duplicate = await controller.delete(ingredient());
      expect((duplicate as Error).failure.code, 'INGREDIENT_BUSY');
      session = null;
      pending.complete(Success(ingredient()));
      expect((await first as Error).failure.code, 'INGREDIENT_SCOPE_CHANGED');
      expect(repository.writes.length, 1);
      expect(controller.state.rows, isEmpty);
    },
  );

  test('newer query wins when list requests complete out of order', () async {
    final first = Completer<Result<MenuPage<Ingredient>>>();
    final second = Completer<Result<MenuPage<Ingredient>>>();
    final repository = FakeIngredients()
      ..onList = (q) => q.q == '' ? first.future : second.future;
    final controller = _controller(repository);
    final load = controller.load();
    controller.setQuery(const IngredientQuery(q: 'new'));
    second.complete(Success(page([ingredient(name: 'Kết quả mới')])));
    await Future<void>.delayed(Duration.zero);
    first.complete(Success(page([ingredient(name: 'Kết quả cũ')])));
    await load;
    expect(controller.state.rows.single.name, 'Kết quả mới');
    expect(controller.state.query.q, 'new');
  });

  testWidgets(
    'search debounces, filters reset page, refresh preserves loaded rows',
    (tester) async {
      final repository = FakeIngredients();
      final controller = _controller(repository);
      await controller.load();
      controller.search('bo');
      controller.search('bo uc');
      await tester.pump(const Duration(milliseconds: 349));
      expect(repository.queries.length, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(repository.queries.last.q, 'bo uc');
      final pending = Completer<Result<MenuPage<Ingredient>>>();
      repository.onList = (_) => pending.future;
      final refresh = controller.load();
      expect(controller.state.rows, isNotEmpty);
      expect(controller.state.loading, isTrue);
      pending.complete(Success(page([ingredient()])));
      await refresh;
    },
  );

  test(
    'delete refreshes the previous page when the last row disappears',
    () async {
      final repository = FakeIngredients();
      var deleted = false;
      repository.onList = (query) async => Success(
        page(
          deleted ? [] : [ingredient()],
          index: query.page,
          pages: deleted ? 1 : 2,
        ),
      );
      repository.onWrite = () async {
        deleted = true;
        return Success(ingredient());
      };
      final controller = _controller(repository);
      await controller.load();
      controller.setPage(1);
      await Future<void>.delayed(Duration.zero);
      await controller.delete(ingredient());
      expect(controller.state.query.page, 0);
      expect(repository.queries.map((q) => q.page), [0, 1, 1, 0]);
    },
  );

  test(
    'not found refreshes ingredients without falling back to menu endpoints',
    () async {
      final repository = FakeIngredients()
        ..onDetail = () async => const Error(
          Failure(
            type: FailureType.notFound,
            code: 'INGREDIENT_NOT_FOUND',
            message: 'Đã xóa',
          ),
        );
      final controller = _controller(repository);
      expect(await controller.detail('missing'), isA<Error>());
      expect(repository.detailCalls, 1);
      expect(repository.queries.length, 1);
    },
  );

  test(
    'scope preserves state on token rotation and resets on tenant change/logout',
    () async {
      final events = SessionEvents();
      final auth = makeController(
        sessionEvents: events,
        authRepository: FakeAuthRepository()
          ..loginResult = Success(
            makeAuthSession(permissions: ingredientPermissions),
          ),
        entitlementRepository: FakeEntitlementRepository()
          ..result = Success(makeEntitlement(features: {'RECIPE_MANAGEMENT'})),
      );
      await auth.login(
        const LoginCredentials(
          email: 'ingredient@example.com',
          password: 'password',
        ),
      );
      final repository = FakeIngredients();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          ingredientRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(events.dispose);
      addTearDown(container.dispose);
      final subscription = container.listen(
        ingredientControllerProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final first = container.read(ingredientControllerProvider);
      first.setQuery(const IngredientQuery(q: 'draft'));
      await Future<void>.delayed(Duration.zero);
      events.refreshed(
        makeAuthSession(
          permissions: ingredientPermissions,
          tokens: makeTokens(accessToken: 'rotated'),
        ),
      );
      await container.pump();
      expect(
        identical(container.read(ingredientControllerProvider), first),
        isTrue,
      );
      expect(first.state.query.q, 'draft');
      repository.rows = [];
      events.refreshed(
        makeAuthSession(
          permissions: ingredientPermissions,
          restaurantId: 'restaurant-2',
        ),
      );
      await container.pump();
      final second = container.read(ingredientControllerProvider);
      expect(identical(first, second), isFalse);
      expect(first.isCurrent, isFalse);
      expect(second.state.query.q, '');
      expect(second.state.rows, isEmpty);
      await auth.logout();
      await container.pump();
      expect(second.isCurrent, isFalse);
      expect(container.read(ingredientControllerProvider).state.rows, isEmpty);
    },
  );

  test(
    'repeated access refusal triggers only one recovery per scope',
    () async {
      final authRepo = FakeAuthRepository()
        ..loginResult = Success(
          makeAuthSession(permissions: ingredientPermissions),
        )
        ..restoreResult = Success(
          makeAuthSession(permissions: ingredientPermissions),
        );
      final auth = makeController(
        authRepository: authRepo,
        entitlementRepository: FakeEntitlementRepository()
          ..result = Success(makeEntitlement(features: {'RECIPE_MANAGEMENT'})),
      );
      addTearDown(auth.dispose);
      await auth.login(
        const LoginCredentials(
          email: 'ingredient@example.com',
          password: 'password',
        ),
      );
      final recovery = IngredientAccessRecovery(auth, (_) {});
      const failure = Failure(
        type: FailureType.forbidden,
        code: 'FORBIDDEN',
        message: 'Thiếu quyền',
      );
      await recovery.handle(failure);
      await recovery.handle(failure);
      expect(authRepo.restoreCalls, 1);
      expect(authRepo.logoutCalls, 0);
    },
  );
}
