import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/values/item_type.dart';
import 'package:pos_saas_app/features/inventory/data/dto/inventory_alert_dto.dart';
import 'package:pos_saas_app/features/inventory/data/dto/inventory_dto.dart';
import 'package:pos_saas_app/features/inventory/data/dto/order_item_allocation_dto.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_audit_dto.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_document_dto.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_document_requests.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_item_ref_dto.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_document.dart';
import '../order/order_ingredient_fakes.dart';
import 'inventory_alert_fakes.dart';
import 'inventory_fakes.dart';
import 'stock_audit_fakes.dart';
import 'stock_fakes.dart';

Map<String, dynamic> direct(Map<String, dynamic> json, [String id = 'coca']) =>
    {...json, 'itemId': id, 'itemType': 'MENU_ITEM', 'ingredientId': null};

Map<String, dynamic> directUseJson() => direct({
  ...recipeUseJson(),
  'recipeUsageId': null,
  'transactionType': 'DIRECT_USE',
});

void main() {
  group('stock item reference', () {
    test('accepts legacy and V40 identities', () {
      expect(StockItemRefDto.parse({'ingredientId': 'i1'}), (
        stockItemId: 'i1',
        itemType: ItemType.ingredient,
      ));
      expect(
        StockItemRefDto.parse({
          'itemId': 'i1',
          'itemType': 'INGREDIENT',
          'ingredientId': 'i1',
        }),
        (stockItemId: 'i1', itemType: ItemType.ingredient),
      );
      expect(
        StockItemRefDto.parse({
          'itemId': 'coca',
          'itemType': 'MENU_ITEM',
          'ingredientId': null,
        }),
        (stockItemId: 'coca', itemType: ItemType.menuItem),
      );
    });
    for (final bad in <Map<String, dynamic>>[
      {},
      {'itemId': 'coca'},
      {'itemId': 'coca', 'itemType': 'OTHER'},
      {'itemId': 'coca', 'itemType': 'MENU_ITEM', 'ingredientId': 'coca'},
      {'itemId': 'i1', 'itemType': 'INGREDIENT', 'ingredientId': 'i2'},
      {'itemId': 'i1', 'itemType': 'INGREDIENT', 'ingredientId': null},
      {'itemId': ' ', 'itemType': 'MENU_ITEM'},
    ]) {
      test('rejects $bad', () {
        expect(() => StockItemRefDto.parse(bad), throwsFormatException);
      });
    }
  });

  test('menu item balances keep distinct identities', () {
    final rows = [
      InventoryDto.balance(direct(balanceJson(), 'coca')),
      InventoryDto.balance(direct(balanceJson(), 'pepsi')),
    ];
    expect(rows.map((r) => r.key).toSet().length, 2);
    expect(rows.first.itemType, ItemType.menuItem);
  });

  test('documents with menu item lines parse and send itemId', () {
    final value = StockDocumentDto.detail(
      stockDetailJson(
        items: [
          direct(stockItemJson(id: 's1'), 'coca'),
          direct(stockItemJson(id: 's2'), 'pepsi'),
        ],
      ),
    );
    expect(value.items.map((r) => r.stockItemId), ['coca', 'pepsi']);
    final body = StockDocumentRequests.line(stockLine(id: 'coca'));
    expect(body['itemId'], 'coca');
    expect(body.containsKey('ingredientId'), false);
    expect(
      StockDocumentRequests.line(
        stockLine(id: 'coca'),
        includeItem: false,
      ).containsKey('itemId'),
      false,
    );
  });

  group('DIRECT_USE ledger row', () {
    test('parses without a recipe usage', () {
      final row = StockDocumentDto.transaction(directUseJson());
      expect(row.type, InventoryTransactionType.directUse);
      expect(row.stockItemId, 'coca');
      expect(row.recipeUsageId, isNull);
      expect(row.unitCost, isNull);
    });
    final cases = <String, Map<String, dynamic>>{
      'recipe usage': {'recipeUsageId': 'u1'},
      'ingredient': {'itemType': 'INGREDIENT', 'ingredientId': 'coca'},
      'positive change': {
        'quantityChange': 2,
        'beforeQuantity': 8,
        'afterQuantity': 10,
      },
      'document source': {
        'sourceType': 'STOCK_DOCUMENT',
        'orderId': null,
        'orderItemId': null,
        'reservationId': null,
        'stockDocumentId': 'd1',
        'documentCode': 'ISS-d1',
        'documentType': 'ISSUE',
        'unitCost': 100,
      },
    };
    for (final entry in cases.entries) {
      test('rejects ${entry.key}', () {
        expect(
          () => StockDocumentDto.transaction({
            ...directUseJson(),
            ...entry.value,
          }),
          throwsFormatException,
        );
      });
    }
    test('RECIPE_USE still requires its usage', () {
      expect(
        () => StockDocumentDto.transaction({
          ...recipeUseJson(),
          'recipeUsageId': null,
        }),
        throwsFormatException,
      );
    });
  });

  test('audit rows and alerts accept menu items', () {
    expect(
      StockAuditDto.item(direct(stockAuditItemJson())).stockItemId,
      'coca',
    );
    expect(
      InventoryAlertDto.parse(direct(inventoryAlertJson())).itemType,
      ItemType.menuItem,
    );
  });

  group('direct allocation', () {
    Map<String, dynamic> allocation({
      bool snapshot = true,
      Object? usage,
      String type = 'MENU_ITEM',
    }) {
      final json = allocationJson();
      return {
        ...json,
        'inventoryMode': 'DIRECT',
        'directStockSnapshot': snapshot,
        'ingredients': [
          for (final row in json['ingredients'] as List)
            {
              ...row as Map<String, dynamic>,
              'recipeUsageId': usage,
              'itemId': 'coca',
              'itemType': type,
              'ingredientId': type == 'INGREDIENT' ? 'coca' : null,
            },
        ],
      };
    }

    test('parses a line without ingredient or usage', () {
      final value = OrderItemAllocationDto.parse(allocation());
      expect(value.directStock, true);
      expect(value.ingredients.single.stockItemId, 'coca');
      expect(value.ingredients.single.recipeUsageId, isNull);
    });
    test('rejects lines that contradict the mode', () {
      for (final bad in [
        allocation(usage: 'usage-1'),
        allocation(type: 'INGREDIENT'),
        allocation(snapshot: false),
      ]) {
        expect(() => OrderItemAllocationDto.parse(bad), throwsFormatException);
      }
    });
    test('payloads without the flag stay recipe based', () {
      expect(OrderItemAllocationDto.parse(allocationJson()).directStock, false);
    });
  });
}
