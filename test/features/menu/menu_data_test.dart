import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/menu/data/data_sources/menu_remote_data_source.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_requests.dart';
import 'package:pos_saas_app/features/menu/data/repositories/menu_item_repository_impl.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_item.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_price.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_query.dart';
import 'package:pos_saas_app/features/menu/domain/validation/menu_validation.dart';
import 'menu_fakes.dart';

void main() {
  test(
    'all 14 endpoints use direct bodies, exact verbs, baseline versions and 204',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://menu.invalid'));
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests.add(request);
            final entity = request.path.contains('/groups')
                ? groupJson()
                : itemJson();
            final list =
                request.method == 'GET' &&
                (request.path.endsWith('/groups') ||
                    request.path.endsWith('/items'));
            handler.resolve(
              Response(
                requestOptions: request,
                statusCode: request.method == 'DELETE' ? 204 : 200,
                data: request.method == 'DELETE'
                    ? null
                    : list
                    ? {
                        'content': [entity],
                        'page': 0,
                        'size': 20,
                        'totalElements': 1,
                        'totalPages': 1,
                      }
                    : entity,
              ),
            );
          },
        ),
      );
      final api = MenuRemoteDataSource(dio);
      expect(
        (await api.listGroups(
          const MenuQuery(q: ' tea ', active: false),
        )).toEntity().content.single.version,
        7,
      );
      await api.getGroup('g1');
      await api.createGroup(
        const CreateMenuGroupInput(name: ' Tea ', displayOrder: 2),
      );
      await api.updateGroup(
        'g1',
        const UpdateMenuGroupInput(expectedVersion: 7, name: 'Hot'),
      );
      await api.setGroupStatus('g1', false, 7);
      await api.deleteGroup('g1', 7);
      await api.listItems(
        const MenuQuery(
          groupId: 'g1',
          availabilityStatus: AvailabilityStatus.outOfStock,
          sellable: false,
        ),
      );
      await api.getItem('i1');
      await api.createItem(
        CreateMenuItemInput(
          name: ' Tea ',
          baseUnit: ' cup ',
          salePrice: MenuPrice.parse('999999999999.99'),
        ),
      );
      await api.updateItem(
        'i1',
        const UpdateMenuItemInput(
          expectedVersion: 9,
          sku: '',
          description: '',
          imageUrl: '',
        ),
      );
      await api.setItemStatus('i1', false, 9);
      await api.setAvailability('i1', AvailabilityStatus.outOfStock, 9);
      await api.setGroup('i1', null, 9);
      await api.deleteItem('i1', 9);
      expect(requests.map((r) => '${r.method} ${r.path}'), [
        'GET /api/v1/menu/groups',
        'GET /api/v1/menu/groups/g1',
        'POST /api/v1/menu/groups',
        'PATCH /api/v1/menu/groups/g1',
        'PATCH /api/v1/menu/groups/g1/status',
        'DELETE /api/v1/menu/groups/g1',
        'GET /api/v1/menu/items',
        'GET /api/v1/menu/items/i1',
        'POST /api/v1/menu/items',
        'PATCH /api/v1/menu/items/i1',
        'PATCH /api/v1/menu/items/i1/status',
        'PATCH /api/v1/menu/items/i1/availability',
        'PUT /api/v1/menu/items/i1/group',
        'DELETE /api/v1/menu/items/i1',
      ]);
      expect(requests[0].queryParameters, {
        'q': 'tea',
        'active': false,
        'page': 0,
        'size': 20,
        'sortBy': 'createdAt',
        'direction': 'desc',
      });
      expect(requests[2].data, {
        'name': 'Tea',
        'displayOrder': 2,
        'active': true,
      });
      expect(requests[3].data, {'name': 'Hot', 'expectedVersion': 7});
      expect(requests[4].data, {'active': false, 'expectedVersion': 7});
      expect(requests[5].queryParameters, {'expectedVersion': 7});
      expect(
        requests[6].queryParameters,
        containsPair('availabilityStatus', 'OUT_OF_STOCK'),
      );
      expect(requests[6].queryParameters, containsPair('sellable', false));
      expect(requests[8].data['salePrice'], isA<num>());
      // An untouched price must not explicitly configure zero after V37.
      expect((requests[8].data as Map).containsKey('costPrice'), false);
      expect(requests[8].data['recipeEnabled'], false);
      expect(jsonEncode(requests[8].data), contains('999999999999.99'));
      expect(requests[9].data, {
        'sku': '',
        'description': '',
        'imageUrl': '',
        'expectedVersion': 9,
      });
      expect(requests[10].data, {'active': false, 'expectedVersion': 9});
      expect(requests[11].data, {
        'availabilityStatus': 'OUT_OF_STOCK',
        'expectedVersion': 9,
      });
      expect(requests[12].data, {'groupId': null, 'expectedVersion': 9});
      expect(requests[13].queryParameters, {'expectedVersion': 9});
      for (final request in requests) {
        for (final field in [
          'restaurantId',
          'itemType',
          'trackInventory',
          'createdBy',
        ]) {
          expect(request.queryParameters.containsKey(field), false);
          if (request.data is Map) {
            expect((request.data as Map).containsKey(field), false);
          }
        }
      }
    },
  );
  test(
    'DTO rejects malformed mandatory data instead of fabricating defaults',
    () {
      for (final key in [
        'id',
        'name',
        'baseUnit',
        'salePrice',
        'costConfigured',
        'recipeEnabled',
        'active',
        'sellable',
        'availabilityStatus',
        'version',
        'createdAt',
        'updatedAt',
      ]) {
        expect(
          () => MenuItemDto.fromJson(itemJson()..remove(key)),
          throwsFormatException,
          reason: key,
        );
      }
      for (final entry in {
        'version': -1,
        'salePrice': '35000',
        'availabilityStatus': 'UNKNOWN',
        'active': 'true',
        'costConfigured': 0,
        'recipeEnabled': 'false',
        'createdAt': 'yesterday',
      }.entries) {
        expect(
          () => MenuItemDto.fromJson(itemJson()..[entry.key] = entry.value),
          throwsFormatException,
        );
      }
      for (final key in groupJson().keys) {
        expect(
          () => MenuGroupDto.fromJson(groupJson()..remove(key)),
          throwsFormatException,
          reason: key,
        );
      }
      final ungrouped = MenuItemDto.fromJson(
        itemJson()
          ..['group'] = null
          ..['sku'] = null,
      ).toEntity();
      expect(ungrouped.group, isNull);
      expect(ungrouped.sku, isNull);
      expect(
        MenuItemDto.fromJson(itemJson(sellable: false)).toEntity().sellable,
        false,
      );
      expect(
        () => MenuItemDto.fromJson({'data': itemJson()}),
        throwsFormatException,
      );
    },
  );
  test('exact decimal parsing, changed fields and explicit clears', () {
    expect(MenuPrice.parse('0').minorUnits, 0);
    expect(MenuPrice.parse('0.1'), MenuPrice.parse('0.10'));
    expect(MenuPrice.parse('999999999999.99').minorUnits, 99999999999999);
    for (final value in [
      '-1',
      'NaN',
      'Infinity',
      '1.001',
      '1000000000000',
      '35,000',
      '1e2',
      '',
    ]) {
      expect(
        () => MenuPrice.parse(value),
        throwsFormatException,
        reason: value,
      );
    }
    final baseline = item();
    final same = UpdateMenuItemInput.changes(
      baseline,
      name: baseline.name,
      baseUnit: 'ly',
      salePrice: MenuPrice.parse('35000.50'),
      sku: 'TEA',
      description: '',
      imageUrl: '',
    );
    expect(same.isEmpty, true);
    final patch = UpdateMenuItemInput.changes(
      baseline,
      name: baseline.name,
      baseUnit: 'ly',
      salePrice: baseline.salePrice,
      sku: '',
      description: '',
      imageUrl: '',
    );
    expect(MenuRequests.updateItem(patch), {'sku': '', 'expectedVersion': 9});
  });
  test(
    'costPrice reads decimals, defaults explicit null to zero and preserves unknown omitted values',
    () {
      expect(
        MenuItemDto.fromJson(
          itemJson()..['costPrice'] = null,
        ).toEntity().costPrice,
        MenuPrice.zero,
      );
      expect(
        MenuItemDto.fromJson(
          itemJson()..['costPrice'] = 0,
        ).toEntity().costPrice,
        MenuPrice.zero,
      );
      expect(
        MenuItemDto.fromJson(
          itemJson()..['costPrice'] = 12500.50,
        ).toEntity().costPrice,
        MenuPrice.parse('12500.50'),
      );
      expect(MenuItemDto.fromJson(itemJson()).toEntity().costPrice, isNull);
      for (final invalid in [-1, 0.001, 1000000000000, '12500', true]) {
        expect(
          () => MenuItemDto.fromJson(itemJson()..['costPrice'] = invalid),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'untouched create cost is omitted; PATCH omission keeps cost and explicit zero configures it',
    () {
      final create = CreateMenuItemInput(
        name: 'Tea',
        baseUnit: 'cup',
        salePrice: MenuPrice.parse('35000'),
      );
      expect(create.costPrice, isNull);
      expect(MenuRequests.createItem(create).containsKey('costPrice'), false);
      expect(
        MenuRequests.createItem(create).containsKey('costConfigured'),
        false,
      );
      expect(
        MenuRequests.updateItem(
          const UpdateMenuItemInput(expectedVersion: 9, name: 'Changed'),
        ),
        {'name': 'Changed', 'expectedVersion': 9},
      );
      final reset = UpdateMenuItemInput(
        expectedVersion: 9,
        costPrice: MenuPrice.zero,
      );
      expect(reset.isEmpty, false);
      expect(MenuRequests.updateItem(reset), {
        'costPrice': 0,
        'expectedVersion': 9,
      });
    },
  );
  test(
    'explicit cost PATCH preserves intent even when equal and sends numeric decimal',
    () async {
      final baseline = MenuItemDto.fromJson(
        itemJson()..['costPrice'] = 12500.5,
      ).toEntity();
      UpdateMenuItemInput changes(MenuPrice? cost) =>
          UpdateMenuItemInput.changes(
            baseline,
            name: baseline.name,
            baseUnit: baseline.baseUnit,
            salePrice: baseline.salePrice,
            sku: baseline.sku ?? '',
            description: '',
            imageUrl: '',
            costPrice: cost,
          );
      expect(changes(MenuPrice.parse('12500.50')).isEmpty, false);
      final changed = changes(MenuPrice.parse('999999999999.99'));
      expect(changed.isEmpty, false);
      final requests = <RequestOptions>[];
      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests.add(r);
            h.resolve(
              Response(
                requestOptions: r,
                data: itemJson()..['costPrice'] = 999999999999.99,
              ),
            );
          },
        ),
      );
      await MenuRemoteDataSource(dio).updateItem(baseline.id, changed);
      expect(requests.single.method, 'PATCH');
      expect(
        requests.single.data.keys,
        unorderedEquals(['costPrice', 'expectedVersion']),
      );
      expect(requests.single.data['costPrice'], isA<num>());
      expect(jsonEncode(requests.single.data), contains('999999999999.99'));
      expect(requests.single.data['expectedVersion'], baseline.version);
      expect(MenuRequests.updateItem(changes(MenuPrice.zero)), {
        'costPrice': 0,
        'expectedVersion': 9,
      });
    },
  );
  test(
    'optional cost price accepts blank/null as zero but does not round invalid prices',
    () {
      expect(MenuPrice.parseOrZero(null), MenuPrice.zero);
      expect(MenuPrice.parseOrZero('  '), MenuPrice.zero);
      expect(MenuValidation.optionalPrice(null), isNull);
      expect(MenuValidation.optionalPrice(''), isNull);
      expect(MenuValidation.optionalPrice('0.01'), isNull);
      expect(MenuValidation.optionalPrice('999999999999.99'), isNull);
      for (final invalid in ['-1', '1.001', '1000000000000', 'null']) {
        expect(MenuValidation.optionalPrice(invalid), isNotNull);
      }
    },
  );
  test('validation and allowed query fields', () {
    for (final url in [
      'ftp://example.com/a',
      'https://u:p@example.com/a',
      '/photo.jpg',
      'https://',
      'https://example.com/a b',
    ]) {
      expect(MenuValidation.imageUrl(url), isNotNull);
    }
    expect(MenuValidation.imageUrl('https://example.com/a.png'), isNull);
    expect(MenuValidation.imageUrl(''), isNull);
    expect(const MenuQuery(size: 101).isValid(items: true), false);
    expect(const MenuQuery(sortBy: 'version').isValid(items: true), false);
    expect(const MenuQuery(groupId: 'g1').isValid(items: false), false);
    expect(const MenuQuery(sortBy: 'salePrice').isValid(items: false), false);
    expect(MenuRequests.query(const MenuQuery()).values, isNot(contains(null)));
  });
  test(
    'known menu errors preserve codes and field errors, hide internal details',
    () {
      const types = {
        'MENU_GROUP_NAME_EXISTS': FailureType.conflict,
        'SKU_EXISTS': FailureType.conflict,
        'MENU_GROUP_INACTIVE': FailureType.conflict,
        'MENU_GROUP_NOT_EMPTY': FailureType.conflict,
        'MENU_ITEM_NOT_FOUND': FailureType.notFound,
        'MENU_GROUP_NOT_FOUND': FailureType.notFound,
        'INVALID_MENU_ITEM_TRANSITION': FailureType.conflict,
        'CONCURRENT_MENU_UPDATE': FailureType.conflict,
        'INVALID_REQUEST_BODY': FailureType.validation,
        'EMPTY_UPDATE_REQUEST': FailureType.validation,
        'VALIDATION_ERROR': FailureType.validation,
        'FEATURE_NOT_ENTITLED': FailureType.featureNotEntitled,
        'SUBSCRIPTION_NOT_ACTIVE': FailureType.subscriptionNotActive,
        'FORBIDDEN': FailureType.forbidden,
        'UNAUTHORIZED': FailureType.unauthorized,
        'RESTAURANT_INACTIVE': FailureType.restaurantInactive,
        'INTERNAL_ERROR': FailureType.internal,
      };
      for (final entry in types.entries) {
        final request = RequestOptions(path: '/api/v1/menu/items');
        final failure = ApiErrorMapper.fromException(
          DioException(
            requestOptions: request,
            response: Response(
              requestOptions: request,
              statusCode: 400,
              data: {
                'code': entry.key,
                'message': 'database secret',
                'fieldErrors': {'name': 'Name error'},
              },
            ),
          ),
        );
        expect(failure.type, entry.value);
        expect(failure.code, entry.key);
        expect(failure.fieldErrors, {'name': 'Name error'});
        if (entry.value == FailureType.internal) {
          expect(failure.message, isNot(contains('secret')));
        }
      }
    },
  );
  test('repository converts invalid response to failure', () async {
    final dio = Dio();
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) => h.resolve(Response(requestOptions: r, data: {})),
      ),
    );
    final result = await MenuItemRepositoryImpl(
      MenuRemoteDataSource(dio),
    ).detail('i1');
    expect(result, isA<Error<MenuItem>>());
    expect((result as Error).failure.code, 'INVALID_MENU_RESPONSE');
  });
}
