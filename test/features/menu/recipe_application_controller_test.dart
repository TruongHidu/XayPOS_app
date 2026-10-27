import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_item.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe.dart';
import 'package:pos_saas_app/features/menu/domain/use_cases/menu_item_use_cases.dart';
import 'package:pos_saas_app/features/menu/presentation/controllers/menu_catalog_events.dart';
import 'package:pos_saas_app/features/menu/presentation/controllers/recipe_application_controller.dart';
import '../../helpers/auth_fakes.dart';
import 'menu_fakes.dart';
import 'recipe_state_fakes.dart';

class _Harness {
  _Harness({
    bool feature = true,
    bool enabled = false,
    Set<String> permissions = const {
      'MENU_VIEW',
      'MENU_UPDATE',
      'RECIPE_DELETE',
    },
  }) {
    appSession = makeAppSession(
      permissions: permissions,
      features: {'MENU_MANAGEMENT', if (feature) 'RECIPE_MANAGEMENT'},
    );
    repo.current = item(recipeEnabled: enabled);
    controller = RecipeApplicationController(
      menuItemId: 'i1',
      session: () => appSession,
      get: GetMenuItemDetail(repo),
      events: events,
      itemPending: () => locked,
      update: (id, input) async {
        writes.add(input);
        if (onUpdate != null) return onUpdate!(input);
        repo.current = item(
          version: input.expectedVersion + 1,
          recipeEnabled: input.recipeEnabled!,
          costConfigured: repo.current.costConfigured,
        );
        return Success(repo.current);
      },
    );
    addTearDown(() {
      controller.dispose();
      events.dispose();
    });
  }
  AppSession? appSession;
  final repo = FakeMenuItems(), events = MenuCatalogEvents();
  final writes = <UpdateMenuItemInput>[];
  late final RecipeApplicationController controller;
  bool locked = false;
  Future<Result<MenuItem>> Function(UpdateMenuItemInput)? onUpdate;
}

