import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/widgets/list_states.dart';
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

  /// When the board last read the server successfully, for "Cập nhật hh:mm".
  DateTime? _updatedAt;
  bool _wasLoading = false;

  /// Polling follows the controller actually on screen (it changes with scope).
  void _show(TakeawayOrdersController c) {
    if (identical(_shown, c)) return;
    _shown?.setVisible(false);
    _shown = c..setVisible(true);
    _updatedAt = c.hasLoaded && !c.loading ? DateTime.now() : null;
    _wasLoading = c.loading;
  }

  /// Notes the time each load finishes without a failure.
  void _track(TakeawayOrdersController c) {
    if (_wasLoading && !c.loading && c.failure == null && c.hasLoaded) {
      _updatedAt = DateTime.now();
    }
    _wasLoading = c.loading;
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

  void _create() => _go('/app/order-create?serviceType=TAKEAWAY');
  void _history() => _go('/app/orders?serviceType=TAKEAWAY');

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(currentSessionProvider);
    if (!AccessPolicy.canOrders(session, 'ORDER_VIEW')) {
      return const SingleChildScrollView(
        child: EmptyState(
          icon: Icons.lock_outline,
          message: 'Bạn không có quyền xem đơn.',
          hint: 'Liên hệ chủ quán hoặc quản lý để được cấp quyền.',
        ),
      );
    }
    final c = ref.watch(takeawayOrdersProvider);
    _show(c);
    _track(c);
    final canCreate =
        AccessPolicy.canCreateOrder(session, takeaway: true) &&
        AccessPolicy.canMenu(session, 'MENU_VIEW');

    return LayoutBuilder(
      builder: (context, box) {
        // Landscape tablets see the three stages side by side.
        final wide = box.maxWidth >= 900;
        final gutter = AppSpacing.pageGutter(box.maxWidth);
        final header = _BoardHeader(
          controller: c,
          updatedAt: _updatedAt,
          gutter: gutter,
          onHistory: _history,
          onCreate: wide && canCreate ? _create : null,
        );
        final status = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LoadingStrip(loading: c.loading && c.hasLoaded),
            OrderFailurePanel(
              failure: c.failure,
              retry: c.loading ? null : c.load,
              label: 'Tải lại',
            ),
          ],
        );
        final fab = canCreate && !wide
            ? FloatingActionButton.extended(
                key: const ValueKey('takeaway-create-action'),
                tooltip: 'Tạo đơn mang đi',
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('Đơn mới'),
              )
            : null;

        final Widget body;
        if (c.hasLoaded && c.rows.isEmpty) {
          body = RefreshIndicator(
            onRefresh: c.load,
            child: ListView(
              // Bottom inset keeps the history link clear of the floating button.
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                header,
                status,
                EmptyState(
                  icon: Icons.shopping_bag_outlined,
                  message: 'Chưa có đơn mang đi nào đang xử lý.',
                  action: TextButton.icon(
                    onPressed: _history,
                    icon: const Icon(Icons.history),
                    label: const Text('Xem lịch sử đơn mang đi'),
                  ),
                ),
              ],
            ),
          );
        } else if (wide) {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              status,
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, gutter),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, stage)
                          in TakeawayStage.values.indexed) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: _StageColumn(
                            stage: stage,
                            controller: c,
                            open: _openOrder,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        } else {
          body = _StageTabs(
            controller: c,
            header: header,
            status: status,
            gutter: gutter,
            open: _openOrder,
          );
        }
        return Scaffold(floatingActionButton: fab, body: body);
      },
    );
  }

  void _openOrder(OrderSummary order) => _go('/app/takeaway/${order.id}');
}

/// "4 đơn đang xử lý · Cập nhật 21:31", history and refresh.
class _BoardHeader extends StatelessWidget {
  const _BoardHeader({
    required this.controller,
    required this.updatedAt,
    required this.gutter,
    required this.onHistory,
    this.onCreate,
  });
  final TakeawayOrdersController controller;
  final DateTime? updatedAt;
  final double gutter;
  final VoidCallback onHistory;

