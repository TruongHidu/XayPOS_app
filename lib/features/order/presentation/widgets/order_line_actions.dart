import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_item_action.dart';
import '../../domain/policies/order_access_policy.dart';
import 'order_mutation_forms.dart';
import 'order_widgets.dart';

class OrderLineLayout extends StatelessWidget {
  const OrderLineLayout({
    super.key,
    required this.thumbnail,
    required this.details,
    required this.actions,
  });
  final Widget thumbnail, details, actions;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxWidth < 480 ||
          MediaQuery.textScalerOf(context).scale(14) > 22;
      final description = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          thumbnail,
          const SizedBox(width: 12),
          Expanded(child: details),
        ],
      );
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [description, const SizedBox(height: 12), actions],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: description),
          const SizedBox(width: 12),
          actions,
        ],
      );
    },
  );
}

class OrderLineActions extends ConsumerWidget {
  const OrderLineActions({
    super.key,
    required this.order,
    required this.line,
    required this.child,
  });
  final OrderDetail order;
  final OrderLine line;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(orderDetailProvider(order.id));
    final terminal = const {
      OrderStatus.completed,
      OrderStatus.cancelled,
    }.contains(order.summary.status);
    final enabled =
        !terminal &&
        !controller.busy &&
        !controller.loading &&
        !controller.blocked &&
        !controller.requiresVerification &&
        (OrderItemAction.next(line.status) != null ||
            controller.lineCancellable(line));
    return InkWell(
      key: ValueKey('order-line-actions-${line.id}'),
      borderRadius: BorderRadius.circular(12),
      onTap: !enabled
          ? null
          : () async {
              final cancel = await showOrderDialog<bool>(
                context,
                ref,
                permission: 'ORDER_VIEW',
                child: _LineDialog(order: order, line: line),
              );
              if (cancel != true || !context.mounted) return;
              await showOrderDialog<void>(
                context,
                ref,
                permission: OrderAccessPolicy.lineCancelPermission(order),
                child: OrderMutationForm(
                  order: order,
                  action: OrderFormAction.cancelLine,
                  line: line,
                ),
              );
            },
      child: child,
    );
  }
}

class _LineDialog extends ConsumerWidget {
  const _LineDialog({required this.order, required this.line});
  final OrderDetail order;
  final OrderLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(orderDetailProvider(order.id));
    final changed = controller.order?.version != order.version;
    final action = OrderItemAction.next(line.status);
    return PopScope(
      canPop: !controller.busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(line.itemName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${line.quantity} ${line.unit} · ${line.status.label}'),
            if (line.note?.isNotEmpty == true) Text('Ghi chú: ${line.note}'),
            const SizedBox(height: 12),
            if (order.summary.status == OrderStatus.open)
              const Text('Xác nhận đơn trước khi chuyển trạng thái món.'),
            if (line.status == OrderItemStatus.cooking)
              const Text('Món đang chế biến không thể hủy.'),
            if (!order.unpaid)
              const Text('Đơn đã có thanh toán nên không thể hủy món.'),
            if (changed)
              const Text(
                'Đơn đã thay đổi. Đóng và mở lại món để xem trạng thái mới.',
              ),
            if (action != null &&
                order.summary.status != OrderStatus.open &&
                !changed &&
                !controller.busy &&
                !controller.requiresVerification &&
                !controller.lineTransitionable(line, action))
              const Text(
                'Bạn chưa có quyền thực hiện bước tiếp theo hoặc tính năng chưa khả dụng.',
              ),
            if (controller.busy) const LinearProgressIndicator(),
            OrderFailurePanel(
              failure: controller.failure,
              retry: controller.requiresVerification && !controller.busy
                  ? controller.load
                  : null,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: controller.busy
                ? null
                : () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
          if (!changed && controller.lineCancellable(line))
            TextButton(
              onPressed: controller.busy
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('Hủy món'),
            ),
          if (action != null)
            FilledButton(
              onPressed: changed || !controller.lineTransitionable(line, action)
                  ? null
                  : () async {
                      final result = await controller.transitionLine(
                        line,
                        action,
                        order.version,
                      );
                      if (!context.mounted || !controller.current) return;
                      if (result is Success<OrderDetail>) {
                        Navigator.of(context).pop();
                      }
                    },
              child: Text(action.label),
            ),
        ],
      ),
    );
  }
}
