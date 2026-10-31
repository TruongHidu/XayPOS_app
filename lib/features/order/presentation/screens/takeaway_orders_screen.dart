import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../domain/entities/order_entities.dart';
import '../controllers/takeaway_orders_controller.dart';
import '../widgets/order_widgets.dart';
import '../widgets/takeaway_order_card.dart';

/// Board of takeaway orders still in progress, so staff can find them again
/// after leaving the order screen and act without opening each one.
class TakeawayOrdersScreen extends ConsumerStatefulWidget {
  const TakeawayOrdersScreen({super.key});

  @override
  ConsumerState<TakeawayOrdersScreen> createState() =>
      _TakeawayOrdersScreenState();
}

class _TakeawayOrdersScreenState extends ConsumerState<TakeawayOrdersScreen> {
  TakeawayOrdersController? _shown;

  /// Polling follows the controller actually on screen (it changes with scope).
  void _show(TakeawayOrdersController c) {
    if (identical(_shown, c)) return;
    _shown?.setVisible(false);
    _shown = c..setVisible(true);
  }

  @override
  void dispose() {
    _shown?.setVisible(false);
    super.dispose();
  }

  void _go(String location) {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    router.push(location);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canOrders(session, 'ORDER_VIEW')) {
      return const Center(child: Text('Bạn không có quyền xem đơn.'));
    }
    final c = ref.watch(takeawayOrdersProvider);
    _show(c);
    final canCreate =
        AccessPolicy.canCreateOrder(session, takeaway: true) &&
        AccessPolicy.canMenu(session, 'MENU_VIEW');
    final create = FilledButton.icon(
      onPressed: canCreate
          ? () => _go('/app/order-create?serviceType=TAKEAWAY')
          : null,
      icon: const Icon(Icons.add),
      label: const Text('Tạo đơn mang đi'),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final header = Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Đơn mang đi',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    c.hasLoaded
                        ? '${c.activeCount} đơn đang xử lý'
                        : 'Đang tải đơn…',
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (canCreate) create,
                  IconButton(
                    tooltip: 'Tải lại đơn mang đi',
                    onPressed: c.loading ? null : c.load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
          ),
        );
        final history = Center(
          child: TextButton.icon(
            onPressed: () => _go('/app/orders?serviceType=TAKEAWAY'),
            icon: const Icon(Icons.history),
            label: const Text('Xem lịch sử đơn mang đi'),
          ),
        );
        final status = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (c.loading) const LinearProgressIndicator(),
            OrderFailurePanel(
              failure: c.failure,
              retry: c.loading ? null : c.load,
              label: 'Tải lại',
            ),
          ],
        );

        if (c.hasLoaded && c.rows.isEmpty) {
          return RefreshIndicator(
            onRefresh: c.load,
            child: ListView(
              children: [
                header,
                status,
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.shopping_bag_outlined,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Chưa có đơn mang đi nào đang xử lý.',
                        textAlign: TextAlign.center,
                      ),
                      if (canCreate) ...[const SizedBox(height: 12), create],
                    ],
                  ),
                ),
                history,
              ],
            ),
          );
        }

        if (wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              status,
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final stage in TakeawayStage.values)
                        Expanded(
                          child: _StageColumn(
                            stage: stage,
                            rows: c.stage(stage),
                            open: _openOrder,
                            onRefresh: c.load,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              history,
            ],
          );
        }

        return DefaultTabController(
          length: TakeawayStage.values.length,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              status,
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  for (final stage in TakeawayStage.values)
                    Tab(text: '${stage.label} (${c.stage(stage).length})'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final stage in TakeawayStage.values)
                      _StageList(
                        rows: c.stage(stage),
                        open: _openOrder,
                        onRefresh: c.load,
                        footer: history,
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openOrder(OrderSummary order) => _go('/app/takeaway/${order.id}');
}

class _StageColumn extends StatelessWidget {
  const _StageColumn({
    required this.stage,
    required this.rows,
    required this.open,
    required this.onRefresh,
  });
  final TakeawayStage stage;
  final List<OrderSummary> rows;
  final void Function(OrderSummary) open;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(horizontal: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF9FAFB),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(
            '${stage.label} (${rows.length})',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          child: _StageList(rows: rows, open: open, onRefresh: onRefresh),
        ),
      ],
    ),
  );
}

class _StageList extends StatelessWidget {
  const _StageList({
    required this.rows,
    required this.open,
    required this.onRefresh,
    this.footer,
  });
  final List<OrderSummary> rows;
  final void Function(OrderSummary) open;
  final Future<void> Function() onRefresh;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      padding: const EdgeInsets.all(8),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Không có đơn.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        for (final order in rows)
          TakeawayOrderCard(
            key: ValueKey('takeaway-card-${order.id}'),
            order: order,
            onOpen: () => open(order),
          ),
        if (footer != null) footer!,
      ],
    ),
  );
}
