import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_document_dto.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_document_requests.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_quantity.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_document.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_inputs.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_numbers.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_queries.dart';
import 'package:pos_saas_app/features/inventory/domain/repositories/stock_document_repository.dart';
import 'inventory_fakes.dart';

const stockPermissions = {
  ...inventoryPermissions,
  'INVENTORY_RECEIVE',
  'INVENTORY_ISSUE',
  'INVENTORY_ADJUST',
};
StockLineInput stockLine({
  String id = 'i1',
  String quantity = '2',
  String cost = '100',
  AdjustmentDirection? direction,
  String? note,
}) => StockLineInput(
  ingredientId: id,
  quantity: InventoryQuantity.parse(quantity),
  unitCost: StockMoney.unitCost(cost),
  direction: direction,
  note: note,
);
Map<String, dynamic> stockItemJson({
  String id = 'si1',
  String ingredient = 'i1',
  num quantity = 2,
  num cost = 100,
  String? direction,
  String? name,
  String unit = 'g',
  String? note,
}) => {
  'id': id,
  'ingredientId': ingredient,
  'ingredientSku': null,
  'ingredientName': name ?? 'Nguyên liệu $ingredient',
  'unit': unit,
  'quantity': quantity,
  'unitCost': cost,
  'adjustmentDirection': direction,
  'note': note,
  'totalCost': num.parse(
    stockLineCost(
      InventoryQuantity.fromNumber(quantity),
      StockMoney.unitCost(cost.toString()),
    ).toString(),
  ),
};
Map<String, dynamic> stockDetailJson({
  String id = 'd1',
  String warehouse = 'w1',
  String type = 'RECEIPT',
  String status = 'DRAFT',
  int version = 3,
  List<Map<String, dynamic>>? items,
  String? note = 'Nhập đầu ca',
  String? warehouseName,
}) {
  items ??= [
    stockItemJson(direction: type == 'ADJUSTMENT' ? 'INCREASE' : null),
  ];
  final q = items.fold(
    BigInt.zero,
    (sum, r) =>
        sum +
        BigInt.from(InventoryQuantity.fromNumber(r['quantity'] as num).scaled),
  );
  final cost = items.fold(
    BigInt.zero,
    (sum, r) => sum + StockMoney.parse(r['totalCost'].toString()).cents,
  );
  return {
    'id': id,
    'documentCode': 'RCV-20261018-$id',
    'documentType': type,
    'status': status,
    'warehouseId': warehouse,
    'warehouseCode': 'KHO-${warehouse.toUpperCase()}',
    'warehouseName': warehouseName ?? 'Kho chính',
    'note': note,
    'lineCount': items.length,
    'totalQuantity': num.parse(stockDecimal(q, 3)),
    'totalCost': num.parse(stockDecimal(cost, 2)),
    'items': items,
    'createdBy': 'user-1',
    'confirmedBy': status == 'CONFIRMED' ? 'user-1' : null,
    'cancelledBy': status == 'CANCELLED' ? 'user-1' : null,
    'version': version,
    'createdAt': '2026-10-18T01:00:00Z',
    'updatedAt': '2026-10-18T02:00:00Z',
    'confirmedAt': status == 'CONFIRMED' ? '2026-10-18T02:00:00Z' : null,
    'cancelledAt': status == 'CANCELLED' ? '2026-10-18T02:00:00Z' : null,
  };
}

