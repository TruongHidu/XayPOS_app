import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/policies/order_access_policy.dart';
import '../../domain/use_cases/order_use_cases.dart';
import 'order_append_dialog.dart';
import 'order_mutation_forms.dart';
import 'order_payment_dialog.dart';
import 'order_widgets.dart';

enum TakeawayQuickAction {
  confirm('Xác nhận', Icons.send_outlined),
  append('Gọi thêm', Icons.add),
  pay('Thanh toán', Icons.payments_outlined),
  complete('Giao khách & hoàn tất', Icons.task_alt);

  const TakeawayQuickAction(this.label, this.icon);
  final String label;
  final IconData icon;
}

const _working = {
  OrderStatus.confirmed,
  OrderStatus.preparing,
  OrderStatus.ready,
  OrderStatus.served,
};

/// Which shortcuts the card offers. The summary decides visibility; the full
/// order is re-checked when a shortcut is pressed.
List<TakeawayQuickAction> takeawayQuickActions(
  OrderSummary order,
  WidgetRef ref,
) {
  final session = ref.watch(authControllerProvider).state.session;
  final unpaid = order.paymentStatus == OrderPaymentStatus.unpaid;
  return [
    if (order.status == OrderStatus.open &&
        AccessPolicy.canOrders(session, 'ORDER_UPDATE'))
      TakeawayQuickAction.confirm,
    if (unpaid &&
        _working.contains(order.status) &&
        order.totalAmount.minorUnits > 0 &&
        AccessPolicy.canRecordOrderPayment(session))
      TakeawayQuickAction.pay,
    if (order.paymentStatus == OrderPaymentStatus.paid &&
        _working.contains(order.status) &&
        AccessPolicy.canCompleteOrder(session, takeaway: true))
      TakeawayQuickAction.complete,
    if (unpaid &&
        (order.status == OrderStatus.open || _working.contains(order.status)) &&
        AccessPolicy.canAppendOrder(session, takeaway: true) &&
        AccessPolicy.canMenu(session, 'MENU_VIEW'))
      TakeawayQuickAction.append,
  ];
}

/// "5 phút", "1 giờ 10 phút": how long the customer has been waiting.
String takeawayWaited(DateTime createdAt, DateTime now) {
  final minutes = now.difference(createdAt).inMinutes;
  if (minutes < 1) return 'Vừa đặt';
  if (minutes < 60) return '$minutes phút';
  final rest = minutes % 60;
  return '${minutes ~/ 60} giờ${rest == 0 ? '' : ' $rest phút'}';
}

class TakeawayOrderCard extends ConsumerStatefulWidget {
  const TakeawayOrderCard({super.key, required this.order, this.onOpen});
  final OrderSummary order;
  final VoidCallback? onOpen;

  @override
  ConsumerState<TakeawayOrderCard> createState() => _TakeawayOrderCardState();
}

class _TakeawayOrderCardState extends ConsumerState<TakeawayOrderCard> {
  TakeawayQuickAction? _busy;

  Future<void> _run(TakeawayQuickAction action) async {
    setState(() => _busy = action);
    // Dialogs need the full order (items, latest version), not the summary.
    final result = await GetOrderDetail(ref.read(orderRepositoryProvider))(
      widget.order.id,
    );
    if (!mounted) return;
    setState(() => _busy = null);
    final messenger = ScaffoldMessenger.maybeOf(context);
    switch (result) {
      case Error(failure: final failure):
        messenger?.showSnackBar(SnackBar(content: Text(failure.message)));
      case Success(value: final order):
        final problem = switch (action) {
          TakeawayQuickAction.confirm
              when !OrderAccessPolicy.canConfirm(order, true) =>
            'Đơn chưa có món hoặc đã đổi trạng thái. Hãy mở đơn để kiểm tra.',
          TakeawayQuickAction.pay when !OrderAccessPolicy.canPay(order, true) =>
            'Đơn không còn ở trạng thái chờ thanh toán.',
          TakeawayQuickAction.complete
              when !OrderAccessPolicy.canServeAndComplete(order, true) =>
            'Đơn chưa đủ điều kiện hoàn tất. Hãy mở đơn để kiểm tra.',
          TakeawayQuickAction.append
              when !OrderAccessPolicy.canAppend(order, true) =>
            'Đơn đã thanh toán hoặc kết thúc, không gọi thêm được.',
          _ => null,
        };
        if (problem != null) {
          messenger?.showSnackBar(SnackBar(content: Text(problem)));
          await ref.read(takeawayOrdersProvider).load();
          return;
        }
        await switch (action) {
          TakeawayQuickAction.confirm => showOrderDialog<void>(
            context,
            ref,
            permission: 'ORDER_UPDATE',
            child: OrderMutationForm(
              order: order,
              action: OrderFormAction.confirm,
            ),
          ),
          TakeawayQuickAction.append => showOrderDialog<void>(
            context,
            ref,
            permission: 'ORDER_UPDATE',
            child: OrderAppendDialog(order: order),
          ),
          TakeawayQuickAction.pay => showOrderPaymentDialog(
            context,
            ref,
            order,
          ),
          TakeawayQuickAction.complete => showOrderCompletionDialog(
            context,
            ref,
            order,
          ),
        };
        if (mounted) await ref.read(takeawayOrdersProvider).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final actions = takeawayQuickActions(order, ref);
    final paid = order.paymentStatus == OrderPaymentStatus.paid;
    final name = order.customerName?.trim();
    return Card(
      key: ValueKey('takeaway-order-${order.id}'),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: order.status == OrderStatus.ready
              ? const Color(0xFF16A34A)
              : const Color(0xFFE5E7EB),
          width: order.status == OrderStatus.ready ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    order.orderCode,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFF111827),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          takeawayWaited(order.createdAt, DateTime.now()),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                name == null || name.isEmpty ? 'Khách lẻ' : name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Badge(
                    order.status.label,
                    background: order.status == OrderStatus.ready
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFE0F2FE),
                    foreground: order.status == OrderStatus.ready
                        ? const Color(0xFF15803D)
                        : const Color(0xFF0284C7),
                  ),
                  _Badge(
                    order.paymentStatus.label,
                    background: paid
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEF3C7),
                    foreground: paid
                        ? const Color(0xFF15803D)
                        : const Color(0xFFB45309),
                  ),
                  Text(
                    orderMoney(
                      BigInt.from(order.totalAmount.minorUnits),
                      currency: order.currencyCode,
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: OrderPalette.orange,
                    ),
                  ),
                ],
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (index, action) in actions.indexed)
                      _actionButton(action, primary: index == 0),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton(TakeawayQuickAction action, {required bool primary}) {
    final icon = _busy == action
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(action.icon, size: 18);
    final onPressed = _busy == null ? () => _run(action) : null;
    final label = Text(action.label);
    return primary
        ? FilledButton.icon(onPressed: onPressed, icon: icon, label: label)
        : OutlinedButton.icon(onPressed: onPressed, icon: icon, label: label);
  }
}

class _Badge extends StatelessWidget {
  const _Badge(
    this.label, {
    required this.background,
    required this.foreground,
  });
  final String label;
  final Color background, foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: foreground,
      ),
    ),
  );
}
