import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_payment.dart';
import '../controllers/order_settlement_controller.dart';
import 'order_widgets.dart';

Future<void> showOrderPaymentDialog(
  BuildContext context,
  WidgetRef ref,
  OrderDetail order,
) => _showSettlementDialog(
  context,
  ref,
  order,
  completing: false,
  child: OrderPaymentDialog(order: order),
);

Future<void> showOrderCompletionDialog(
  BuildContext context,
  WidgetRef ref,
  OrderDetail order,
) => _showSettlementDialog(
  context,
  ref,
  order,
  completing: true,
  child: OrderCompletionDialog(order: order),
);

Future<void> _showSettlementDialog(
  BuildContext context,
  WidgetRef ref,
  OrderDetail order, {
  required bool completing,
  required Widget child,
}) async {
  final session = ref.read(authControllerProvider).state.session;
  final allowed = completing
      ? AccessPolicy.canCompleteOrder(
          session,
          takeaway: order.summary.serviceType == ServiceType.takeaway,
        )
      : AccessPolicy.canRecordOrderPayment(session);
  if (!allowed) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SettlementScopeGuard(
      scope: AccessPolicy.orderScope(session),
      completing: completing,
      takeaway: order.summary.serviceType == ServiceType.takeaway,
      child: child,
    ),
  );
}

class _SettlementScopeGuard extends ConsumerWidget {
  const _SettlementScopeGuard({
    required this.scope,
    required this.completing,
    required this.takeaway,
    required this.child,
  });
  final Object? scope;
  final bool completing, takeaway;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    final allowed = completing
        ? AccessPolicy.canCompleteOrder(session, takeaway: takeaway)
        : AccessPolicy.canRecordOrderPayment(session);
    if (AccessPolicy.orderScope(session) != scope || !allowed) {
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && route?.isActive == true) {
          Navigator.of(context).removeRoute(route!);
        }
      });
      return const SizedBox.shrink();
    }
    return child;
  }
}

