import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../../../core/ui/widgets/list_states.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../../qr_order/presentation/widgets/qr_inbox_visibility.dart';
import '../../../reports/presentation/controllers/daily_report_controller.dart';
import '../../../reports/presentation/widgets/report_kpi_card.dart';
import '../../../reports/presentation/widgets/report_kpi_grid.dart';
import '../../../../core/ui/widgets/section_header.dart';

/// The owner's first look at the day: what came in so far and what needs
/// attention right now. Each figure opens the screen that deals with it, and
/// each part shows only to someone allowed to open that screen.
class OverviewScreen extends ConsumerStatefulWidget {
  const OverviewScreen({super.key});

  @override
  ConsumerState<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends ConsumerState<OverviewScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) _refreshCounts();
    });
  }

  /// Counts that only load on demand elsewhere (sidebar open, own screen).
  /// Opening the page keeps a recent count; pull-to-refresh always asks.
  Future<void> _refreshCounts({bool force = false}) async {
    final session = ref.read(authControllerProvider).state.session;
    final lowStock = ref.read(inventoryLowStockCountProvider);
    final takeaway = ref.read(takeawayCountRefresherProvider);
    await Future.wait([
      if (AccessPolicy.canViewInventoryAlerts(session))
        force ? lowStock.load() : lowStock.refreshIfStale(),
      if (AccessPolicy.canTakeawayOrders(session))
        force ? takeaway.refresh() : takeaway.refreshIfStale(),
    ]);
  }

  Future<void> _refresh() async {
    final session = ref.read(authControllerProvider).state.session;
    await Future.wait([
      ref.read(dailyReportControllerProvider).refresh(),
      if (AccessPolicy.canOrderWorkspace(session))
        ref.read(orderServiceContextProvider).refresh(),
      _refreshCounts(force: true),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).state.session;
    final report = ref.watch(dailyReportControllerProvider);
    final qrAllowed = AccessPolicy.canHandleQrRequests(session);

    final tiles = <Widget>[
      if (AccessPolicy.canOrderWorkspace(session)) const _TablesTile(),
      if (AccessPolicy.canTakeawayOrders(session)) const _TakeawayTile(),
      if (qrAllowed) const _QrTile(),
      if (AccessPolicy.canViewInventoryAlerts(session)) const _LowStockTile(),
    ];

    final body = RefreshIndicator(
      onRefresh: _refresh,
      // Every tile keeps its live data while the page is open; a lazy list
      // would drop tiles scrolled out of view and reload them on return.
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(restaurant: session?.authenticatedUser.restaurantName),
            const SizedBox(height: 16),
            _SectionTitle(
              title: 'Doanh thu hôm nay',
              action: TextButton(
                onPressed: () => context.go(AppRoutes.dailyRevenue),
                child: const Text('Xem chi tiết'),
              ),
            ),
            _Revenue(report: report),
            if (tiles.isNotEmpty) ...[
              const SizedBox(height: 24),
              const _SectionTitle(title: 'Đang diễn ra'),
              ResponsiveColumns(
                minColumnWidth: 220,
                maxColumns: 4,
                spacing: 12,
                children: tiles,
              ),
            ],
          ],
        ),
      ),
    );
    // The QR queue polls only while someone who can act on it is looking.
    return qrAllowed ? QrInboxVisibility(child: body) : body;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.restaurant});
  final String? restaurant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hôm nay, ${formatLocalDate(DateTime.now())}',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (restaurant != null && restaurant!.isNotEmpty)
          Text(
            restaurant!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.grey600,
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => SectionHeader(
    title,
    trailing: action,
    padding: const EdgeInsets.only(bottom: 8),
  );
}

class _Revenue extends StatelessWidget {
  const _Revenue({required this.report});
  final DailyReportController report;

