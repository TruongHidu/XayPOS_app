import 'package:flutter/material.dart';
import '../../../order/domain/entities/order_entities.dart';
import '../../domain/entities/kitchen_queue.dart';

abstract final class KitchenStyle {
  static const background = Color(0xFFF1F3F5);
  static const cardBackground = Colors.white;
  static const borderColor = Color(0xFFE2E8F0);

  static Color color(OrderItemStatus status) => switch (status) {
    OrderItemStatus.pending => const Color(0xFFB45309),
    OrderItemStatus.cooking => const Color(0xFF1D4ED8),
    _ => const Color(0xFF15803D),
  };

  static Color bgColor(OrderItemStatus status) => switch (status) {
    OrderItemStatus.pending => const Color(0xFFFFFBEB),
    OrderItemStatus.cooking => const Color(0xFFEFF6FF),
    _ => const Color(0xFFF0FDF4),
  };

  static Color borderColorFor(OrderItemStatus status) => switch (status) {
    OrderItemStatus.pending => const Color(0xFFFDE68A),
    OrderItemStatus.cooking => const Color(0xFFBFDBFE),
    _ => const Color(0xFFBBF7D0),
  };

  static String label(OrderItemStatus status) => switch (status) {
    OrderItemStatus.pending => 'Chờ nấu',
    OrderItemStatus.cooking => 'Đang nấu',
    _ => 'Sẵn sàng',
  };

  static const warningAfter = Duration(minutes: 20);
}

class KitchenStatusBadge extends StatelessWidget {
  const KitchenStatusBadge({super.key, required this.status});
  final OrderItemStatus status;

  @override
  Widget build(BuildContext context) {
    final color = KitchenStyle.color(status);
    final bg = KitchenStyle.bgColor(status);
    final border = KitchenStyle.borderColorFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Text(
        KitchenStyle.label(status),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class KitchenQueueContext extends StatelessWidget {
  const KitchenQueueContext({super.key, required this.item, required this.now});
  final KitchenQueueItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final elapsed = now.difference(item.queuedAt);
    final minutes = elapsed.inMinutes.clamp(0, 99999);
    final local = item.queuedAt.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    final isDelayed = elapsed >= KitchenStyle.warningAfter;
    final timerColor = isDelayed
        ? const Color(0xFFB91C1C)
        : Colors.blueGrey.shade700;

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
              color: const Color(0xFF334155),
            ),
            Text(
              item.seating.isEmpty ? 'Tại bàn' : item.seating,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Color(0xFF334155),
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
                color: Colors.blueGrey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
            Text(
              '$minutes phút · $time',
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
  });
  final KitchenQueueItem item;
  final DateTime now;
  final bool busy;
  final VoidCallback? onStart, onReady;

  @override
  Widget build(BuildContext context) {
    final statusColor = KitchenStyle.color(item.itemStatus);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 3.5,
            color: statusColor,
          ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
                    color: Color(0xFF0F172A),
                    height: 1.25,
                  ),
                ),
                if (item.note?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Text(
                      'Ghi chú: ${item.note}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const Divider(height: 16, thickness: 1, color: Color(0xFFF1F5F9)),
                KitchenQueueContext(item: item, now: now),
                const SizedBox(height: 10),
                if (item.itemStatus == OrderItemStatus.ready)
                  const Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline, color: Color(0xFF15803D), size: 18),
                      Text(
                        'Sẵn sàng phục vụ',
                        style: TextStyle(
                          color: Color(0xFF15803D),
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
                      minimumSize: const Size(double.infinity, 42),
                      backgroundColor: statusColor,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
    this.orderStatus,
  });
  final List<KitchenQueueItem> items;
  final DateTime now;
  final bool complete, busy;
  final OrderStatus? orderStatus;
  final VoidCallback? onReadyOrder;
  final VoidCallback? Function(KitchenQueueItem) actionFor;

  @override
  Widget build(BuildContext context) {
    final ready = items
        .where((r) => r.itemStatus == OrderItemStatus.ready)
        .length;
    final allReady = ready == items.length;
    final hasCooking = items.any((r) => r.itemStatus == OrderItemStatus.cooking);
    final headerAccentColor = allReady
        ? const Color(0xFF15803D)
        : hasCooking
        ? const Color(0xFF1D4ED8)
        : const Color(0xFFB45309);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 3.5,
            color: headerAccentColor,
          ),
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
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),
                KitchenQueueContext(item: items.first, now: now),
                const SizedBox(height: 8),
                Text(
                  '$ready/${items.length} dòng trong queue đã sẵn sàng${complete ? '' : ' · Chưa đủ dữ liệu'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.blueGrey.shade700,
                  ),
                ),
                for (final item in items) ...[
                  const Divider(height: 18, thickness: 1, color: Color(0xFFF1F5F9)),
                  Text(
                    '${item.quantity} ${item.unit} · ${item.itemName}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
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
                          color: Color(0xFF92400E),
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
                            minimumSize: const Size(40, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                const Divider(height: 18, thickness: 1, color: Color(0xFFF1F5F9)),
                const SizedBox(height: 4),
                if (orderStatus == OrderStatus.ready)
                  const Text(
                    '✓ Đơn đã sẵn sàng',
                    style: TextStyle(
                      color: Color(0xFF15803D),
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  )
                else if (orderStatus == OrderStatus.served)
                  const Text(
                    'Đơn đã được phục vụ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  )
                else
                  FilledButton.icon(
                    key: ValueKey('ready-order-${items.first.orderId}'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tổng hợp món cần nấu${complete ? '' : ' · Chưa đủ dữ liệu'}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (summaries.isEmpty)
            const Text(
              'Không có món chờ nấu hoặc đang nấu.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final summary in summaries)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: KitchenStyle.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
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
