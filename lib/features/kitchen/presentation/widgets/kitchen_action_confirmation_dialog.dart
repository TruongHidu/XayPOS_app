import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../app/providers.dart';
import '../../domain/entities/kitchen_queue.dart';
import '../providers/kitchen_providers.dart';

class KitchenActionConfirmationDialog extends ConsumerWidget {
  const KitchenActionConfirmationDialog({
    super.key,
    required this.item,
    required this.scope,
    this.wholeOrder = false,
  });
  final KitchenQueueItem item;
  final Object? scope;
  final bool wholeOrder;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(kitchenActionsProvider);
    final display = ref.watch(kitchenDisplayProvider);
    final currentScope = AccessPolicy.kitchenScope(
      ref.watch(authControllerProvider).state.session,
    );
    if (currentScope != scope) {
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && route?.isActive == true) {
          Navigator.of(context).removeRoute(route!);
        }
      });
      return const SizedBox.shrink();
    }
    final allowed =
        currentScope == scope &&
        (wholeOrder
            ? actions.canReadyOrder(item.orderId)
            : actions.canAct(item, KitchenAction.markReady));
    return AlertDialog(
      title: Text(wholeOrder ? 'Ready cả đơn?' : 'Xác nhận món đã xong?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.orderCode} · ${item.seating.isEmpty ? 'Tại bàn' : item.seating}',
            ),
            const SizedBox(height: 12),
            Text(
              wholeOrder
                  ? 'Xác nhận các món đang nấu đã hoàn thành? Mỗi dòng sẽ được cập nhật lần lượt.'
                  : '${item.quantity} ${item.unit} · ${item.itemName}\nXác nhận hoàn thành toàn bộ số lượng của dòng này.',
            ),
            if (wholeOrder)
              for (final row
                  in display
                      .forOrder(item.orderId)
                      .where(
                        (row) =>
                            row.itemStatus == KitchenAction.markReady.source,
                      ))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('${row.quantity} ${row.unit} · ${row.itemName}'),
                ),
            if (item.note?.trim().isNotEmpty == true && !wholeOrder) ...[
              const SizedBox(height: 8),
              Text('Ghi chú: ${item.note}'),
            ],
            if (!allowed) ...[
              const SizedBox(height: 12),
              const Text(
                'Dữ liệu hoặc quyền thao tác đã thay đổi. Hãy quay lại để kiểm tra.',
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Quay lại'),
        ),
        FilledButton(
          onPressed: allowed ? () => Navigator.of(context).pop(true) : null,
          child: Text(
            wholeOrder ? 'Xác nhận Ready cả đơn' : 'Xác nhận đã xong',
          ),
        ),
      ],
    );
  }
}
