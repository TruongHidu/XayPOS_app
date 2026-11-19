import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_status_colors.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/ui/widgets/elapsed_text.dart';
import '../../../../core/ui/widgets/status_badge.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/policies/order_access_policy.dart';
import '../../domain/use_cases/order_use_cases.dart';
import 'order_append_navigation.dart';
import 'order_mutation_forms.dart';
import 'order_payment_dialog.dart';
import 'order_widgets.dart';
import '../../../../app/theme/app_tokens.dart';

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
  final session = ref.watch(currentSessionProvider);
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
          TakeawayQuickAction.append => openOrderAppend(context, order.id),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final order = widget.order;
    final actions = takeawayQuickActions(order, ref);
    final paid = order.paymentStatus == OrderPaymentStatus.paid;
    final ready = order.status == OrderStatus.ready;
    final name = order.customerName?.trim();
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Card(
      key: ValueKey('takeaway-order-${order.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        // A ready order stands out: it is waiting for the customer.
        side: BorderSide(
          color: ready
              ? context.tone(AppTone.success).foreground
              : colors.outlineVariant,
          width: ready ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Name, code and badges open the order; the buttons stay apart.
            InkWell(
              borderRadius: AppRadius.smAll,
              onTap: widget.onOpen,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Name left, waiting time right; with large text the time
                  // takes its own line.
                  OverflowBar(
                    alignment: MainAxisAlignment.spaceBetween,
                    spacing: AppSpacing.sm,
                    overflowSpacing: 2,
                    children: [
                      Text(
                        name == null || name.isEmpty ? 'Khách lẻ' : name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: MinuteTickerBuilder(
                                builder: (context, now) => Text(
                                  takeawayWaited(order.createdAt, now),
                                  style: muted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // The full code, never cut: it is what the bill shows.
                  Text(order.orderCode, style: muted),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          StatusBadge(
                            label: order.status.label,
                            tone: ready ? AppTone.success : AppTone.info,
                            icon: ready
                                ? Icons.check_circle_outline
                                : Icons.restaurant_outlined,
                          ),
                          StatusBadge(
                            label: order.paymentStatus.label,
                            tone: paid ? AppTone.success : AppTone.warning,
                            icon: paid
                                ? Icons.paid_outlined
                                : Icons.hourglass_empty,
                          ),
                        ],
                      ),
                      Text(
                        orderMoney(
                          BigInt.from(order.totalAmount.minorUnits),
                          currency: order.currencyCode,
                        ),
                        softWrap: false,
                        style: theme.textTheme.moneyLarge,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _actionRow(actions),
            ],
          ],
        ),
      ),
    );
  }

  /// Equal-width 48dp buttons, the main one last (under the right thumb);
  /// stacked when large text leaves no room side by side.
  Widget _actionRow(List<TakeawayQuickAction> actions) {
    final ordered = [...actions.skip(1), actions.first];
    final buttons = [
      for (final action in ordered)
        _actionButton(action, primary: identical(action, actions.first)),
    ];
    final stacked = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3;
    if (stacked || buttons.length > 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, button) in buttons.reversed.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            button,
          ],
        ],
      );
    }
    return Row(
      children: [
        for (final (i, button) in buttons.indexed) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          Expanded(child: button),
        ],
      ],
    );
  }

  Widget _actionButton(TakeawayQuickAction action, {required bool primary}) {
    final icon = _busy == action
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(action.icon, size: 18);
    final onPressed = _busy == null ? () => _run(action) : null;
    final label = Text(action.label, textAlign: TextAlign.center);
    const size = Size(0, 48);
    return primary
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: icon,
            label: label,
            style: FilledButton.styleFrom(minimumSize: size),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: icon,
            label: label,
            style: OutlinedButton.styleFrom(minimumSize: size),
          );
  }
}
