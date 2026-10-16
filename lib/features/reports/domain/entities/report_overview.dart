import 'report_money.dart';

class ReportCollectionsSummary {
  const ReportCollectionsSummary({
    required this.collectedAmount,
    required this.successfulPaymentCount,
    required this.paidOrderCount,
  });

  /// "Tiền đã thu" - sum of successful payments by paidAt in range.
  final ReportMoney collectedAmount;

  /// "Giao dịch thành công" - count of successful payment rows.
  final int successfulPaymentCount;

  /// "Đơn có phát sinh thu tiền" - distinct order IDs with successful payments.
  final int paidOrderCount;
}

class ReportOrdersSummary {
  const ReportOrdersSummary({
    required this.createdOrderCount,
    required this.completedOrderCount,
    required this.cancelledOrderCount,
    required this.completedSubtotalAmount,
    required this.completedDiscountAmount,
    required this.completedTaxAmount,
    required this.completedServiceChargeAmount,
    required this.completedOrderSalesAmount,
    required this.averageCompletedOrderValue,
  });

  /// "Đơn được tạo" - count by createdAt.
  final int createdOrderCount;

  /// "Đơn hoàn tất" - count by completedAt.
  final int completedOrderCount;

  /// "Đơn đã hủy" - count by cancelledAt.
  final int cancelledOrderCount;

  /// "Tiền hàng (đơn hoàn tất)"
  final ReportMoney completedSubtotalAmount;

  /// "Giảm giá (đơn hoàn tất)"
  final ReportMoney completedDiscountAmount;

  /// "Thuế (đơn hoàn tất)"
  final ReportMoney completedTaxAmount;

  /// "Phí phục vụ (đơn hoàn tất)"
  final ReportMoney completedServiceChargeAmount;

  /// "Doanh số đơn hoàn tất" - sum of totalAmount of completed orders by completedAt.
  final ReportMoney completedOrderSalesAmount;

  /// "Giá trị TB/đơn hoàn tất" - backend provided average value.
  final ReportMoney averageCompletedOrderValue;
}

class ReportOverview {
  const ReportOverview({required this.collections, required this.orders});

  final ReportCollectionsSummary collections;
  final ReportOrdersSummary orders;
}
