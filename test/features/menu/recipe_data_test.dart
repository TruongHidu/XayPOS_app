import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/menu/data/data_sources/recipe_remote_data_source.dart';
import 'package:pos_saas_app/features/menu/data/dto/recipe_dto.dart';
import 'package:pos_saas_app/features/menu/data/dto/recipe_requests.dart';
import 'package:pos_saas_app/features/menu/data/repositories/recipe_repository_impl.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_amount.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_query.dart';
import 'package:pos_saas_app/features/menu/domain/validation/recipe_validation.dart';

void main() {
  test(
    'six recipe endpoints preserve exact API bodies and lock version',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://recipes.invalid',
          headers: {'Authorization': 'Bearer session-token'},
        ),
      );
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests.add(request);
            final history =
                request.method == 'GET' && request.path.endsWith('/recipes');
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: request.method == 'DELETE'
                    ? 204
                    : request.method == 'POST'
                    ? 201
                    : 200,
                data: request.method == 'DELETE'
                    ? null
                    : history
                    ? {
                        'content': [_summaryJson()],
                        'page': 2,
                        'size': 10,
                        'totalElements': 21,
                        'totalPages': 3,
                      }
                    : _recipeJson(),
              ),
            );
          },
        ),
      );
      final repository = RecipeRepositoryImpl(RecipeRemoteDataSource(dio));
      final active = await repository.active('menu-1') as Success<Recipe>;
      expect(active.value.recipeVersion, 42);
      expect(active.value.version, 0);
      final history = await repository.history(
        'menu-1',
        const RecipeQuery(
          page: 2,
          size: 10,
          sortBy: 'updatedAt',
          direction: 'asc',
        ),
      );
      expect(history, isA<Success>());
      expect((history as Success).value.content.single.ingredientCount, 2);
      expect(await repository.detail('menu-1', 'recipe-42'), isA<Success>());
      expect(await repository.create('menu-1', _input()), isA<Success>());
      expect(
        await repository.createVersion(
          'menu-1',
          active.value.id,
          CreateRecipeVersionInput(
            expectedVersion: active.value.version,
            yieldQuantity: _input().yieldQuantity,
            ingredients: _input().ingredients,
          ),
        ),
        isA<Success>(),
      );
      expect(
        await repository.deactivate(
          'menu-1',
          active.value.id,
          active.value.version,
        ),
        isA<Success>(),
      );
      expect(requests.map((request) => '${request.method} ${request.path}'), [
        'GET /api/v1/menu/items/menu-1/recipes/active',
        'GET /api/v1/menu/items/menu-1/recipes',
        'GET /api/v1/menu/items/menu-1/recipes/recipe-42',
        'POST /api/v1/menu/items/menu-1/recipes',
        'POST /api/v1/menu/items/menu-1/recipes/recipe-42/versions',
        'DELETE /api/v1/menu/items/menu-1/recipes/recipe-42',
      ]);
      expect(requests[1].queryParameters, {
        'page': 2,
        'size': 10,
        'sortBy': 'updatedAt',
        'direction': 'asc',
      });
      expect(requests[3].data, {
        'yieldQuantity': 10,
        'ingredients': [
          {
            'ingredientId': 'ingredient-1',
            'quantity': 1200.125,
            'wastePercent': 5.25,
          },
          {
            'ingredientId': 'ingredient-2',
            'quantity': 0.001,
            'wastePercent': 0,
          },
        ],
      });
      expect(requests[4].data, {
        ...requests[3].data as Map,
        'expectedVersion': 0,
      });
      expect(requests.last.queryParameters, {'expectedVersion': 0});
      expect(requests.last.data, isNull);
      for (final request in requests) {
        expect(request.headers['Accept'], Headers.jsonContentType);
        expect(request.headers['Authorization'], 'Bearer session-token');
        if (request.method == 'POST') {
          expect(request.contentType, Headers.jsonContentType);
        }
        final serialized = jsonEncode({
          'query': request.queryParameters,
          'data': request.data,
        });
        for (final forbidden in [
          'restaurantId',
          'yieldUnit',
          'recipeVersion',
          'active',
          'sku',
          'name',
          'unit',
          'metadata',
          'trackInventory',
          'costPrice',
        ]) {
          expect(
            serialized,
            isNot(contains('"$forbidden":')),
            reason: forbidden,
          );
        }
      }
    },
  );

  test(
    'recipe decimal values validate scales and bounds with exact equality',
    () {
      expect(RecipeQuantity.parse('999999999.999').scaledUnits, 999999999999);
      expect(RecipeQuantity.parse('0.001').scaledUnits, 1);
      expect(RecipeQuantity.parse('0001.000'), RecipeQuantity.parse('1'));
      expect(RecipeQuantity.parse('1.000').toString(), '1');
      expect(RecipeQuantity.parse('1200.120').toString(), '1200.12');
      expect(
        RecipeQuantity.parse('1').hashCode,
        RecipeQuantity.parse('1.000').hashCode,
      );
      expect(RecipeWastePercent.parseOrZero(null), RecipeWastePercent.zero);
      expect(
        RecipeWastePercent.parseOrZero('  '),
        RecipeWastePercent.parse('0.00'),
      );
      expect(RecipeWastePercent.parse('100').scaledUnits, 10000);
      expect(RecipeWastePercent.parse('0.01').scaledUnits, 1);
      expect(RecipeWastePercent.parse('5.20').toString(), '5.2');
      for (final invalid in [
        '',
        '0',
        '-1',
        '1000000000',
        '999999999.9999',
        '1.0000',
        '0.0001',
        'NaN',
        'Infinity',
        '1e3',
        '1,000',
        '1.',
        '.1',
        '+1',
      ]) {
        expect(
          () => RecipeQuantity.parse(invalid),
          throwsFormatException,
          reason: invalid,
        );
        expect(RecipeValidation.quantity(invalid), isNotNull);
      }
      for (final invalid in [
        '-0.01',
        '100.01',
        '101',
        '5.001',
        '1e2',
        'NaN',
        'Infinity',
      ]) {
        expect(
          () => RecipeWastePercent.parse(invalid),
          throwsFormatException,
          reason: invalid,
        );
        expect(RecipeValidation.wastePercent(invalid), isNotNull);
      }
      expect(
        () => RecipeQuantity.fromNumber(double.nan),
        throwsFormatException,
      );
      expect(
        () => RecipeWastePercent.fromNumber(double.infinity),
        throwsFormatException,
      );
      expect(RecipeValidation.quantity(null), isNotNull);
      expect(RecipeValidation.quantity('1.001'), isNull);
      expect(RecipeValidation.wastePercent(''), isNull);
      final encoded = RecipeRequests.create(
        RecipeInput(
          yieldQuantity: RecipeQuantity.parse('999999999.999'),
          ingredients: _input().ingredients,
        ),
      );
      expect(encoded['yieldQuantity'], isA<num>());
      expect(jsonEncode(encoded), contains('999999999.999'));
    },
  );

  test(
    'normalized recipe comparison ignores order and snapshots but detects actual changes',
    () {
      final baseline = RecipeDto.fromJson(_recipeJson()).toEntity();
      final unchanged = RecipeInput(
        yieldQuantity: RecipeQuantity.parse('10.000'),
        ingredients: _input().ingredients.reversed.toList(),
      );
      expect(unchanged.sameAs(baseline), isTrue);
      final snapshotChanged = RecipeDto.fromJson(
        _recipeJson()..['yieldUnit'] = 'đĩa mới',
      ).toEntity();
      expect(unchanged.sameAs(snapshotChanged), isTrue);
      expect(
        RecipeInput(
          yieldQuantity: RecipeQuantity.parse('11'),
          ingredients: unchanged.ingredients,
        ).sameAs(baseline),
        isFalse,
      );
      expect(
        RecipeInput(
          yieldQuantity: unchanged.yieldQuantity,
          ingredients: [
            RecipeIngredientInput(
              ingredientId: 'ingredient-1',
              quantity: RecipeQuantity.parse('1200.126'),
              wastePercent: RecipeWastePercent.parse('5.25'),
            ),
            unchanged.ingredients.first,
          ],
        ).sameAs(baseline),
        isFalse,
      );
      expect(
        RecipeInput(
          yieldQuantity: unchanged.yieldQuantity,
          ingredients: [
            RecipeIngredientInput(
              ingredientId: 'ingredient-1',
              quantity: RecipeQuantity.parse('1200.125'),
              wastePercent: RecipeWastePercent.parse('5.26'),
            ),
            unchanged.ingredients.first,
          ],
        ).sameAs(baseline),
        isFalse,
      );
      expect(
        RecipeInput(
          yieldQuantity: unchanged.yieldQuantity,
          ingredients: [
            unchanged.ingredients.first,
            unchanged.ingredients.first,
          ],
        ).sameAs(baseline),
        isFalse,
      );
    },
  );

  test(
    'recipe validation requires one to one hundred unique ingredients and valid lock versions',
    () {
      RecipeInput input(List<RecipeIngredientInput> ingredients) => RecipeInput(
        yieldQuantity: RecipeQuantity.parse('1'),
        ingredients: ingredients,
      );
      expect(RecipeValidation.input(input([])), contains('ingredients'));
      final lines = List.generate(
        100,
        (index) => RecipeIngredientInput(
          ingredientId: '$index',
          quantity: RecipeQuantity.parse('1'),
        ),
      );
      expect(RecipeValidation.input(input(lines)), isEmpty);
      expect(
        RecipeValidation.input(input([...lines, _input().ingredients.first])),
        contains('ingredients'),
      );
      expect(
        RecipeValidation.input(input([lines.first, lines.first])),
        contains('ingredients[1].ingredientId'),
      );
      expect(
        RecipeValidation.input(
          input([
            RecipeIngredientInput(
              ingredientId: ' ',
              quantity: RecipeQuantity.parse('1'),
            ),
          ]),
        ),
        contains('ingredients[0].ingredientId'),
      );
      expect(
        RecipeValidation.input(
          CreateRecipeVersionInput(
            expectedVersion: -1,
            yieldQuantity: RecipeQuantity.parse('1'),
            ingredients: [lines.first],
          ),
        ),
        contains('expectedVersion'),
      );
      expect(() => input(lines).ingredients.clear(), throwsUnsupportedError);
      expect(
        () => RecipeDto.fromJson(_recipeJson()).toEntity().ingredients.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('history query allowlist and defaults match contract', () {
    expect(RecipeRequests.query(const RecipeQuery()), {
      'page': 0,
      'size': 20,
      'sortBy': 'recipeVersion',
      'direction': 'desc',
    });
    for (final sortBy in ['recipeVersion', 'createdAt', 'updatedAt']) {
      expect(RecipeQuery(sortBy: sortBy).isValid, isTrue);
    }
    expect(const RecipeQuery().copyWith(page: 2).page, 2);
    for (final query in [
      const RecipeQuery(page: -1),
      const RecipeQuery(size: 0),
      const RecipeQuery(size: 101),
      const RecipeQuery(sortBy: 'version'),
      const RecipeQuery(direction: 'ASC'),
    ]) {
      expect(query.isValid, isFalse);
    }
  });

  test(
    'DTO preserves snapshot strings, summary has no details, mandatory malformed data is rejected',
    () {
      final recipe = RecipeDto.fromJson(_recipeJson()).toEntity();
      expect(recipe.ingredients.first.name, 'Thịt bò lịch sử');
      expect(recipe.ingredients.first.sku, ' BO-CU ');
      expect(recipe.ingredients.first.unit, 'g cũ');
      expect(recipe.ingredients.last.sku, isNull);
      expect(recipe.yieldUnit, 'tô cũ');
      final summary = RecipeSummaryDto.fromJson(_summaryJson()).toEntity();
      expect(summary.ingredientCount, 2);
      expect(() => RecipeDto.fromJson(_summaryJson()), throwsFormatException);
      expect(
        () => RecipeSummaryDto.fromJson(_recipeJson()),
        throwsFormatException,
      );
      for (final key in [
        'id',
        'menuItemId',
        'recipeVersion',
        'yieldQuantity',
        'yieldUnit',
        'active',
        'ingredients',
        'version',
        'createdAt',
        'updatedAt',
      ]) {
        expect(
          () => RecipeDto.fromJson(_recipeJson()..remove(key)),
          throwsFormatException,
          reason: key,
        );
      }
      for (final entry in <String, Object?>{
        'recipeVersion': 0,
        'version': -1,
        'yieldQuantity': '10.000',
        'active': 'true',
        'ingredients': [],
        'createdAt': '2026-02-30T00:00:00Z',
        'updatedAt': 'yesterday',
      }.entries) {
        expect(
          () => RecipeDto.fromJson(_recipeJson()..[entry.key] = entry.value),
          throwsFormatException,
          reason: entry.key,
        );
      }
      expect(
        () => RecipeDto.fromJson({'data': _recipeJson()}),
        throwsFormatException,
      );
      expect(
        () => RecipeIngredientDto.fromJson({
          ..._lineJson(),
          'wastePercent': 0.001,
        }),
        throwsFormatException,
      );
      expect(
        () => RecipeIngredientDto.fromJson({..._lineJson(), 'quantity': 0}),
        throwsFormatException,
      );
      expect(
        () => RecipeSummaryDto.fromJson({
          ..._summaryJson(),
          'ingredientCount': 101,
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'invalid mutations and queries fail validation before sending HTTP',
    () async {
      var calls = 0;
      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            calls++;
            handler.resolve(
              Response(requestOptions: request, data: _recipeJson()),
            );
          },
        ),
      );
      final repository = RecipeRepositoryImpl(RecipeRemoteDataSource(dio));
      expect(
        await repository.create(
          'menu-1',
          RecipeInput(
            yieldQuantity: RecipeQuantity.parse('1'),
            ingredients: [],
          ),
        ),
        isA<Error>(),
      );
      expect(
        await repository.createVersion(
          'menu-1',
          'recipe-42',
          CreateRecipeVersionInput(
            expectedVersion: -1,
            yieldQuantity: _input().yieldQuantity,
            ingredients: _input().ingredients,
          ),
        ),
        isA<Error>(),
      );
      expect(
        await repository.deactivate('menu-1', 'recipe-42', -1),
        isA<Error>(),
      );
      expect(
        await repository.history('menu-1', const RecipeQuery(size: 101)),
        isA<Error>(),
      );
      expect(calls, 0);
    },
  );

  test(
    'recipe errors preserve API code and field errors without auto retry',
    () async {
      const types = {
        'RECIPE_NOT_FOUND': FailureType.notFound,
        'ACTIVE_RECIPE_NOT_FOUND': FailureType.notFound,
        'MENU_ITEM_NOT_FOUND': FailureType.notFound,
        'INGREDIENT_NOT_FOUND': FailureType.notFound,
        'ACTIVE_RECIPE_ALREADY_EXISTS': FailureType.conflict,
        'RECIPE_NOT_ACTIVE': FailureType.conflict,
        'DUPLICATE_RECIPE_INGREDIENT': FailureType.conflict,
        'INGREDIENT_INACTIVE': FailureType.conflict,
        'SAME_RECIPE_VERSION_NOT_ALLOWED': FailureType.conflict,
        'CONCURRENT_RECIPE_UPDATE': FailureType.conflict,
        'VALIDATION_ERROR': FailureType.validation,
        'INVALID_REQUEST_BODY': FailureType.validation,
        'FORBIDDEN': FailureType.forbidden,
        'SUBSCRIPTION_NOT_ACTIVE': FailureType.subscriptionNotActive,
        'FEATURE_NOT_ENTITLED': FailureType.featureNotEntitled,
      };
      for (final entry in types.entries) {
        final request = RequestOptions(path: '/recipes');
        final failure = ApiErrorMapper.fromException(
          DioException(
            requestOptions: request,
            response: Response(
              requestOptions: request,
              statusCode: 409,
              data: {
                'success': false,
                'code': entry.key,
                'message': 'server message',
                'fieldErrors': {
                  'ingredients[0].quantity': 'Lượng dùng không hợp lệ.',
                },
              },
            ),
          ),
        );
        expect(failure.type, entry.value);
        expect(failure.code, entry.key);
        expect(failure.fieldErrors, {
          'ingredients[0].quantity': 'Lượng dùng không hợp lệ.',
        });
        if (entry.key == 'SAME_RECIPE_VERSION_NOT_ALLOWED') {
          expect(failure.message, 'Công thức chưa có thay đổi thực tế.');
        }
      }
      for (final errorCode in [
        'ACTIVE_RECIPE_NOT_FOUND',
        'MENU_ITEM_NOT_FOUND',
        'FORBIDDEN',
        'CONCURRENT_RECIPE_UPDATE',
      ]) {
        var calls = 0;
        final dio = Dio();
        addTearDown(dio.close);
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              calls++;
              handler.reject(
                DioException(
                  requestOptions: request,
                  response: Response(
                    requestOptions: request,
                    statusCode: 409,
                    data: {'code': errorCode, 'message': 'server message'},
                  ),
                ),
              );
            },
          ),
        );
        final result = await RecipeRepositoryImpl(
          RecipeRemoteDataSource(dio),
        ).active('menu-1');
        expect(result, isA<Error<Recipe>>());
        expect((result as Error).failure.code, errorCode);
        expect(calls, 1);
      }
      final dio = Dio();
      addTearDown(dio.close);
      var attempts = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            attempts++;
            handler.reject(
              DioException(
                requestOptions: request,
                type: DioExceptionType.receiveTimeout,
              ),
            );
          },
        ),
      );
      final result = await RecipeRepositoryImpl(
        RecipeRemoteDataSource(dio),
      ).create('menu-1', _input());
      expect((result as Error).failure.type, FailureType.network);
      expect(attempts, 1);
    },
  );

  test(
    'repository rejects malformed server data using recipe-specific failure',
    () async {
      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) =>
              handler.resolve(Response(requestOptions: request, data: {})),
        ),
      );
      final result = await RecipeRepositoryImpl(
        RecipeRemoteDataSource(dio),
      ).active('menu-1');
      expect(result, isA<Error<Recipe>>());
      expect((result as Error).failure.code, 'INVALID_RECIPE_RESPONSE');
    },
  );
}

