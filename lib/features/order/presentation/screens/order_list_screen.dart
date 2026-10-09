import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../domain/entities/order_entities.dart';
import '../widgets/order_widgets.dart';

class OrderListScreen extends ConsumerWidget {
  const OrderListScreen({super.key, this.sessionId});
  final String? sessionId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(orderListProvider(sessionId));
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canOrders(session, 'ORDER_VIEW')) {
      return const Center(child: Text('Bạn không có quyền xem đơn.'));
    }
    return Column(
      children: [
        if (sessionId != null)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Lịch sử đơn trong phiên. Gọi món tại bàn từ màn hình Gọi món.',
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            maxLength: 100,
            onChanged: c.search,
            decoration: const InputDecoration(
              labelText: 'Tìm mã đơn',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              DropdownButton<OrderStatus?>(
                value: c.query.status,
                hint: const Text('Mọi trạng thái'),
                items: [
                  const DropdownMenuItem<OrderStatus?>(
                    value: null,
                    child: Text('Mọi trạng thái'),
                  ),
                  for (final status in OrderStatus.values)
                    DropdownMenuItem(value: status, child: Text(status.label)),
                ],
                onChanged: (status) => c.filter(
                  status: status,
                  type: c.query.serviceType,
                  sortBy: c.query.sortBy,
                  direction: c.query.direction,
                ),
              ),
              DropdownButton<ServiceType?>(
                value: c.query.serviceType,
                hint: const Text('Mọi loại đơn'),
                items: [
                  const DropdownMenuItem<ServiceType?>(
                    value: null,
                    child: Text('Mọi loại đơn'),
                  ),
                  for (final type in ServiceType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: (type) => c.filter(
                  status: c.query.status,
                  type: type,
                  sortBy: c.query.sortBy,
                  direction: c.query.direction,
                ),
              ),
              DropdownButton<String>(
                value: c.query.sortBy,
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
              IconButton(
                tooltip: c.query.direction == 'desc' ? 'Giảm dần' : 'Tăng dần',
                onPressed: () => c.filter(
                  status: c.query.status,
                  type: c.query.serviceType,
                  sortBy: c.query.sortBy,
                  direction: c.query.direction == 'desc' ? 'asc' : 'desc',
                ),
                icon: const Icon(Icons.swap_vert),
              ),
            ],
          ),
        ),
        if (c.loading) const LinearProgressIndicator(),
        OrderFailurePanel(failure: c.failure, retry: c.load),
        Expanded(
          child: RefreshIndicator(
            onRefresh: c.load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                if (c.page?.content.isEmpty == true)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Chưa có đơn phù hợp.'),
                  ),
                for (final order in c.page?.content ?? <OrderSummary>[])
                  Card(
                    child: ListTile(
                      onTap: () => context.push('/app/orders/${order.id}'),
                      leading: Icon(
                        order.serviceType == ServiceType.takeaway
                            ? Icons.shopping_cart_outlined
                            : Icons.table_restaurant,
                        color: OrderPalette.orange,
                      ),
                      title: Text(order.orderCode),
                      subtitle: Text(
                        '${order.serviceType.label} · ${order.status.label}\n${order.paymentStatus.label}\n${formatLocalDate(order.createdAt)}',
                      ),
                      trailing: Text(
                        orderMoney(
                          BigInt.from(order.totalAmount.minorUnits),
                          currency: order.currencyCode,
                        ),
                      ),
                    ),
                  ),
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
