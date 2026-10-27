import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/exact_json.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/data/data_sources/order_recipe_snapshot_remote_data_source.dart';
import 'package:pos_saas_app/features/order/data/repositories/order_recipe_snapshot_repository_impl.dart';
import 'package:pos_saas_app/features/order/data/dto/order_recipe_snapshot_dto.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_recipe_snapshot.dart';
import 'package:pos_saas_app/features/inventory/data/data_sources/order_item_allocation_remote_data_source.dart';
import 'package:pos_saas_app/features/inventory/data/repositories/order_item_allocation_repository_impl.dart';
import 'package:pos_saas_app/features/inventory/data/dto/order_item_allocation_dto.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/order_item_allocation.dart';
import '../../helpers/auth_fakes.dart';
import 'order_ingredient_fakes.dart';

void main() {
  test(
    'source decisions preserve nullable history and reject malformed/contradictory metadata',
    () {
      final manual = OrderRecipeSnapshotDto.parse(
        snapshotJson(status: 'RECIPE_DISABLED'),
      );
      expect(manual.recipeEnabledSnapshot, false);
      expect(manual.costSourceSnapshot, RecipeCostSourceSnapshot.manual);
      expect(manual.capturedAt, isNotNull);
      expect(manual.ingredients, isEmpty);
      final unavailable = OrderRecipeSnapshotDto.parse(
        snapshotJson(status: 'FEATURE_DISABLED'),
      );
      expect(unavailable.recipeEnabledSnapshot, true);
      expect(unavailable.costSourceSnapshot, RecipeCostSourceSnapshot.recipe);
      for (final status in [
        'CAPTURED',
        'FEATURE_DISABLED',
        'NO_RECIPE',
        'LEGACY_UNAVAILABLE',
        'NOT_SUBMITTED',
      ]) {
        final legacy = snapshotJson(status: status, legacyDecision: true)
          ..remove('recipeEnabledSnapshot')
          ..remove('costSourceSnapshot');
        final snapshot = OrderRecipeSnapshotDto.parse(legacy);
        expect(snapshot.recipeEnabledSnapshot, null);
        expect(snapshot.costSourceSnapshot, null);
      }
      for (final raw in [
        snapshotJson()..['recipeEnabledSnapshot'] = 1,
        snapshotJson()..['costSourceSnapshot'] = false,
        snapshotJson()..['costSourceSnapshot'] = 'MENU_CURRENT',
        snapshotJson()..['costSourceSnapshot'] = 'MANUAL',
        snapshotJson(status: 'RECIPE_DISABLED')
          ..['recipeEnabledSnapshot'] = true,
        snapshotJson(status: 'RECIPE_DISABLED')..['capturedAt'] = null,
        snapshotJson(status: 'NOT_SUBMITTED')
          ..['costSourceSnapshot'] = 'RECIPE',
      ]) {
        expect(() => OrderRecipeSnapshotDto.parse(raw), throwsFormatException);
      }
    },
  );
  test(
    'disabled application and unavailable recipe feature keep distinct allocation decisions',
    () {
      final off = OrderItemAllocationDto.parse(
        allocationJson(status: 'SKIPPED', reason: 'SNAPSHOT_RECIPE_DISABLED'),
      );
      final feature = OrderItemAllocationDto.parse(
        allocationJson(status: 'SKIPPED', reason: 'SNAPSHOT_FEATURE_DISABLED'),
      );
      expect(off.skipReason, AllocationSkipReason.recipeApplicationDisabled);
      expect(feature.skipReason, AllocationSkipReason.recipeFeatureDisabled);
      expect(off.skipReason, isNot(feature.skipReason));
      expect(off.ingredients, isEmpty);
      expect(off.warehouseId, null);
      expect(off.reservedAt, null);
      expect(
        () => OrderItemAllocationDto.parse(
          allocationJson(status: 'RESERVED')
            ..['skipReason'] = 'SNAPSHOT_RECIPE_DISABLED',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'both GET endpoints use exact IDs, auth/no-store and no body/query/version/key',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://ingredients.invalid',
          headers: {'Authorization': 'Bearer token'},
        ),
      );
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests.add(r);
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: 200,
                data: jsonEncode(
                  r.path.endsWith('/allocation')
                      ? allocationJson(order: 'order / 1', line: 'line / 1')
                      : snapshotJson(order: 'order / 1', line: 'line / 1'),
                ),
              ),
            );
          },
        ),
      );
      final snapshots = OrderRecipeSnapshotRepositoryImpl(
        OrderRecipeSnapshotRemoteDataSource(dio),
      );
      final allocations = OrderItemAllocationRepositoryImpl(
        OrderItemAllocationRemoteDataSource(dio),
      );
      final snapshot =
          await snapshots.get('order / 1', 'line / 1')
              as Success<OrderRecipeSnapshot>;
      expect(snapshot.value.recipeVersion, 2);
      expect(
        snapshot.value.ingredients.first.requiredQuantity.toString(),
        '315',
      );
      expect(
        await allocations.get('order / 1', 'line / 1'),
        isA<Success<OrderItemAllocation>>(),
      );
      expect(requests.map((r) => r.path), [
        '/api/v1/orders/order%20%2F%201/items/line%20%2F%201/recipe-snapshot',
        '/api/v1/inventory/orders/order%20%2F%201/items/line%20%2F%201/allocation',
      ]);
      for (final r in requests) {
        expect(r.method, 'GET');
        expect(r.data, isNull);
        expect(r.queryParameters, isEmpty);
        expect(r.headers['Accept'], 'application/json');
        expect(r.headers['Authorization'], 'Bearer token');
        expect(r.headers['Cache-Control'], 'no-store');
        expect(r.headers['Idempotency-Key'], isNull);
        expect(r.responseType, ResponseType.plain);
      }
    },
  );
  test(
    'snapshot states preserve order quantity and status-specific nullable recipe metadata',
    () {
      for (final state in RecipeSnapshotStatus.values) {
        final snapshot = OrderRecipeSnapshotDto.parse(
          snapshotJson(status: state.code),
        );
        expect(snapshot.orderQuantity.toString(), '3');
        expect(snapshot.orderUnit, 'phần');
        expect(
          snapshot.ingredients.length,
          state == RecipeSnapshotStatus.captured ? 2 : 0,
        );
        expect(
          snapshot.ingredients.where((e) => !e.trackInventory).length,
          state == RecipeSnapshotStatus.captured ? 1 : 0,
        );
        if (state != RecipeSnapshotStatus.captured) {
          expect(snapshot.recipeId, isNull);
        }
      }
      expect(
        () =>
            OrderRecipeSnapshotDto.parse(snapshotJson()..['ingredients'] = []),
        throwsFormatException,
      );
      expect(
        () => OrderRecipeSnapshotDto.parse(
          snapshotJson(status: 'NO_RECIPE')..['recipeVersion'] = 2,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'allocation states retain historic rows and skipped reasons need no current warehouse',
    () {
      for (final state in AllocationStatus.values) {
        final allocation = OrderItemAllocationDto.parse(
          allocationJson(status: state.code),
        );
        expect(allocation.status, state);
        expect(
          allocation.ingredients.length,
          {
                AllocationStatus.skipped,
                AllocationStatus.notSubmitted,
              }.contains(state)
              ? 0
              : 1,
        );
        if (state == AllocationStatus.notSubmitted) {
          expect(allocation.id, isNull);
        }
      }
      for (final reason in AllocationSkipReason.values) {
        expect(
          OrderItemAllocationDto.parse(
            allocationJson(status: 'SKIPPED', reason: reason.code),
          ).skipReason,
          reason,
        );
      }
      expect(
        () => OrderItemAllocationDto.parse(
          allocationJson(status: 'CONSUMED')..['consumedAt'] = null,
        ),
        throwsFormatException,
      );
      expect(
        () => OrderItemAllocationDto.parse(
          allocationJson(status: 'NOT_SUBMITTED')..['warehouseId'] = 'w1',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'required quantities retain full 14,3 precision and do not recompute CEILING or cost',
    () {
      final raw = jsonEncode(
        snapshotJson(),
      ).replaceFirst('315.0', '99999999999.999').replaceFirst('0.3', '0.001');
      final value = OrderRecipeSnapshotDto.parse(decodeExactJson(raw));
      expect(
        value.ingredients.first.requiredQuantity.toString(),
        '99999999999.999',
      );
      expect(value.ingredients.last.requiredQuantity.toString(), '0.001');
      for (final invalid in [null, -1, '315', 0.0001]) {
        final raw = snapshotJson();
        raw['ingredients'][0] = <String, dynamic>{
          ...raw['ingredients'][0] as Map<String, dynamic>,
          'requiredQuantity': invalid,
        };
        expect(() => OrderRecipeSnapshotDto.parse(raw), throwsFormatException);
      }
    },
  );
  test(
    'identity mismatches and HTTP failures never become an empty successful snapshot',
    () async {
      final dio = Dio();
      addTearDown(dio.close);
      var wrong = true;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            if (wrong) {
              h.resolve(
                Response(
                  requestOptions: r,
                  statusCode: 200,
                  data: snapshotJson(line: 'another-line'),
                ),
              );
            } else {
              h.reject(
                DioException(
                  requestOptions: r,
                  type: DioExceptionType.badResponse,
                  response: Response(
                    requestOptions: r,
                    statusCode: 409,
                    data: jsonEncode({
                      'success': false,
                      'code': 'ORDER_ITEM_RECIPE_SNAPSHOT_CONFLICT',
                      'message': 'Conflict',
                      'fieldErrors': {},
                    }),
                  ),
                ),
              );
            }
          },
        ),
      );
      final repo = OrderRecipeSnapshotRepositoryImpl(
        OrderRecipeSnapshotRemoteDataSource(dio),
      );
      expect(
        (await repo.get('o1', 'line1') as Error).failure.type,
        FailureType.internal,
      );
      wrong = false;
      expect(
        (await repo.get('o1', 'line1') as Error).failure.type,
        FailureType.conflict,
      );
    },
  );
  test(
    'inspection rights require the full permission/feature intersection without changing command rights',
    () {
      for (final p in ingredientReadPermissions) {
        final s = makeAppSession(
          permissions: {...ingredientReadPermissions}..remove(p),
          features: ingredientReadFeatures,
        );
        expect(AccessPolicy.canViewOrderItemAllocation(s), isFalse);
        expect(
          AccessPolicy.canViewOrderRecipeSnapshot(s),
          p == 'INVENTORY_VIEW',
        );
      }
      for (final f in ingredientReadFeatures) {
        final s = makeAppSession(
          permissions: ingredientReadPermissions,
          features: {...ingredientReadFeatures}..remove(f),
        );
        expect(AccessPolicy.canViewOrderItemAllocation(s), isFalse);
      }
      final s = makeAppSession(
        permissions: {'ORDER_UPDATE'},
        features: {'ORDER_MANAGEMENT'},
      );
      expect(AccessPolicy.canOrders(s, 'ORDER_UPDATE'), isTrue);
      expect(AccessPolicy.canViewOrderRecipeSnapshot(s), isFalse);
    },
  );
}
