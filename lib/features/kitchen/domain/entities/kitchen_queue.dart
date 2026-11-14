import '../../../order/domain/entities/order_entities.dart';
import '../../../order/domain/entities/order_quantity.dart';

const kitchenStatuses = [
  OrderItemStatus.pending,
  OrderItemStatus.cooking,
  OrderItemStatus.ready,
];

class KitchenQueueItem {
  const KitchenQueueItem({
    required this.orderId,
    required this.orderCode,
    required this.orderVersion,
    required this.orderItemId,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.note,
    required this.itemStatus,
    required this.serviceType,
    required this.createdAt,
    required this.sentToKitchenAt,
    required this.sessionId,
    required this.tableId,
    required this.tableCode,
    required this.tableName,
  });

  final String orderId, orderCode, orderItemId, itemName, unit;
  final int orderVersion;
  final OrderQuantity quantity;
  final String? note, sessionId, tableId, tableCode, tableName;
  final OrderItemStatus itemStatus;
  final ServiceType serviceType;
  final DateTime createdAt;
  final DateTime? sentToKitchenAt;
  String get key => '$orderId/$orderItemId';
  DateTime get queuedAt => sentToKitchenAt ?? createdAt;
  String get seating => serviceType == ServiceType.takeaway
      ? 'Mang đi'
      : [
          tableName,
          tableCode,
        ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');

  KitchenQueueItem fromOrder(OrderDetail order, OrderLine line) =>
      KitchenQueueItem(
        orderId: order.id,
        orderCode: order.summary.orderCode,
        orderVersion: order.version,
        orderItemId: line.id,
        itemName: line.itemName,
        quantity: line.quantity,
        unit: line.unit,
        note: line.note,
        itemStatus: line.status,
        serviceType: order.summary.serviceType,
        createdAt: createdAt,
        sentToKitchenAt: line.sentToKitchenAt ?? sentToKitchenAt,
        sessionId: order.summary.tableSessionId,
        tableId: tableId,
        tableCode: tableCode,
        tableName: tableName,
      );
}

class KitchenQueueQuery {
  const KitchenQueueQuery({
    required this.status,
    this.page = 0,
    this.size = 20,
  });
  final OrderItemStatus status;
  final int page, size;
  bool get valid =>
      kitchenStatuses.contains(status) && page >= 0 && size >= 1 && size <= 100;
}

class KitchenQueuePage {
  KitchenQueuePage({
    required List<KitchenQueueItem> content,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  }) : content = List.unmodifiable(content);
  final List<KitchenQueueItem> content;
  final int page, size, totalElements, totalPages;
}

enum KitchenAction {
  startCooking(
    'start-cooking',
    'KITCHEN_START_COOKING',
    OrderItemStatus.pending,
    OrderItemStatus.cooking,
  ),
  markReady(
    'mark-ready',
    'KITCHEN_MARK_READY',
    OrderItemStatus.cooking,
    OrderItemStatus.ready,
  ),

  /// Handing a ready dish over; an order permission, not a kitchen one.
  markServed(
    'mark-served',
    'ORDER_MARK_SERVED',
    OrderItemStatus.ready,
    OrderItemStatus.served,
  );

  const KitchenAction(this.path, this.permission, this.source, this.target);
  final String path, permission;
  final OrderItemStatus source, target;
}

/// A kitchen write against one order version. Kept whole so an uncertain
/// outcome can be retried exactly, whether it moved one dish or the order.
sealed class KitchenCommand {
  const KitchenCommand();
  String get orderId;
  int get expectedOrderVersion;
  KitchenAction get action;
  bool get valid;
}

class KitchenItemTransition extends KitchenCommand {
  const KitchenItemTransition({
    required this.orderId,
    required this.orderItemId,
    required this.expectedOrderVersion,
    required this.action,
  });
  @override
  final String orderId;
  final String orderItemId;
  @override
  final int expectedOrderVersion;
  @override
  final KitchenAction action;
  @override
  bool get valid =>
      orderId.trim().isNotEmpty &&
      orderItemId.trim().isNotEmpty &&
      expectedOrderVersion >= 0;
}

/// Every dish of the order that is not done yet becomes ready at once,
/// including dishes nobody started: the server deducts their stock then.
class KitchenOrderReady extends KitchenCommand {
  const KitchenOrderReady({
    required this.orderId,
    required this.expectedOrderVersion,
  });
  @override
  final String orderId;
  @override
  final int expectedOrderVersion;
  @override
  KitchenAction get action => KitchenAction.markReady;
  @override
  bool get valid => orderId.trim().isNotEmpty && expectedOrderVersion >= 0;
}

class KitchenDishSummary {
  const KitchenDishSummary(this.name, this.unit, this.note, this.quantity);
  final String name, unit;
  final String? note;
  final OrderQuantity quantity;
}

List<KitchenDishSummary> summarizeKitchenDishes(
  Iterable<KitchenQueueItem> items,
) {
  final sums = <(String, String, String?), OrderQuantity>{};
  for (final item in items) {
    if (item.itemStatus == OrderItemStatus.ready) continue;
    final key = (item.itemName, item.unit, item.note?.trim());
    sums[key] = (sums[key] ?? OrderQuantity.zero) + item.quantity;
  }
  return [
    for (final e in sums.entries)
      KitchenDishSummary(e.key.$1, e.key.$2, e.key.$3, e.value),
  ];
}
