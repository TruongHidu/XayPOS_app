import '../entities/order_entities.dart';
import '../entities/order_item_action.dart';

/// Pure action rules; permission/entitlement are supplied by the application.
abstract final class OrderAccessPolicy {
  static bool canPay(OrderDetail order, bool allowed) =>
      allowed &&
      order.unpaid &&
      order.summary.totalAmount.minorUnits > 0 &&
      const {
        OrderStatus.confirmed,
        OrderStatus.preparing,
        OrderStatus.ready,
        OrderStatus.served,
      }.contains(order.summary.status);

  static bool canComplete(OrderDetail order, bool allowed) {
    final summary = order.summary;
    final liveItems = order.items.where(
      (item) => item.status != OrderItemStatus.cancelled,
    );
    return allowed &&
        const {
          OrderStatus.confirmed,
          OrderStatus.preparing,
          OrderStatus.ready,
          OrderStatus.served,
        }.contains(summary.status) &&
        summary.paymentStatus == OrderPaymentStatus.paid &&
        summary.totalAmount.minorUnits > 0 &&
        summary.paidAmount.minorUnits == summary.totalAmount.minorUnits &&
        liveItems.isNotEmpty &&
        liveItems.every((item) => item.status == OrderItemStatus.served);
  }

  static bool canServeAndComplete(OrderDetail order, bool allowed) =>
      allowed &&
      order.summary.paymentStatus == OrderPaymentStatus.paid &&
      order.summary.totalAmount.minorUnits > 0 &&
      order.summary.paidAmount == order.summary.totalAmount &&
      const {
        OrderStatus.confirmed,
        OrderStatus.preparing,
        OrderStatus.ready,
        OrderStatus.served,
      }.contains(order.summary.status) &&
      order.items.any((line) => line.status != OrderItemStatus.cancelled);

  static bool canTransitionLine(
    OrderDetail order,
    OrderLine line,
    OrderItemAction action,
    bool allowed,
  ) =>
      allowed &&
      line.status == action.source &&
      const {
        OrderStatus.confirmed,
        OrderStatus.preparing,
        OrderStatus.ready,
        OrderStatus.served,
      }.contains(order.summary.status);

  static bool isUuid(String? value) =>
      value != null &&
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value);
  static bool canEdit(OrderDetail order, bool updatePermission) =>
      updatePermission && order.editable;
  static bool canAppend(OrderDetail order, bool updateAndTypeFeature) =>
      updateAndTypeFeature &&
      order.unpaid &&
      const {
        OrderStatus.open,
        OrderStatus.confirmed,
        OrderStatus.preparing,
        OrderStatus.ready,
        OrderStatus.served,
      }.contains(order.summary.status);
  static String lineCancelPermission(OrderDetail order) =>
      order.confirmedAt == null ? 'ORDER_UPDATE' : 'ORDER_CANCEL';
  static bool canCancelLine(
    OrderDetail order,
    OrderLine line,
    bool permission,
  ) =>
      permission &&
      order.unpaid &&
      const {
        OrderStatus.open,
        OrderStatus.confirmed,
        OrderStatus.preparing,
        OrderStatus.ready,
        OrderStatus.served,
      }.contains(order.summary.status) &&
      line.status == OrderItemStatus.pending;
  static bool canConfirm(OrderDetail order, bool updatePermission) =>
      canEdit(order, updatePermission) &&
      order.items.any((line) => line.status != OrderItemStatus.cancelled);
  static bool canCancel(OrderDetail order, bool cancelPermission) =>
      cancelPermission && order.cancellable;
}