/// Payment/completion controls shared by the bill footer and its compact view.
class OrderSettlementActions extends ConsumerWidget {
  const OrderSettlementActions({
    super.key,
    required this.order,
    this.blocked = false,
  });
  final OrderDetail order;
  final bool blocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settlement = ref.watch(orderSettlementProvider(order.id));
    final session = ref.watch(authControllerProvider).state.session;
    final summary = order.summary;
    if (settlement.ownsMutationBlock || settlement.needsReview) {
      final completing = settlement.completionAttempt;
      final allowed = completing
          ? AccessPolicy.canCompleteOrder(
              session,
              takeaway: summary.serviceType == ServiceType.takeaway,
            )
          : AccessPolicy.canRecordOrderPayment(session);
      return FilledButton.icon(
        onPressed: settlement.busy || !allowed
            ? null
            : () => completing
                  ? showOrderCompletionDialog(context, ref, order)
                  : showOrderPaymentDialog(context, ref, order),
        icon: const Icon(Icons.sync),
        label: Text(
          settlement.busy
              ? 'Đang xử lý…'
              : completing
              ? 'Kiểm tra hoàn tất'
              : settlement.paymentRecordedAwaitingRefresh
              ? 'Đã thu tiền · tải lại'
              : 'Kiểm tra thanh toán',
        ),
      );
    }
    if (summary.status == OrderStatus.completed) {
      return const Text(
        'Đã hoàn tất',
        style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
      );
    }
    if (summary.status == OrderStatus.cancelled) {
      return const SizedBox.shrink();
    }
    if (summary.paymentStatus == OrderPaymentStatus.paid) {
      final allowed = AccessPolicy.canCompleteOrder(
        session,
        takeaway: summary.serviceType == ServiceType.takeaway,
      );
      final remaining = order.items
          .where(
            (line) =>
                line.status != OrderItemStatus.cancelled &&
                line.status != OrderItemStatus.served,
          )
          .length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: !blocked && settlement.canBeginCompletion
                ? () => showOrderCompletionDialog(context, ref, order)
                : null,
            icon: const Icon(Icons.task_alt),
            label: const Text('Hoàn tất đơn'),
          ),
          if (!allowed) const Text('Bạn không có quyền hoàn tất đơn.'),
          if (remaining > 0) ...[
            Text('Còn $remaining dòng món chưa đánh dấu phục vụ.'),
            Text(
              AccessPolicy.canOrders(session, 'ORDER_MARK_SERVED')
                  ? 'Khi hoàn tất, cần xác nhận đã phục vụ thực tế tất cả món.'
                  : 'Cần quyền xác nhận phục vụ tất cả món trước khi hoàn tất.',
            ),
          ],
          if (summary.paidAmount.minorUnits != summary.totalAmount.minorUnits)
            const Text(
              'Số tiền đã trả chưa khớp tổng đơn. Hãy tải lại để đối chiếu.',
            ),
        ],
      );
    }
    if (summary.paymentStatus == OrderPaymentStatus.unpaid &&
        AccessPolicy.canRecordOrderPayment(session)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FilledButton.icon(
            onPressed: !blocked && settlement.canPay
                ? () => showOrderPaymentDialog(context, ref, order)
                : null,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Thanh toán hóa đơn'),
          ),
          if (summary.status == OrderStatus.open)
            const Text('Xác nhận đơn trước khi thanh toán.'),
          if (summary.totalAmount.minorUnits <= 0)
            const Text('Đơn chưa có số tiền hợp lệ để thanh toán.'),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class OrderPaymentDialog extends ConsumerStatefulWidget {
  const OrderPaymentDialog({super.key, required this.order});
  final OrderDetail order;

  @override
  ConsumerState<OrderPaymentDialog> createState() => _OrderPaymentDialogState();
}

class _OrderPaymentDialogState extends ConsumerState<OrderPaymentDialog> {
  final _form = GlobalKey<FormState>();
  final _reference = TextEditingController();
  OrderPaymentMethod _method = OrderPaymentMethod.cash;
  bool _received = false;

  @override
  void initState() {
    super.initState();
    final pending = ref.read(orderSettlementProvider(widget.order.id)).pending;
    if (pending != null) {
      _method = pending.paymentMethod;
      _reference.text = pending.referenceNo ?? '';
      _received = true;
    }
  }

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _send(OrderSettlementController controller) async {
    if (!_form.currentState!.validate() || !_received) return;
    final result = await controller.pay(
      widget.order,
      _method,
      referenceNo: _method == OrderPaymentMethod.transfer
          ? _reference.text.trim()
          : null,
    );
    _closeOnVerifiedPayment(controller, result);
  }

  void _closeOnVerifiedPayment(
    OrderSettlementController controller,
    Result<OrderDetail> result,
  ) {
    if (!mounted || !controller.current) return;
    if (result case Success(value: final order)) {
      if (order.summary.paymentStatus == OrderPaymentStatus.paid &&
          !controller.ownsMutationBlock &&
          !controller.needsReview) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _check(OrderSettlementController controller) async {
    final result = await controller.refresh();
    _closeOnVerifiedPayment(controller, result);
  }

  Future<void> _retry(OrderSettlementController controller) async {
    final result = await controller.retryPayment();
    _closeOnVerifiedPayment(controller, result);
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(orderSettlementProvider(widget.order.id));
    final current = ref.watch(orderDetailProvider(widget.order.id)).order;
    final changed =
        current != null &&
        (current.version != widget.order.version ||
            current.summary.totalAmount.minorUnits !=
                widget.order.summary.totalAmount.minorUnits);
    final frozen =
        controller.busy ||
        controller.ownsMutationBlock ||
        controller.needsReview;
    final amount =
        controller.pending?.amount ?? widget.order.summary.totalAmount;
    return PopScope(
      canPop: !controller.busy,
      child: _SettlementDialogFrame(
        title: 'Thanh toán · ${widget.order.summary.orderCode}',
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Cần thu: ${orderMoney(BigInt.from(amount.minorUnits), currency: widget.order.summary.currencyCode)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Chỉ xác nhận sau khi đã nhận đủ tiền của khách.'),
              const SizedBox(height: 16),
              DropdownButtonFormField<OrderPaymentMethod>(
                value: _method,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Phương thức thanh toán',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final method in OrderPaymentMethod.values)
                    DropdownMenuItem(value: method, child: Text(method.label)),
                ],
                onChanged: frozen || changed
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            _method = value;
                            _received = false;
                          });
                        }
                      },
              ),
              if (_method == OrderPaymentMethod.transfer) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _reference,
                  enabled: !frozen && !changed,
                  maxLength: 100,
                  decoration: const InputDecoration(
                    labelText: 'Mã tham chiếu chuyển khoản',
                    helperText: 'Nhập mã giao dịch đã đối soát từ ngân hàng.',
                    helperMaxLines: 3,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      _method == OrderPaymentMethod.transfer &&
                          (value == null || value.trim().isEmpty)
                      ? 'Vui lòng nhập mã tham chiếu đã đối soát.'
                      : null,
                ),
              ],
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  _method == OrderPaymentMethod.transfer
                      ? 'Tôi đã đối soát và nhận đủ tiền chuyển khoản'
                      : 'Tôi xác nhận đã nhận đủ tiền mặt',
                ),
                value: _received,
                onChanged: frozen || changed
                    ? null
                    : (value) => setState(() => _received = value ?? false),
              ),
              if (controller.busy) const LinearProgressIndicator(),
              if (controller.paymentOutcomeUnknown)
                const Text(
                  'Chưa xác định kết quả thanh toán. Không thu tiền lần nữa. '
                  'Kiểm tra lại hoặc gửi lại đúng yêu cầu ban đầu.',
                ),
              if (controller.paymentRecordedAwaitingRefresh)
                const Text(
                  'Đã ghi nhận thanh toán. Chưa tải được trạng thái mới của đơn; '
                  'hãy tải lại, không thanh toán lại.',
                ),
              if (controller.payment != null)
                Text('Phiếu thu: ${controller.payment!.paymentCode}'),
              if (controller.needsReview)
                const Text(
                  'Dữ liệu hoặc trạng thái đơn đã thay đổi. Tải lại và đối chiếu '
                  'trước khi mở một lần thanh toán mới.',
                ),
              if (changed && !frozen)
                const Text(
                  'Đơn đã thay đổi từ lúc mở thanh toán. Đóng và mở lại để kiểm tra '
                  'số tiền, trạng thái và phiên bản mới.',
                ),
              OrderFailurePanel(failure: controller.failure),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: controller.busy
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Đóng'),
                  ),
                  if (controller.ownsMutationBlock || controller.needsReview)
                    OutlinedButton(
                      onPressed: controller.busy
                          ? null
                          : () => _check(controller),
                      child: const Text('Tải lại đơn để đối chiếu'),
                    ),
                  if (controller.canRetryPayment)
                    FilledButton(
                      onPressed: controller.busy
                          ? null
                          : () => _retry(controller),
                      child: const Text('Kiểm tra lại lần thanh toán'),
                    ),
                  if (controller.needsReview)
                    FilledButton(
                      onPressed: !controller.canReviewCurrent
                          ? null
                          : () {
                              if (controller.reviewCurrent()) {
                                Navigator.of(context).pop();
                              }
                            },
                      child: const Text('Đã đối chiếu · mở lại thanh toán'),
                    ),
                  if (!controller.ownsMutationBlock && !controller.needsReview)
                    FilledButton(
                      onPressed:
                          !controller.busy &&
                              !changed &&
                              _received &&
                              controller.canPay
                          ? () => _send(controller)
                          : null,
                      child: const Text('Xác nhận đã nhận tiền'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OrderCompletionDialog extends ConsumerWidget {
  const OrderCompletionDialog({super.key, required this.order});
  final OrderDetail order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(orderSettlementProvider(order.id));
    final current = ref.watch(orderDetailProvider(order.id)).order;
    final changed = current != null && current.version != order.version;
    Future<void> submit({bool check = false}) async {
      final result = await (check
          ? controller.refresh()
          : controller.serveAllAndComplete(order));
      if (!context.mounted || !controller.current) return;
      if (result case Success(value: final value)) {
        if (value.summary.status == OrderStatus.completed) {
          Navigator.of(context).pop();
        }
      }
    }

    return PopScope(
      canPop: !controller.busy,
      child: _SettlementDialogFrame(
        title: 'Hoàn tất · ${order.summary.orderCode}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (order.items.any(
              (line) =>
                  line.status != OrderItemStatus.cancelled &&
                  line.status != OrderItemStatus.served,
            ))
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Bạn xác nhận đã phục vụ thực tế tất cả món chưa hủy? '
                  'Sau khi xác nhận, các món sẽ được đánh dấu Đã phục vụ trước khi hoàn tất đơn.',
                ),
              ),
            Text(
              order.summary.serviceType == ServiceType.dineIn
                  ? 'Xác nhận đã thanh toán đủ và phục vụ hết các món. '
                        'Hoàn tất đơn sẽ đồng thời giải phóng bàn của phiên này.'
                  : 'Xác nhận đã thanh toán đủ và phục vụ hết các món để hoàn tất đơn.',
            ),
            if (controller.busy) const LinearProgressIndicator(),
            if (controller.completeOutcomeUnknown)
              Text(
                controller.servingOutcomeUnknown
                    ? 'Chưa xác định kết quả đánh dấu phục vụ. Tải lại đơn để đối chiếu trước khi tiếp tục.'
                    : 'Chưa xác định kết quả hoàn tất. Tải lại đơn để kiểm tra.',
              ),
            if (controller.servedBeforeCompletion)
              const Text(
                'Các món đã được đánh dấu phục vụ. Nếu hoàn tất chưa thành công, '
                'kết quả phục vụ vẫn được giữ; hãy đối chiếu trước khi hoàn tất lại.',
              ),
            if (changed && !controller.completeOutcomeUnknown)
              const Text(
                'Đơn đã thay đổi. Đóng và mở lại sau khi đối chiếu dữ liệu mới.',
              ),
            if (controller.needsReview)
              const Text(
                'Hãy tải lại và kiểm tra trạng thái đơn trước khi thử lại.',
              ),
            OrderFailurePanel(failure: controller.failure),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: controller.busy
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Đóng'),
                ),
                if (controller.completeOutcomeUnknown || controller.needsReview)
                  OutlinedButton(
                    onPressed: controller.busy
                        ? null
                        : () => submit(check: true),
                    child: const Text('Kiểm tra lại hoàn tất'),
                  ),
                if (controller.needsReview)
                  FilledButton(
                    onPressed: !controller.canReviewCurrent
                        ? null
                        : () {
                            if (controller.reviewCurrent()) {
                              Navigator.of(context).pop();
                            }
                          },
                    child: const Text('Đã đối chiếu · đóng'),
                  ),
                if (!controller.completeOutcomeUnknown &&
                    !controller.needsReview)
                  FilledButton(
                    onPressed:
                        !controller.busy &&
                            !changed &&
                            controller.canBeginCompletion
                        ? () => submit()
                        : null,
                    child: const Text('Xác nhận hoàn tất'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettlementDialogFrame extends StatelessWidget {
  const _SettlementDialogFrame({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 540),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    ),
  );
}