RecipeInput _input() => RecipeInput(
  yieldQuantity: RecipeQuantity.parse('10.000'),
  ingredients: [
    RecipeIngredientInput(
      ingredientId: 'ingredient-1',
      quantity: RecipeQuantity.parse('1200.125'),
      wastePercent: RecipeWastePercent.parse('5.25'),
    ),
    RecipeIngredientInput(
      ingredientId: 'ingredient-2',
      quantity: RecipeQuantity.parse('0.001'),
    ),
  ],
);

Map<String, dynamic> _lineJson() => {
  'id': 'line-1',
  'ingredientId': 'ingredient-1',
  'sku': ' BO-CU ',
  'name': 'Thịt bò lịch sử',
  'unit': 'g cũ',
  'quantity': 1200.125,
  'wastePercent': 5.25,
};

Map<String, dynamic> _recipeJson() => {
  ..._summaryJson()..remove('ingredientCount'),
  'ingredients': [
    _lineJson(),
    {
      ..._lineJson(),
      'id': 'line-2',
      'ingredientId': 'ingredient-2',
      'sku': null,
      'quantity': 0.001,
      'wastePercent': 0,
    },
  ],
};

Map<String, dynamic> _summaryJson() => {
  'id': 'recipe-42',
  'menuItemId': 'menu-1',
  'recipeVersion': 42,
  'yieldQuantity': 10,
  'yieldUnit': 'tô cũ',
  'active': true,
  'ingredientCount': 2,
  'version': 0,
  'createdAt': '2026-10-15T01:00:00Z',
  'updatedAt': '2026-10-16T01:00:00Z',
};
