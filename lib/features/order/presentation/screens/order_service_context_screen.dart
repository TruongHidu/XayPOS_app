import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_status_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/formatters/elapsed.dart';
import '../../../../core/ui/widgets/elapsed_text.dart';
import '../../../../core/ui/widgets/list_states.dart';
import '../../../../core/ui/widgets/status_badge.dart';
import '../../../tables/domain/entities/table_entities.dart';
import '../../../qr_order/presentation/widgets/qr_request_inbox.dart';
import '../../../qr_order/presentation/widgets/qr_inbox_visibility.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_table_workspace.dart';
import '../controllers/takeaway_orders_controller.dart';
import '../widgets/order_widgets.dart';

class OrderServiceContextScreen extends ConsumerWidget {
  const OrderServiceContextScreen({super.key});

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    RestaurantTable table,
  ) async {
    final controller = ref.read(orderServiceContextProvider);
    final result = await controller.selectTable(table.id);
    if (!context.mounted || !controller.current) return;
    if (result case Success(value: final selection)) {
      switch (selection) {
        case ViewTableOrder(order: final order):
          await context.push(
            '/app/order-create/bill/${Uri.encodeComponent(order.id)}?tableName=${Uri.encodeQueryComponent(table.name)}',
          );
        case ComposeTableOrder(context: final target):
          await context.push(
            '/app/order-create?tableId=${Uri.encodeQueryComponent(target.tableId!)}',
          );
      }
      if (context.mounted && controller.current) await controller.refresh();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(orderServiceContextProvider);
    final qr = ref.watch(qrInboxProvider);
    final session = ref.watch(currentSessionProvider);
    final menuAllowed = AccessPolicy.canMenu(session, 'MENU_VIEW');
    // Each part shows only to someone who can use it, instead of a notice.
    final qrAllowed = AccessPolicy.canHandleQrRequests(session);
    final body = Column(
      children: [
        if (c.tableAccess) ...[
          Row(
            children: [
              for (final filter in [
                (null, 'Tất cả'),
                (true, 'Sử dụng'),
                (false, 'Còn trống'),
              ])
                Expanded(
                  child: _OccupancyTab(
                    key: ValueKey('table-filter-${filter.$1}'),
                    label: filter.$2,
                    // Counts follow the loaded snapshot; hide them until then.
                    count: c.loading && c.countWhere(null) == 0
                        ? null
                        : c.countWhere(filter.$1),
                    selected: c.query.occupied == filter.$1,
                    onTap: c.selecting
                        ? null
                        : () => c.filter(
                            occupied: filter.$1,
                            areaId: c.query.areaId,
                          ),
                  ),
                ),
            ],
          ),
          const Divider(height: 1),
        ],
        if (qrAllowed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => showQrRequestInbox(
                      context,
                      ref,
                      tableNames: {
                        for (final table in c.tables) table.id: table.name,
                      },
                    ),
                    icon: Icon(
                      qr.failure == null ? Icons.qr_code_2 : Icons.sync_problem,
                    ),
                    label: Text('Yêu cầu QR (${qr.pending.length})'),
                  ),
                  if (qr.failure != null)
                    const StatusBadge(
                      label: 'QR chưa đồng bộ',
                      tone: AppTone.warning,
                      icon: Icons.sync_problem,
                    ),
                  if (qr.arrivals > 0 && qr.failure == null)
                    StatusBadge(
                      label: 'Có ${qr.arrivals} yêu cầu QR mới',
                      tone: AppTone.info,
                      dot: true,
                    ),
                ],
              ),
            ),
          ),
        if (c.tableAccess)
          SizedBox(
            height: 58 + (MediaQuery.textScalerOf(context).scale(14) - 14) * 2,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Tất cả khu vực'),
                    selected: c.query.areaId == null,
                    onSelected: c.selecting
                        ? null
                        : (_) => c.filter(occupied: c.query.occupied),
                  ),
                ),
                for (final area in c.areas)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(area.name),
                      selected: c.query.areaId == area.id,
                      onSelected: c.selecting
                          ? null
                          : (_) => c.filter(
                              occupied: c.query.occupied,
                              areaId: area.id,
                            ),
                    ),
                  ),
              ],
            ),
          ),
        // Cards stay visible but locked without the menu; say why once.
        if (!menuAllowed && (c.takeawayAllowed || c.dineInAllowed))
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Bạn chưa có quyền xem thực đơn nên chưa chọn được món. Liên hệ người quản lý để được cấp quyền.',
            ),
          ),
        if (c.loading || c.billsLoading || c.selecting)
          const LinearProgressIndicator(),
        OrderFailurePanel(failure: c.areasFailure, retry: c.loadAreas),
        OrderFailurePanel(failure: c.failure, retry: c.refresh),
        OrderFailurePanel(
          failure: c.billsFailure,
          retry: c.load,
          label: 'Tải lại tiền đơn',
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: c.refresh,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tables = c.tables;
                final takeaway = c.takeawayAllowed;
                return GridView.builder(
                  key: const ValueKey('order-table-grid'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:
                        qrAllowed &&
                            qr.pending.isNotEmpty &&
                            MediaQuery.textScalerOf(context).scale(14) > 22
                        ? (constraints.maxWidth / 320).floor().clamp(1, 6)
                        : constraints.maxWidth < 300
                        ? 1
                        : constraints.maxWidth < 600
                        ? 2
                        : (constraints.maxWidth / 200).floor().clamp(3, 6),
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    // Includes the status strip and badge; 22 of it is the
                    // guests · seated-for line.
                    mainAxisExtent:
                        192 +
                        (MediaQuery.textScalerOf(context).scale(14) - 14) * 8 +
                        (!qrAllowed || qr.pending.isEmpty
                            ? 0
                            : 52 +
                                  (MediaQuery.textScalerOf(context).scale(14) -
                                          14) *
                                      2),
                  ),
                  itemCount: tables.length + (takeaway ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (takeaway && index == 0) {
                      return _TakeawayCard(menuAllowed: menuAllowed);
                    }
                    final table = tables[index - (takeaway ? 1 : 0)];
                    final tile = c.tile(table);
                    final qrRequests = qrAllowed
                        ? qr.forTable(table.id, table.currentSession?.id).length
                        : 0;
                    final hasUnconfirmedOrder =
                        tile.order?.status == OrderStatus.open;
                    final subtitle = switch (tile.billState) {
                      TableBillState.noSession => 'Còn trống',
                      TableBillState.noOrder => 'Đang sử dụng · Chưa có đơn',
                      TableBillState.inconsistent => 'Cần đồng bộ phiên/đơn',
                      TableBillState.ready when hasUnconfirmedOrder =>
                        'Chưa xác nhận',
                      _ => 'Đang sử dụng',
                    };
                    final amount = switch (tile.billState) {
                      TableBillState.ready =>
                        'Tổng: ${orderMoney(BigInt.from(tile.order!.totalAmount.minorUnits), currency: tile.order!.currencyCode)}',
                      TableBillState.loading => 'Đang tải tiền đơn…',
                      TableBillState.unknown => 'Chưa tải được tiền đơn',
                      TableBillState.forbidden => 'Không có quyền xem đơn',
                      TableBillState.inconsistent => '—',
                      _ => null,
                    };
                    return OrderContextCard(
                      key: ValueKey('order-table-${table.id}'),
                      name: table.name,
                      icon: Icons.table_restaurant,
                      hasOrder: tile.order != null,
                      hasUnconfirmedOrder: hasUnconfirmedOrder,
                      guests: table.currentSession?.guestCount,
                      seatedSince: table.currentSession?.openedAt,
                      qrRequests: qrRequests,
                      onQrTap: qrRequests == 0
                          ? null
                          : () => showQrRequestInbox(
                              context,
                              ref,
                              tableId: table.id,
                              tableNames: {table.id: table.name},
                            ),
                      subtitle: table.area?.active == false
                          ? '$subtitle\nKhu vực ngừng hoạt động'
                          : subtitle,
                      amount: amount,
                      onTap: c.canSelect(table)
                          ? () => _select(context, ref, table)
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ),
        if (c.tableAccess &&
            !c.loading &&
            c.failure == null &&
            c.tables.isEmpty)
          const EmptyState(
            icon: Icons.table_restaurant_outlined,
            message: 'Không có bàn phù hợp.',
          ),
      ],
    );
    // Polling the QR queue is only worth it for someone who can act on it.
    return qrAllowed ? QrInboxVisibility(child: body) : body;
  }
}

