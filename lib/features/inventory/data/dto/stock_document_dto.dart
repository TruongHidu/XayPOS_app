import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/inventory_quantity.dart';
import '../../domain/entities/stock_document.dart';
import '../../domain/entities/stock_numbers.dart';
import 'inventory_dto.dart';
import 'stock_json.dart';

abstract final class StockDocumentDto {
  static int integer(Map<String, dynamic> j, String key) {
    final raw = stockNumberText(j[key]);
    if (!RegExp(r'^\d+$').hasMatch(raw)) throw FormatException('Invalid $key');
    final value = BigInt.parse(raw);
    if (value > BigInt.parse('9007199254740991')) {
      throw FormatException('Unsafe $key');
    }
    return value.toInt();
  }

  static T enumeration<T>(
    Object? value,
    Iterable<T> values,
    String Function(T) code,
  ) =>
      values.where((v) => code(v) == value).firstOrNull ??
      (throw const FormatException('Unsupported stock enum'));
  static StockMoney money(
    Map<String, dynamic> j,
    String key, [
    int digits = 16,
  ]) => StockMoney.parse(stockNumberText(j[key]), integerDigits: digits);
  static InventoryQuantity quantity(Map<String, dynamic> j, String key) =>
      InventoryQuantity.parse(stockNumberText(j[key]));
  static StockDocumentSummary summary(Object? raw) {
    final j = InventoryDto.object(raw);
    return StockDocumentSummary(
      id: InventoryDto.text(j, 'id'),
      stockAuditId: j['stockAuditId'] == null
          ? null
          : InventoryDto.text(j, 'stockAuditId'),
      documentCode: InventoryDto.text(j, 'documentCode'),
      type: enumeration(
        j['documentType'],
        StockDocumentType.values,
        (v) => v.code,
      ),
      status: enumeration(
        j['status'],
        StockDocumentStatus.values,
        (v) => v.code,
      ),
      warehouseId: InventoryDto.text(j, 'warehouseId'),
      warehouseCode: InventoryDto.text(j, 'warehouseCode'),
      warehouseName: InventoryDto.text(j, 'warehouseName'),
      note: InventoryDto.optionalText(j, 'note'),
      lineCount: integer(j, 'lineCount'),
      totalQuantity: StockQuantityTotal.parse(
        stockNumberText(j['totalQuantity']),
      ),
      totalCost: money(j, 'totalCost'),
      createdBy: InventoryDto.text(j, 'createdBy'),
      version: integer(j, 'version'),
      createdAt: InventoryDto.date(j, 'createdAt')!,
      updatedAt: InventoryDto.date(j, 'updatedAt')!,
    );
  }

  static StockDocumentItem item(Object? raw, StockDocumentType type) {
    final j = InventoryDto.object(raw),
        direction = j['adjustmentDirection'] == null
            ? null
            : enumeration(
                j['adjustmentDirection'],
                AdjustmentDirection.values,
                (v) => v.code,
              );
    final result = StockDocumentItem(
      id: InventoryDto.text(j, 'id'),
      ingredientId: InventoryDto.text(j, 'ingredientId'),
      ingredientSku: InventoryDto.optionalText(j, 'ingredientSku'),
      ingredientName: InventoryDto.text(j, 'ingredientName'),
      unit: InventoryDto.text(j, 'unit'),
      quantity: quantity(j, 'quantity'),
      direction: direction,
      unitCost: money(j, 'unitCost', 12),
      totalCost: money(j, 'totalCost', 14),
      note: InventoryDto.optionalText(j, 'note'),
    );
    if (result.quantity.scaled <= 0 ||
        (type == StockDocumentType.adjustment) != (direction != null)) {
      throw const FormatException('Invalid stock item');
    }
    // Server total is authoritative; do not derive it using a guessed rounding rule.
    return result;
  }

  static StockDocumentDetail detail(Object? raw) {
    final j = InventoryDto.object(raw), s = summary(raw);
    if (j['items'] is! List) {
      throw const FormatException('Missing document items');
    }
    final items = (j['items'] as List).map((v) => item(v, s.type)).toList();
    if (items.length != s.lineCount ||
        items.map((v) => v.id).toSet().length != items.length ||
        items.map((v) => v.ingredientId).toSet().length != items.length) {
      throw const FormatException('Duplicate/missing stock lines');
    }
    final value = StockDocumentDetail(
      id: s.id,
      stockAuditId: s.stockAuditId,
      documentCode: s.documentCode,
      type: s.type,
      status: s.status,
      warehouseId: s.warehouseId,
      warehouseCode: s.warehouseCode,
      warehouseName: s.warehouseName,
      note: s.note,
      lineCount: s.lineCount,
      totalQuantity: s.totalQuantity,
      totalCost: s.totalCost,
      createdBy: s.createdBy,
      version: s.version,
      createdAt: s.createdAt,
      updatedAt: s.updatedAt,
      items: items,
      confirmedBy: InventoryDto.optionalText(j, 'confirmedBy'),
      cancelledBy: InventoryDto.optionalText(j, 'cancelledBy'),
      confirmedAt: InventoryDto.date(j, 'confirmedAt', nullable: true),
      cancelledAt: InventoryDto.date(j, 'cancelledAt', nullable: true),
    );
    if (s.status == StockDocumentStatus.confirmed &&
            (value.confirmedAt == null ||
                value.confirmedBy == null ||
                items.isEmpty) ||
        s.status == StockDocumentStatus.cancelled &&
            (value.cancelledAt == null || value.cancelledBy == null)) {
      throw const FormatException('Invalid stock lifecycle');
    }
    final quantitySum = items.fold(
      BigInt.zero,
      (sum, row) => sum + BigInt.from(row.quantity.scaled),
    );
    final costSum = items.fold(
      BigInt.zero,
      (sum, row) => sum + row.totalCost.cents,
    );
    if (quantitySum != s.totalQuantity.scaled || costSum != s.totalCost.cents) {
      throw const FormatException('Invalid document totals');
    }
    return value;
  }