StockDocumentDetail stockDocument({
  String id = 'd1',
  String type = 'RECEIPT',
  String status = 'DRAFT',
  int version = 3,
  List<Map<String, dynamic>>? items,
}) => StockDocumentDto.detail(
  stockDetailJson(
    id: id,
    type: type,
    status: status,
    version: version,
    items: items,
  ),
);
Map<String, dynamic> transactionJson({
  String id = 't1',
  String warehouse = 'w1',
  String ingredient = 'i1',
  String document = 'd1',
  String type = 'ISSUE',
  num change = -2,
  num before = 10,
  num after = 8,
  String? name,
}) => {
  'transactionId': id,
  'warehouseId': warehouse,
  'warehouseCode': 'KHO-${warehouse.toUpperCase()}',
  'ingredientId': ingredient,
  'ingredientSku': null,
  'ingredientName': name ?? 'Nguyên liệu $ingredient',
  'unit': 'g',
  'stockDocumentId': document,
  'documentCode': 'ISS-$document',
  'documentType': type.startsWith('ADJUSTMENT') ? 'ADJUSTMENT' : type,
  'transactionType': type,
  'quantityChange': change,
  'beforeQuantity': before,
  'afterQuantity': after,
  'unitCost': 100,
  'createdBy': 'user-1',
  'createdAt': '2026-10-18T02:00:00Z',
};

class FakeStockKeys implements StockKeyGenerator {
  int calls = 0;
  @override
  String next() => 'stock-key-${++calls}';
}

class FakeStockDocuments implements StockDocumentRepository {
  Map<String, dynamic> value = stockDetailJson();
  final queries = <StockDocumentQuery>[];
  final sentKeys = <String>[];
  final sentInputs = <CreateStockDocumentInput>[];
  int details = 0,
      updates = 0,
      adds = 0,
      edits = 0,
      deletes = 0,
      confirms = 0,
      cancels = 0;
  int? lastVersion;
  StockDocumentLineInput? lastLine;
  Future<Result<StockDocumentDetail>> Function(
    String,
    CreateStockDocumentInput,
  )?
  onCreate;
  Future<Result<StockDocumentDetail>> Function(String)? onDetail;
  Future<Result<StockDocumentDetail>> Function(String, UpdateStockDocumentNote)?
  onUpdate;
  Future<Result<StockDocumentDetail>> Function(String, StockDocumentLineInput)?
  onAdd;
  Future<Result<StockDocumentDetail>> Function(String, StockDocumentVersion)?
  onConfirm;
  Future<Result<InventoryPage<StockDocumentSummary>>> Function(
    StockDocumentQuery,
  )?
  onList;
  @override
  Future<Result<InventoryPage<StockDocumentSummary>>> list(
    StockDocumentQuery q,
  ) async {
    queries.add(q);
    return onList != null
        ? onList!(q)
        : Success(
            inventoryPage([StockDocumentDto.summary(value)], page: q.page),
          );
  }

  @override
  Future<Result<StockDocumentDetail>> detail(String id) async {
    details++;
    return onDetail != null
        ? onDetail!(id)
        : Success(StockDocumentDto.detail({...value, 'id': id}));
  }

  @override
  Future<Result<StockDocumentDetail>> create(
    String key,
    CreateStockDocumentInput input,
  ) async {
    sentKeys.add(key);
    sentInputs.add(input);
    if (onCreate != null) return onCreate!(key, input);
    value = stockDetailJson(
      id: 'created-1',
      warehouse: input.warehouseId,
      type: input.type.code,
      note: input.note,
      items: [
        for (final row in input.items)
          stockItemJson(
            id: 'line-${row.ingredientId}',
            ingredient: row.ingredientId,
            quantity: row.quantity.toNumber(),
            cost: row.unitCost.toUnitCostNumber(),
            direction: row.direction?.code,
            note: row.note,
          ),
      ],
    );
    return Success(StockDocumentDto.detail(value));
  }

  @override
  Future<Result<StockDocumentDetail>> update(
    String id,
    UpdateStockDocumentNote input,
  ) async {
    updates++;
    lastVersion = input.expectedVersion;
    if (onUpdate != null) return onUpdate!(id, input);
    value = {
      ...value,
      'note': StockDocumentRequests.note(input.note),
      'version': input.expectedVersion + 1,
    };
    return Success(StockDocumentDto.detail(value));
  }