/// Entry to takeaway orders: shows how many are in progress and opens the
/// takeaway board; the "+" button still starts a new order in one tap.
class _TakeawayCard extends ConsumerWidget {
  const _TakeawayCard({required this.menuAllowed});
  final bool menuAllowed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(currentSessionProvider);
    final canView = AccessPolicy.canTakeawayOrders(session);
    final counts = canView
        ? ref.watch(
            takeawayOrdersProvider.select(
              (board) => board.hasLoaded
                  ? (
                      board.activeCount,
                      board.stage(TakeawayStage.waiting).length,
                    )
                  : null,
            ),
          )
        : null;
    void create() => context.push('/app/order-create?serviceType=TAKEAWAY');
    return OrderContextCard(
      name: 'Mang đi',
      icon: Icons.shopping_bag_outlined,
      hasOrder: (counts?.$1 ?? 0) > 0,
      hasUnconfirmedOrder: (counts?.$2 ?? 0) > 0,
      subtitle: counts == null
          ? null
          : counts.$1 == 0
          ? 'Chưa có đơn đang chờ'
          : '${counts.$1} đơn đang chờ',
      onTap: canView
          ? () => context.push('/app/takeaway')
          : menuAllowed
          ? create
          : null,
      action: canView && menuAllowed
          ? IconButton(
              key: const ValueKey('takeaway-create'),
              tooltip: 'Tạo đơn mang đi',
              visualDensity: VisualDensity.compact,
              onPressed: create,
              icon: const Icon(Icons.add_circle_outline),
            )
          : null,
    );
  }
}

