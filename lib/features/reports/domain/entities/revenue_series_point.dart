import 'report_date.dart';
import 'report_money.dart';

class RevenueSeriesPoint {
  const RevenueSeriesPoint({
    required this.bucketStartDate,
    required this.collectedAmount,
    required this.completedOrderSalesAmount,
    required this.successfulPaymentCount,
    required this.completedOrderCount,
  });

  final ReportDate bucketStartDate;

  /// "Tiền đã thu" in bucket
  final ReportMoney collectedAmount;

  /// "Doanh số đơn hoàn tất" in bucket
  final ReportMoney completedOrderSalesAmount;

  final int successfulPaymentCount;
  final int completedOrderCount;
}
