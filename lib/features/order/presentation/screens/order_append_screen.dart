import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/result/result.dart';
import '../../../menu/domain/entities/menu_item.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_quantity.dart';
import '../controllers/order_append_controller.dart';
import '../controllers/order_draft_controller.dart' show OrderDraftLine;
import '../providers/order_providers.dart';
import '../widgets/order_cart_layout.dart';
import '../widgets/order_menu_picker.dart';
import '../widgets/order_widgets.dart';

class OrderAppendScreen extends ConsumerStatefulWidget {
  const OrderAppendScreen({super.key, required this.orderId, this.tableName});

  final String orderId;
  final String? tableName;

  @override
  ConsumerState<OrderAppendScreen> createState() => _OrderAppendScreenState();
}

class _OrderAppendScreenState extends ConsumerState<OrderAppendScreen>
    with SingleTickerProviderStateMixin, OrderCartUndo {
  // Created up front: side by side it may never be read during build, and
  // creating it lazily in dispose() would look up a deactivated ancestor.
  late final TabController _tabController;

  /// Menu and cart side by side; set on each layout.
  bool _wide = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(() {
      if (!mounted) return;
      final detail = ref.read(orderDetailProvider(widget.orderId));
      if (detail.order != null) {
        ref.read(orderAppendProvider(widget.orderId)).begin(detail.order!);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Side by side the cart is always in view; only the tabs need a switch.
  void _showCart() {
    if (!_wide) _tabController.animateTo(1);
  }

  void _showMenu() {
    if (!_wide) _tabController.animateTo(0);
  }

  void _removeLine(OrderAppendController cart, OrderDraftLine line) {
    final index = cart.lines.indexWhere((l) => l.id == line.id);
    if (index < 0) return;
    cart.remove(line.id);
    if (!cart.lines.any((l) => l.id == line.id)) rememberRemoved(line, index);
  }

  void _undoRemove(OrderAppendController cart) {
    final removed = takeRemoved();
    if (removed != null) cart.restore(removed.line, removed.index);
  }

  void _increment(OrderAppendController cart, MenuItem item) {
    final matching = cart.lines.where((l) => l.item.id == item.id).toList();
    if (matching.isEmpty) {
      cart.add(item);
    } else if (matching.length == 1) {
      final line = matching.first;
      cart.edit(line.id, line.quantity + OrderQuantity.one, line.note);
    } else {
      _showCart();
    }
  }

  void _decrement(OrderAppendController cart, MenuItem item) {
    final matching = cart.lines.where((l) => l.item.id == item.id).toList();
    if (matching.isEmpty) return;
    if (matching.length == 1) {
      final line = matching.first;
      if (line.quantity.milliUnits <= 1000) {
        cart.remove(line.id);
      } else {
        cart.edit(line.id, line.quantity - OrderQuantity.one, line.note);
      }
    } else {
      _showCart();
    }
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
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/app/order-create/bill/${widget.orderId}');
      }
    }
  }

  Future<void> _back(OrderAppendController cart) async {
    if (cart.frozen) {
      if (context.canPop()) context.pop();
      return;
    }
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
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/app/order-create/bill/${widget.orderId}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(orderDetailProvider(widget.orderId));
    final cart = ref.watch(orderAppendProvider(widget.orderId));
    if (detail.order != null && cart.baselineVersion == null) {
      cart.begin(detail.order!);
    }

    final order = detail.order;
    final currency = order?.summary.currencyCode;
    final title =
        widget.tableName ?? order?.summary.orderCode ?? 'Gọi thêm món';

    return PopScope(
      canPop: !cart.busy && !cart.uncertain && !cart.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && mounted) {
          await _back(cart);
        }
      },
      child: Material(
        color: AppColors.grey50,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textGrowth = (MediaQuery.textScalerOf(context).scale(14) - 14)
                .clamp(0.0, 28.0);
            final compact = constraints.maxHeight < 420 + textGrowth * 2;
            _wide = constraints.maxWidth >= orderSplitMinWidth;

            final Widget menuPane = OrderMenuPicker(
              permission: 'ORDER_UPDATE',
              cartLines: cart.lines,
              currencyCode: currency,
              enabled: cart.canPick,
              onSelect: cart.add,
              onIncrement: (item) => _increment(cart, item),
              onDecrement: (item) => _decrement(cart, item),
              onEditLine: (item) => _showCart(),
            );

            final Widget cartPane = ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
              children: [
                if (cart.lines.isEmpty && removedLine == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Chưa chọn món gọi thêm nào.')),
                  ),
                ...withUndoTile(
                  enabled: cart.canPick,
                  onUndo: () => _undoRemove(cart),
                  [
                    for (final line in cart.lines)
                      Card(
                        color: Colors.white,
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: AppColors.grey200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      line.item.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    orderMoney(
                                      line.previewMinor,
                                      currency: currency,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: OrderPalette.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${line.quantity} ${line.item.baseUnit}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.grey600,
                                ),
                              ),
                              if (line.note != null &&
                                  line.note!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Ghi chú: ${line.note}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.brown.shade700,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: 4,
                                  children: [
                                    TextButton.icon(
                                      onPressed: cart.canPick
                                          ? () => _edit(cart, line)
                                          : null,
                                      icon: const Icon(
                                        Icons.edit_note,
                                        size: 16,
                                      ),
                                      label: const Text('Sửa'),
                                    ),
                                    TextButton.icon(
                                      onPressed: cart.canPick
                                          ? () => _removeLine(cart, line)
                                          : null,
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        size: 16,
                                      ),
                                      label: const Text('Bỏ món'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                if (cart.lines.isNotEmpty) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Tổng phần mới dự kiến: ${orderMoney(cart.previewMinor, currency: currency)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    'Giá và tổng chính thức lấy từ backend. Các món đã lưu không đổi.',
                    style: TextStyle(fontSize: 12, color: AppColors.grey600),
                  ),
                ],
              ],
            );

            return Column(
              children: [
                // ── In-page Header ──────────────────────────────────────
                SafeArea(
                  child: Container(
                    color: Colors.white,
                    padding: compact
                        ? const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          )
                        : const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.grey200),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.chevron_left, size: 22),
                            tooltip: 'Quay lại',
                            onPressed: () => _back(cart),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 38,
                              minHeight: 38,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.grey900,
                                ),
                              ),
                              if (!compact)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 2,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF0EB),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'Gọi thêm món',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: OrderPalette.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    // if (order != null)
                                    //   Text(
                                    //     '#${order.summary.orderCode}',
                                    //     style: TextStyle(
                                    //       fontSize: 12,
                                    //       color: AppColors.grey600,
                                    //     ),
                                    //   ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.grey200),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.search, size: 18),
                            tooltip: 'Tìm kiếm',
                            onPressed: _showMenu,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 38,
                              minHeight: 38,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Navigation Tabs ─────────────────────────────────────
                if (!_wide)
                  Container(
                    color: Colors.white,
                    child: TabBar(
                      controller: _tabController,
                      indicatorColor: OrderPalette.primary,
                      labelColor: OrderPalette.primary,
                      unselectedLabelColor: AppColors.grey700,
                      tabs: [
                        const Tab(text: 'Chọn món'),
                        Tab(text: 'Giỏ gọi thêm (${cart.lines.length})'),
                      ],
                    ),
                  ),

                if (cart.busy) const LinearProgressIndicator(),

                // ── Error & Review panels ───────────────────────────────
                OrderFailurePanel(
                  failure: cart.failure,
                  retry: cart.canRetry ? () => _send(cart, retry: true) : null,
                  label: 'Kiểm tra lại lần gọi thêm',
                ),
                if (cart.uncertain)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Chưa xác định kết quả. Giỏ đã khóa; kiểm tra lại đúng yêu cầu ban đầu.',
                    ),
                  ),
                if (cart.keyConflict)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Lần gửi này trùng với một lần gửi trước nhưng nội dung khác. Đừng gửi lại, hãy nhờ người quản lý kiểm tra đơn.',
                    ),
                  ),
                if (cart.needsReview)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        if (detail.can('ORDER_VIEW'))
                          TextButton(
                            onPressed: detail.loading || cart.busy
                                ? null
                                : detail.load,
                            child: const Text('Tải hiện trạng đơn'),
                          ),
                        TextButton(
                          onPressed: cart.busy
                              ? null
                              : () {
                                  if (!cart.reviewCurrent()) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Cần dữ liệu mới và đơn còn cho phép gọi thêm.',
                                        ),
                                      ),
                                    );
                                  }
                                },
                          child: const Text('Đã đối chiếu, dùng dữ liệu mới'),
                        ),
                      ],
                    ),
                  ),

                // ── Main Tab Views ──────────────────────────────────────
                Expanded(
                  child: _wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: menuPane),
                            const VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: AppColors.grey200,
                            ),
                            SizedBox(
                              key: const ValueKey('order-cart-pane'),
                              width: orderCartPaneWidth(constraints.maxWidth),
                              child: Column(
                                children: [
                                  OrderCartPaneHeader(
                                    title:
                                        'Giỏ gọi thêm (${cart.lines.length})',
                                  ),
                                  const Divider(
                                    height: 1,
                                    color: AppColors.grey200,
                                  ),
                                  Expanded(child: cartPane),
                                ],
                              ),
                            ),
                          ],
                        )
                      : TabBarView(
                          controller: _tabController,
                          children: [menuPane, cartPane],
                        ),
                ),

                // ── Sticky Bottom Cart Bar ──────────────────────────────
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
                  padding: compact
                      ? const EdgeInsets.fromLTRB(8, 4, 8, 6)
                      : const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: SafeArea(
                    top: false,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        if (!compact)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Giỏ gọi thêm (${cart.lines.length})',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.grey900,
                                ),
                              ),
                              Text(
                                'Tạm tính : ${orderMoney(cart.previewMinor, currency: currency)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.grey700,
                                ),
                              ),
                            ],
                          ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (!compact && !_wide)
                              OutlinedButton(
                                onPressed: _showCart,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: OrderPalette.primary,
                                  side: const BorderSide(
                                    color: OrderPalette.primary,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Text('Xem món gọi thêm'),
                                    SizedBox(width: 4),
                                    Icon(Icons.arrow_upward, size: 15),
                                  ],
                                ),
                              ),
                            FilledButton(
                              onPressed: cart.canPick && cart.lines.isNotEmpty
                                  ? () => _send(cart)
                                  : null,
                              style: FilledButton.styleFrom(
                                backgroundColor: OrderPalette.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(
                                cart.busy
                                    ? 'Đang xử lý...'
                                    : 'Gửi món gọi thêm',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
