import 'order_entities.dart';

enum OrderItemAction {
  startCooking(
    'start-cooking',
    'Bắt đầu chế biến',
    OrderItemStatus.pending,
    OrderItemStatus.cooking,
    'KITCHEN_START_COOKING',
  ),
  markReady(
    'mark-ready',
    'Đã chế biến xong',
    OrderItemStatus.cooking,
    OrderItemStatus.ready,
    'KITCHEN_MARK_READY',
  ),
  markServed(
    'mark-served',
    'Đã phục vụ',
    OrderItemStatus.ready,
    OrderItemStatus.served,
    'ORDER_MARK_SERVED',
  );

  const OrderItemAction(
    this.endpoint,
    this.label,
    this.source,
    this.target,
    this.permission,
  );
  final String endpoint, label, permission;
  final OrderItemStatus source, target;
  bool get kitchen => this != markServed;

  static OrderItemAction? next(OrderItemStatus status) => switch (status) {
    OrderItemStatus.pending => startCooking,
    OrderItemStatus.cooking => markReady,
    OrderItemStatus.ready => markServed,
    _ => null,
  };
}
