import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/policies/order_access_policy.dart';
import '../../domain/policies/order_table_policy.dart';
import '../widgets/order_append_dialog.dart';
import '../widgets/order_mutation_forms.dart';
import '../widgets/order_widgets.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.id, this.initialOrder});
  final String id;
  final OrderDetail? initialOrder;
  Future<void> _form(
    BuildContext context,
    WidgetRef ref,
    OrderDetail order,
    OrderFormAction action, {
    OrderLine? line,
  }) => showOrderDialog<void>(
    context,
    ref,
    permission: action == OrderFormAction.cancel
        ? 'ORDER_CANCEL'
        : action == OrderFormAction.cancelLine
        ? OrderAccessPolicy.lineCancelPermission(order)
        : 'ORDER_UPDATE',
    child: OrderMutationForm(order: order, action: action, line: line),
  );
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(orderDetailProvider(id));
    if (initialOrder != null) c.seed(initialOrder!);
    final order = c.order;
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canOrders(session, 'ORDER_VIEW') &&
        initialOrder == null) {
      return const Center(child: Text('Bạn không có quyền xem đơn.'));
    }
    if (order == null) {
      return Column(
        children: [
          if (c.loading) const LinearProgressIndicator(),
          OrderFailurePanel(failure: c.failure, retry: c.load),
          if (!c.loading && c.failure == null)
            const Text('Chưa có dữ liệu đơn.'),
        ],
      );
    }
    final s = order.summary;
    final append = ref.watch(orderAppendProvider(id));
    final canAppend =
        !c.loading &&
        !c.busy &&
        !append.busy &&
        !c.requiresVerification &&
        !append.uncertain &&
        OrderAccessPolicy.canAppend(
          order,
          AccessPolicy.canAppendOrder(
            session,
            takeaway: s.serviceType == ServiceType.takeaway,
          ),
        );
    return PopScope(
      canPop: !append.busy && !append.uncertain,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
            children: [
              if (c.loading || c.busy) const LinearProgressIndicator(),
              OrderFailurePanel(
                failure: c.failure,
                retry: c.can('ORDER_VIEW') && !c.busy ? c.load : null,
              ),
              if (append.uncertain) ...[
                const Text(
                  'Lần gọi thêm chưa rõ kết quả. Không gửi một yêu cầu mới.',
                ),
                OrderFailurePanel(
                  failure: append.failure,
                  retry: append.canRetry ? append.retry : null,
                  label: 'Kiểm tra lại lần gọi thêm',
                ),
              ],
              Text(
                s.orderCode,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(s.serviceType.label)),
                  Chip(label: Text(s.status.label)),
                  Chip(label: Text(s.paymentStatus.label)),
                ],
              ),
              Text('Tạo: ${formatLocalDate(s.createdAt)}'),
              if (s.tableSessionId != null) Text('Phiên: ${s.tableSessionId}'),
              Text('Số khách: ${s.guestCount}'),
              if (s.customerName != null) Text('Khách: ${s.customerName}'),
              if (order.customerPhone != null)
                Text('Điện thoại: ${order.customerPhone}'),
              if (order.note != null) Text('Ghi chú: ${order.note}'),
              if (order.cancelReason != null)
                Text('Lý do hủy: ${order.cancelReason}'),
              const SizedBox(height: 12),
              for (final line in order.items)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.itemName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: line.status == OrderItemStatus.cancelled
                                ? TextDecoration.lineThrough
                                : null,
                            color: line.status == OrderItemStatus.cancelled
                                ? Colors.grey
                                : null,
                          ),
                        ),
                        Text(
                          '${line.quantity} ${line.unit} × ${orderMoney(BigInt.from(line.unitPrice.minorUnits), currency: s.currencyCode)}',
                        ),
                        Text(
                          'Thành tiền: ${orderMoney(BigInt.from(line.lineTotal.minorUnits), currency: s.currencyCode)} · ${line.status.label}',
                        ),
                        if (line.note != null) Text('Ghi chú: ${line.note}'),
                        if (line.cancelReason != null)
                          Text('Lý do hủy: ${line.cancelReason}'),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (c.editable &&
                                line.status == OrderItemStatus.pending)
                              TextButton(
                                onPressed: c.busy
                                    ? null
                                    : () => _form(
                                        context,
                                        ref,
                                        order,
                                        OrderFormAction.line,
                                        line: line,
                                      ),
                                child: const Text('Sửa'),
                              ),
                            if (c.lineCancellable(line))
                              TextButton(
                                onPressed: c.busy
                                    ? null
                                    : () => _form(
                                        context,
                                        ref,
                                        order,
                                        OrderFormAction.cancelLine,
                                        line: line,
                                      ),
                                child: const Text('Hủy món'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const Divider(),
              Text(
                'Tiền hàng: ${orderMoney(BigInt.from(order.subtotalAmount.minorUnits), currency: s.currencyCode)}',
              ),
              Text(
                'Giảm giá: ${orderMoney(BigInt.from(order.discountAmount.minorUnits), currency: s.currencyCode)}',
              ),
              Text(
                'Thuế: ${orderMoney(BigInt.from(order.taxAmount.minorUnits), currency: s.currencyCode)}',
              ),
              Text(
                'Phí phục vụ: ${orderMoney(BigInt.from(order.serviceChargeAmount.minorUnits), currency: s.currencyCode)}',
              ),
              Text(
                'Tổng: ${orderMoney(BigInt.from(s.totalAmount.minorUnits), currency: s.currencyCode)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'Đã trả: ${orderMoney(BigInt.from(s.paidAmount.minorUnits), currency: s.currencyCode)}',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (c.editable)
                    OutlinedButton(
                      onPressed: c.busy
                          ? null
                          : () => _form(
                              context,
                              ref,
                              order,
                              OrderFormAction.metadata,
                            ),
                      child: const Text('Sửa thông tin'),
                    ),
                  if (append.uncertain)
                    OutlinedButton(
                      onPressed: c.busy
                          ? null
                          : () => showOrderDialog<void>(
                              context,
                              ref,
                              permission: 'ORDER_UPDATE',
                              child: OrderAppendDialog(order: order),
                            ),
                      child: const Text('Mở giỏ gọi thêm'),
                    ),
                  if (c.confirmable)
                    FilledButton(
                      onPressed: c.busy
                          ? null
                          : () => _form(
                              context,
                              ref,
                              order,
                              OrderFormAction.confirm,
                            ),
                      child: const Text('Xác nhận đơn'),
                    ),
                  if (c.cancellable)
                    OutlinedButton(
                      onPressed: c.busy
                          ? null
                          : () => _form(
                              context,
                              ref,
                              order,
                              OrderFormAction.cancel,
                            ),
                      child: const Text('Hủy đơn'),
                    ),
                  if (!append.uncertain &&
                      AccessPolicy.canCreateOrder(
                        session,
                        takeaway: s.serviceType == ServiceType.takeaway,
                      ) &&
                      AccessPolicy.canMenu(session, 'MENU_VIEW') &&
                      (s.serviceType == ServiceType.takeaway ||
                          !OrderTablePolicy.servingStatuses.contains(
                                s.status,
                              ) &&
                              AccessPolicy.canTables(session, 'TABLE_VIEW')))
                    TextButton(
                      onPressed: () => context.push(
                        s.serviceType == ServiceType.takeaway
                            ? '/app/order-create?serviceType=TAKEAWAY'
                            : '/app/order-create?tableSessionId=${Uri.encodeQueryComponent(s.tableSessionId!)}',
                      ),
                      child: const Text('Tạo đơn mới'),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Chưa hỗ trợ gửi bếp, thanh toán hoặc đóng bill.'),
            ],
          ),
          if (canAppend && AccessPolicy.canMenu(session, 'MENU_VIEW'))
            Positioned(
              right: 16,
              bottom: 16,
              child: SafeArea(
                child: FloatingActionButton(
                  heroTag: 'order-append-$id',
                  tooltip: 'Gọi thêm món',
                  onPressed: () => showOrderDialog<void>(
                    context,
                    ref,
                    permission: 'ORDER_UPDATE',
                    child: OrderAppendDialog(order: order),
                  ),
                  child: const Icon(Icons.add),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
