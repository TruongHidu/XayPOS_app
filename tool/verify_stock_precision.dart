// Compile with dart compile js, then execute the output in Node/browser.
// This intentionally imports only the inventory code that is independent of Flutter.
import 'dart:convert';
import 'package:pos_saas_app/features/inventory/data/dto/stock_json.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_quantity.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_numbers.dart';

void main() {
  void check(bool value, String label) {
    if (!value) throw StateError(label);
  }

  final raw =
      decodeStockJson(
            '{"totalCost":9999999999999999.99,"totalQuantity":9999999999999.999,"note":"123.45"}',
          )
          as Map;
  check(
    StockMoney.parse(stockNumberText(raw['totalCost'])).cents ==
        BigInt.parse('999999999999999999'),
    'Large money lost precision',
  );
  check(
    StockQuantityTotal.parse(stockNumberText(raw['totalQuantity'])).scaled ==
        BigInt.parse('9999999999999999'),
    'Aggregate lost precision',
  );
  check(raw['note'] == '123.45', 'Quoted number changed');
  check(
    StockQuantityChange.parse('-0.001').scaled == -BigInt.one,
    'Signed delta lost precision',
  );
  final quantity = InventoryQuantity.parse('99999999999.999'),
      cost = StockMoney.unitCost('999999999999.99');
  final encoded = jsonEncode({
    'quantity': quantity.toNumber(),
    'unitCost': cost.toUnitCostNumber(),
  });
  final roundTrip = decodeStockJson(encoded) as Map;
  check(
    stockNumberText(roundTrip['quantity']) == quantity.toString(),
    'JSON quantity lost precision',
  );
  check(
    stockNumberText(roundTrip['unitCost']) == cost.toString(),
    'JSON unit cost lost precision',
  );
  check(
    stockLineCost(
          InventoryQuantity.parse('1.125'),
          StockMoney.unitCost('1234.56'),
        ).toString() ==
        '1388.88',
    'Preview lost precision',
  );
}
