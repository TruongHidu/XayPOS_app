import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/exact_json.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/menu/data/data_sources/recipe_remote_data_source.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/menu/data/dto/recipe_cost_estimate_dto.dart';
import 'package:pos_saas_app/features/menu/data/repositories/recipe_repository_impl.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_cost_amount.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_cost_estimate.dart';
import 'package:pos_saas_app/features/menu/domain/policies/recipe_cost_comparison.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/recipe_cost_format.dart';
import 'menu_fakes.dart';
import 'recipe_cost_fakes.dart';

void main() {
  test(
    'real Dio transformer preserves decimal tokens instead of decoding doubles',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://recipe.invalid'));
      addTearDown(dio.close);
      dio.httpClientAdapter = _EstimateAdapter(
        jsonEncode(recipeCostJson())
            .replaceFirst('369000', '999999999999999999.99')
            .replaceFirst('1260.0', '0.0010001'),
      );
      final result =
          await RecipeRepositoryImpl(
                RecipeRemoteDataSource(dio),
              ).costEstimate('i1', 'r7')
              as Success<RecipeCostEstimate>;
      expect(result.value.totalBatchCost.toString(), '999999999999999999.99');
      expect(
        result.value.ingredients.first.grossQuantity.toString(),
        '0.0010001',
      );
    },
  );
  test(
    'GET has only scoped path and headers, no body or query and fresh data per call',
    () async {
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://recipe.invalid',
          headers: {'Authorization': 'Bearer token'},
        ),
      );
      addTearDown(dio.close);
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests.add(r);
            h.resolve(
              Response(
                requestOptions: r,
                statusCode: 200,
                data: jsonEncode(
                  recipeCostJson(
                    recipe: 'r / 7',
                    cost: requests.length == 1 ? 36900 : 40000,
                  ),
                ),
              ),
            );
          },
        ),
      );
      final repository = RecipeRepositoryImpl(RecipeRemoteDataSource(dio));
      final first =
          await repository.costEstimate('i1', 'r / 7')
              as Success<RecipeCostEstimate>;
      final second =
          await repository.costEstimate('i1', 'r / 7')
              as Success<RecipeCostEstimate>;
      expect(first.value.costPerYieldUnit.toString(), '36900');
      expect(second.value.costPerYieldUnit.toString(), '40000');
      for (final r in requests) {
        expect(r.method, 'GET');
        expect(
          r.path,
          '/api/v1/menu/items/i1/recipes/r%20%2F%207/cost-estimate',
        );
        expect(r.data, isNull);
        expect(r.queryParameters, isEmpty);
        expect(r.responseType, ResponseType.plain);
        expect(r.headers['Accept'], 'application/json');
        expect(r.headers['Authorization'], 'Bearer token');
        expect(r.headers['Idempotency-Key'], isNull);
        expect(r.headers['Cache-Control'], 'no-store');
      }
    },
  );

  test(
    'numeric lexemes preserve tiny gross quantity, exponents and large money',
    () {
      final raw = jsonEncode(recipeCostJson())
          .replaceFirst('1260.0', '0.0010001')
          .replaceFirst('369000', '999999999999999999.99');
      final value = RecipeCostEstimateDto.fromJson(decodeExactJson(raw));
      expect(value.ingredients.first.grossQuantity.toString(), '0.0010001');
      expect(value.totalBatchCost.toString(), '999999999999999999.99');
      expect(
        recipeCostNumber(value.ingredients.first.grossQuantity),
        '0,0010001',
      );
      expect(RecipeCostAmount.parse('1.0001e-3').toString(), '0.0010001');
      expect(
        RecipeCostAmount.parse('1e18', money: true).cents.toString(),
        '100000000000000000000',
      );
      expect(
        exactJsonNumberText(
          (decodeExactJson('{"n":1e-7,"text":"note 12 \\" 34"}') as Map)['n'],
        ),
        '1e-7',
      );
    },
  );

  test(
    'zero is valid, warnings deduplicate, malformed fields never become zero',
    () {
      final json = recipeCostJson(zero: true);
      (json['warnings'] as List).add((json['warnings'] as List).first);
      final value = RecipeCostEstimateDto.fromJson(json);
      expect(value.costPerYieldUnit.isZero, isTrue);
      expect(value.warnings, hasLength(2));
      for (final key in [
        'totalBatchCost',
        'costPerYieldUnit',
        'yieldQuantity',
        'recipeActive',
        'currencyCode',
        'estimatedAt',
      ]) {
        expect(
          () => RecipeCostEstimateDto.fromJson({...json, key: null}),
          throwsFormatException,
        );
      }
      for (final invalid in [-1, '0', 0.001]) {
        expect(
          () => RecipeCostEstimateDto.fromJson({
            ...json,
            'totalBatchCost': invalid,
          }),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'wrong identity and 409 error envelopes are mapped rather than accepted as estimate',
    () async {
      final dio = Dio();
      addTearDown(dio.close);
      String? code;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            if (code == null) {
              h.resolve(
                Response(
                  requestOptions: r,
                  statusCode: 200,
                  data: jsonEncode(recipeCostJson(recipe: 'other')),
                ),
              );
            } else {
              h.reject(
                DioException(
                  requestOptions: r,
                  response: Response(
                    requestOptions: r,
                    statusCode: 409,
                    data: jsonEncode({
                      'success': false,
                      'code': code,
                      'message': 'Backend message',
                      'fieldErrors': {},
                    }),
                  ),
                  type: DioExceptionType.badResponse,
                ),
              );
            }
          },
        ),
      );
      final repository = RecipeRepositoryImpl(RecipeRemoteDataSource(dio));
      expect(await repository.costEstimate('i1', 'r7'), isA<Error>());
      for (final error in [
        'INGREDIENT_COST_UNIT_MISMATCH',
        'INGREDIENT_COST_UNAVAILABLE',
        'INVALID_INGREDIENT_REFERENCE_COST',
        'INVALID_RECIPE_COST_DATA',
      ]) {
        code = error;
        final result = await repository.costEstimate('i1', 'r7') as Error;
        expect(result.failure.type, FailureType.conflict);
        expect(result.failure.code, error);
        expect(result.failure.message, isNot('Backend message'));
      }
    },
  );

  test(
    'comparison uses per-yield cost, cents, HALF_UP percent and guarded denominators',
    () {
      final estimate = RecipeCostEstimateDto.fromJson(recipeCostJson());
      final item = MenuItemDto.fromJson(
        itemJson()
          ..['salePrice'] = 60000
          ..['baseUnit'] = 'tô',
      ).toEntity();
      final result = RecipeCostComparison.evaluate(
        estimate,
        item,
        saleCurrencyCode: 'VND',
      );
      expect(result.differenceCents, BigInt.from(2310000));
      expect(recipeCostPercent(result.costPercentTenths!), '61,5%');
      expect(recipeCostCents(result.differenceCents!, 'VND'), '23.100 VND');
      for (final currency in [null, 'USD']) {
        expect(
          RecipeCostComparison.evaluate(
            estimate,
            item,
            saleCurrencyCode: currency,
          ).comparable,
          isFalse,
        );
      }
      final different = MenuItemDto.fromJson(itemJson()).toEntity();
      expect(
        RecipeCostComparison.evaluate(
          estimate,
          different,
          saleCurrencyCode: 'VND',
        ).comparable,
        isFalse,
      );
      final zero = MenuItemDto.fromJson(
        itemJson()
          ..['salePrice'] = 0
          ..['baseUnit'] = 'tô',
      ).toEntity();
      final loss = RecipeCostComparison.evaluate(
        estimate,
        zero,
        saleCurrencyCode: 'VND',
      );
      expect(loss.costPercentTenths, isNull);
      expect(loss.differenceCents!.isNegative, isTrue);
      final rounding = RecipeCostComparison.evaluate(
        RecipeCostEstimateDto.fromJson(recipeCostJson(cost: 0.01)),
        MenuItemDto.fromJson(
          itemJson()
            ..['salePrice'] = 16
            ..['baseUnit'] = 'tô',
        ).toEntity(),
        saleCurrencyCode: 'VND',
      );
      expect(rounding.costPercentTenths, BigInt.one); // 0.0625% -> 0.1%.
    },
  );
}

class _EstimateAdapter implements HttpClientAdapter {
  _EstimateAdapter(this.body);
  final String body;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    200,
    headers: {
      'content-type': ['application/json'],
      'cache-control': ['no-store'],
    },
  );
  @override
  void close({bool force = false}) {}
}
