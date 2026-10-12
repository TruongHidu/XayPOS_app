import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/policies/order_access_policy.dart';
import '../../domain/policies/order_table_policy.dart';
import '../../../tables/domain/entities/table_entities.dart';
import '../../../tables/presentation/widgets/table_transfer_dialog.dart';
import '../widgets/order_append_dialog.dart';
import '../widgets/order_mutation_forms.dart';
import '../widgets/order_widgets.dart';

class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({
    super.key,
    required this.id,
    this.initialOrder,
    this.tableName,
    this.isOrderCreateFlow = false,
  });

  final String id;
  final OrderDetail? initialOrder;
  final String? tableName;
  final bool isOrderCreateFlow;

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

  void _handleBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else if (isOrderCreateFlow) {
      context.go('/app/order-create');
    } else {
      context.go('/app/orders');
    }
  }

  void _openAppend(
    BuildContext context,
    WidgetRef ref,
    OrderDetail order,
    String? currentTableName,
  ) {
    final router = GoRouter.maybeOf(context);
    if (router != null && isOrderCreateFlow) {
      final param = currentTableName != null
          ? '?tableName=${Uri.encodeQueryComponent(currentTableName)}'
          : '';
      context.push('/app/order-create/bill/${order.id}/add-items$param');
    } else {
      showOrderDialog<void>(
        context,
        ref,
        permission: 'ORDER_UPDATE',
        child: OrderAppendDialog(order: order),
      );
    }
  }

  void _showProvisionalBill(
    BuildContext context,
    OrderDetail order,
    String? currentTableName,
  ) {
    final s = order.summary;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Phiếu tạm tính'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currentTableName ?? s.orderCode,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text('Mã đơn: ${s.orderCode} · ${s.status.label}'),
                Text('Thời gian: ${formatLocalDate(s.createdAt)}'),
                const Divider(),
                for (final line in order.items)
                  if (line.status != OrderItemStatus.cancelled)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${line.itemName} x ${line.quantity}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            orderMoney(
                              BigInt.from(line.lineTotal.minorUnits),
                              currency: s.currencyCode,
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                const Divider(),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      const Text(
                        'Tổng thanh toán:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        orderMoney(
                          BigInt.from(s.totalAmount.minorUnits),
                          currency: s.currencyCode,
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: OrderPalette.orange,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Bản xem tạm tính không thay đổi trạng thái và không tạo hóa đơn chính thức.',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _lineThumbnail(String? itemId) {
    final cached = itemId != null ? getCachedCatalogImage(itemId) : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 48,
        height: 48,
        color: Colors.grey.shade100,
        child: cached != null
            ? Image.network(
                cached,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.restaurant,
                  color: OrderPalette.orange,
                  size: 24,
                ),
              )
            : const Icon(
                Icons.restaurant,
                color: OrderPalette.orange,
                size: 24,
              ),
      ),
    );
  }

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
    final tableSessionId = s.serviceType == ServiceType.dineIn
        ? s.tableSessionId
        : null;
    if (tableSessionId != null) {
      ref.watch(orderTableTransferProvider(tableSessionId));
    }
    final transfer = tableSessionId == null
        ? null
        : ref.watch(tableTransferControllerProvider(tableSessionId));
    final currentTableName = transfer?.currentSession?.tableName ?? tableName;
    final canViewTables = AccessPolicy.canTables(session, 'TABLE_VIEW');
    final canTransferTables = AccessPolicy.canTables(session, 'TABLE_TRANSFER');
    final canShowTransfer =
        tableSessionId != null &&
        canViewTables &&
        canTransferTables &&
        (transfer?.uncertain == true ||
            transfer?.currentSession?.status == TableSessionStatus.open);
    final transferBlocked =
        transfer?.busy == true || transfer?.uncertain == true;
    final canAppend =
        !c.loading &&
        !c.busy &&
        !append.busy &&
        !transferBlocked &&
        !c.requiresVerification &&
        !append.uncertain &&
        OrderAccessPolicy.canAppend(
          order,
          AccessPolicy.canAppendOrder(
            session,
            takeaway: s.serviceType == ServiceType.takeaway,
          ),
        );

    final displayTitle =
        currentTableName ??
        (s.serviceType == ServiceType.takeaway ? 'Mang đi' : s.orderCode);

    return PopScope(
      canPop: !append.busy && !append.uncertain && !transferBlocked,
      child: Material(
        color: Colors.grey.shade50,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                // ── In-page Header matching Photo 2 ─────────────────
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Quay lại',
                        onPressed: () => _handleBack(context),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  s.orderCode,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    s.status.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue.shade900,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        s.paymentStatus ==
                                            OrderPaymentStatus.paid
                                        ? Colors.green.shade50
                                        : Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    s.paymentStatus.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color:
                                          s.paymentStatus ==
                                              OrderPaymentStatus.paid
                                          ? Colors.green.shade900
                                          : Colors.amber.shade900,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Overflow menu for authorized actions
                      if (c.editable ||
                          c.confirmable ||
                          c.cancellable ||
                          canShowTransfer)
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          tooltip: 'Thao tác khác',
                          onSelected: (val) {
                            switch (val) {
                              case 'edit':
                                _form(
                                  context,
                                  ref,
                                  order,
                                  OrderFormAction.metadata,
                                );
                              case 'confirm':
                                _form(
                                  context,
                                  ref,
                                  order,
                                  OrderFormAction.confirm,
                                );
                              case 'cancel':
                                _form(
                                  context,
                                  ref,
                                  order,
                                  OrderFormAction.cancel,
                                );
                              case 'transfer':
                                if (tableSessionId != null) {
                                  showTableTransferDialog(
                                    context,
                                    ref,
                                    sessionId: tableSessionId,
                                  );
                                }
                            }
                          },
                          itemBuilder: (ctx) => [
                            if (c.editable)
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Sửa thông tin'),
                              ),
                            if (c.confirmable)
                              const PopupMenuItem(
                                value: 'confirm',
                                child: Text('Xác nhận đơn'),
                              ),
                            if (c.cancellable)
                              const PopupMenuItem(
                                value: 'cancel',
                                child: Text('Hủy đơn'),
                              ),
                            if (canShowTransfer)
                              PopupMenuItem(
                                value: 'transfer',
                                enabled:
                                    !c.busy &&
                                    !c.requiresVerification &&
                                    !append.busy &&
                                    !append.uncertain &&
                                    transfer?.busy != true,
                                child: Text(
                                  transfer?.uncertain == true
                                      ? 'Xử lý chuyển bàn đang chờ'
                                      : 'Chuyển bàn',
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),

                if (c.loading || c.busy) const LinearProgressIndicator(),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                    children: [
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
                      if (transfer?.uncertain == true) ...[
                        const Text(
                          'Lần chuyển bàn chưa rõ kết quả. Không tạo yêu cầu mới.',
                        ),
                        OrderFailurePanel(
                          failure: transfer!.failure,
                          retry: () => showTableTransferDialog(
                            context,
                            ref,
                            sessionId: tableSessionId!,
                          ),
                          label: 'Mở lại yêu cầu chuyển bàn',
                        ),
                      ],

                      // ── Order metadata card ───────────────────────────
                      Card(
                        color: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 16,
                                    color: Colors.grey.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Thông tin đơn',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Colors.grey.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    'Loại: ${s.serviceType.label}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    'Số khách: ${s.guestCount}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    'Tạo: ${formatLocalDate(s.createdAt)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (s.customerName != null)
                                    Text(
                                      'Khách: ${s.customerName}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (order.customerPhone != null)
                                    Text(
                                      'SĐT: ${order.customerPhone}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  if (s.tableSessionId != null)
                                    Text(
                                      'Phiên: ${s.tableSessionId}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                ],
                              ),
                              if (order.note != null &&
                                  order.note!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Ghi chú: ${order.note}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.brown.shade800,
                                  ),
                                ),
                              ],
                              if (order.cancelReason != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'Lý do hủy: ${order.cancelReason}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── Section Title: Saved Order Lines ─────────────
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          'Danh sách món (${order.items.length})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),

                      // ── Saved lines cards ────────────────────────────
                      for (final line in order.items)
                        Card(
                          color: Colors.white,
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade200),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _lineThumbnail(line.itemId),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        line.itemName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          decoration:
                                              line.status ==
                                                  OrderItemStatus.cancelled
                                              ? TextDecoration.lineThrough
                                              : null,
                                          color:
                                              line.status ==
                                                  OrderItemStatus.cancelled
                                              ? Colors.grey
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${line.quantity} ${line.unit} × ${orderMoney(BigInt.from(line.unitPrice.minorUnits), currency: s.currencyCode)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                      if (line.note != null &&
                                          line.note!.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Ghi chú: ${line.note}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.brown.shade800,
                                          ),
                                        ),
                                      ],
                                      if (line.cancelReason != null)
                                        Text(
                                          'Lý do hủy: ${line.cancelReason}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.red,
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade100,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          line.status.label,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      orderMoney(
                                        BigInt.from(line.lineTotal.minorUnits),
                                        currency: s.currencyCode,
                                      ),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        decoration:
                                            line.status ==
                                                OrderItemStatus.cancelled
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color:
                                            line.status ==
                                                OrderItemStatus.cancelled
                                            ? Colors.grey
                                            : OrderPalette.orange,
                                      ),
                                    ),
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
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(40, 28),
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
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(40, 28),
                                          foregroundColor: Colors.red.shade700,
                                        ),
                                        child: const Text('Hủy món'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 8),

                      // ── Financial breakdown card ─────────────────────
                      Card(
                        color: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tiền hàng: ${orderMoney(BigInt.from(order.subtotalAmount.minorUnits), currency: s.currencyCode)}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Giảm giá: ${orderMoney(BigInt.from(order.discountAmount.minorUnits), currency: s.currencyCode)}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Thuế: ${orderMoney(BigInt.from(order.taxAmount.minorUnits), currency: s.currencyCode)}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Phí phục vụ: ${orderMoney(BigInt.from(order.serviceChargeAmount.minorUnits), currency: s.currencyCode)}',
                                style: const TextStyle(fontSize: 13),
                              ),
                              const Divider(height: 16),
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    'Tổng: ${orderMoney(BigInt.from(s.totalAmount.minorUnits), currency: s.currencyCode)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: OrderPalette.orange,
                                        ),
                                  ),
                                  Text(
                                    'Đã trả: ${orderMoney(BigInt.from(s.paidAmount.minorUnits), currency: s.currencyCode)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ── Actions row (preserved for regression compatibility) ──
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
                                      AccessPolicy.canTables(
                                        session,
                                        'TABLE_VIEW',
                                      )))
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
                      const Text(
                        'Chưa hỗ trợ gửi bếp, thanh toán hoặc đóng bill.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),

                // ── Sticky bottom bar matching Photo 2 ───────────────
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Tổng: ${orderMoney(BigInt.from(s.totalAmount.minorUnits), currency: s.currencyCode)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: OrderPalette.orange,
                            ),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => _showProvisionalBill(
                            context,
                            order,
                            currentTableName,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: OrderPalette.orange,
                            side: const BorderSide(color: OrderPalette.orange),
                          ),
                          child: const Text('Tạm tính'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ── FAB (+) "Gọi thêm món" ──────────────────────────────
            if (canAppend && AccessPolicy.canMenu(session, 'MENU_VIEW'))
              Positioned(
                right: 16,
                bottom: 76,
                child: SafeArea(
                  child: FloatingActionButton(
                    heroTag: 'order-append-$id',
                    tooltip: 'Gọi thêm món',
                    backgroundColor: OrderPalette.orange,
                    foregroundColor: Colors.white,
                    onPressed: () =>
                        _openAppend(context, ref, order, currentTableName),
                    child: const Icon(Icons.add),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
