import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';
import 'package:pos_saas_app/core/values/inventory_mode.dart';
import 'package:dio/dio.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_requests.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_inputs.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_item.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_price.dart';
import 'package:pos_saas_app/features/menu/domain/validation/menu_validation.dart';
import 'menu_fakes.dart' hide group;

UpdateMenuItemInput _changes(MenuItem baseline, InventoryMode? mode) =>
    UpdateMenuItemInput.changes(
      baseline,
      name: baseline.name,
      baseUnit: baseline.baseUnit,
      salePrice: baseline.salePrice,
      inventoryMode: mode,
      sku: baseline.sku ?? '',
      description: baseline.description ?? '',
      imageUrl: baseline.imageUrl ?? '',
    );

void main() {
  group('response', () {
    test('derives the mode and tolerates pre-V40 payloads', () {
      expect(item().inventoryMode, InventoryMode.none);
      expect(item(recipeEnabled: true).inventoryMode, InventoryMode.recipe);
      expect(item(trackInventory: true).inventoryMode, InventoryMode.direct);
    });
    test('accepts a matching inventoryMode', () {
      final parsed = MenuItemDto.fromJson({
        ...itemJson(trackInventory: true),
        'inventoryMode': 'DIRECT',
      }).toEntity();
      expect(parsed.trackInventory, true);
    });
    for (final bad in <String, Map<String, dynamic>>{
      'conflicting flags': itemJson(recipeEnabled: true, trackInventory: true),
      'mismatched mode': {...itemJson(), 'inventoryMode': 'DIRECT'},
      'unknown mode': {...itemJson(), 'inventoryMode': 'OTHER'},
      'non boolean flag': {...itemJson(), 'trackInventory': 'yes'},
    }.entries) {
      test('rejects ${bad.key}', () {
        expect(() => MenuItemDto.fromJson(bad.value), throwsFormatException);
      });
    }
  });

  group('requests', () {
    final price = MenuPrice.parse('15000');
    test('create only mentions trackInventory for direct items', () {
      final none = CreateMenuItemInput(
        name: 'Coca lon',
        baseUnit: 'lon',
        salePrice: price,
      );
      final direct = CreateMenuItemInput(
        name: 'Coca lon',
        baseUnit: 'lon',
        salePrice: price,
        trackInventory: true,
      );
      expect(
        MenuRequests.createItem(none).containsKey('trackInventory'),
        false,
      );
      expect(MenuRequests.createItem(direct)['trackInventory'], true);
      expect(
        MenuRequests.createItem(direct).containsKey('inventoryMode'),
        false,
      );
    });
    test('patch sends only the flags that change', () {
      final none = item(),
          recipe = item(recipeEnabled: true),
          direct = item(trackInventory: true);
      expect(_changes(none, InventoryMode.none).isEmpty, true);
      expect(_changes(none, null).isEmpty, true);
      final enable = _changes(none, InventoryMode.direct);
      expect(enable.isEmpty, false);
      expect(MenuRequests.updateItem(enable), {
        'trackInventory': true,
        'expectedVersion': 9,
      });
      expect(MenuRequests.updateItem(_changes(recipe, InventoryMode.direct)), {
        'recipeEnabled': false,
        'trackInventory': true,
        'expectedVersion': 9,
      });
      expect(MenuRequests.updateItem(_changes(direct, InventoryMode.recipe)), {
        'recipeEnabled': true,
        'trackInventory': false,
        'expectedVersion': 9,
      });
    });
    test('validation rejects both flags together', () {
      expect(
        MenuValidation.itemPatch(
          const UpdateMenuItemInput(
            expectedVersion: 1,
            recipeEnabled: true,
            trackInventory: true,
          ),
        ).containsKey('inventoryMode'),
        true,
      );
    });
  });

  test('direct stock error codes keep their type and a Vietnamese message', () {
    for (final entry in {
      'INVENTORY_TRACKING_MODE_CONFLICT': FailureType.conflict,
      'STOCK_TRACKING_CHANGE_NOT_ALLOWED': FailureType.conflict,
      'STOCK_ITEM_UNIT_CHANGE_NOT_ALLOWED': FailureType.conflict,
      'STOCK_ITEM_DELETE_NOT_ALLOWED': FailureType.conflict,
      'INVALID_STOCK_ITEM_REFERENCE': FailureType.validation,
    }.entries) {
      final options = RequestOptions(path: '/api/v1/menu/items');
      final failure = ApiErrorMapper.fromException(
        DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: entry.value == FailureType.conflict ? 409 : 400,
            data: {'code': entry.key, 'message': 'server text'},
          ),
        ),
      );
      expect(failure.type, entry.value, reason: entry.key);
      expect(failure.message, isNot('server text'), reason: entry.key);
    }
  });
}
