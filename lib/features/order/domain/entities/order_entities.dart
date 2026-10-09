import '../../../menu/domain/entities/menu_price.dart';
import 'order_quantity.dart';

enum ServiceType {
  dineIn('DINE_IN', 'Tại bàn'),
  takeaway('TAKEAWAY', 'Mang đi');

  const ServiceType(this.code, this.label);
  final String code, label;
}

enum OrderStatus {
  open('OPEN', 'Chưa xác nhận'),
  confirmed('CONFIRMED', 'Đã xác nhận'),
  preparing('PREPARING', 'Đang chế biến'),
  ready('READY', 'Sẵn sàng'),
  served('SERVED', 'Đã phục vụ'),
  completed('COMPLETED', 'Hoàn tất'),
  cancelled('CANCELLED', 'Đã hủy');

  const OrderStatus(this.code, this.label);
  final String code, label;
}

enum OrderItemStatus {
  pending('PENDING', 'Chờ xử lý'),
  cooking('COOKING', 'Đang chế biến'),
  ready('READY', 'Sẵn sàng'),
  served('SERVED', 'Đã phục vụ'),
  cancelled('CANCELLED', 'Đã hủy');

  const OrderItemStatus(this.code, this.label);
  final String code, label;
}

enum OrderPaymentStatus {
  unpaid('UNPAID', 'Chưa thanh toán'),
  partiallyPaid('PARTIALLY_PAID', 'Thanh toán một phần'),
  paid('PAID', 'Đã thanh toán'),
  partiallyRefunded('PARTIALLY_REFUNDED', 'Hoàn một phần'),
  refunded('REFUNDED', 'Đã hoàn tiền');

  const OrderPaymentStatus(this.code, this.label);
  final String code, label;
}

class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.orderCode,
    required this.serviceType,
    required this.sourceChannel,
    required this.tableSessionId,
    required this.status,
    required this.paymentStatus,
    required this.customerName,
    required this.guestCount,
    required this.currencyCode,
    required this.totalAmount,
    required this.paidAmount,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
  });
  final String id, orderCode, sourceChannel, currencyCode;
  final String? tableSessionId, customerName;
  final ServiceType serviceType;
  final OrderStatus status;
  final OrderPaymentStatus paymentStatus;
  final int guestCount, version;
  final MenuPrice totalAmount, paidAmount;
  final DateTime createdAt, updatedAt;
}

class OrderDetail {
  OrderDetail({
    required this.summary,
    required this.customerPhone,
    required this.note,
    required this.subtotalAmount,
    required this.discountAmount,
    required this.taxAmount,
    required this.serviceChargeAmount,
    required this.createdBy,
    required this.confirmedAt,
    required this.completedAt,
    required this.cancelledAt,
    required this.cancelReason,
    required List<OrderLine> items,
  }) : items = List.unmodifiable(items);
  final OrderSummary summary;
  final String? customerPhone, note, createdBy, cancelReason;
  final MenuPrice subtotalAmount,
      discountAmount,
      taxAmount,
      serviceChargeAmount;
  final DateTime? confirmedAt, completedAt, cancelledAt;
  final List<OrderLine> items;
  String get id => summary.id;
  int get version => summary.version;
  bool get unpaid =>
      summary.paymentStatus == OrderPaymentStatus.unpaid &&
      summary.paidAmount.minorUnits == 0;
  bool get editable => summary.status == OrderStatus.open && unpaid;
  bool get cancellable =>
      unpaid &&
      const {
        OrderStatus.open,
        OrderStatus.confirmed,
      }.contains(summary.status) &&
      items.every(
        (line) => const {
          OrderItemStatus.pending,
          OrderItemStatus.cancelled,
        }.contains(line.status),
      );
}

class OrderLine {
  const OrderLine({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.discountAmount,
    required this.lineTotal,
    required this.status,
    required this.note,
    required this.cancelReason,
    required this.sentToKitchenAt,
  });
  final String id, itemName, unit;
  final String? itemId, note, cancelReason;
  final OrderQuantity quantity;
  final MenuPrice unitPrice, discountAmount, lineTotal;
  final OrderItemStatus status;
  final DateTime? sentToKitchenAt;
}

class OrderPage {
  OrderPage({
    required List<OrderSummary> content,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  }) : content = List.unmodifiable(content);
  final List<OrderSummary> content;
  final int page, size, totalElements, totalPages;
}
