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
import '../../domain/entities/order_transfer_qr.dart';
import '../controllers/order_settlement_controller.dart';
import '../providers/order_transfer_qr_providers.dart';
import 'order_widgets.dart';
import 'transfer_qr_panel.dart';

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
    // Tapping outside closes like "Đóng"; each dialog's PopScope refuses it
    // while a request is in flight, and the controller keeps any outcome.
    barrierDismissible: true,
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
        style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold),
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

  /// The QR transfer content this dialog put into [_reference], if any.
  String? _prefilledReference;

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

  /// The customer's transfer carries the QR content, so it is the natural
  /// reference; a cashier who already typed one keeps theirs.
  void _prefillReference(OrderTransferQrCode? code) {
    if (!mounted || code == null || _reference.text.trim().isNotEmpty) return;
    setState(() {
      _prefilledReference = code.details.transferContent;
      _reference.text = code.details.transferContent;
    });
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
    // Like the calculator, the QR gives way to the recovery steps once a
    // payment is out or under review, and never asks to pay a paid order.
    final showQr =
        _method == OrderPaymentMethod.transfer &&
        !controller.ownsMutationBlock &&
        !controller.needsReview &&
        (current ?? widget.order).summary.paymentStatus ==
            OrderPaymentStatus.unpaid;
    final OrderTransferQrKey qrKey = (
      orderId: widget.order.id,
      orderVersion: current?.version ?? widget.order.version,
    );
    if (showQr) {
      ref.listen(orderTransferQrProvider(qrKey), (_, next) {
        if (next case AsyncData(:final value)) _prefillReference(value);
      });
    }
    final prefilled =
        _prefilledReference != null && _reference.text == _prefilledReference;
    final actions = <Widget>[
      TextButton(
        onPressed: controller.busy ? null : () => Navigator.of(context).pop(),
        child: const Text('Đóng'),
      ),
      if (controller.ownsMutationBlock || controller.needsReview)
        OutlinedButton(
          onPressed: controller.busy ? null : () => _check(controller),
          child: const Text('Tải lại đơn để đối chiếu'),
        ),
      if (controller.canRetryPayment)
        FilledButton(
          onPressed: controller.busy ? null : () => _retry(controller),
          child: const Text('Kiểm tra lại lần thanh toán'),
        ),
      if (controller.needsReview)
        FilledButton(
          onPressed: !controller.canReviewCurrent
              ? null
              : () {
                  if (controller.reviewCurrent()) Navigator.of(context).pop();
                },
          child: const Text('Đã đối chiếu · mở lại thanh toán'),
        ),
      // The amount on the button is the confirmation itself: the cashier
      // reads exactly what they are attesting to.
      if (!controller.ownsMutationBlock && !controller.needsReview)
        FilledButton.icon(
          key: const ValueKey('payment-confirm'),
          style: _primaryAction,
          onPressed:
              !controller.busy && !changed && !_short(due) && controller.canPay
              ? () => _send(controller, due)
              : null,
          icon: controller.busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text('Đã nhận $dueText'),
        ),
    ];
    return PopScope(
      canPop: !controller.busy,
      child: _SettlementDialogFrame(
        title: 'Thanh toán',
        orderCode: widget.order.summary.orderCode,
        actions: actions,
        body: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AmountDue(text: dueText),
              const SizedBox(height: 20),
              const _SectionLabel('Phương thức thanh toán'),
              const SizedBox(height: 8),
              _MethodPicker(
                selected: _method,
                enabled: editable,
                onChanged: (method) => setState(() => _method = method),
              ),
              if (collecting) ...[
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('payment-cash-given'),
                  controller: _cashGiven,
                  enabled: editable,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [_WholeAmountInputFormatter()],
                  style: Theme.of(context).textTheme.titleMedium,
                  decoration: InputDecoration(
                    labelText: 'Khách đưa',
                    helperText: 'Bỏ trống nếu khách đưa đúng số tiền.',
                    helperMaxLines: 2,
                    prefixIcon: const Icon(Icons.payments_outlined),
                    suffixText: currency.isEmpty
                        ? defaultCurrencySymbol
                        : currency,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
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
                if (showQr) ...[
                  const SizedBox(height: 20),
                  TransferQrPanel(qrKey: qrKey, dueMinor: due),
                ],
                const SizedBox(height: 20),
                TextFormField(
                  key: const ValueKey('payment-reference'),
                  controller: _reference,
                  enabled: editable,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: 'Mã tham chiếu chuyển khoản',
                    helperText: prefilled
                        ? 'Đã điền sẵn nội dung chuyển khoản. Có thể thay bằng mã giao dịch ngân hàng.'
                        : 'Nhập mã giao dịch đã đối soát từ ngân hàng.',
                    helperMaxLines: 3,
                    prefixIcon: const Icon(Icons.tag_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) =>
                      _method == OrderPaymentMethod.transfer &&
                          (value == null || value.trim().isEmpty)
                      ? 'Vui lòng nhập mã tham chiếu đã đối soát.'
                      : null,
                ),
              ],
              if (controller.busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
              if (controller.paymentOutcomeUnknown)
                const _StatusNote(
                  'Chưa xác định kết quả thanh toán. Không thu tiền lần nữa. '
                  'Kiểm tra lại hoặc gửi lại đúng yêu cầu ban đầu.',
                ),
              if (controller.paymentRecordedAwaitingRefresh)
                const _StatusNote(
                  'Đã ghi nhận thanh toán. Chưa tải được trạng thái mới của đơn; '
                  'hãy tải lại, không thanh toán lại.',
                ),
              if (controller.payment != null)
                _StatusNote('Phiếu thu: ${controller.payment!.paymentCode}'),
              if (controller.needsReview)
                const _StatusNote(
                  'Dữ liệu hoặc trạng thái đơn đã thay đổi. Tải lại và đối chiếu '
                  'trước khi mở một lần thanh toán mới.',
                ),
              if (changed && !frozen)
                const _StatusNote(
                  'Đơn đã thay đổi từ lúc mở thanh toán. Đóng và mở lại để kiểm tra '
                  'số tiền, trạng thái và phiên bản mới.',
                ),
              OrderFailurePanel(failure: controller.failure),
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

    final unserved = order.items.any(
      (line) =>
          line.status != OrderItemStatus.cancelled &&
          line.status != OrderItemStatus.served,
    );
    return PopScope(
      canPop: !controller.busy,
      child: _SettlementDialogFrame(
        title: 'Hoàn tất đơn',
        orderCode: order.summary.orderCode,
        actions: [
          TextButton(
            onPressed: controller.busy
                ? null
                : () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
          if (controller.completeOutcomeUnknown || controller.needsReview)
            OutlinedButton(
              onPressed: controller.busy ? null : () => submit(check: true),
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
          if (!controller.completeOutcomeUnknown && !controller.needsReview)
            FilledButton.icon(
              style: _primaryAction,
              onPressed:
                  !controller.busy && !changed && controller.canBeginCompletion
                  ? () => submit()
                  : null,
              icon: const Icon(Icons.task_alt_rounded),
              label: const Text('Xác nhận hoàn tất'),
            ),
        ],
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (unserved)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: _StatusNote(
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
            if (controller.busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (controller.completeOutcomeUnknown)
              _StatusNote(
                controller.servingOutcomeUnknown
                    ? 'Chưa xác định kết quả đánh dấu phục vụ. Tải lại đơn để đối chiếu trước khi tiếp tục.'
                    : 'Chưa xác định kết quả hoàn tất. Tải lại đơn để kiểm tra.',
              ),
            if (controller.servedBeforeCompletion)
              const _StatusNote(
                'Các món đã được đánh dấu phục vụ. Nếu hoàn tất chưa thành công, '
                'kết quả phục vụ vẫn được giữ; hãy đối chiếu trước khi hoàn tất lại.',
              ),
            if (changed && !controller.completeOutcomeUnknown)
              const _StatusNote(
                'Đơn đã thay đổi. Đóng và mở lại sau khi đối chiếu dữ liệu mới.',
              ),
            if (controller.needsReview)
              const _StatusNote(
                'Hãy tải lại và kiểm tra trạng thái đơn trước khi thử lại.',
              ),
            OrderFailurePanel(failure: controller.failure),
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

/// Big enough to hit without looking twice.
final _primaryAction = FilledButton.styleFrom(
  minimumSize: const Size(0, 48),
  padding: const EdgeInsets.symmetric(horizontal: 20),
  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
);

/// The last characters of a long order code, which is also what the transfer
/// content carries ("TT 12C7A6972F"). Short codes stay whole.
String _shortOrderCode(String code) {
  final plain = code.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
  return plain.length <= 10 ? code : '…${plain.substring(plain.length - 10)}';
}

/// Title, a scrolling body and actions that stay on screen however long the
/// body gets (a QR code, many notes). When the dialog is too short for that,
/// the whole thing scrolls instead.
class _SettlementDialogFrame extends StatelessWidget {
  const _SettlementDialogFrame({
    required this.title,
    required this.orderCode,
    required this.body,
    required this.actions,
  });
  final String title, orderCode;
  final Widget body;
  final List<Widget> actions;

  /// Height below which pinning the header and actions would squeeze the
  /// body out (keyboard open, large text): then everything scrolls together.
  static const _pinnedMinHeight = 480.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Tooltip(
            message: orderCode,
            child: Container(
              key: const ValueKey('settlement-order-code'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Đơn ${_shortOrderCode(orderCode)}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.grey700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final footer = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      // The usual pair (Đóng + the main action) shares one row with the main
      // action filling it; recovery states wrap as needed.
      child: actions.length == 2
          ? Row(
              children: [
                actions.first,
                const SizedBox(width: 8),
                Expanded(child: actions.last),
              ],
            )
          : Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: actions,
            ),
    );
    const bodyPadding = EdgeInsets.fromLTRB(20, 0, 20, 16);
    const divider = Divider(height: 1, color: AppColors.grey200);
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pinned =
                constraints.maxHeight >= _pinnedMinHeight * textScale;
            if (!pinned) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    Padding(padding: bodyPadding, child: body),
                    divider,
                    footer,
                  ],
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                Flexible(
                  child: SingleChildScrollView(
                    padding: bodyPadding,
                    child: body,
                  ),
                ),
                divider,
                footer,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The amount to collect, the one figure the cashier must not misread.
class _AmountDue extends StatelessWidget {
  const _AmountDue({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('payment-amount-due'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cần thu',
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppColors.grey700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Chỉ xác nhận sau khi đã nhận đủ tiền của khách.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.grey600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleSmall?.copyWith(
      color: AppColors.grey700,
      fontWeight: FontWeight.w600,
    ),
  );
}

/// Two equal tiles, one tap each; labels wrap instead of overflowing.
class _MethodPicker extends StatelessWidget {
  const _MethodPicker({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });
  final OrderPaymentMethod selected;
  final bool enabled;
  final ValueChanged<OrderPaymentMethod> onChanged;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, method) in OrderPaymentMethod.values.indexed) ...[
          if (index > 0) const SizedBox(width: 10),
          Expanded(
            child: _MethodTile(
              key: ValueKey('payment-method-${method.code}'),
              method: method,
              selected: method == selected,
              onTap: enabled ? () => onChanged(method) : null,
            ),
          ),
        ],
      ],
    ),
  );
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    super.key,
    required this.method,
    required this.selected,
    required this.onTap,
  });
  final OrderPaymentMethod method;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.grey700;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: Material(
        color: selected ? AppColors.primarySoft : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.grey300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  method == OrderPaymentMethod.cash
                      ? Icons.payments_outlined
                      : Icons.account_balance_outlined,
                  color: color,
                ),
                const SizedBox(height: 6),
                Text(
                  method.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A state the cashier must notice before acting again.
class _StatusNote extends StatelessWidget {
  const _StatusNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.warningTint,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.warningBorder),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 18, color: AppColors.warning),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}
