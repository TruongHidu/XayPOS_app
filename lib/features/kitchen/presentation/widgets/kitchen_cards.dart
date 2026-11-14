import '../../../../core/ui/formatters/elapsed.dart';
import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../order/domain/entities/order_entities.dart';
import '../../domain/entities/kitchen_queue.dart';
import '../../../../core/ui/widgets/status_badge.dart';
import '../../../../app/theme/app_status_colors.dart';

abstract final class KitchenStyle {
  static const background = AppColors.grey100;
  static const cardBackground = Colors.white;
  static const borderColor = AppColors.grey200;

  static Color color(OrderItemStatus status) => switch (status) {
    OrderItemStatus.pending => AppColors.warning,
    OrderItemStatus.cooking => AppColors.infoStrong,
    _ => AppColors.success,
  };

  static Color bgColor(OrderItemStatus status) => switch (status) {
    OrderItemStatus.pending => AppColors.warningTint,
    OrderItemStatus.cooking => AppColors.infoSoft,
    _ => AppColors.successTint,
  };

  static Color borderColorFor(OrderItemStatus status) => switch (status) {
    OrderItemStatus.pending => AppColors.warningBorder,
    OrderItemStatus.cooking => AppColors.infoBorder,
    _ => AppColors.successBorder,
  };

  static AppTone tone(OrderItemStatus status) => switch (status) {
    OrderItemStatus.pending => AppTone.warning,
    OrderItemStatus.cooking => AppTone.info,
    _ => AppTone.success,
  };

  static String label(OrderItemStatus status) => switch (status) {
    OrderItemStatus.pending => 'Chờ nấu',
    OrderItemStatus.cooking => 'Đang nấu',
    _ => 'Sẵn sàng',
  };

  static const warningAfter = Duration(minutes: 20);
}

/// How long a dish has waited, in the largest units that read naturally.
String kitchenWaited(Duration elapsed) => formatElapsed(elapsed);

class KitchenStatusBadge extends StatelessWidget {
  const KitchenStatusBadge({super.key, required this.status});
  final OrderItemStatus status;

  @override
  Widget build(BuildContext context) => StatusBadge(
    label: KitchenStyle.label(status),
    tone: KitchenStyle.tone(status),
    dot: true,
  );
}

