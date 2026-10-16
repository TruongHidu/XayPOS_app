import '../../../order/domain/entities/order_entities.dart'
    show OrderPaymentStatus, OrderStatus, ServiceType;
import 'report_enums.dart';
import 'report_money.dart';

class ReportOrderRow {
  const ReportOrderRow({
    required this.id,
    required this.orderCode,
    required this.serviceType,
    required this.sourceChannel,
    required this.status,
    required this.paymentStatus,
    required this.currencyCode,
    required this.totalAmount,
    required this.collectedAmountInRange,
    required this.createdAt,
    this.completedAt,
    this.cancelledAt,
    required this.reportEventAt,
  });

  final String id;
  final String orderCode;
  final ServiceType serviceType;
  final ReportSourceChannel sourceChannel;
  final OrderStatus status;
  final OrderPaymentStatus paymentStatus;
  final String currencyCode;

  /// "Tổng giá trị đơn"
  final ReportMoney totalAmount;

  /// "Tiền thu trong khoảng"
  final ReportMoney collectedAmountInRange;

  final DateTime createdAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  /// Event timestamp based on dateBasis (e.g. latest paidAt for PAID basis, completedAt for COMPLETED, etc.)
  final DateTime reportEventAt;

  String get orderId => id;
}
