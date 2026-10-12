import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../domain/entities/order_entities.dart';
import '../controllers/order_list_controller.dart';
import '../widgets/order_widgets.dart';

class OrderListScreen extends ConsumerStatefulWidget {
  const OrderListScreen({super.key, this.sessionId});
  final String? sessionId;

  @override
  ConsumerState<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends ConsumerState<OrderListScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildDropdownPill<T>({
    required T? value,
    required String hint,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    bool isActive = false,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFFFF7ED) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? OrderPalette.orange : const Color(0xFFE5E7EB),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: isActive ? OrderPalette.orange : Colors.grey.shade500,
          ),
          borderRadius: BorderRadius.circular(12),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            color: isActive ? OrderPalette.orange : const Color(0xFF374151),
          ),
          hint: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 5),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          selectedItemBuilder: (context) {
            return items.map((item) {
              final text = item.child is Text ? (item.child as Text).data ?? '' : '';
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 14,
                    color: isActive ? OrderPalette.orange : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    text,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive
                          ? OrderPalette.orange
                          : const Color(0xFF374151),
                    ),
                  ),
                ],
              );
            }).toList();
          },
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDirectionButton({
    required bool isDesc,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Tooltip(
        message: isDesc ? 'Đang giảm dần' : 'Đang tăng dần',
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isDesc
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  size: 15,
                  color: OrderPalette.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  isDesc ? 'Giảm dần' : 'Tăng dần',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterCard(OrderListController c) {
    final hasActiveFilter = c.query.status != null ||
        c.query.serviceType != null ||
        c.query.sortBy != 'createdAt' ||
        c.query.direction != 'desc' ||
        _searchController.text.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Search Input ───────────────────────────────────────────
          TextField(
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
              hintStyle: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade400,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: OrderPalette.orange,
                size: 20,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.cancel_rounded, size: 18),
                      color: Colors.grey.shade400,
                      onPressed: () {
                        _searchController.clear();
                        c.search('');
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: OrderPalette.orange,
                  width: 1.5,
                ),
              ),
              counterText: '',
            ),
          ),

          const SizedBox(height: 10),

          // ── Filter Pills & Sort Options ────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // 1. Trạng thái đơn (Status)
              _buildDropdownPill<OrderStatus?>(
                value: c.query.status,
                hint: 'Mọi trạng thái',
                icon: Icons.flag_outlined,
                isActive: c.query.status != null,
                items: [
                  const DropdownMenuItem<OrderStatus?>(
                    value: null,
                    child: Text('Mọi trạng thái'),
                  ),
                  for (final status in OrderStatus.values)
                    DropdownMenuItem(
                      value: status,
                      child: Text(status.label),
                    ),
                ],
                onChanged: (status) => c.filter(
                  status: status,
                  type: c.query.serviceType,
                  sortBy: c.query.sortBy,
                  direction: c.query.direction,
                ),
              ),

              // 2. Loại đơn (Service Type)
              _buildDropdownPill<ServiceType?>(
                value: c.query.serviceType,
                hint: 'Mọi loại đơn',
                icon: Icons.storefront_outlined,
                isActive: c.query.serviceType != null,
                items: [
                  const DropdownMenuItem<ServiceType?>(
                    value: null,
                    child: Text('Mọi loại đơn'),
                  ),
                  for (final type in ServiceType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(type.label),
                    ),
                ],
                onChanged: (type) => c.filter(
                  status: c.query.status,
                  type: type,
                  sortBy: c.query.sortBy,
                  direction: c.query.direction,
                ),
              ),

              // 3. Sắp xếp theo (Sort By)
              _buildDropdownPill<String>(
                value: c.query.sortBy,
                hint: 'Thời gian tạo',
                icon: Icons.sort_rounded,
                isActive: c.query.sortBy != 'createdAt',
                items: [
                  for (final entry in {
                    'createdAt': 'Thời gian tạo',
                    'updatedAt': 'Cập nhật',
                    'orderCode': 'Mã đơn',
                    'totalAmount': 'Tổng tiền',
                  }.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (sort) => c.filter(
                  status: c.query.status,
                  type: c.query.serviceType,
                  sortBy: sort!,
                  direction: c.query.direction,
                ),
              ),

              // 4. Chiều sắp xếp (Tăng / Giảm)
              _buildDirectionButton(
                isDesc: c.query.direction == 'desc',
                onTap: () => c.filter(
                  status: c.query.status,
                  type: c.query.serviceType,
                  sortBy: c.query.sortBy,
                  direction: c.query.direction == 'desc' ? 'asc' : 'desc',
                ),
              ),

              // 5. Nút đặt lại (Reset filters)
              if (hasActiveFilter)
                InkWell(
                  onTap: () {
                    _searchController.clear();
                    c.search('');
                    c.filter(
                      status: null,
                      type: null,
                      sortBy: 'createdAt',
                      direction: 'desc',
                    );
                    setState(() {});
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          size: 15,
                          color: Colors.red.shade400,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Đặt lại',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(OrderSummary order) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      color: Colors.white,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 6,
        ),
        onTap: () => context.push('/app/orders/${order.id}'),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            order.serviceType == ServiceType.takeaway
                ? Icons.shopping_cart_outlined
                : Icons.table_restaurant_outlined,
            color: OrderPalette.orange,
            size: 22,
          ),
        ),
        title: Text(
          order.orderCode,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: Color(0xFF111827),
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
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      order.serviceType.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade700,
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
                          ? const Color(0xFFFEE2E2)
                          : (order.status == OrderStatus.completed
                                ? const Color(0xFFF3F4F6)
                                : const Color(0xFFE0F2FE)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      order.status.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: order.status == OrderStatus.cancelled
                            ? const Color(0xFFDC2626)
                            : (order.status == OrderStatus.completed
                                  ? const Color(0xFF4B5563)
                                  : const Color(0xFF0284C7)),
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
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      order.paymentStatus.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: order.paymentStatus == OrderPaymentStatus.paid
                            ? const Color(0xFF15803D)
                            : const Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                formatLocalDate(order.createdAt),
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.grey.shade500,
                ),
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
            color: OrderPalette.orange,
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

    return Column(
      children: [
        if (c.loading) const LinearProgressIndicator(),
        OrderFailurePanel(failure: c.failure, retry: c.load),
        Expanded(
          child: RefreshIndicator(
            onRefresh: c.load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                if (widget.sessionId != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFEDD5)),
                      ),
                      child: Row(
                        children: const [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: OrderPalette.orange,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Lịch sử đơn trong phiên. Gọi món tại bàn từ màn hình Gọi món.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF9A3412),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ── Phần tìm kiếm & bộ lọc thẩm mỹ (cuộn theo list) ────
                _buildFilterCard(c),

                // ── Danh sách đơn hàng ─────────────────────────────────
                if (c.page?.content.isEmpty == true)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Chưa có đơn phù hợp.',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                for (final order in c.page?.content ?? <OrderSummary>[])
                  _buildOrderCard(order),
              ],
            ),
          ),
        ),
        OrderPaging(
          page: c.page?.page ?? 0,
          totalPages: c.page?.totalPages ?? 0,
          loading: c.loading,
          onPage: c.go,
        ),
      ],
    );
  }
}
