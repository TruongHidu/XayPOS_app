import 'package:flutter/material.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../../reports/domain/entities/report_money.dart';
import '../../../reports/presentation/widgets/report_kpi_card.dart';
import '../../domain/entities/reference_margin_report.dart';
import 'reference_margin_common.dart';
import 'reference_margin_coverage.dart';
import 'reference_margin_format.dart';

/// Reads in order: data scope, covered result, then the whole completed cohort.
class MarginSummary extends StatelessWidget {
  const MarginSummary({
    super.key,
    required this.value,
    required this.currency,
    required this.layout,
    required this.onExcluded,
  });
  final ReferenceMarginSummary value;
  final String currency;
  final MarginLayout layout;
  final VoidCallback onExcluded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = marginTextScale(context).clamp(1.0, 2.0);
    final negative = value.coveredReferenceMarginAmount.isNegative;
    final covered = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MarginSectionHeader(
          title: 'Các đơn đủ giá vốn',
          subtitle:
              'Chỉ tính những đơn có đủ giá vốn của mọi dòng món không hủy.',
        ),
        ResponsiveColumns(
          minColumnWidth: 220 * scale,
          maxColumns: 4,
          spacing: 12,
          children: [
            ReportKpiCard(
              title: 'Doanh số thuần đủ giá vốn',
              valueText: marginMoney(value.coveredNetSalesAmount, currency),
              icon: Icons.sell_outlined,
              secondaryText: '${value.fullyCostedOrderCount} đơn đủ giá vốn',
              tooltip:
                  'Tiền hàng trừ giảm giá của các đơn đủ giá vốn, chưa gồm thuế và phí phục vụ.',
            ),
            ReportKpiCard(
              title: 'Giá vốn tham chiếu',
              valueText: marginMoney(
                value.coveredReferenceCostAmount,
                currency,
              ),
              icon: Icons.inventory_2_outlined,
              color: theme.colorScheme.tertiary,
              tooltip:
                  'Tổng giá vốn đã chốt khi nhận món, không tính lại theo giá hiện tại.',
            ),
            ReportKpiCard(
              title: 'Lãi tham chiếu',
              valueText: marginMoney(
                value.coveredReferenceMarginAmount,
                currency,
              ),
              icon: negative ? Icons.trending_down : Icons.trending_up,
              color: negative ? theme.colorScheme.error : null,
              tooltip: 'Doanh số thuần đủ giá vốn trừ giá vốn tham chiếu.',
            ),
            ReportKpiCard(
              title: 'Tỷ lệ lãi tham chiếu',
              valueText: marginPercent(value.coveredReferenceMarginPercent),
              icon: Icons.percent,
              color: negative ? theme.colorScheme.error : null,
              tooltip:
                  'Lãi chia doanh số thuần của cùng nhóm đơn đủ giá vốn, do máy chủ tính.',
            ),
          ],
        ),
      ],
    );
    final coverage = MarginCoverageCard(value: value, onExcluded: onExcluded);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (layout == MarginLayout.expanded)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: coverage),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: covered),
            ],
          )
        else ...[
          coverage,
          const SizedBox(height: 16),
          covered,
        ],
        const SizedBox(height: 20),
        const MarginSectionHeader(
          title: 'Toàn bộ đơn hoàn tất',
          subtitle: 'Gồm cả đơn thiếu giá vốn; dùng để đối chiếu doanh số.',
        ),
        ResponsiveColumns(
          minColumnWidth: 220 * scale,
          maxColumns: 3,
          spacing: 12,
          children: [
            ReportKpiCard.count(
              title: 'Đơn hoàn tất',
              count: value.completedOrderCount,
              icon: Icons.receipt_long_outlined,
              color: theme.colorScheme.secondary,
              unit: 'đơn',
            ),
            ReportKpiCard(
              title: 'Doanh số thuần',
              valueText: marginMoney(value.netSalesAmount, currency),
              icon: Icons.payments_outlined,
              color: theme.colorScheme.secondary,
              tooltip: 'Tiền hàng trừ giảm giá, chưa gồm thuế và phí phục vụ.',
            ),
            ReportKpiCard(
              title: 'Doanh số gồm thuế/phí',
              valueText: marginMoney(value.salesAmount, currency),
              icon: Icons.point_of_sale_outlined,
              color: theme.colorScheme.secondary,
              tooltip: 'Doanh số thuần cộng thuế và phí phục vụ.',
            ),
          ],
        ),
        const SizedBox(height: 12),
        MarginSectionCard(
          padding: EdgeInsets.zero,
          child: Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: const PageStorageKey('margin-sales-breakdown'),
              leading: const Icon(Icons.calculate_outlined),
              title: const Text('Cơ cấu doanh số toàn bộ đơn'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                MarginSalesBreakdown(
                  subtotal: value.subtotalAmount,
                  discount: value.discountAmount,
                  tax: value.taxAmount,
                  serviceCharge: value.serviceChargeAmount,
                  netSales: value.netSalesAmount,
                  sales: value.salesAmount,
                  currency: currency,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Subtotal → net sales → sales, using the server totals rather than
/// recomputing them on the client.
class MarginSalesBreakdown extends StatelessWidget {
  const MarginSalesBreakdown({
    super.key,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.serviceCharge,
    required this.netSales,
    required this.sales,
    required this.currency,
  });
  final ReportMoney subtotal, discount, tax, serviceCharge, netSales, sales;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MarginAmountRow(
          label: 'Tiền hàng',
          value: marginMoney(subtotal, currency),
        ),
        MarginAmountRow(
          label: '− Giảm giá',
          value: marginMoney(discount, currency),
        ),
        const Divider(height: 8),
        MarginAmountRow(
          label: '= Doanh số thuần',
          value: marginMoney(netSales, currency),
          emphasis: true,
        ),
        MarginAmountRow(label: '+ Thuế', value: marginMoney(tax, currency)),
        MarginAmountRow(
          label: '+ Phí phục vụ',
          value: marginMoney(serviceCharge, currency),
        ),
        const Divider(height: 8),
        MarginAmountRow(
          label: '= Doanh số gồm thuế/phí',
          value: marginMoney(sales, currency),
          emphasis: true,
        ),
      ],
    );
  }
}
