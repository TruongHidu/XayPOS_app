import '../../../order/domain/entities/order_entities.dart' show ServiceType;
import '../../../reports/domain/entities/report_date.dart';
import '../../../reports/domain/entities/report_enums.dart';
import '../../../reports/domain/entities/report_money.dart';
import 'reference_margin_enums.dart';

/// A server-calculated percentage with two decimal places, not a money value.
class ReferenceMarginPercent {
  const ReferenceMarginPercent(this.hundredths);
  final BigInt hundredths;

  String get formatted {
    final absolute = hundredths.abs();
    return '${hundredths.isNegative ? '-' : ''}${absolute ~/ BigInt.from(100)},${(absolute % BigInt.from(100)).toString().padLeft(2, '0')}%';
  }

  @override
  bool operator ==(Object other) =>
      other is ReferenceMarginPercent && other.hundredths == hundredths;
  @override
  int get hashCode => hundredths.hashCode;
}

class ReferenceMarginIssue {
  const ReferenceMarginIssue({
    required this.code,
    required this.orderCount,
    required this.itemCount,
  });
  final String code;
  final int orderCount, itemCount;
  String get label => switch (code) {
    'INCOMPLETE' => 'Chưa cấu hình đủ giá vốn',
    'UNAVAILABLE' => 'Chưa có nguồn giá vốn',
    'LEGACY_UNAVAILABLE' => 'Đơn cũ chưa có snapshot giá vốn',
    'NO_ELIGIBLE_ITEMS' => 'Không có dòng món được xét',
    _ => 'Dữ liệu giá vốn cần đối soát ($code)',
  };
}

class ReferenceMarginSummary {
  const ReferenceMarginSummary({
    required this.costBasis,
    required this.marginScope,
    required this.costCoverageStatus,
    required this.completedOrderCount,
    required this.fullyCostedOrderCount,
    required this.excludedOrderCount,
    required this.orderCoveragePercent,
    required this.subtotalAmount,
    required this.discountAmount,
    required this.taxAmount,
    required this.serviceChargeAmount,
    required this.salesAmount,
    required this.netSalesAmount,
    required this.coveredNetSalesAmount,
    required this.coveredReferenceCostAmount,
    required this.coveredReferenceMarginAmount,
    required this.coveredReferenceMarginPercent,
    required this.costIssues,
  });
  final String costBasis, marginScope;
  final CostCoverageStatus costCoverageStatus;
  final int completedOrderCount, fullyCostedOrderCount, excludedOrderCount;
  final ReferenceMarginPercent? orderCoveragePercent,
      coveredReferenceMarginPercent;
  final ReportMoney subtotalAmount,
      discountAmount,
      taxAmount,
      serviceChargeAmount,
      salesAmount,
      netSalesAmount;
  final ReportMoney coveredNetSalesAmount,
      coveredReferenceCostAmount,
      coveredReferenceMarginAmount;
  final List<ReferenceMarginIssue> costIssues;
}

class ReferenceMarginSeriesPoint {
  const ReferenceMarginSeriesPoint({
    required this.bucketStartDate,
    required this.metrics,
  });
  final ReportDate bucketStartDate;
  final ReferenceMarginSummary metrics;
}

class ReferenceMarginOrderRow {
  const ReferenceMarginOrderRow({
    required this.orderId,
    required this.orderCode,
    required this.completedAt,
    required this.serviceType,
    required this.sourceChannel,
    required this.subtotalAmount,
    required this.discountAmount,
    required this.taxAmount,
    required this.serviceChargeAmount,
    required this.salesAmount,
    required this.netSalesAmount,
    required this.eligibleItemCount,
    required this.fullyCostedItemCount,
    required this.costCoverageStatus,
    required this.costIssues,
    required this.referenceCostAmount,
    required this.referenceMarginAmount,
    required this.referenceMarginPercent,
  });
  final String orderId, orderCode;
  final DateTime completedAt;
  final ServiceType serviceType;
  final ReportSourceChannel sourceChannel;
  final ReportMoney subtotalAmount,
      discountAmount,
      taxAmount,
      serviceChargeAmount,
      salesAmount,
      netSalesAmount;
  final int eligibleItemCount, fullyCostedItemCount;
  final CostCoverageStatus costCoverageStatus;
  final List<ReferenceMarginIssue> costIssues;
  final ReportMoney? referenceCostAmount, referenceMarginAmount;
  final ReferenceMarginPercent? referenceMarginPercent;
}
