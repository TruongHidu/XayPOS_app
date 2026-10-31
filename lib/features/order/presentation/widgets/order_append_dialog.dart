import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_quantity.dart';
import '../controllers/order_append_controller.dart';
import '../controllers/order_draft_controller.dart' show OrderDraftLine;
import '../providers/order_providers.dart';
import 'order_menu_picker.dart';
import 'order_widgets.dart';

class OrderAppendDialog extends ConsumerStatefulWidget {
  const OrderAppendDialog({super.key, required this.order});
  final OrderDetail order;
  @override
  ConsumerState<OrderAppendDialog> createState() => _OrderAppendDialogState();
}

class _OrderAppendDialogState extends ConsumerState<OrderAppendDialog> {
  @override
  void initState() {
    super.initState();
    ref.read(orderDetailProvider(widget.order.id)).seed(widget.order);
    ref.read(orderAppendProvider(widget.order.id)).begin(widget.order);
  }

  Future<void> _edit(OrderAppendController cart, OrderDraftLine line) async {
    final input = await showOrderDialog<(OrderQuantity, String)>(
      context,
      ref,
      permission: 'ORDER_UPDATE',
      child: OrderLineEditor(quantity: line.quantity, note: line.note),
    );
    if (mounted && input != null) cart.edit(line.id, input.$1, input.$2);
  }

  Future<void> _send(OrderAppendController cart, {bool retry = false}) async {
    final result = await (retry ? cart.retry() : cart.send());
    if (mounted && cart.current && result is Success<OrderDetail>) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _close(OrderAppendController cart) async {
    if (cart.frozen) return;
    if (cart.dirty &&
        !await confirmOrderAction(
          context,
          ref,
          'ORDER_UPDATE',
          'Bỏ giỏ gọi thêm?',
          'Các món đang chọn chưa được gửi và sẽ bị bỏ.',
        )) {
      return;
    }
    if (mounted && cart.current) {
      cart.discard();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(orderAppendProvider(widget.order.id));
    final detail = ref.watch(orderDetailProvider(widget.order.id));
    final size = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: !cart.busy && !cart.uncertain && !cart.dirty,
      child: Dialog(
        child: SizedBox(
          width: 600,
          height: (size.height - MediaQuery.viewInsetsOf(context).bottom - 80)
              .clamp(180, 720),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final minimum =
                  480.0 +
                  (MediaQuery.textScalerOf(context).scale(14) - 14) * 16;
              return SingleChildScrollView(
                child: SizedBox(
                  height: constraints.maxHeight < minimum
                      ? minimum
                      : constraints.maxHeight,
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'Gọi thêm · ${widget.order.summary.orderCode}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TabBar(
                          tabs: [
                            const Tab(text: 'Chọn món gọi thêm'),
                            Tab(text: 'Giỏ gọi thêm (${cart.lines.length})'),
                          ],
                        ),
                        if (cart.busy) const LinearProgressIndicator(),
                        Expanded(
                          child: TabBarView(
                            children: [
                              OrderMenuPicker(
                                permission: 'ORDER_UPDATE',
                                onSelect: cart.add,
                                enabled: cart.canPick,
                                cartLines: cart.lines,
                              ),
                              ListView(
                                padding: const EdgeInsets.all(12),
                                children: [
                                  if (cart.lines.isEmpty)
                                    const Text('Chưa chọn món gọi thêm.'),
                                  for (final line in cart.lines)
                                    Card(
                                      child: ListTile(
                                        title: Text(line.item.name),
                                        subtitle: Text(
                                          '${line.quantity} ${line.item.baseUnit} · ${orderMoney(line.previewMinor, currency: widget.order.summary.currencyCode)}'
                                          '${line.note == null ? '' : '\n${line.note}'}',
                                        ),
                                        trailing: Wrap(
                                          children: [
                                            IconButton(
                                              tooltip: 'Sửa dòng gọi thêm',
                                              onPressed: cart.canPick
                                                  ? () => _edit(cart, line)
                                                  : null,
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Bỏ dòng gọi thêm',
                                              onPressed: cart.canPick
                                                  ? () => cart.remove(line.id)
                                                  : null,
                                              icon: const Icon(
                                                Icons.delete_outline,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  Text(
                                    'Tổng phần mới dự kiến: ${orderMoney(cart.previewMinor, currency: widget.order.summary.currencyCode)}',
                                  ),
                                  const Text(
                                    'Giá và tổng chính thức lấy từ backend. Không thay đổi các món đã lưu.',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: size.height * .25,
                          ),
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                OrderFailurePanel(
                                  failure: cart.failure,
                                  retry: cart.canRetry
                                      ? () => _send(cart, retry: true)
                                      : null,
                                  label: 'Kiểm tra lại lần gọi thêm',
                                ),
                                if (cart.uncertain)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      'Chưa xác định kết quả. Giỏ đã khóa; kiểm tra lại đúng yêu cầu ban đầu. Tải hiện trạng không xác nhận lần gửi này.',
                                    ),
                                  ),
                                if (cart.keyConflict)
                                  const Text(
                                    'Lần gửi này trùng với một lần gửi trước nhưng nội dung khác. Đừng gửi lại, hãy nhờ người quản lý kiểm tra đơn.',
                                  ),
                                if (cart.needsReview)
                                  Wrap(
                                    children: [
                                      if (detail.can('ORDER_VIEW'))
                                        TextButton(
                                          onPressed: detail.loading || cart.busy
                                              ? null
                                              : detail.load,
                                          child: const Text(
                                            'Tải hiện trạng đơn',
                                          ),
                                        ),
                                      TextButton(
                                        onPressed: cart.busy
                                            ? null
                                            : () {
                                                if (!cart.reviewCurrent()) {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                        'Cần dữ liệu mới và đơn còn cho phép gọi thêm.',
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                        child: const Text(
                                          'Đã đối chiếu, dùng dữ liệu mới',
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: cart.frozen
                                    ? null
                                    : () => _close(cart),
                                child: const Text('Đóng'),
                              ),
                              FilledButton(
                                onPressed: cart.canPick && cart.lines.isNotEmpty
                                    ? () => _send(cart)
                                    : null,
                                child: Text(
                                  cart.busy
                                      ? 'Đang xử lý...'
                                      : 'Gửi món gọi thêm',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
