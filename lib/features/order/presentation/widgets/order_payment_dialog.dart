import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/formatters/money_format.dart';
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
          // The completion dialog asks to confirm unserved lines; only a
          // missing right needs explaining here, as it disables the button.
          if (remaining > 0 &&
              !AccessPolicy.canOrders(session, 'ORDER_MARK_SERVED'))
            const Text(
              'Cần quyền xác nhận phục vụ tất cả món trước khi hoàn tất.',
            ),
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

  /// Cash handed over, in whole units. Only used to work out the change; the
  /// payment itself is always the order total.
  final _cashGiven = TextEditingController();
  OrderPaymentMethod _method = OrderPaymentMethod.cash;

  @override
  void initState() {
    super.initState();
    final pending = ref.read(orderSettlementProvider(widget.order.id)).pending;
    if (pending != null) {
      _method = pending.paymentMethod;
      _reference.text = pending.referenceNo ?? '';
    }
  }

  @override
  void dispose() {
    _reference.dispose();
    _cashGiven.dispose();
    super.dispose();
  }

  BigInt? get _givenMinor {
    final digits = _cashGiven.text.replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? null : BigInt.parse(digits) * BigInt.from(100);
  }

  /// Cash typed but less than [due]: confirming would record money not taken.
  bool _short(BigInt due) {
    final given = _givenMinor;
    return _method == OrderPaymentMethod.cash && given != null && given < due;
  }

  void _setGiven(BigInt minor) {
    final whole = (minor + BigInt.from(99)) ~/ BigInt.from(100);
    HapticFeedback.selectionClick();
    setState(() => _cashGiven.text = formatDecimal(whole.toString()));
  }

  Future<void> _send(OrderSettlementController controller, BigInt due) async {
    unawaited(HapticFeedback.mediumImpact());
    if (!_form.currentState!.validate() || _short(due)) return;
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
    final currency = widget.order.summary.currencyCode;
    final due = BigInt.from(amount.minorUnits);
    final dueText = orderMoney(due, currency: currency);
    final editable = !frozen && !changed;
    // Once a payment is out or under review, the change calculator is noise
    // next to the recovery steps.
    final collecting =
        _method == OrderPaymentMethod.cash &&
        !controller.ownsMutationBlock &&
        !controller.needsReview;
    final given = collecting ? _givenMinor : null;
    final textTheme = Theme.of(context).textTheme;
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
              Text('Cần thu: $dueText', style: textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text('Chỉ xác nhận sau khi đã nhận đủ tiền của khách.'),
              const SizedBox(height: 16),
              Text('Phương thức thanh toán', style: textTheme.labelLarge),
              const SizedBox(height: 8),
              // One tap per method; chips wrap instead of overflowing at
              // large text sizes.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final method in OrderPaymentMethod.values)
                    ChoiceChip(
                      key: ValueKey('payment-method-${method.code}'),
                      avatar: Icon(
                        method == OrderPaymentMethod.cash
                            ? Icons.payments_outlined
                            : Icons.account_balance_outlined,
                        size: 20,
                      ),
                      label: Text(method.label),
                      labelPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      showCheckmark: false,
                      selected: _method == method,
                      onSelected: editable
                          ? (_) => setState(() => _method = method)
                          : null,
                    ),
                ],
              ),
              if (collecting) ...[
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('payment-cash-given'),
                  controller: _cashGiven,
                  enabled: editable,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [_WholeAmountInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Khách đưa',
                    helperText: 'Bỏ trống nếu khách đưa đúng số tiền.',
                    helperMaxLines: 2,
                    suffixText: currency.isEmpty
                        ? defaultCurrencySymbol
                        : currency,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (index, value) in cashSuggestions(
                      due,
                      currency: currency,
                    ).indexed)
                      ActionChip(
                        key: ValueKey('payment-cash-quick-$index'),
                        label: Text(index == 0 ? 'Đủ tiền' : orderMoney(value)),
                        onPressed: editable ? () => _setGiven(value) : null,
                      ),
                  ],
                ),
                if (given != null) ...[
                  const SizedBox(height: 12),
                  _CashChangeLine(due: due, given: given, currency: currency),
                ],
              ],
              if (_method == OrderPaymentMethod.transfer) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _reference,
                  enabled: editable,
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
              const SizedBox(height: 12),
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
                  // The amount on the button is the confirmation itself: the
                  // cashier reads exactly what they are attesting to.
                  if (!controller.ownsMutationBlock && !controller.needsReview)
                    FilledButton.icon(
                      key: const ValueKey('payment-confirm'),
                      onPressed:
                          !controller.busy &&
                              !changed &&
                              !_short(due) &&
                              controller.canPay
                          ? () => _send(controller, due)
                          : null,
                      icon: const Icon(Icons.check),
                      label: Text('Đã nhận $dueText'),
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

/// Amounts a customer is likely to hand over for [dueMinor]: the exact amount
/// first, then the next round notes above it, at most four in all.
List<BigInt> cashSuggestions(BigInt dueMinor, {String? currency}) {
  if (dueMinor <= BigInt.zero) return const [];
  final hundred = BigInt.from(100);
  final due = (dueMinor + hundred - BigInt.one) ~/ hundred;
  final dong = currency == null || currency.isEmpty || currency == 'VND';
  final steps = dong
      ? const [10000, 50000, 100000, 200000, 500000, 1000000]
      : const [1, 5, 10, 20, 50, 100];
  final amounts = <BigInt>{dueMinor};
  for (final step in steps) {
    if (amounts.length >= 4) break;
    final unit = BigInt.from(step);
    final rounded = (due + unit - BigInt.one) ~/ unit * unit * hundred;
    if (rounded > dueMinor) amounts.add(rounded);
  }
  return amounts.toList()..sort();
}

/// Whole amounts only, grouped as 1.250.000 while typing.
class _WholeAmountInputFormatter extends TextInputFormatter {
  const _WholeAmountInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text
        .replaceAll(RegExp(r'\D'), '')
        .replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (digits.length > 12) return oldValue;
    final text = digits.isEmpty ? '' : formatDecimal(digits);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _CashChangeLine extends StatelessWidget {
  const _CashChangeLine({
    required this.due,
    required this.given,
    required this.currency,
  });
  final BigInt due, given;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final change = given - due;
    final short = change.isNegative;
    final colors = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('payment-cash-change'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: short ? colors.errorContainer : AppColors.successSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        short
            ? 'Còn thiếu: ${orderMoney(-change, currency: currency)}'
            : 'Tiền thừa trả khách: ${orderMoney(change, currency: currency)}',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: short ? colors.onErrorContainer : AppColors.success,
          fontWeight: FontWeight.w700,
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