class OrderContextCard extends StatelessWidget {
  const OrderContextCard({
    super.key,
    required this.name,
    required this.icon,
    this.hasOrder = false,
    this.hasUnconfirmedOrder = false,
    this.guests,
    this.seatedSince,
    this.qrRequests = 0,
    this.onQrTap,
    this.subtitle,
    this.amount,
    this.onTap,
    this.action,
  });
  final String name;
  final IconData icon;
  final bool hasOrder;
  final bool hasUnconfirmedOrder;

  /// Guests and opening time of the table's serving session, if any.
  final int? guests;
  final DateTime? seatedSince;
  final int qrRequests;
  final VoidCallback? onQrTap;
  final String? subtitle, amount;
  final VoidCallback? onTap;

  /// Optional secondary button in the bottom row (e.g. create a new order).
  final Widget? action;

  /// Waiting for confirmation stands out most, then a running bill; a free
  /// table stays quiet so busy tables are found at a glance.
  AppTone get _tone => hasUnconfirmedOrder
      ? AppTone.warning
      : hasOrder
      ? AppTone.success
      : AppTone.neutral;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tone = context.tone(_tone);
    final active = hasOrder || hasUnconfirmedOrder;
    return Semantics(
      button: true,
      enabled: onTap != null,
      excludeSemantics: qrRequests == 0,
      label: qrRequests == 0
          ? [
              name,
              subtitle,
              if (guests != null) '$guests khách',
              if (seatedSince != null)
                'ngồi ${formatElapsed(DateTime.now().difference(seatedSince!))}',
              amount,
            ].whereType<String>().join(', ')
          : null,
      child: Material(
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(
            color: active ? tone.border : colors.outlineVariant,
            width: active ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status strip: colour reads before any text does.
              ColoredBox(
                color: active ? tone.foreground : colors.surface,
                child: const SizedBox(height: 4),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: active
                                  ? tone.background
                                  : colors.surfaceContainer,
                              borderRadius: AppRadius.smAll,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(5),
                              child: Icon(
                                icon,
                                size: 18,
                                color: active
                                    ? tone.foreground
                                    : colors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (qrRequests > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: TextButton(
                            key: const ValueKey('table-qr-requests'),
                            style: TextButton.styleFrom(
                              foregroundColor: context
                                  .tone(AppTone.info)
                                  .foreground,
                              backgroundColor: context
                                  .tone(AppTone.info)
                                  .background,
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                            ),
                            onPressed: onQrTap,
                            child: Text(
                              'QR · $qrRequests yêu cầu mới',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium,
                            ),
                          ),
                        ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: StatusBadge(
                            label: subtitle!,
                            tone: _tone,
                            dot: true,
                            maxLines: 3,
                          ),
                        ),
                      if (seatedSince != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: _SeatedInfo(
                            guests: guests,
                            since: seatedSince!,
                          ),
                        ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (amount != null)
                            Expanded(
                              child: Text(
                                amount!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.money,
                              ),
                            ),
                          if (amount == null && action != null) const Spacer(),
                          if (action != null) action!,
                          if (onTap == null)
                            Icon(
                              Icons.lock_outline,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the "Tất cả / Sử dụng / Còn trống" filters: the chosen one is
/// marked by weight, colour and an underline, not by text colour alone.
class _OccupancyTab extends StatelessWidget {
  const _OccupancyTab({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = selected ? colors.primary : colors.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? colors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 2,
            children: [
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (count != null)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.primary.withValues(alpha: 0.12)
                        : colors.surfaceContainer,
                    borderRadius: AppRadius.pillAll,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    child: Text(
                      '$count',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "6 khách · 45 phút" for a table in use; the time moves on by itself with
/// the shared minute clock instead of a timer per table.
class _SeatedInfo extends StatelessWidget {
  const _SeatedInfo({required this.guests, required this.since});
  final int? guests;
  final DateTime since;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    // One line, so the card height stays predictable at large text.
    return Row(
      key: const ValueKey('table-seated-info'),
      children: [
        Icon(Icons.schedule, size: 14, color: muted),
        const SizedBox(width: 4),
        Expanded(
          child: MinuteTickerBuilder(
            builder: (context, now) {
              final elapsed = now.difference(since);
              final seated = formatElapsed(
                elapsed.isNegative ? Duration.zero : elapsed,
              );
              return Text(
                guests == null ? seated : '$guests khách · $seated',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              );
            },
          ),
        ),
      ],
    );
  }
}
