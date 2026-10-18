import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import '../../../tables/domain/entities/table_entities.dart';
import '../../../qr_order/presentation/widgets/qr_request_inbox.dart';
import '../../../qr_order/presentation/widgets/qr_inbox_visibility.dart';
import '../../domain/entities/order_entities.dart';
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
          await context.push(
            '/app/order-create/bill/${Uri.encodeComponent(order.id)}?tableName=${Uri.encodeQueryComponent(table.name)}',
          );
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
    final qr = ref.watch(qrInboxProvider);
    final session = ref.watch(authControllerProvider).state.session;
    final menuAllowed = AccessPolicy.canMenu(session, 'MENU_VIEW');
    return QrInboxVisibility(
      child: Column(
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
          if (qr.can('ORDER_VIEW'))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => showQrRequestInbox(
                        context,
                        ref,
                        tableNames: {
                          for (final table in c.tables) table.id: table.name,
                        },
                      ),
                      icon: Icon(
                        qr.failure == null
                            ? Icons.qr_code_2
                            : Icons.sync_problem,
                      ),
                      label: Text('Yêu cầu QR (${qr.pending.length})'),
                    ),
                    if (qr.failure != null)
                      const Text(
                        'QR chưa đồng bộ',
                        style: TextStyle(fontSize: 12),
                      ),
                    if (qr.arrivals > 0 && qr.failure == null)
                      Text(
                        'Có ${qr.arrivals} yêu cầu QR mới',
                        style: const TextStyle(
                          color: Color(0xFF1565C0),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (c.tableAccess)
            SizedBox(
              height:
                  58 + (MediaQuery.textScalerOf(context).scale(14) - 14) * 2,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Tất cả khu vực'),
                      selected: c.query.areaId == null,
                      selectedColor: OrderPalette.white,
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
                        selectedColor: OrderPalette.white,
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
                      crossAxisCount:
                          qr.pending.isNotEmpty &&
                              MediaQuery.textScalerOf(context).scale(14) > 22
                          ? (constraints.maxWidth / 320).floor().clamp(1, 6)
                          : constraints.maxWidth < 300
                          ? 1
                          : constraints.maxWidth < 600
                          ? 2
                          : (constraints.maxWidth / 200).floor().clamp(3, 6),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      mainAxisExtent:
                          160 +
                          (MediaQuery.textScalerOf(context).scale(14) - 14) *
                              7 +
                          (qr.pending.isEmpty
                              ? 0
                              : 52 +
                                    (MediaQuery.textScalerOf(
                                              context,
                                            ).scale(14) -
                                            14) *
                                        2),
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
                      final qrRequests = qr
                          .forTable(table.id, table.currentSession?.id)
                          .length;
                      final hasUnconfirmedOrder =
                          tile.order?.status == OrderStatus.open;
                      final subtitle = switch (tile.billState) {
                        TableBillState.noSession => 'Còn trống',
                        TableBillState.noOrder => 'Đang sử dụng · Chưa có đơn',
                        TableBillState.inconsistent => 'Cần đồng bộ phiên/đơn',
                        TableBillState.ready when hasUnconfirmedOrder =>
                          'Chưa xác nhận',
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
                        hasOrder: tile.order != null,
                        hasUnconfirmedOrder: hasUnconfirmedOrder,
                        qrRequests: qrRequests,
                        onQrTap: qrRequests == 0
                            ? null
                            : () => showQrRequestInbox(
                                context,
                                ref,
                                tableId: table.id,
                                tableNames: {table.id: table.name},
                              ),
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
      ),
    );
  }
}

class OrderContextCard extends StatelessWidget {
  const OrderContextCard({
    super.key,
    required this.name,
    required this.icon,
    this.hasOrder = false,
    this.hasUnconfirmedOrder = false,
    this.qrRequests = 0,
    this.onQrTap,
    this.subtitle,
    this.amount,
    this.onTap,
  });
  final String name;
  final IconData icon;
  final bool hasOrder;
  final bool hasUnconfirmedOrder;
  final int qrRequests;
  final VoidCallback? onQrTap;
  final String? subtitle, amount;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final accent = hasUnconfirmedOrder
        ? const Color(0xFF9A6700)
        : hasOrder
        ? const Color(0xFF2E7D32)
        : OrderPalette.orange;
    return Semantics(
      button: true,
      enabled: onTap != null,
      excludeSemantics: qrRequests == 0,
      label: qrRequests == 0
          ? [name, subtitle, amount].whereType<String>().join(', ')
          : null,
      child: Material(
        color: hasUnconfirmedOrder
            ? const Color(0xFFFFF8E1)
            : hasOrder
            ? const Color(0xFFE8F5E9)
            : OrderPalette.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: accent, width: 1.2),
        ),
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
                    Icon(icon, size: 18, color: accent),
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
                if (qrRequests > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextButton(
                      key: const ValueKey('table-qr-requests'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF0D47A1),
                        backgroundColor: const Color(0xFFE3F2FD),
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                      ),
                      onPressed: onQrTap,
                      child: Text(
                        'QR · $qrRequests yêu cầu mới',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: hasUnconfirmedOrder
                          ? const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            )
                          : EdgeInsets.zero,
                      decoration: hasUnconfirmedOrder
                          ? BoxDecoration(
                              color: const Color(0xFFFFECB3),
                              borderRadius: BorderRadius.circular(4),
                            )
                          : null,
                      child: Text(
                        subtitle!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: hasUnconfirmedOrder ? accent : null,
                          fontWeight: hasUnconfirmedOrder
                              ? FontWeight.w700
                              : null,
                        ),
                      ),
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
}
