import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../../../core/ui/widgets/endless_list_footer.dart';
import '../../../../core/ui/widgets/filter_panel_button.dart';
import '../../../../core/ui/widgets/list_states.dart';
import '../../domain/entities/order_entities.dart';
import '../controllers/order_list_controller.dart';
import '../widgets/order_widgets.dart';

class OrderListScreen extends ConsumerStatefulWidget {
  const OrderListScreen({super.key, this.sessionId, this.initialServiceType});
  final String? sessionId;

  /// Pre-selects the order type filter, e.g. from "Xem lịch sử đơn mang đi".
  final ServiceType? initialServiceType;

  @override
  ConsumerState<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends ConsumerState<OrderListScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    final type = widget.initialServiceType;
    if (type != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(orderListProvider(widget.sessionId)).filter(type: type);
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _select<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) => DropdownButtonFormField<T>(
    key: ValueKey((label, value)),
    value: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final entry in items.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
    ],
    onChanged: (value) => onChanged(value as T),
  );

  Widget _buildFilterCard(OrderListController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SearchFilterRow(
        search: TextField(
          controller: _searchController,
          maxLength: 100,
          onChanged: (val) {
            c.search(val);
            setState(() {});
          },
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Tìm theo mã đơn (ví dụ: OD-001)...',
            hintStyle: TextStyle(fontSize: 13, color: AppColors.grey400),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: OrderPalette.primary,
              size: 20,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.cancel_rounded, size: 18),
                    color: AppColors.grey400,
                    onPressed: () {
                      _searchController.clear();
                      c.search('');
                      setState(() {});
                    },
                  )
                : null,
            filled: true,
            fillColor: AppColors.grey50,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.grey200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.grey200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: OrderPalette.primary,
                width: 1.5,
              ),
            ),
            counterText: '',
          ),
        ),
        filter: FilterPanelButton(
          listenable: c,
          title: 'Bộ lọc đơn hàng',
          onRefresh: c.load,
          activeCount: () => [
            c.query.status != null,
            c.query.serviceType != null,
            c.query.sortBy != 'createdAt',
            c.query.direction != 'desc',
          ].where((active) => active).length,
          onClear: () =>
              c.filter(status: null, type: null, sortBy: 'createdAt'),
          filters: () => [
            _select<OrderStatus?>(
              label: 'Trạng thái đơn',
              value: c.query.status,
              items: {
                null: 'Mọi trạng thái',
                for (final status in OrderStatus.values) status: status.label,
              },
              onChanged: (status) => c.filter(
                status: status,
                type: c.query.serviceType,
                sortBy: c.query.sortBy,
                direction: c.query.direction,
              ),
            ),
            _select<ServiceType?>(
              label: 'Loại đơn',
              value: c.query.serviceType,
              items: {
                null: 'Mọi loại đơn',
                for (final type in ServiceType.values) type: type.label,
              },
              onChanged: (type) => c.filter(
                status: c.query.status,
                type: type,
                sortBy: c.query.sortBy,
                direction: c.query.direction,
              ),
            ),
            _select<String>(
              label: 'Sắp xếp theo',
              value: c.query.sortBy,
              items: const {
                'createdAt': 'Thời gian tạo',
                'updatedAt': 'Cập nhật',
                'orderCode': 'Mã đơn',
                'totalAmount': 'Tổng tiền',
              },
              onChanged: (sort) => c.filter(
                status: c.query.status,
                type: c.query.serviceType,
                sortBy: sort,
                direction: c.query.direction,
              ),
            ),
            _select<String>(
              label: 'Thứ tự',
              value: c.query.direction,
              items: const {'desc': 'Mới/lớn trước', 'asc': 'Cũ/nhỏ trước'},
              onChanged: (direction) => c.filter(
                status: c.query.status,
                type: c.query.serviceType,
                sortBy: c.query.sortBy,
                direction: direction,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(OrderSummary order) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.grey200),
      ),
      color: Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        onTap: () => context.push('/app/orders/${order.id}'),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.warningTint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            order.serviceType == ServiceType.takeaway
                ? Icons.shopping_cart_outlined
                : Icons.table_restaurant_outlined,
            color: OrderPalette.primary,
            size: 22,
          ),
        ),
        title: Text(
          order.orderCode,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: AppColors.grey900,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  // Badge loại đơn
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.grey100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      order.serviceType.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.grey700,
                      ),
                    ),
                  ),
                  // Badge trạng thái
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: order.status == OrderStatus.cancelled
                          ? AppColors.dangerSoft
                          : (order.status == OrderStatus.completed
                                ? AppColors.grey100
                                : AppColors.infoSoft),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      order.status.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: order.status == OrderStatus.cancelled
                            ? AppColors.danger
                            : (order.status == OrderStatus.completed
                                  ? AppColors.grey600
                                  : AppColors.info),
                      ),
                    ),
                  ),
                  // Badge thanh toán
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: order.paymentStatus == OrderPaymentStatus.paid
                          ? AppColors.successSoft
                          : AppColors.warningSoft,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      order.paymentStatus.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: order.paymentStatus == OrderPaymentStatus.paid
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                formatLocalDate(order.createdAt),
                style: TextStyle(fontSize: 12, color: AppColors.grey500),
              ),
            ],
          ),
        ),
        trailing: Text(
          orderMoney(
            BigInt.from(order.totalAmount.minorUnits),
            currency: order.currencyCode,
          ),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: OrderPalette.primary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(orderListProvider(widget.sessionId));
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canOrders(session, 'ORDER_VIEW')) {
      return const Center(child: Text('Bạn không có quyền xem đơn.'));
    }

    final orders = c.page?.content ?? const <OrderSummary>[];
    final footer = orders.isNotEmpty;
    // Banner, filters and loading/empty states sit above the cards.
    final leading = <Widget>[
      if (widget.sessionId != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.warningTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warningBorder),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline, size: 16, color: OrderPalette.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lịch sử đơn trong phiên. Gọi món tại bàn từ màn hình Gọi món.',
                    style: TextStyle(fontSize: 12.5, color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
        ),

      // ── Phần tìm kiếm & bộ lọc thẩm mỹ (cuộn theo list) ────
      _buildFilterCard(c),

      // ── Danh sách đơn hàng ─────────────────────────────────
      if (c.page == null && c.loading)
        const ListSkeleton(count: 5, height: 84, maxColumns: 1),
      if (c.page?.content.isEmpty == true)
        const EmptyState(
          icon: Icons.receipt_long_outlined,
          message: 'Chưa có đơn phù hợp.',
        ),
    ];

    return Column(
      children: [
        LoadingStrip(loading: c.loading),
        OrderFailurePanel(failure: c.failure, retry: c.load),
        Expanded(
          child: RefreshIndicator(
            onRefresh: c.load,
            // Built lazily: only the cards on screen exist, however many
            // pages have been loaded, and a realtime refresh rebuilds only them.
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: leading.length + orders.length + (footer ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < leading.length) return leading[index];
                final at = index - leading.length;
                if (at < orders.length) {
                  final order = orders[at];
                  return KeyedSubtree(
                    key: ValueKey('order-card-${order.id}'),
                    child: _buildOrderCard(order),
                  );
                }
                return EndlessListFooter(
                  hasMore: c.hasMore,
                  failureMessage: c.endless.failure?.message,
                  endLabel: 'Đã hiển thị tất cả ${c.page!.totalElements} đơn',
                  onLoadMore: c.loadMore,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
