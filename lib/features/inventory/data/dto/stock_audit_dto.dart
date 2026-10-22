import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/stock_audit.dart';
import 'inventory_dto.dart';
import 'stock_document_dto.dart';
import 'stock_json.dart';

abstract final class StockAuditDto {
  static StockAuditSummary summary(Object? raw) {
    final j = InventoryDto.object(raw);
    final value = StockAuditSummary(
      id: InventoryDto.text(j, 'id'),
      auditCode: InventoryDto.text(j, 'auditCode'),
      warehouseId: InventoryDto.text(j, 'warehouseId'),
      warehouseCode: InventoryDto.text(j, 'warehouseCode'),
      warehouseName: InventoryDto.text(j, 'warehouseName'),
      status: StockDocumentDto.enumeration(
        j['status'],
        StockAuditStatus.values,
        (v) => v.code,
      ),
      note: InventoryDto.optionalText(j, 'note'),
      itemCount: StockDocumentDto.integer(j, 'itemCount'),
      countedItemCount: StockDocumentDto.integer(j, 'countedItemCount'),
      changedItemCount: StockDocumentDto.integer(j, 'changedItemCount'),
      adjustmentDocumentId: _optionalIdentity(j, 'adjustmentDocumentId'),
      adjustmentDocumentCode: _optionalIdentity(j, 'adjustmentDocumentCode'),
      version: StockDocumentDto.integer(j, 'version'),
      createdAt: InventoryDto.date(j, 'createdAt')!,
      updatedAt: InventoryDto.date(j, 'updatedAt')!,
      startedAt: InventoryDto.date(j, 'startedAt', nullable: true),
    );
    if (value.changedItemCount > value.countedItemCount ||
        value.countedItemCount > value.itemCount ||
        (value.adjustmentDocumentId == null) !=
            (value.adjustmentDocumentCode == null) ||
        value.status == StockAuditStatus.draft &&
            (value.startedAt != null || value.itemCount != 0) ||
        const {
              StockAuditStatus.counting,
              StockAuditStatus.confirmed,
            }.contains(value.status) &&
            (value.startedAt == null || value.itemCount == 0) ||
        value.status != StockAuditStatus.confirmed &&
            value.adjustmentDocumentId != null ||
        value.status == StockAuditStatus.confirmed &&
            (value.countedItemCount != value.itemCount ||
                (value.changedItemCount > 0) !=
                    (value.adjustmentDocumentId != null))) {
      throw const FormatException('Invalid audit summary lifecycle');
    }
    return value;
  }

  static String? _optionalIdentity(Map<String, dynamic> j, String key) {
    final value = InventoryDto.optionalText(j, key);
    return value == null ? null : InventoryDto.text(j, key);
  }

  static StockAuditDetail detail(Object? raw) {
    final j = InventoryDto.object(raw), s = summary(raw);
    final value = StockAuditDetail(
      id: s.id,
      auditCode: s.auditCode,
      warehouseId: s.warehouseId,
      warehouseCode: s.warehouseCode,
      warehouseName: s.warehouseName,
      status: s.status,
      note: s.note,
      itemCount: s.itemCount,
      countedItemCount: s.countedItemCount,
      changedItemCount: s.changedItemCount,
      adjustmentDocumentId: s.adjustmentDocumentId,
      adjustmentDocumentCode: s.adjustmentDocumentCode,
      version: s.version,
      createdAt: s.createdAt,
      updatedAt: s.updatedAt,
      startedAt: s.startedAt,
      createdBy: InventoryDto.text(j, 'createdBy'),
      startedBy: _optionalIdentity(j, 'startedBy'),
      confirmedBy: _optionalIdentity(j, 'confirmedBy'),
      cancelledBy: _optionalIdentity(j, 'cancelledBy'),
      confirmedAt: InventoryDto.date(j, 'confirmedAt', nullable: true),
      cancelledAt: InventoryDto.date(j, 'cancelledAt', nullable: true),
    );
    if ((value.startedAt == null) != (value.startedBy == null) ||
        (value.status == StockAuditStatus.confirmed) !=
            (value.confirmedAt != null && value.confirmedBy != null) ||
        (value.status == StockAuditStatus.cancelled) !=
            (value.cancelledAt != null && value.cancelledBy != null) ||
        (value.confirmedAt == null) != (value.confirmedBy == null) ||
        (value.cancelledAt == null) != (value.cancelledBy == null)) {
      throw const FormatException('Invalid audit actor lifecycle');
    }
    return value;
  }

  static StockAuditItem item(Object? raw) {
    final j = InventoryDto.object(raw);
    for (final key in ['countedQuantity', 'differenceQuantity']) {
      if (!j.containsKey(key)) throw FormatException('Missing $key');
    }
    final value = StockAuditItem(
      id: InventoryDto.text(j, 'id'),
      ingredientId: InventoryDto.text(j, 'ingredientId'),
      sku: InventoryDto.optionalText(j, 'sku'),
      name: InventoryDto.text(j, 'name'),
      unit: InventoryDto.text(j, 'unit'),
      systemQuantity: StockDocumentDto.quantity(j, 'systemQuantity'),
      countedQuantity: j['countedQuantity'] == null
          ? null
          : StockDocumentDto.quantity(j, 'countedQuantity'),
      differenceQuantity: j['differenceQuantity'] == null
          ? null
          : StockAuditDifference.parse(
              stockNumberText(j['differenceQuantity']),
            ),
      referenceUnitCostSnapshot: StockDocumentDto.money(
        j,
        'referenceUnitCostSnapshot',
        12,
      ),
      note: InventoryDto.optionalText(j, 'note'),
    );
    if ((value.countedQuantity == null) != (value.differenceQuantity == null) ||
        value.countedQuantity != null &&
            StockAuditDifference.between(
                  value.countedQuantity!,
                  value.systemQuantity,
                ) !=
                value.differenceQuantity) {
      throw const FormatException('Invalid audit count/difference');
    }
    return value;
  }

  static InventoryPage<T> page<T>(
    Object? raw,
    T Function(Object?) parse,
    int expectedPage,
    int expectedSize,
  ) {
    final value = StockDocumentDto.page(raw, parse, expectedPage);
    final expectedPages = value.totalElements == 0
        ? 0
        : (value.totalElements + value.size - 1) ~/ value.size;
    if (value.size != expectedSize || value.totalPages != expectedPages) {
      throw const FormatException('Invalid audit pagination');
    }
    return value;
  }
}
