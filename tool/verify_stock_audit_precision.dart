import 'dart:convert';
import 'package:pos_saas_app/features/inventory/data/dto/stock_audit_dto.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_audit_requests.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_json.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_quantity.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_audit.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_audit_inputs.dart';

void main() {
  final row = StockAuditDto.item(
    decodeStockJson(r'''{
    "id":"ai1","ingredientId":"i1","sku":null,
    "name":"Nguyên liệu lịch sử","unit":"g",
    "systemQuantity":99999999999.999,"countedQuantity":0.001,
    "differenceQuantity":-99999999999.998,
    "referenceUnitCostSnapshot":999999999999.99,"note":null
  }'''),
  );
  check(row.systemQuantity.scaled.toString() == '99999999999999');
  check(row.countedQuantity!.scaled == 1);
  check(row.differenceQuantity!.scaled.toString() == '-99999999999998');
  check(row.referenceUnitCostSnapshot.cents.toString() == '99999999999999');
  check(
    StockAuditDifference.between(row.systemQuantity, row.systemQuantity).isZero,
  );
  check(StockAuditDifference.parse('-0').toString() == '0');
  check(
    StockAuditDifference.between(
          row.systemQuantity,
          InventoryQuantity.zero,
        ).toString() ==
        '99999999999.999',
  );
  final body = jsonEncode(
    StockAuditRequests.counts(
      StockAuditCountsInput(
        expectedVersion: 1,
        items: [
          StockAuditCountInput(
            auditItemId: 'ai1',
            countedQuantity: row.systemQuantity,
          ),
        ],
      ),
    ),
  );
  check(body.contains('"countedQuantity":99999999999.999'));
  final decoded = decodeStockJson(body) as Map<String, dynamic>;
  final item = (decoded['items'] as List).single as Map<String, dynamic>;
  check(
    stockNumberText(item['countedQuantity']) == row.systemQuantity.toString(),
  );
}

void check(bool condition) {
  if (!condition) throw StateError('Stock audit precision regression');
}