  /// Wide screens create from here instead of a floating button.
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final at = updatedAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        AppSpacing.sm,
        gutter - AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  c.hasLoaded
                      ? '${c.activeCount} đơn đang xử lý'
                      : 'Đang tải đơn…',
                  style: theme.textTheme.titleSmall,
                ),
                if (at != null && c.hasLoaded)
                  Text(
                    'Cập nhật ${two(at.hour)}:${two(at.minute)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          // Large text has no room for the label: history moves into ⋮.
          if (MediaQuery.textScalerOf(context).scale(14) >= 14 * 1.5)
            PopupMenuButton<void>(
              tooltip: 'Thao tác khác',
              icon: const Icon(Icons.more_vert),
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: onHistory,
                  child: const Text('Lịch sử đơn mang đi'),
                ),
              ],
            )
          else
            Tooltip(
              message: 'Xem lịch sử đơn mang đi',
              child: TextButton.icon(
                onPressed: onHistory,
                icon: const Icon(Icons.history),
                label: const Text('Lịch sử'),
              ),
            ),
          IconButton(
            tooltip: 'Tải lại đơn mang đi',
            onPressed: c.loading ? null : c.load,
            icon: c.loading
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          if (onCreate != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: 'Tạo đơn mang đi',
              child: FilledButton.icon(
                key: const ValueKey('takeaway-create-action'),
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Đơn mới'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// How many orders a stage holds; "–" until the board has loaded.
class _StageCount extends StatelessWidget {
  const _StageCount({required this.stage, required this.count});
  final TakeawayStage stage;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final has = (count ?? 0) > 0;
    return DecoratedBox(
      key: ValueKey('takeaway-stage-count-${stage.name}'),
      decoration: BoxDecoration(
        color: has ? colors.primary : colors.surfaceContainerHighest,
        borderRadius: AppRadius.pillAll,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              count == null ? '–' : '$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: has ? colors.onPrimary : colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                height: 1,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StageLabel extends StatelessWidget {
  const _StageLabel({required this.stage, required this.count});
  final TakeawayStage stage;
  final int? count;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(
        child: Text(stage.label, textAlign: TextAlign.center, maxLines: 2),
      ),
      const SizedBox(width: AppSpacing.sm),
      _StageCount(stage: stage, count: count),
    ],
  );
}

/// Phones and portrait tablets: one tab per stage.
class _StageTabs extends StatefulWidget {
  const _StageTabs({
    required this.controller,
    required this.header,
    required this.status,
    required this.gutter,
    required this.open,
  });
  final TakeawayOrdersController controller;
  final Widget header, status;
  final double gutter;
  final void Function(OrderSummary) open;

  @override
  State<_StageTabs> createState() => _StageTabsState();
}

class _StageTabsState extends State<_StageTabs>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: TakeawayStage.values.length,
    vsync: this,
    animationDuration: const Duration(milliseconds: 200),
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    // Fixed equal tabs show all three counts; very large text scrolls them.
    final scroll = MediaQuery.textScalerOf(context).scale(14) >= 14 * 1.5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.header,
        widget.status,
        ColoredBox(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _tabs,
            isScrollable: scroll,
            tabAlignment: scroll ? TabAlignment.start : TabAlignment.fill,
            labelStyle: Theme.of(context).textTheme.titleSmall,
            tabs: [
              for (final stage in TakeawayStage.values)
                Tab(
                  key: ValueKey('takeaway-stage-${stage.name}'),
                  height: 56,
                  child: _StageLabel(
                    stage: stage,
                    count: c.hasLoaded ? c.stage(stage).length : null,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              for (final stage in TakeawayStage.values)
                _StageList(
                  stage: stage,
                  controller: c,
                  open: widget.open,
                  gutter: widget.gutter,
                  // An empty stage points at one that has orders.
                  onShowStage: (other) => _tabs.animateTo(other.index),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StageColumn extends StatelessWidget {
  const _StageColumn({
    required this.stage,
    required this.controller,
    required this.open,
  });
  final TakeawayStage stage;
  final TakeawayOrdersController controller;
  final void Function(OrderSummary) open;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.titleSmall,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _StageLabel(
                  stage: stage,
                  count: c.hasLoaded ? c.stage(stage).length : null,
                ),
              ),
            ),
          ),
          Expanded(
            child: _StageList(
              stage: stage,
              controller: c,
              open: open,
              gutter: AppSpacing.md,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageList extends StatelessWidget {
  const _StageList({
    required this.stage,
    required this.controller,
    required this.open,
    required this.gutter,
    this.onShowStage,
  });
  final TakeawayStage stage;
  final TakeawayOrdersController controller;
  final void Function(OrderSummary) open;
  final double gutter;

  /// Switches to another stage; tabs only.
  final ValueChanged<TakeawayStage>? onShowStage;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final rows = c.stage(stage);
    final elsewhere = onShowStage == null
        ? null
        : TakeawayStage.values
              .where((s) => s != stage && c.stage(s).isNotEmpty)
              .firstOrNull;
    return RefreshIndicator(
      onRefresh: c.load,
      child: ListView(
        // Bottom inset keeps the last card clear of the floating button.
        padding: EdgeInsets.fromLTRB(gutter, AppSpacing.md, gutter, 88),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (!c.hasLoaded && c.loading)
            const ListSkeleton(count: 3, height: 168)
          else if (rows.isEmpty)
            EmptyState(
              icon: Icons.shopping_bag_outlined,
              message: 'Không có đơn ${stage.label.toLowerCase()}.',
              action: elsewhere == null
                  ? null
                  : TextButton(
                      onPressed: () => onShowStage!(elsewhere),
                      child: Text(
                        '${elsewhere.label} có ${c.stage(elsewhere).length} đơn · Xem',
                      ),
                    ),
            ),
          for (final order in rows)
            TakeawayOrderCard(
              key: ValueKey('takeaway-card-${order.id}'),
              order: order,
              onOpen: () => open(order),
            ),
        ],
      ),
    );
  }
}
