import '../../../order/data/dto/order_dto.dart';
import '../../../order/domain/entities/order_entities.dart';
import '../../../order/domain/entities/order_quantity.dart';
import '../../domain/entities/kitchen_queue.dart';

abstract final class KitchenDto {
  static KitchenQueueItem item(Object? value) {
    final j = OrderDto.object(value);
    final quantity = j['quantity'];
    if (quantity is! num) {
      throw const FormatException('Invalid kitchen quantity');
    }
    final status = OrderDto.parseEnum(
      OrderItemStatus.values,
      OrderDto.string(j, 'itemStatus'),
      (v) => v.code,
    );
    if (!kitchenStatuses.contains(status)) {
      throw const FormatException('Invalid kitchen status');
    }
    return KitchenQueueItem(
      orderId: OrderDto.string(j, 'orderId'),
      orderCode: OrderDto.string(j, 'orderCode'),
      orderVersion: OrderDto.integer(j, 'orderVersion'),
      orderItemId: OrderDto.string(j, 'orderItemId'),
      itemName: OrderDto.string(j, 'itemName'),
      quantity: OrderQuantity.fromNumber(quantity),
      unit: OrderDto.string(j, 'unit'),
      note: OrderDto.nullableString(j, 'note'),
      itemStatus: status,
      serviceType: OrderDto.parseEnum(
        ServiceType.values,
        OrderDto.string(j, 'serviceType'),
        (v) => v.code,
      ),
      createdAt: OrderDto.date(j, 'createdAt')!,
      sentToKitchenAt: OrderDto.date(j, 'sentToKitchenAt', nullable: true),
      sessionId: OrderDto.nullableString(j, 'sessionId'),
      tableId: OrderDto.nullableString(j, 'tableId'),
      tableCode: OrderDto.nullableString(j, 'tableCode'),
      tableName: OrderDto.nullableString(j, 'tableName'),
    );
  }

  static KitchenQueuePage page(Object? value) {
    final j = OrderDto.object(value);
    final content = j['content'];
    final size = OrderDto.integer(j, 'size');
    if (content is! List || size < 1 || size > 100 || content.length > size) {
      throw const FormatException('Invalid kitchen page');
    }
    return KitchenQueuePage(
      content: content.map(item).toList(),
      page: OrderDto.integer(j, 'page'),
      size: size,
      totalElements: OrderDto.integer(j, 'totalElements'),
      totalPages: OrderDto.integer(j, 'totalPages'),
    );
  }

  static Map<String, Object> transition(KitchenItemTransition input) => {
    'expectedOrderVersion': input.expectedOrderVersion,
  };
}
