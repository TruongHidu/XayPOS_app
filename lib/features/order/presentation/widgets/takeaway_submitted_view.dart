import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/policies/order_access_policy.dart';
import 'order_payment_dialog.dart';
import 'order_widgets.dart';

/// Shown right after a takeaway order is sent: the counter usually takes
/// payment next, or starts the next customer's order.
class TakeawaySubmittedView extends ConsumerWidget {
  const TakeawaySubmittedView({
    super.key,
    required this.order,
    this.onCreateAnother,
  });
  final OrderDetail order;
  final VoidCallback? onCreateAnother;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Seeded with the created order, so this only re-reads after a change
    // such as recording the payment.
    final c = ref.watch(orderDetailProvider(order.id));
    c.seed(order);
    final live = c.order ?? order;
    final s = live.summary;
    final session = ref.watch(authControllerProvider).state.session;
    final router = GoRouter.maybeOf(context);
    final draft = s.status == OrderStatus.open;
    final done = s.status == OrderStatus.completed;
    final canPay = OrderAccessPolicy.canPay(
      live,
      AccessPolicy.canRecordOrderPayment(session),
    );
    final canFinish = OrderAccessPolicy.canServeAndComplete(
      live,
      AccessPolicy.canCompleteOrder(session, takeaway: true),
    );
    final toBoard = AccessPolicy.canTakeawayOrders(session);
    void openDetail() =>
        router?.push('/app/takeaway/${Uri.encodeComponent(live.id)}');
    final name = s.customerName?.trim();
    final paid = s.paymentStatus == OrderPaymentStatus.paid;

    return Material(
      color: Colors.grey.shade50,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Quay lại',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: router == null
                        ? null
                        : () => router.go(
                            toBoard ? '/app/takeaway' : '/app/order-create',
                          ),
                  ),
                  const Expanded(
                    child: Text(
                      'Mang đi',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          draft
                              ? Icons.edit_note
                              : done
                              ? Icons.task_alt
                              : Icons.check_circle,
                          size: 56,
                          color: draft
                              ? const Color(0xFF9A6700)
                              : const Color(0xFF16A34A),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          draft
                              ? 'Đã tạo đơn nháp'
                              : done
                              ? 'Đơn đã hoàn tất'
                              : 'Đã gửi đơn xuống bếp',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          s.orderCode,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (name != null && name.isNotEmpty)
                          Text('Khách: $name', textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Chip(label: Text(s.status.label)),
                            Chip(
                              label: Text(s.paymentStatus.label),
                              backgroundColor: paid
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFFEF3C7),
                            ),
                            Text(
                              orderMoney(
                                BigInt.from(s.totalAmount.minorUnits),
                                currency: s.currencyCode,
                              ),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: OrderPalette.orange,
                              ),
                            ),
                          ],
                        ),
                        if (draft)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Đơn nháp chưa xuống bếp. Mở đơn để xác nhận khi sẵn sàng.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(height: 20),
                        if (canPay)
                          _Action(
                            primary: true,
                            icon: Icons.payments_outlined,
                            label: 'Thanh toán ngay',
                            onPressed: () =>
                                showOrderPaymentDialog(context, ref, live),
                          ),
                        if (canFinish)
                          _Action(
                            primary: true,
                            icon: Icons.task_alt,
                            label: 'Giao khách & hoàn tất',
                            onPressed: () =>
                                showOrderCompletionDialog(context, ref, live),
                          ),
                        if (draft && router != null)
                          _Action(
                            primary: true,
                            icon: Icons.open_in_new,
                            label: 'Mở đơn để xác nhận',
                            onPressed: openDetail,
                          ),
                        if (onCreateAnother != null)
                          _Action(
                            icon: Icons.add,
                            label: 'Tạo đơn khác',
                            onPressed: onCreateAnother!,
                          ),
                        if (toBoard && router != null)
                          _Action(
                            icon: Icons.shopping_bag_outlined,
                            label: 'Về danh sách mang đi',
                            onPressed: () => router.go('/app/takeaway'),
                          ),
                        if (router != null && !draft)
                          TextButton(
                            onPressed: openDetail,
                            child: const Text('Xem chi tiết đơn'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: primary
          ? FilledButton.icon(
              style: style,
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
            )
          : OutlinedButton.icon(
              style: style,
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
            ),
    );
  }
}
