import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import '../../../tables/domain/entities/table_entities.dart';
import '../../domain/entities/order_table_workspace.dart';
import '../widgets/order_widgets.dart';

class OrderServiceContextScreen extends ConsumerWidget {
  const OrderServiceContextScreen({super.key});

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    RestaurantTable table,
  ) async {
    final controller = ref.read(orderServiceContextProvider);
    final result = await controller.selectTable(table.id);
    if (!context.mounted || !controller.current) return;
    if (result case Success(value: final selection)) {
      switch (selection) {
        case ViewTableOrder(order: final order):
          await context.push('/app/orders/${Uri.encodeComponent(order.id)}');
        case ComposeTableOrder(context: final target):
          await context.push(
            '/app/order-create?tableId=${Uri.encodeQueryComponent(target.tableId!)}',
          );
      }
      if (context.mounted && controller.current) await controller.refresh();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(orderServiceContextProvider);
    final session = ref.watch(authControllerProvider).state.session;
    final menuAllowed = AccessPolicy.canMenu(session, 'MENU_VIEW');
    return Column(
      children: [
        Row(
          children: [
            for (final filter in [
              (null, 'Tất cả'),
              (true, 'Sử dụng'),
              (false, 'Còn trống'),
            ])
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: c.query.occupied == filter.$1
                        ? Colors.black
                        : Colors.grey,
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: c.selecting
                      ? null
                      : () => c.filter(
                          occupied: filter.$1,
                          areaId: c.query.areaId,
                        ),
                  child: Text(filter.$2),
                ),
              ),
          ],
        ),
        const Divider(height: 1),
        if (c.tableAccess)
          SizedBox(
            height: 58 + (MediaQuery.textScalerOf(context).scale(14) - 14) * 2,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Tất cả khu vực'),
                    selected: c.query.areaId == null,
                    selectedColor: OrderPalette.pink,
                    onSelected: c.selecting
                        ? null
                        : (_) => c.filter(occupied: c.query.occupied),
                  ),
                ),
                for (final area in c.areas)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(area.name),
                      selected: c.query.areaId == area.id,
                      selectedColor: OrderPalette.pink,
                      backgroundColor: OrderPalette.grey,
                      onSelected: c.selecting
                          ? null
                          : (_) => c.filter(
                              occupied: c.query.occupied,
                              areaId: area.id,
                            ),
                    ),
                  ),
              ],
            ),
          ),
        if (!menuAllowed)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Cần MENU_VIEW và MENU_MANAGEMENT để chọn món; vẫn xem đơn nếu có ORDER_VIEW.',
            ),
          ),
        if (!c.tableAccess)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Chưa có quyền xem bàn. Bạn vẫn có thể tạo đơn mang đi nếu được cấp quyền.',
            ),
          ),
        if (c.loading || c.billsLoading || c.selecting)
          const LinearProgressIndicator(),
        OrderFailurePanel(failure: c.areasFailure, retry: c.loadAreas),
        OrderFailurePanel(failure: c.failure, retry: c.refresh),
        OrderFailurePanel(
          failure: c.billsFailure,
          retry: c.load,
          label: 'Tải lại tiền đơn',
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: c.refresh,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tables = c.tables;
                final takeaway = c.takeawayAllowed;
                return GridView.builder(
                  key: const ValueKey('order-table-grid'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(10),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: constraints.maxWidth < 300
                        ? 1
                        : constraints.maxWidth < 600
                        ? 2
                        : (constraints.maxWidth / 200).floor().clamp(3, 6),
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    mainAxisExtent:
                        160 +
                        (MediaQuery.textScalerOf(context).scale(14) - 14) * 7,
                  ),
                  itemCount: tables.length + (takeaway ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (takeaway && index == 0) {
                      return OrderContextCard(
                        name: 'Mang đi',
                        icon: Icons.shopping_cart_outlined,
                        onTap: menuAllowed
                            ? () => context.push(
                                '/app/order-create?serviceType=TAKEAWAY',
                              )
                            : null,
                      );
                    }
                    final table = tables[index - (takeaway ? 1 : 0)];
                    final tile = c.tile(table);
                    final subtitle = switch (tile.billState) {
                      TableBillState.noSession => 'Còn trống',
                      TableBillState.noOrder => 'Đang sử dụng · Chưa có đơn',
                      TableBillState.inconsistent => 'Cần đồng bộ phiên/đơn',
                      _ => 'Đang sử dụng',
                    };
                    final amount = switch (tile.billState) {
                      TableBillState.ready =>
                        'Tổng: ${orderMoney(BigInt.from(tile.order!.totalAmount.minorUnits), currency: tile.order!.currencyCode)}',
                      TableBillState.loading => 'Đang tải tiền đơn…',
                      TableBillState.unknown => 'Chưa tải được tiền đơn',
                      TableBillState.forbidden => 'Không có quyền xem đơn',
                      TableBillState.inconsistent => '—',
                      _ => null,
                    };
                    return OrderContextCard(
                      key: ValueKey('order-table-${table.id}'),
                      name: table.name,
                      icon: Icons.table_restaurant,
                      subtitle: table.area?.active == false
                          ? '$subtitle\nKhu vực ngừng hoạt động'
                          : subtitle,
                      amount: amount,
                      onTap: c.canSelect(table)
                          ? () => _select(context, ref, table)
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ),
        if (c.tableAccess &&
            !c.loading &&
            c.failure == null &&
            c.tables.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Không có bàn phù hợp.'),
          ),
      ],
    );
  }
}

class OrderContextCard extends StatelessWidget {
  const OrderContextCard({
    super.key,
    required this.name,
    required this.icon,
    this.subtitle,
    this.amount,
    this.onTap,
  });
  final String name;
  final IconData icon;
  final String? subtitle, amount;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    excludeSemantics: true,
    label: [name, subtitle, amount].whereType<String>().join(', '),
    child: Material(
      color: OrderPalette.pink,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: OrderPalette.orange),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    subtitle!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (amount != null)
                    Expanded(
                      child: Text(
                        amount!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (onTap == null) const Icon(Icons.lock_outline, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
