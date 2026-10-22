import '../../domain/entities/inventory_alert.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/inventory_quantity.dart';
import 'inventory_dto.dart';
import 'stock_document_dto.dart';

abstract final class InventoryAlertDto {
  static InventoryQuantity? _optionalQuantity(
    Map<String, dynamic> j,
    String key,
  ) {
    if (!j.containsKey(key)) throw FormatException('Missing $key');
    return j[key] == null ? null : StockDocumentDto.quantity(j, key);
  }

  static InventoryAlert parse(Object? raw) {
    final j = InventoryDto.object(raw);
    final value = InventoryAlert(
      id: InventoryDto.text(j, 'id'),
      warehouseId: InventoryDto.text(j, 'warehouseId'),
      warehouseCode: InventoryDto.text(j, 'warehouseCode'),
      warehouseName: InventoryDto.text(j, 'warehouseName'),
      ingredientId: InventoryDto.text(j, 'ingredientId'),
      ingredientSku: InventoryDto.optionalText(j, 'ingredientSku'),
      ingredientName: InventoryDto.text(j, 'ingredientName'),
      unit: InventoryDto.text(j, 'unit'),
      status: StockDocumentDto.enumeration(
        j['status'],
        InventoryAlertStatus.values,
        (s) => s.code,
      ),
      quantityAtTrigger: StockDocumentDto.quantity(j, 'quantityAtTrigger'),
      thresholdQuantity: StockDocumentDto.quantity(j, 'thresholdQuantity'),
      currentQuantity: _optionalQuantity(j, 'currentQuantity'),
      reservedQuantity: _optionalQuantity(j, 'reservedQuantity'),
      availableQuantity: _optionalQuantity(j, 'availableQuantity'),
      currentMinQuantity: _optionalQuantity(j, 'currentMinQuantity'),
      triggeredAt: InventoryDto.date(j, 'triggeredAt')!,
      acknowledgedBy: InventoryDto.optionalText(j, 'acknowledgedBy'),
      acknowledgedAt: InventoryDto.date(j, 'acknowledgedAt', nullable: true),
      resolvedAt: InventoryDto.date(j, 'resolvedAt', nullable: true),
      resolutionReason: j['resolutionReason'] == null
          ? null
          : StockDocumentDto.enumeration<InventoryAlertResolution>(
              j['resolutionReason'],
              InventoryAlertResolution.values,
              (s) => s.code,
            ),
      version: StockDocumentDto.integer(j, 'version'),
      createdAt: InventoryDto.date(j, 'createdAt')!,
      updatedAt: InventoryDto.date(j, 'updatedAt')!,
    );
    final acknowledged = value.acknowledgedAt != null;
    if ((value.acknowledgedBy != null) != acknowledged ||
        value.status == InventoryAlertStatus.open && acknowledged ||
        value.status == InventoryAlertStatus.acknowledged && !acknowledged ||
        (value.status == InventoryAlertStatus.resolved) !=
            (value.resolvedAt != null) ||
        (value.status == InventoryAlertStatus.resolved) !=
            (value.resolutionReason != null) ||
        value.thresholdQuantity.scaled <= 0 ||
        value.quantityAtTrigger.scaled > value.thresholdQuantity.scaled) {
      throw const FormatException('Invalid alert lifecycle');
    }
    final current = [
      value.currentQuantity,
      value.reservedQuantity,
      value.availableQuantity,
      value.currentMinQuantity,
    ];
    if (current.any((q) => q == null) && current.any((q) => q != null) ||
        value.currentQuantity != null &&
            (value.reservedQuantity!.scaled > value.currentQuantity!.scaled ||
                value.currentQuantity!.scaled -
                        value.reservedQuantity!.scaled !=
                    value.availableQuantity!.scaled)) {
      throw const FormatException('Invalid current stock comparison');
    }
    return value;
  }

  static InventoryPage<InventoryAlert> page(Object? raw, int page) =>
      StockDocumentDto.page(raw, parse, page);
}
