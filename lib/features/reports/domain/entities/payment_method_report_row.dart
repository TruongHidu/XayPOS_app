import 'report_enums.dart';
import 'report_money.dart';

class PaymentMethodReportRow {
  const PaymentMethodReportRow({
    required this.paymentMethod,
    required this.collectedAmount,
    required this.successfulPaymentCount,
    required this.percentage,
  });

  final ReportPaymentMethod paymentMethod;
  final ReportMoney collectedAmount;
  final int successfulPaymentCount;

  /// Percentage calculated by server based on collectedAmount (not payment count).
  final double percentage;
}
