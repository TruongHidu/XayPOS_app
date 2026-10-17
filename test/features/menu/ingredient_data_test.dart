import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/menu/data/data_sources/menu_remote_data_source.dart';
import 'package:pos_saas_app/features/menu/data/dto/ingredient_dto.dart';
import 'package:pos_saas_app/features/menu/data/dto/ingredient_requests.dart';
import 'package:pos_saas_app/features/menu/data/repositories/ingredient_repository_impl.dart';
import 'package:pos_saas_app/features/menu/domain/entities/ingredient_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/ingredient_query.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_price.dart';
import 'package:pos_saas_app/features/menu/domain/validation/ingredient_validation.dart';
import 'ingredient_fakes.dart';

void main() {
  test(
    'six ingredient endpoints use direct responses, baseline versions and empty 204',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://ingredients.invalid'));
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests.add(request);
            final list =
                request.method == 'GET' &&
                request.path.endsWith('/ingredients');
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
                    : list
                    ? {
                        'content': [ingredientJson()],
                        'page': 0,
                        'size': 20,
                        'totalElements': 1,
                        'totalPages': 1,
                      }
                    : ingredientJson(),
              ),
            );
          },
        ),
      );
      final repository = IngredientRepositoryImpl(MenuRemoteDataSource(dio));
      expect(
        await repository.list(
          const IngredientQuery(
            q: r' bò%_\ ',
            active: false,
            trackInventory: false,
            sortBy: 'costPrice',
            direction: 'asc',
          ),
        ),
        isA<Success>(),
      );
      expect(await repository.detail('ingredient-1'), isA<Success>());
      expect(
        await repository.create(
          const CreateIngredientInput(
            name: ' Thịt bò ',
            baseUnit: ' g ',
            sku: ' nl-bo ',
          ),
        ),
        isA<Success>(),
      );
      expect(
        await repository.update(
          'ingredient-1',
          UpdateIngredientInput(
            expectedVersion: 4,
            sku: '',
            description: '',
            costPrice: MenuPrice.zero,
            trackInventory: false,
          ),
        ),
        isA<Success>(),
      );
      expect(
        await repository.setStatus('ingredient-1', false, 4),
        isA<Success>(),
      );
      expect(await repository.delete('ingredient-1', 4), isA<Success>());

      expect(requests.map((r) => '${r.method} ${r.path}'), [
        'GET /api/v1/menu/ingredients',
        'GET /api/v1/menu/ingredients/ingredient-1',
        'POST /api/v1/menu/ingredients',
        'PATCH /api/v1/menu/ingredients/ingredient-1',
        'PATCH /api/v1/menu/ingredients/ingredient-1/status',
        'DELETE /api/v1/menu/ingredients/ingredient-1',
      ]);
      expect(requests.first.queryParameters, {
        'q': r'bò%_\',
        'active': false,
        'trackInventory': false,
        'page': 0,
        'size': 20,
        'sortBy': 'costPrice',
        'direction': 'asc',
      });
      expect(requests[2].data, {
        'name': 'Thịt bò',
        'baseUnit': 'g',
        'sku': 'NL-BO',
        'costPrice': 0,
        'trackInventory': false,
        'active': true,
      });
      expect(requests[3].data, {
        'sku': '',
        'description': '',
        'costPrice': 0,
        'trackInventory': false,
        'expectedVersion': 4,
      });
      expect(requests[4].data, {'active': false, 'expectedVersion': 4});
      expect(requests.last.queryParameters, {'expectedVersion': 4});
      expect(requests.last.data, isNull);
    },
  );

  test('ingredient response does not require itemType or sale fields', () {
    final json = ingredientJson()
      ..['sku'] = null
      ..['description'] = null;
    final value = IngredientDto.fromJson(json).toEntity();
    expect(value.sku, isNull);
    expect(value.description, isNull);
    expect(value.costPrice, MenuPrice.parse('250.25'));
    expect(value.version, 4);
    expect(
      () => IngredientDto.fromJson({...json, 'costPrice': -1}),
      throwsFormatException,
    );
    expect(
      () => IngredientDto.fromJson({...json}..remove('costPrice')),
      throwsFormatException,
    );
    expect(
      () => IngredientDto.fromJson({...json, 'version': -1}),
      throwsFormatException,
    );
  });

  test(
    'patch distinguishes clearing text and cost from keeping unchanged fields',
    () {
      final initial = ingredient();
      final unchanged = UpdateIngredientInput.changes(
        initial,
        name: initial.name,
        baseUnit: 'g',
        sku: ' nl-bo ',
        description: initial.description!,
        trackInventory: true,
        costPrice: initial.costPrice,
      );
      expect(unchanged.isEmpty, isTrue);
      final clear = UpdateIngredientInput.changes(
        initial,
        name: initial.name,
        baseUnit: 'g',
        sku: '',
        description: '',
        trackInventory: false,
        costPrice: MenuPrice.zero,
      );
      expect(IngredientRequests.update(clear), {
        'sku': '',
        'description': '',
        'costPrice': 0,
        'trackInventory': false,
        'expectedVersion': 4,
      });
      final rename = UpdateIngredientInput.changes(
        initial,
        name: 'Mới',
        baseUnit: 'g',
        sku: 'NL-BO',
        description: initial.description!,
        trackInventory: true,
      );
      expect(IngredientRequests.update(rename), {
        'name': 'Mới',
        'expectedVersion': 4,
      });
    },
  );

  test(
    'ingredient validation enforces price precision and query allowlist',
    () {
      expect(IngredientValidation.costPrice('999999999999.99'), isNull);
      expect(IngredientValidation.costPrice(''), isNull);
      for (final invalid in ['-1', '1000000000000', '0.001', '1e3', '1,000']) {
        expect(IngredientValidation.costPrice(invalid), isNotNull);
      }
      expect(IngredientValidation.name('  '), isNotNull);
      expect(IngredientValidation.name('a' * 151), isNotNull);
      expect(IngredientValidation.baseUnit('g' * 31), isNotNull);
      expect(IngredientValidation.sku('a' * 81), isNotNull);
      expect(IngredientValidation.description('a' * 10001), isNotNull);
      expect(const IngredientQuery(sortBy: 'costPrice').isValid, isTrue);
      for (final query in [
        const IngredientQuery(size: 101),
        const IngredientQuery(page: -1),
        const IngredientQuery(sortBy: 'salePrice'),
        const IngredientQuery(direction: 'up'),
        IngredientQuery(q: 'a' * 101),
      ]) {
        expect(query.isValid, isFalse);
      }
    },
  );

  test(
    'ingredient conflict and not found errors map to Vietnamese messages',
    () {
      for (final code in [
        'INGREDIENT_NOT_FOUND',
        'SKU_EXISTS',
        'CONCURRENT_INGREDIENT_UPDATE',
        'INVALID_INGREDIENT_TRANSITION',
      ]) {
        final failure = ApiErrorMapper.fromException(
          DioException(
            requestOptions: RequestOptions(path: '/ingredients'),
            response: Response(
              requestOptions: RequestOptions(),
              statusCode: code == 'INGREDIENT_NOT_FOUND' ? 404 : 409,
              data: {
                'code': code,
                'message': 'raw backend message',
                'fieldErrors': {},
              },
            ),
            type: DioExceptionType.badResponse,
          ),
        );
        expect(failure.code, code);
        expect(failure.message, isNot('raw backend message'));
      }
    },
  );
}