  static InventoryTransaction transaction(Object? raw) {
    final j = InventoryDto.object(raw);
    for (final key in [
      'stockDocumentId',
      'documentCode',
      'orderId',
      'orderItemId',
      'reservationId',
      'recipeUsageId',
    ]) {
      if (j[key] != null) InventoryDto.text(j, key);
    }
    final value = InventoryTransaction(
      source: enumeration(
        j['sourceType'],
        InventoryTransactionSource.values,
        (v) => v.code,
      ),
      orderId: InventoryDto.optionalText(j, 'orderId'),
      orderItemId: InventoryDto.optionalText(j, 'orderItemId'),
      reservationId: InventoryDto.optionalText(j, 'reservationId'),
      recipeUsageId: InventoryDto.optionalText(j, 'recipeUsageId'),
      id: InventoryDto.text(j, 'transactionId'),
      warehouseId: InventoryDto.text(j, 'warehouseId'),
      warehouseCode: InventoryDto.text(j, 'warehouseCode'),
      ingredientId: InventoryDto.text(j, 'ingredientId'),
      ingredientSku: InventoryDto.optionalText(j, 'ingredientSku'),
      ingredientName: InventoryDto.text(j, 'ingredientName'),
      unit: InventoryDto.text(j, 'unit'),
      documentId: InventoryDto.optionalText(j, 'stockDocumentId'),
      documentCode: InventoryDto.optionalText(j, 'documentCode'),
      documentType: j['documentType'] == null
          ? null
          : enumeration<StockDocumentType>(
              j['documentType'],
              StockDocumentType.values,
              (v) => v.code,
            ),
      type: enumeration(
        j['transactionType'],
        InventoryTransactionType.values,
        (v) => v.code,
      ),
      change: StockQuantityChange.parse(stockNumberText(j['quantityChange'])),
      before: quantity(j, 'beforeQuantity'),
      after: quantity(j, 'afterQuantity'),
      unitCost: j['unitCost'] == null ? null : money(j, 'unitCost', 12),
      createdBy: InventoryDto.text(j, 'createdBy'),
      createdAt: InventoryDto.date(j, 'createdAt')!,
    );
    final negative = const {
      InventoryTransactionType.recipeUse,
      InventoryTransactionType.issue,
      InventoryTransactionType.adjustmentDecrease,
    }.contains(value.type);
    if (negative != value.change.negative ||
        BigInt.from(value.before.scaled) + value.change.scaled !=
            BigInt.from(value.after.scaled)) {
      throw const FormatException('Invalid stock movement');
    }
    final fromOrder = value.source == InventoryTransactionSource.orderItem;
    // Since backend V38, RECIPE_USE carries the frozen reference price of its
    // usage (known or configured zero); unknown/legacy usage stays null.
    if (fromOrder
        ? value.type != InventoryTransactionType.recipeUse ||
              value.orderId == null ||
              value.orderItemId == null ||
              value.reservationId == null ||
              value.recipeUsageId == null ||
              value.documentId != null ||
              value.documentCode != null ||
              value.documentType != null
        : value.type == InventoryTransactionType.recipeUse ||
              value.documentId == null ||
              value.documentCode == null ||
              value.documentType == null ||
              value.unitCost == null ||
              value.orderId != null ||
              value.orderItemId != null ||
              value.reservationId != null ||
              value.recipeUsageId != null) {
      throw const FormatException('Invalid inventory transaction source');
    }
    return value;
  }

  static InventoryPage<T> page<T>(
    Object? raw,
    T Function(Object?) parse,
    int page,
  ) {
    final j = Map<String, dynamic>.from(InventoryDto.object(raw));
    for (final key in ['page', 'size', 'totalElements', 'totalPages']) {
      j[key] = integer(j, key);
    }
    return InventoryDto.page(j, parse, page);
  }
}