class KitchenQueueContext extends StatelessWidget {
  const KitchenQueueContext({super.key, required this.item, required this.now});
  final KitchenQueueItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final elapsed = now.difference(item.queuedAt);
    final local = item.queuedAt.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final isDelayed = elapsed >= KitchenStyle.warningAfter;
    final timerColor = isDelayed ? AppColors.dangerStrong : AppColors.grey700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              item.serviceType == ServiceType.takeaway
                  ? Icons.shopping_bag_outlined
                  : Icons.table_restaurant_outlined,
              size: 18,
              color: AppColors.grey700,
            ),
            Text(
              item.seating.isEmpty ? 'Tại bàn' : item.seating,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.grey700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              item.orderCode,
              style: TextStyle(
                color: AppColors.grey700,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
            Text(
              '${kitchenWaited(elapsed)} · $time',
              style: TextStyle(
                color: timerColor,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class KitchenItemCard extends StatelessWidget {
  const KitchenItemCard({
    super.key,
    required this.item,
    required this.now,
    required this.busy,
    this.onStart,
    this.onReady,
    this.onServe,
  });
  final KitchenQueueItem item;
  final DateTime now;
  final bool busy;
  final VoidCallback? onStart, onReady, onServe;

  @override
  Widget build(BuildContext context) {
    final statusColor = KitchenStyle.color(item.itemStatus);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.grey200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 3.5, color: statusColor),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: KitchenStyle.bgColor(item.itemStatus),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: KitchenStyle.borderColorFor(item.itemStatus),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        '${item.quantity} ${item.unit}',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    KitchenStatusBadge(status: item.itemStatus),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.itemName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.grey900,
                    height: 1.25,
                  ),
                ),
                if (item.note?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.warningTint,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.warningBorder),
                    ),
                    child: Text(
                      'Ghi chú: ${item.note}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.warning,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const Divider(
                  height: 16,
                  thickness: 1,
                  color: AppColors.grey100,
                ),
                KitchenQueueContext(item: item, now: now),
                const SizedBox(height: 10),
                if (item.itemStatus == OrderItemStatus.ready &&
                    (onServe != null || busy))
                  KitchenServeButton(
                    key: ValueKey('kitchen-serve-${item.key}'),
                    busy: busy,
                    onPressed: onServe,
                  )
                else if (item.itemStatus == OrderItemStatus.ready)
                  const Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        color: AppColors.success,
                        size: 18,
                      ),
                      Text(
                        'Sẵn sàng phục vụ',
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  )
                else
                  FilledButton.icon(
                    key: ValueKey('kitchen-action-${item.key}'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      backgroundColor: statusColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    onPressed: busy
                        ? null
                        : item.itemStatus == OrderItemStatus.pending
                        ? onStart
                        : onReady,
                    icon: busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            item.itemStatus == OrderItemStatus.pending
                                ? Icons.soup_kitchen_outlined
                                : Icons.done,
                            size: 18,
                          ),
                    label: Text(
                      busy
                          ? 'Đang xử lý…'
                          : item.itemStatus == OrderItemStatus.pending
                          ? 'Bắt đầu nấu'
                          : 'Đã xong',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class KitchenOrderCard extends StatelessWidget {
  const KitchenOrderCard({
    super.key,
    required this.items,
    required this.now,
    required this.complete,
    required this.busy,
    required this.actionFor,
    this.onReadyOrder,
    this.onServeOrder,
    this.orderStatus,
  });
  final List<KitchenQueueItem> items;
  final DateTime now;
  final bool complete, busy;
  final OrderStatus? orderStatus;
  final VoidCallback? onReadyOrder;

  /// Hands over the dishes that are ready; null when the user can't.
  final VoidCallback? onServeOrder;
  final VoidCallback? Function(KitchenQueueItem) actionFor;

  @override
  Widget build(BuildContext context) {
    final ready = items
        .where((r) => r.itemStatus == OrderItemStatus.ready)
        .length;
    final allReady = ready == items.length;
    final hasCooking = items.any(
      (r) => r.itemStatus == OrderItemStatus.cooking,
    );
    final headerAccentColor = allReady
        ? AppColors.success
        : hasCooking
        ? AppColors.infoStrong
        : AppColors.warning;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.grey200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 3.5, color: headerAccentColor),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  items.first.orderCode,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.grey900,
                  ),
                ),
                const SizedBox(height: 8),
                KitchenQueueContext(item: items.first, now: now),
                const SizedBox(height: 8),
                Text(
                  '$ready/${items.length} món đã xong${complete ? '' : ' · Chưa đủ dữ liệu'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey700,
                  ),
                ),
                for (final item in items) ...[
                  const Divider(
                    height: 18,
                    thickness: 1,
                    color: AppColors.grey100,
                  ),
                  Text(
                    '${item.quantity} ${item.unit} · ${item.itemName}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.grey800,
                    ),
                  ),
                  if (item.note?.trim().isNotEmpty == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Ghi chú: ${item.note}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      KitchenStatusBadge(status: item.itemStatus),
                      if (item.itemStatus != OrderItemStatus.ready)
                        OutlinedButton(
                          key: ValueKey('kitchen-order-action-${item.key}'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(64, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: busy ? null : actionFor(item),
                          child: Text(
                            item.itemStatus == OrderItemStatus.pending
                                ? 'Bắt đầu nấu'
                                : 'Đã xong',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                const Divider(
                  height: 18,
                  thickness: 1,
                  color: AppColors.grey100,
                ),
                const SizedBox(height: 4),
                if (orderStatus == OrderStatus.served)
                  const Text(
                    'Đơn đã được phục vụ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.grey600,
                    ),
                  )
                else if ((allReady || orderStatus == OrderStatus.ready) &&
                    (onServeOrder != null || busy))
                  KitchenServeButton(
                    key: ValueKey('serve-order-${items.first.orderId}'),
                    busy: busy,
                    onPressed: onServeOrder,
                  )
                else if (allReady || orderStatus == OrderStatus.ready)
                  const Text(
                    '✓ Chờ phục vụ',
                    style: TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  )
                // A button that can't be pressed is noise; it appears once
                // the whole order can be marked ready.
                else if (onReadyOrder != null || busy)
                  FilledButton.icon(
                    key: ValueKey('ready-order-${items.first.orderId}'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    onPressed: busy ? null : onReadyOrder,
                    icon: const Icon(Icons.done_all, size: 18),
                    label: Text(
                      busy ? 'Đang xử lý…' : 'Ready cả đơn',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Green "Đã giao" button shared by order cards and the serving list.
class KitchenServeButton extends StatelessWidget {
  const KitchenServeButton({
    super.key,
    required this.busy,
    this.onPressed,
    this.compact = false,
  });
  final bool busy, compact;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => FilledButton.icon(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.success,
      minimumSize: Size(compact ? 64 : double.infinity, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      elevation: 0,
    ),
    onPressed: busy ? null : onPressed,
    icon: busy
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.room_service_outlined, size: 18),
    label: Text(
      busy ? 'Đang xử lý…' : 'Đã giao',
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
    ),
  );
}

/// Ready dishes waiting to be taken out, one compact row per order, so the
/// to-do view stays about cooking.
class KitchenServingList extends StatelessWidget {
  const KitchenServingList({
    super.key,
    required this.orders,
    required this.now,
    required this.expanded,
    required this.onToggle,
    required this.busy,
    required this.onServe,
  });
  final List<List<KitchenQueueItem>> orders;
  final DateTime now;
  final bool expanded;
  final VoidCallback onToggle;
  final bool Function(String orderId) busy;

  /// Null for an order the user can't hand over.
  final VoidCallback? Function(String orderId) onServe;

  @override
  Widget build(BuildContext context) {
    final dishes = orders.fold(0, (sum, order) => sum + order.length);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.successBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('kitchen-serving-toggle'),
            onTap: onToggle,
            child: Container(
              color: AppColors.successTint,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.success,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chờ phục vụ · $dishes món, ${orders.length} đơn',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (expanded)
            for (var i = 0; i < orders.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.grey100),
              _ServingRow(
                key: ValueKey('kitchen-serving-${orders[i].first.orderId}'),
                items: orders[i],
                now: now,
                busy: busy(orders[i].first.orderId),
                onServe: onServe(orders[i].first.orderId),
              ),
            ],
        ],
      ),
    );
  }
}

class _ServingRow extends StatelessWidget {
  const _ServingRow({
    super.key,
    required this.items,
    required this.now,
    required this.busy,
    this.onServe,
  });
  final List<KitchenQueueItem> items;
  final DateTime now;
  final bool busy;
  final VoidCallback? onServe;
  @override
  Widget build(BuildContext context) {
    final first = items.first;
    // The oldest dish decides how long the order has waited.
    final since = items
        .map((r) => r.queuedAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final elapsed = now.difference(since);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  first.seating.isEmpty ? first.orderCode : first.seating,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: AppColors.grey900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    for (final r in items)
                      '${r.quantity} ${r.unit} ${r.itemName}',
                  ].join(', '),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.grey700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Chờ ${kitchenWaited(elapsed)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: elapsed >= KitchenStyle.warningAfter
                        ? AppColors.dangerStrong
                        : AppColors.grey700,
                  ),
                ),
              ],
            ),
          ),
          if (onServe != null || busy) ...[
            const SizedBox(width: 8),
            KitchenServeButton(
              key: ValueKey('serve-row-${first.orderId}'),
              busy: busy,
              compact: true,
              onPressed: onServe,
            ),
          ],
        ],
      ),
    );
  }
}

class KitchenSummaryBar extends StatelessWidget {
  const KitchenSummaryBar({
    super.key,
    required this.items,
    required this.complete,
  });
  final List<KitchenQueueItem> items;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final summaries = summarizeKitchenDishes(items);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tổng hợp món cần nấu${complete ? '' : ' · Chưa đủ dữ liệu'}',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (summaries.isEmpty)
            const Text(
              'Không có món chờ nấu hoặc đang nấu.',
              style: TextStyle(color: AppColors.grey500, fontSize: 13),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final summary in summaries)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: KitchenStyle.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.grey200),
                  ),
                  child: Text(
                    '${summary.quantity} ${summary.unit} · ${summary.name}'
                    '${summary.note?.isNotEmpty == true ? ' · ${summary.note}' : ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
