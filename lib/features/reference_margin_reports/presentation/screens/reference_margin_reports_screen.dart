import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart' show authControllerProvider;
import '../../../../core/auth/access_policy.dart';
import '../controllers/reference_margin_reports_controller.dart';
import '../providers/reference_margin_providers.dart';
import '../widgets/reference_margin_common.dart';
import '../widgets/reference_margin_filters.dart';
import '../widgets/reference_margin_format.dart';
import '../widgets/reference_margin_orders.dart';
import '../widgets/reference_margin_series.dart';
import '../widgets/reference_margin_summary.dart';
import '../../../reports/domain/entities/report_meta.dart';
import '../../domain/entities/reference_margin_enums.dart';

/// A separate capability: an ordinary revenue screen never owns these readers.
class ReferenceMarginReportsScreen extends ConsumerWidget {
  const ReferenceMarginReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canViewReferenceMarginReports(session)) {
      return const Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 48),
              SizedBox(height: 12),
              Text(
                'Chưa có quyền xem giá vốn và lãi tham chiếu.',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Tài khoản cần quyền xem đơn, xem báo cáo chi tiết và nhà hàng cần các tính năng tương ứng trong gói đang hiệu lực.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return _MarginWorkspace(
      key: ValueKey(AccessPolicy.referenceMarginScope(session)),
    );
  }
}

class _MarginWorkspace extends ConsumerStatefulWidget {
  const _MarginWorkspace({super.key});
  @override
  ConsumerState<_MarginWorkspace> createState() => _MarginWorkspaceState();
}

class _MarginWorkspaceState extends ConsumerState<_MarginWorkspace>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  late final TabController _tabs;
  ReferenceMarginReportsController? _controller;
  ModalRoute<void>? _route;
  RouteObserver<ModalRoute<void>>? _observer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(_tabChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _tabChanged() {
    if (_index == _tabs.index) return;
    setState(() => _index = _tabs.index);
    if (_index == 1) _controller?.openOrders();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (route == _route) return;
    _observer?.unsubscribe(this);
    _route = route;
    _observer = ref.read(referenceMarginRouteObserverProvider);
    if (route != null) _observer!.subscribe(this, route);
  }

  @override
  void didPushNext() => _controller?.setVisible(false);
  @override
  void didPopNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && (_route?.isCurrent ?? false)) {
        _controller?.setVisible(true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _controller?.setForeground(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    _observer?.unsubscribe(this);
    _controller?.setVisible(false);
    WidgetsBinding.instance.removeObserver(this);
    _tabs
      ..removeListener(_tabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(referenceMarginReportsProvider);
    if (!identical(c, _controller)) {
      _controller = c;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !identical(c, _controller)) return;
        c.setForeground(
          WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed,
        );
        c.setVisible(_route?.isCurrent ?? true);
      });
    }
    if (!c.current) return const SizedBox.shrink();
    if (!c.allowed) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                c.accessFailure?.message ??
                    'Chưa thể truy cập báo cáo giá vốn.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: c.checkingAccess ? null : c.retryAccess,
                icon: const Icon(Icons.refresh),
                label: const Text('Kiểm tra lại quyền truy cập'),
              ),
            ],
          ),
        ),
      );
    }
    final meta = _index == 1
        ? c.orders.value?.meta
        : c.summary.value?.meta ?? c.series.value?.meta;
    final loading = c.summary.loading || c.series.loading || c.orders.loading;
    final tabLoading = _index == 1
        ? c.orders.loading
        : c.summary.loading || c.series.loading;
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = MarginLayout.of(constraints.maxWidth);
        return RefreshIndicator(
          onRefresh: c.refresh,
          child: SingleChildScrollView(
            key: const PageStorageKey('reference-margin-workspace'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(layout.gutter),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1400),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _MarginHeader(meta: meta),
                    const SizedBox(height: 16),
                    MarginFilters(
                      filter: c.draftFilter,
                      busy: loading,
                      layout: layout,
                      dirty: c.draftFilter != c.appliedFilter,
                      validationError: c.validationError,
                      onRangeChanged: c.setDraftRange,
                      onCurrencyChanged: c.setDraftCurrencyCode,
                      onServiceChanged: c.setDraftServiceType,
                      onSourceChanged: c.setDraftSourceChannel,
                      onApply: c.applyFilters,
                      onReset: c.resetFilters,
                      onRefresh: c.refresh,
                    ),
                    const SizedBox(height: 12),
                    TabBar(
                      controller: _tabs,
                      isScrollable: layout == MarginLayout.compact,
                      tabAlignment: layout == MarginLayout.compact
                          ? TabAlignment.start
                          : TabAlignment.fill,
                      tabs: const [
                        Tab(
                          icon: Icon(Icons.dashboard_outlined),
                          text: 'Tổng quan',
                        ),
                        Tab(
                          icon: Icon(Icons.fact_check_outlined),
                          text: 'Đơn đối chiếu',
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 4,
                      child: tabLoading
                          ? const LinearProgressIndicator()
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 12),
                    if (_index == 0) ...[
                      MarginPanelView(
                        panel: c.summary,
                        onRetry: c.loadSummary,
                        placeholderHeight: 280,
                        builder: (value) => MarginSummary(
                          value: value.data,
                          currency: value.meta.currencyCode,
                          layout: layout,
                          onExcluded: () {
                            c.setCostCoverage(CostCoverageFilter.excluded);
                            _tabs.animateTo(1);
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      MarginPanelView(
                        panel: c.series,
                        onRetry: c.loadSeries,
                        placeholderHeight: 300,
                        builder: (value) => MarginSeries(
                          points: value.data,
                          currency: value.meta.currencyCode,
                          granularity: c.granularity,
                          onGranularity: c.setGranularity,
                          layout: layout,
                          loading: c.series.loading,
                        ),
                      ),
                    ] else ...[
                      MarginOrdersFilters(
                        filter: c.ordersFilter,
                        busy: c.orders.loading,
                        onCoverage: c.setCostCoverage,
                        onSort: c.setSort,
                        onDirection: c.setDirection,
                      ),
                      const SizedBox(height: 12),
                      MarginPanelView(
                        panel: c.orders,
                        onRetry: c.loadOrders,
                        placeholderHeight: 280,
                        builder: (value) => MarginOrders(
                          filter: c.ordersFilter,
                          value: value,
                          busy: c.orders.loading,
                          onPage: c.setPage,
                          onSize: c.setPageSize,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const MarginNotice(
                      message:
                          'Lãi tham chiếu dựa trên giá đã chốt khi nhận món, chưa phản ánh đầy đủ hao hụt, hoàn tiền và chi phí vận hành. Đây không phải giá vốn thực tế hay lợi nhuận ròng.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Title plus the attribution of the data on screen: always the last response,
/// never the unapplied draft filter.
class _MarginHeader extends StatelessWidget {
  const _MarginHeader({required this.meta});
  final ReportMeta? meta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = this.meta;
    Widget chip(IconData icon, String text) => Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        if (meta != null)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              chip(
                Icons.event_outlined,
                '${meta.fromDate.formatDisplay()} – ${meta.toDate.formatDisplay()}',
              ),
              chip(Icons.public, 'Múi giờ: ${meta.timezone}'),
              chip(
                Icons.monetization_on_outlined,
                'Tiền tệ: ${meta.currencyCode}',
              ),
              chip(
                Icons.schedule,
                'Tạo lúc: ${marginTimestamp(meta.generatedAt, meta.timezone)}',
              ),
            ],
          ),
      ],
    );
  }
}