void main() {
  test(
    'application uses latest menu version and menu permission, without recipe-update/inventory/cost gates',
    () async {
      final h = _Harness();
      await h.controller.load();
      expect(h.controller.item!.version, 9);
      h.repo.current = item(version: 14, costConfigured: false);
      final result = await h.controller.setEnabled(true);
      expect(result, isA<Success<MenuItem>>());
      expect(h.writes.single.expectedVersion, 14);
      expect(h.writes.single.recipeEnabled, true);
      expect(h.writes.single.costPrice, null);
      expect(h.writes.single.costConfigured, null);
      expect(h.controller.item!.version, 15);
      expect(h.controller.item!.costConfigured, false);
    },
  );
  test(
    'package downgrade permits disabling but cannot enable or silently turn off',
    () async {
      final h = _Harness(feature: false, enabled: true);
      await h.controller.load();
      expect(h.controller.item!.recipeEnabled, true);
      expect(h.controller.canSet(true), false);
      expect(h.controller.canSet(false), true);
      expect(await h.controller.setEnabled(true), isA<Error<MenuItem>>());
      expect(h.writes, isEmpty);
      expect(await h.controller.setEnabled(false), isA<Success<MenuItem>>());
      expect(h.writes.single.recipeEnabled, false);
    },
  );
  test(
    'shared item pending and application pending block a second intent',
    () async {
      final h = _Harness();
      h.locked = true;
      expect(await h.controller.setEnabled(true), isA<Error<MenuItem>>());
      expect(h.repo.detailCalls, 0);
      expect(h.writes, isEmpty);
      h.locked = false;
      final result = Completer<Result<MenuItem>>();
      h.onUpdate = (_) => result.future;
      final first = h.controller.setEnabled(true);
      await Future<void>.delayed(Duration.zero);
      expect(h.controller.busy, true);
      await h.controller.setEnabled(true);
      expect(h.writes, hasLength(1));
      result.complete(Success(item(version: 10, recipeEnabled: true)));
      await first;
      expect(h.controller.busy, false);
    },
  );
  test(
    '409 requires explicit read before retry and never automatically patches a new version',
    () async {
      final h = _Harness();
      h.onUpdate = (_) async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'CONCURRENT_MENU_ITEM_UPDATE',
          message: 'Changed',
        ),
      );
      await h.controller.setEnabled(true);
      expect(h.controller.needsVerification, true);
      h.repo.current = item(version: 20);
      await h.controller.setEnabled(true);
      expect(h.writes, hasLength(1));
      await h.controller.load();
      h.onUpdate = null;
      await h.controller.setEnabled(true);
      expect(h.writes.last.expectedVersion, 20);
      expect(h.writes, hasLength(2));
    },
  );
  test(
    'save-and-enable keeps definition on second-step failure and cannot recreate it',
    () async {
      final h = _Harness();
      var creates = 0;
      final recipe = stateRecipe(
        menuItemId: 'i1',
        version: 42,
        recipeVersion: 7,
      );
      Future<Result<Recipe>> save() async {
        creates++;
        return Success(recipe);
      }

      h.onUpdate = (_) async => const Error(networkFailure);
      final result = await h.controller.saveAndEnable(save);
      expect(result, isA<Error<Recipe>>());
      expect(h.controller.savedDefinition, same(recipe));
      expect(
        h.controller.failure!.message,
        contains('Đã lưu công thức, chưa bật sử dụng'),
      );
      expect(
        h.writes.single.expectedVersion,
        9,
      ); // Not recipe 42 or business 7.
      await h.controller.saveAndEnable(save);
      expect(creates, 1);
      expect(h.writes, hasLength(1));
      h.repo.current = item(version: 22, recipeEnabled: true);
      await h.controller.load();
      await h.controller.setEnabled(true);
      expect(
        h.writes,
        hasLength(1),
      ); // The unknown first PATCH already succeeded.
      expect(h.controller.savedDefinition, null);
    },
  );
  test('definition failure never patches menu application', () async {
    final h = _Harness();
    await h.controller.saveAndEnable(() async => const Error(networkFailure));
    expect(h.controller.savedDefinition, null);
    expect(h.writes, isEmpty);
  });
  test(
    'archive disables first with menu lock version; failure leaves definition retained and application off',
    () async {
      final h = _Harness(enabled: true);
      final operations = <String>[];
      h.onUpdate = (input) async {
        operations.add('menu:${input.expectedVersion}:${input.recipeEnabled}');
        h.repo.current = item(version: 10, recipeEnabled: false);
        return Success(h.repo.current);
      };
      final recipe = stateRecipe(menuItemId: 'i1', version: 42);
      final result = await h.controller.disableAndArchive(recipe, () async {
        operations.add('recipe:${recipe.version}');
        return const Error(
          Failure(
            type: FailureType.conflict,
            code: 'CONCURRENT_RECIPE_UPDATE',
            message: 'Changed',
          ),
        );
      });
      expect(result, isA<Error<void>>());
      expect(operations, ['menu:9:false', 'recipe:42']);
      expect(h.controller.item!.recipeEnabled, false);
      expect(
        h.controller.failure!.message,
        contains('Đã tắt sử dụng công thức'),
      );
      expect(h.writes, hasLength(1)); // No pretend rollback.
    },
  );
  test(
    'archive cannot disable enabled application without menu-update; inactive history never toggles',
    () async {
      final h = _Harness(
        enabled: true,
        permissions: {'MENU_VIEW', 'RECIPE_DELETE'},
      );
      var archives = 0;
      Future<Result<void>> archive() async {
        archives++;
        return const Success(null);
      }

      await h.controller.disableAndArchive(
        stateRecipe(menuItemId: 'i1'),
        archive,
      );
      expect(archives, 0);
      expect(h.writes, isEmpty);
      await h.controller.disableAndArchive(
        stateRecipe(menuItemId: 'i1', active: false),
        archive,
      );
      expect(archives, 1);
      expect(h.writes, isEmpty);
    },
  );
  test(
    'late GET cannot overwrite newer PATCH; ended scope cannot apply a late workflow',
    () async {
      final h = _Harness();
      final old = Completer<Result<MenuItem>>();
      var reads = 0;
      h.repo.onDetail = () =>
          reads++ == 0 ? old.future : Future.value(Success(item(version: 30)));
      final read = h.controller.load();
      await h.controller.setEnabled(true);
      old.complete(Success(item(version: 9)));
      await read;
      expect(h.controller.item!.version, 31);
      h.repo.onDetail = null;
      final pending = Completer<Result<MenuItem>>();
      h.onUpdate = (_) => pending.future;
      final disabling = h.controller.setEnabled(false);
      await Future<void>.delayed(Duration.zero);
      h.appSession = null;
      pending.complete(Success(item(version: 32)));
      expect(await disabling, isA<Error<MenuItem>>());
      expect(h.controller.item, null);
    },
  );
}