  @override
  Future<Result<StockDocumentDetail>> addItem(
    String id,
    StockDocumentLineInput input,
  ) async {
    adds++;
    lastVersion = input.expectedVersion;
    lastLine = input;
    if (onAdd != null) return onAdd!(id, input);
    final row = input.line;
    value = stockDetailJson(
      id: id,
      type: value['documentType'],
      version: input.expectedVersion + 1,
      items: [
        ...(value['items'] as List).cast<Map<String, dynamic>>(),
        stockItemJson(
          id: 'line-${row.ingredientId}',
          ingredient: row.ingredientId,
          quantity: row.quantity.toNumber(),
          cost: row.unitCost.toUnitCostNumber(),
          direction: row.direction?.code,
          note: row.note,
        ),
      ],
    );
    return Success(StockDocumentDto.detail(value));
  }

  @override
  Future<Result<StockDocumentDetail>> updateItem(
    String id,
    String item,
    StockDocumentLineInput input,
  ) async {
    edits++;
    lastVersion = input.expectedVersion;
    lastLine = input;
    value = stockDetailJson(
      id: id,
      type: value['documentType'],
      version: input.expectedVersion + 1,
      items: [
        for (final row in (value['items'] as List).cast<Map<String, dynamic>>())
          row['id'] == item
              ? stockItemJson(
                  id: item,
                  ingredient: row['ingredientId'],
                  quantity: input.line.quantity.toNumber(),
                  cost: input.line.unitCost.toUnitCostNumber(),
                  direction: input.line.direction?.code,
                  note: input.line.note,
                )
              : row,
      ],
    );
    return Success(StockDocumentDto.detail(value));
  }

  @override
  Future<Result<void>> removeItem(
    String id,
    String item,
    StockDocumentVersion input,
  ) async {
    deletes++;
    lastVersion = input.expectedVersion;
    value = stockDetailJson(
      id: id,
      type: value['documentType'],
      version: input.expectedVersion + 1,
      items: (value['items'] as List)
          .cast<Map<String, dynamic>>()
          .where((r) => r['id'] != item)
          .toList(),
    );
    return const Success(null);
  }

  @override
  Future<Result<StockDocumentDetail>> confirm(
    String id,
    StockDocumentVersion input,
  ) async {
    confirms++;
    lastVersion = input.expectedVersion;
    if (onConfirm != null) return onConfirm!(id, input);
    value = stockDetailJson(
      id: id,
      type: value['documentType'],
      status: 'CONFIRMED',
      version: input.expectedVersion + 1,
      items: (value['items'] as List).cast<Map<String, dynamic>>(),
    );
    return Success(StockDocumentDto.detail(value));
  }

  @override
  Future<Result<StockDocumentDetail>> cancel(
    String id,
    StockDocumentVersion input,
  ) async {
    cancels++;
    lastVersion = input.expectedVersion;
    value = stockDetailJson(
      id: id,
      type: value['documentType'],
      status: 'CANCELLED',
      version: input.expectedVersion + 1,
      items: (value['items'] as List).cast<Map<String, dynamic>>(),
    );
    return Success(StockDocumentDto.detail(value));
  }
}

class FakeStockTransactions implements InventoryTransactionRepository {
  final queries = <InventoryTransactionQuery>[];
  List<InventoryTransaction> rows = [
    StockDocumentDto.transaction(transactionJson()),
  ];
  Future<Result<InventoryPage<InventoryTransaction>>> Function(
    InventoryTransactionQuery,
  )?
  onList;
  @override
  Future<Result<InventoryPage<InventoryTransaction>>> list(
    InventoryTransactionQuery q,
  ) async {
    queries.add(q);
    return onList != null
        ? onList!(q)
        : Success(
            inventoryPage(
              rows
                  .where(
                    (r) =>
                        (q.warehouseId == null ||
                            q.warehouseId == r.warehouseId) &&
                        (q.ingredientId == null ||
                            q.ingredientId == r.ingredientId) &&
                        (q.documentId == null ||
                            q.documentId == r.documentId) &&
                        (q.type == null || q.type == r.type),
                  )
                  .toList(),
              page: q.page,
            ),
          );
  }
}
