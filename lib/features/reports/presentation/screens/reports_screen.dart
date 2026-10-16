import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../controllers/report_orders_controller.dart';
import '../controllers/report_summary_controller.dart';
import '../controllers/top_items_report_controller.dart';
import '../widgets/completed_orders_breakdown_card.dart';
import '../widgets/payment_methods_card.dart';
import '../widgets/report_filter_bar.dart';
import '../widgets/report_kpi_card.dart';
import '../widgets/report_kpi_grid.dart';
import '../widgets/report_orders_table.dart';
import '../widgets/revenue_series_chart.dart';
import '../widgets/top_items_table.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _topItemsLoaded = false;
  bool _ordersLoaded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    final summaryCtrl = ref.read(reportSummaryControllerProvider);
    final parentFilter = summaryCtrl.appliedFilter;

    if (_tabController.index == 1 && !_topItemsLoaded) {
      _topItemsLoaded = true;
      ref
          .read(topItemsReportControllerProvider)
          .updateParentFilter(parentFilter);
    } else if (_tabController.index == 2 && !_ordersLoaded) {
      _ordersLoaded = true;
      ref.read(reportOrdersControllerProvider).updateParentFilter(parentFilter);
    }
  }

  void _onApplyFilters() {
    final summaryCtrl = ref.read(reportSummaryControllerProvider);
    summaryCtrl.applyFilters();

    final parentFilter = summaryCtrl.draftFilter;
    if (_tabController.index == 1 || _topItemsLoaded) {
      ref
          .read(topItemsReportControllerProvider)
          .updateParentFilter(parentFilter);
    }
    if (_tabController.index == 2 || _ordersLoaded) {
      ref.read(reportOrdersControllerProvider).updateParentFilter(parentFilter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summaryCtrl = ref.watch(reportSummaryControllerProvider);
    final topItemsCtrl = ref.watch(topItemsReportControllerProvider);
    final ordersCtrl = ref.watch(reportOrdersControllerProvider);

    final meta =
        summaryCtrl.summaryData?.meta ??
        summaryCtrl.seriesData?.meta ??
        summaryCtrl.paymentsData?.meta;

    final session = ref.watch(authControllerProvider).state.session;
    final canViewOrder =
        session != null && AccessPolicy.canOrders(session, 'ORDER_VIEW');

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await summaryCtrl.refreshAll();
          if (_topItemsLoaded) {
            await topItemsCtrl.refresh();
          }
          if (_ordersLoaded) {
            await ordersCtrl.refresh();
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with Title and Meta Chips
              _buildHeader(context, summaryCtrl, meta),
              const SizedBox(height: 16),

              // Filter Bar
              RangeReportFilterBar(
                range: summaryCtrl.draftFilter.range,
                currencyCode: summaryCtrl.draftFilter.currencyCode,
                serviceType: summaryCtrl.draftFilter.serviceType,
                sourceChannel: summaryCtrl.draftFilter.sourceChannel,
                onRangeChanged: summaryCtrl.setDraftRange,
                onCurrencyChanged: summaryCtrl.setDraftCurrencyCode,
                onServiceTypeChanged: summaryCtrl.setDraftServiceType,
                onSourceChannelChanged: summaryCtrl.setDraftSourceChannel,
                onApply: _onApplyFilters,
                onReset: summaryCtrl.resetToDefaults,
                onRefresh: () => summaryCtrl.refreshAll(),
                isLoading:
                    summaryCtrl.isAnyLoading || summaryCtrl.isAnyRefreshing,
              ),
              const SizedBox(height: 16),

              if (summaryCtrl.isAnyRefreshing)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(),
                ),

              // Tab Bar
              TabBar(
                controller: _tabController,
                isScrollable: MediaQuery.of(context).size.width < 500,
                onTap: (index) {
                  final parentFilter = summaryCtrl.appliedFilter;
                  if (index == 1 && !_topItemsLoaded) {
                    _topItemsLoaded = true;
                    topItemsCtrl.updateParentFilter(parentFilter);
                  } else if (index == 2 && !_ordersLoaded) {
                    _ordersLoaded = true;
                    ordersCtrl.updateParentFilter(parentFilter);
                  }
                },
                tabs: const [
                  Tab(icon: Icon(Icons.dashboard_outlined), text: 'Tổng quan'),
                  Tab(
                    icon: Icon(Icons.emoji_events_outlined),
                    text: 'Món bán chạy',
                  ),
                  Tab(
                    icon: Icon(Icons.fact_check_outlined),
                    text: 'Đơn đối chiếu',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Tab Contents
              AnimatedBuilder(
                animation: _tabController,
                builder: (context, _) {
                  switch (_tabController.index) {
                    case 0:
                      return _buildOverviewTab(
                        context,
                        summaryCtrl,
                        meta?.currencyCode ?? 'VND',
                      );
                    case 1:
                      return _buildTopItemsTab(
                        context,
                        topItemsCtrl,
                        meta?.currencyCode ?? 'VND',
                      );
                    case 2:
                      return _buildOrdersTab(
                        context,
                        ordersCtrl,
                        meta?.currencyCode ?? 'VND',
                        canViewOrder,
                      );
                    default:
                      return const SizedBox.shrink();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ReportSummaryController summaryCtrl,
    dynamic meta,
  ) {
    final theme = Theme.of(context);

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
              'Báo cáo doanh thu',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Phân tích chi tiết doanh thu, xu hướng, phương thức thanh toán và đối chiếu đơn hàng',
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
              if (meta.generatedAt != null)
                Chip(
                  avatar: const Icon(Icons.schedule, size: 16),
                  label: Text('Tạo lúc ${_formatTime(meta.generatedAt!)}'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildOverviewTab(
    BuildContext context,
    ReportSummaryController summaryCtrl,
    String currencyCode,
  ) {
    final width = MediaQuery.of(context).size.width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Panel 1: Summary Overview KPIs
        if (summaryCtrl.summaryFailure != null &&
            summaryCtrl.summaryData == null)
          _buildPanelError(
            title: 'Lỗi tải tổng quan doanh thu',
            message: summaryCtrl.summaryFailure!.message,
            onRetry: summaryCtrl.retrySummary,
          )
        else if (summaryCtrl.summaryLoading && summaryCtrl.summaryData == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (summaryCtrl.summaryData != null) ...[
          _buildKpis(summaryCtrl.summaryData!.data),
          const SizedBox(height: 16),
        ],

        // Panel 2 & 3: Revenue Series Chart & Payment Methods
        if (width >= 1000)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: _buildSeriesPanel(context, summaryCtrl, currencyCode),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 4,
                child: _buildPaymentMethodsPanel(
                  context,
                  summaryCtrl,
                  currencyCode,
                ),
              ),
            ],
          )
        else ...[
          _buildSeriesPanel(context, summaryCtrl, currencyCode),
          const SizedBox(height: 16),
          _buildPaymentMethodsPanel(context, summaryCtrl, currencyCode),
        ],

        if (summaryCtrl.summaryData != null) ...[
          const SizedBox(height: 16),
          CompletedOrdersBreakdownCard(
            ordersSummary: summaryCtrl.summaryData!.data.orders,
          ),
        ],
      ],
    );
  }

  Widget _buildKpis(dynamic data) {
    final kpis = [
      ReportKpiCard.money(
        title: 'Tiền đã thu',
        money: data.collections.collectedAmount,
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF0284C7),
        tooltip:
            'Tổng tiền các giao dịch thanh toán SUCCESS theo thời điểm thu (paidAt) trong khoảng.',
        secondaryText:
            '${data.collections.successfulPaymentCount} giao dịch thành công',
      ),
      ReportKpiCard.money(
        title: 'Doanh số đơn hoàn tất',
        money: data.orders.completedOrderSalesAmount,
        icon: Icons.point_of_sale_outlined,
        color: const Color(0xFFEA580C),
        tooltip:
            'Tổng giá trị các đơn COMPLETED theo thời điểm hoàn tất (completedAt) trong khoảng.',
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

  Widget _buildSeriesPanel(
    BuildContext context,
    ReportSummaryController summaryCtrl,
    String currencyCode,
  ) {
    if (summaryCtrl.seriesFailure != null && summaryCtrl.seriesData == null) {
      return _buildPanelError(
        title: 'Lỗi tải biểu đồ xu hướng',
        message: summaryCtrl.seriesFailure!.message,
        onRetry: summaryCtrl.retrySeries,
      );
    }
    if (summaryCtrl.seriesLoading && summaryCtrl.seriesData == null) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (summaryCtrl.seriesData == null) return const SizedBox.shrink();

    return RevenueSeriesChart(
      points: summaryCtrl.seriesData!.data,
      currencyCode: currencyCode,
      granularity: summaryCtrl.granularity,
      onGranularityChanged: summaryCtrl.setGranularity,
      showCollected: summaryCtrl.showCollectedSeries,
      showCompleted: summaryCtrl.showCompletedSeries,
      onToggleCollected: summaryCtrl.toggleShowCollected,
      onToggleCompleted: summaryCtrl.toggleShowCompleted,
      isTableView: summaryCtrl.isSeriesTableView,
      onToggleTableView: summaryCtrl.toggleSeriesTableView,
    );
  }

  Widget _buildPaymentMethodsPanel(
    BuildContext context,
    ReportSummaryController summaryCtrl,
    String currencyCode,
  ) {
    if (summaryCtrl.paymentsFailure != null &&
        summaryCtrl.paymentsData == null) {
      return _buildPanelError(
        title: 'Lỗi tải phương thức thanh toán',
        message: summaryCtrl.paymentsFailure!.message,
        onRetry: summaryCtrl.retryPayments,
      );
    }
    if (summaryCtrl.paymentsLoading && summaryCtrl.paymentsData == null) {
      return const SizedBox(
        height: 320,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (summaryCtrl.paymentsData == null) return const SizedBox.shrink();

    return PaymentMethodsCard(
      rows: summaryCtrl.paymentsData!.data,
      currencyCode: currencyCode,
    );
  }

  Widget _buildTopItemsTab(
    BuildContext context,
    TopItemsReportController topItemsCtrl,
    String currencyCode,
  ) {
    if (topItemsCtrl.failure != null && topItemsCtrl.data == null) {
      return _buildPanelError(
        title: 'Lỗi tải danh sách món bán chạy',
        message: topItemsCtrl.failure!.message,
        onRetry: topItemsCtrl.retry,
      );
    }
    if (topItemsCtrl.isLoading && topItemsCtrl.data == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (topItemsCtrl.data == null) {
      return const SizedBox.shrink();
    }

    return TopItemsTable(
      page: topItemsCtrl.data!.data,
      currencyCode: currencyCode,
      sortBy: topItemsCtrl.filter.sortBy,
      direction: topItemsCtrl.filter.direction,
      onSortByChanged: topItemsCtrl.setSortBy,
      onToggleDirection: topItemsCtrl.toggleSortDirection,
      onPageChanged: topItemsCtrl.setPage,
      onSizeChanged: topItemsCtrl.setSize,
    );
  }

  Widget _buildOrdersTab(
    BuildContext context,
    ReportOrdersController ordersCtrl,
    String currencyCode,
    bool canViewOrder,
  ) {
    if (ordersCtrl.failure != null && ordersCtrl.data == null) {
      return _buildPanelError(
        title: 'Lỗi tải danh sách đơn đối chiếu',
        message: ordersCtrl.failure!.message,
        onRetry: ordersCtrl.retry,
      );
    }
    if (ordersCtrl.isLoading && ordersCtrl.data == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (ordersCtrl.data == null) {
      return const SizedBox.shrink();
    }

    return ReportOrdersTable(
      page: ordersCtrl.data!.data,
      currencyCode: currencyCode,
      dateBasis: ordersCtrl.filter.dateBasis,
      status: ordersCtrl.filter.status,
      paymentStatus: ordersCtrl.filter.paymentStatus,
      sortBy: ordersCtrl.filter.sortBy,
      direction: ordersCtrl.filter.direction,
      canViewOrderDetail: canViewOrder,
      onDateBasisChanged: ordersCtrl.setDateBasis,
      onStatusChanged: ordersCtrl.setStatus,
      onPaymentStatusChanged: ordersCtrl.setPaymentStatus,
      onSortByChanged: ordersCtrl.setSortBy,
      onToggleDirection: ordersCtrl.toggleSortDirection,
      onPageChanged: ordersCtrl.setPage,
      onSizeChanged: ordersCtrl.setSize,
    );
  }

  Widget _buildPanelError({
    required String title,
    required String message,
    required VoidCallback onRetry,
  }) {
    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 36, color: Colors.red.shade700),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red.shade900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.red.shade800),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Thử lại'),
              onPressed: onRetry,
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
