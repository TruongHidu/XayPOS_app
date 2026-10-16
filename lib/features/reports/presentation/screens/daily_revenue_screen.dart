import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/daily_report_controller.dart';
import '../providers/report_providers.dart';
import '../widgets/completed_orders_breakdown_card.dart';
import '../widgets/report_filter_bar.dart';
import '../widgets/report_kpi_card.dart';
import '../widgets/report_kpi_grid.dart';

class DailyRevenueScreen extends ConsumerWidget {
  const DailyRevenueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(dailyReportControllerProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: controller.refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Bar: Title & Meta Info
              _buildHeader(context, controller),
              const SizedBox(height: 16),

              // Filter Bar
              DailyReportFilterBar(
                selectedDate: controller.draftFilter.date,
                currencyCode: controller.draftFilter.currencyCode,
                serviceType: controller.draftFilter.serviceType,
                sourceChannel: controller.draftFilter.sourceChannel,
                onDateChanged: controller.setDraftDate,
                onCurrencyChanged: controller.setDraftCurrencyCode,
                onServiceTypeChanged: controller.setDraftServiceType,
                onSourceChannelChanged: controller.setDraftSourceChannel,
                onApply: controller.applyFilters,
                onReset: controller.resetToDefaults,
                onRefresh: controller.refresh,
                isLoading: controller.isLoading || controller.isRefreshing,
              ),
              const SizedBox(height: 16),

              if (controller.isRefreshing)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(),
                ),

              // Error State
              if (controller.failure != null && controller.data == null)
                _buildErrorCard(context, controller)
              // Loading State (Initial)
              else if (controller.isLoading && controller.data == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              // Data Content
              else if (controller.data != null) ...[
                _buildKpiGrid(controller),
                const SizedBox(height: 16),
                CompletedOrdersBreakdownCard(
                  ordersSummary: controller.data!.data.orders,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, DailyReportController controller) {
    final theme = Theme.of(context);
    final meta = controller.data?.meta;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Doanh thu ngày',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Theo dõi tình hình thu tiền và doanh số theo từng ngày lịch',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
        if (meta != null)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(
                avatar: const Icon(Icons.public, size: 16),
                label: Text(meta.timezone),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                avatar: const Icon(Icons.monetization_on_outlined, size: 16),
                label: Text(meta.currencyCode),
                visualDensity: VisualDensity.compact,
              ),
              Chip(
                avatar: const Icon(Icons.schedule, size: 16),
                label: Text('Tạo lúc ${_formatTime(meta.generatedAt)}'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildKpiGrid(DailyReportController controller) {
    final data = controller.data!.data;

    final kpis = [
      ReportKpiCard.money(
        title: 'Tiền đã thu',
        money: data.collections.collectedAmount,
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF0284C7),
        tooltip:
            'Tổng tiền các giao dịch thanh toán SUCCESS theo thời điểm thu (paidAt) trong ngày.',
        secondaryText:
            '${data.collections.successfulPaymentCount} giao dịch thành công',
      ),
      ReportKpiCard.money(
        title: 'Doanh số đơn hoàn tất',
        money: data.orders.completedOrderSalesAmount,
        icon: Icons.point_of_sale_outlined,
        color: const Color(0xFFEA580C),
        tooltip:
            'Tổng giá trị các đơn COMPLETED theo thời điểm hoàn tất (completedAt) trong ngày.',
        secondaryText: '${data.orders.completedOrderCount} đơn hoàn tất',
      ),
      ReportKpiCard.count(
        title: 'Đơn hoàn tất',
        count: data.orders.completedOrderCount,
        icon: Icons.check_circle_outline,
        color: const Color(0xFF10B981),
        unit: 'đơn',
        tooltip: 'Số lượng đơn COMPLETED theo completedAt.',
        secondaryText:
            'Khởi tạo: ${data.orders.createdOrderCount} | Đã hủy: ${data.orders.cancelledOrderCount}',
      ),
      ReportKpiCard.money(
        title: 'Giá trị TB / đơn hoàn tất',
        money: data.orders.averageCompletedOrderValue,
        icon: Icons.trending_up,
        color: const Color(0xFF8B5CF6),
        tooltip:
            'Giá trị trung bình của mỗi đơn hoàn tất do backend tính toán.',
        secondaryText:
            '${data.collections.paidOrderCount} đơn có phát sinh thu tiền',
      ),
    ];

    return ReportKpiGrid(children: kpis);
  }

  Widget _buildErrorCard(
    BuildContext context,
    DailyReportController controller,
  ) {
    final theme = Theme.of(context);
    final fail = controller.failure!;

    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade700),
            const SizedBox(height: 12),
            Text(
              'Không thể tải báo cáo doanh thu ngày',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.red.shade900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              fail.message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red.shade800),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Thử lại'),
              onPressed: controller.refresh,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