  @override
  Widget build(BuildContext context) {
    final envelope = report.data;
    if (envelope == null) {
      if (report.failure != null && !report.isLoading) {
        return _Problem(
          message: report.failure!.message,
          onRetry: report.refresh,
        );
      }
      return const ListSkeleton(count: 4, height: 96, minColumnWidth: 220);
    }
    final data = envelope.data;
    return ReportKpiGrid(
      children: [
        ReportKpiCard.money(
          title: 'Tiền đã thu',
          money: data.collections.collectedAmount,
          icon: Icons.account_balance_wallet_outlined,
          color: AppColors.info,
          secondaryText:
              '${data.collections.successfulPaymentCount} giao dịch thành công',
        ),
        ReportKpiCard.count(
          title: 'Đơn hoàn tất',
          count: data.orders.completedOrderCount,
          icon: Icons.check_circle_outline,
          color: AppColors.success,
          unit: 'đơn',
          secondaryText: 'Đã tạo ${data.orders.createdOrderCount} đơn',
        ),
        ReportKpiCard.money(
          title: 'Giá trị TB / đơn',
          money: data.orders.averageCompletedOrderValue,
          icon: Icons.trending_up,
          color: AppColors.primary,
        ),
        ReportKpiCard.count(
          title: 'Đơn đã hủy',
          count: data.orders.cancelledOrderCount,
          icon: Icons.cancel_outlined,
          color: data.orders.cancelledOrderCount > 0
              ? AppColors.danger
              : AppColors.grey500,
          unit: 'đơn',
        ),
      ],
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Chưa tải được doanh thu. $message',
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Thử lại')),
        ],
      ),
    );
  }
}

/// A live figure that opens the screen where it is dealt with. [alert]
/// colours it when the figure asks for action.
class _LiveTile extends StatelessWidget {
  const _LiveTile({
    required this.tileKey,
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    required this.route,
    this.alert,
  });
  final String tileKey;
  final IconData icon;
  final String label;

  /// Null while the figure is still loading.
  final String? value;
  final String hint;
  final String route;
  final Color? alert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = alert ?? theme.colorScheme.primary;
    return Semantics(
      button: true,
      label: '$label: ${value ?? 'đang tải'}. $hint',
      excludeSemantics: true,
      child: Material(
        key: ValueKey('overview-$tileKey'),
        color: alert == null ? Colors.white : alert!.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: alert == null ? AppColors.grey200 : alert!,
            width: alert == null ? 1 : 1.5,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.go(route),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: accent),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.grey700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value ?? '—',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: alert ?? AppColors.grey900,
                        ),
                      ),
                      Text(
                        hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppColors.grey400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TablesTile extends ConsumerWidget {
  const _TablesTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tables = ref.watch(orderServiceContextProvider);
    final occupancy = tables.occupancy;
    final known =
        tables.tableAccess && !(tables.loading && occupancy.total == 0);
    return _LiveTile(
      tileKey: 'tables',
      icon: Icons.table_restaurant_outlined,
      label: 'Bàn đang phục vụ',
      value: !tables.tableAccess
          ? 'Không có quyền'
          : known
          ? '${occupancy.occupied}/${occupancy.total}'
          : null,
      hint: 'Mở sơ đồ gọi món',
      route: AppRoutes.orderCreate,
    );
  }
}

class _TakeawayTile extends ConsumerWidget {
  const _TakeawayTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(takeawayCountProvider);
    return _LiveTile(
      tileKey: 'takeaway',
      icon: Icons.shopping_bag_outlined,
      label: 'Đơn mang đi đang chờ',
      value: count?.toString(),
      hint: 'Mở bảng đơn mang đi',
      route: AppRoutes.takeaway,
    );
  }
}

class _QrTile extends ConsumerWidget {
  const _QrTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(qrInboxProvider);
    final pending = inbox.pending.length;
    return _LiveTile(
      tileKey: 'qr',
      icon: Icons.qr_code_2,
      label: 'Yêu cầu QR chờ duyệt',
      value: inbox.failure != null && pending == 0 ? '—' : '$pending',
      hint: inbox.failure != null ? 'Chưa đồng bộ được' : 'Duyệt tại Gọi món',
      route: AppRoutes.orderCreate,
      alert: pending > 0 ? AppColors.warning : null,
    );
  }
}

class _LowStockTile extends ConsumerWidget {
  const _LowStockTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(
      inventoryLowStockCountProvider.select((counter) => counter.count),
    );
    return _LiveTile(
      tileKey: 'low-stock',
      icon: Icons.inventory_2_outlined,
      label: 'Nguyên liệu sắp hết',
      value: count?.toString(),
      hint: 'Mở danh sách tồn kho thấp',
      route: AppRoutes.inventoryLowStock,
      alert: (count ?? 0) > 0 ? AppColors.danger : null,
    );
  }
}
