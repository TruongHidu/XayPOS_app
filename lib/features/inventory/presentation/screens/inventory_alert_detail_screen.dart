import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/inventory_quantity.dart';
import '../widgets/inventory_alert_widgets.dart';
import '../widgets/inventory_alert_sync_status.dart';
import '../widgets/inventory_widgets.dart';
import '../widgets/stock_widgets.dart';

class InventoryAlertDetailScreen extends ConsumerWidget {
  const InventoryAlertDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canViewInventoryAlerts(session)) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Bạn cần quyền xem kho và tính năng cảnh báo tồn thấp để mở màn hình này.',
          ),
        ),
      );
    }
    final c = ref.watch(inventoryAlertDetailProvider(id)), row = c.value;
    Widget metric(String label, InventoryQuantity value, String unit) => Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 6),
            Text(
              inventoryAmount(value, unit),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
    return RefreshIndicator(
      onRefresh: c.load,
      child: CustomScrollView(
        key: PageStorageKey((
          'alert-detail-scroll',
          ref.watch(inventoryScopeProvider),
          id,
        )),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const InventoryAlertSyncStatus(),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      Text(
                        'Chi tiết cảnh báo',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () =>
                                context.go('/app/inventory/alerts'),
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Về cảnh báo'),
                          ),
                          IconButton(
                            tooltip: 'Tải lại cảnh báo',
                            onPressed: c.loading || c.busy ? null : c.load,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (c.loading || c.busy) const LinearProgressIndicator(),
                  InventoryFailurePanel(
                    failure: c.failure,
                    retry: c.loading || c.busy ? null : c.load,
                  ),
                  if (c.requiresReview)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Kết quả cần được đối chiếu. Tải lại cảnh báo trước khi xác nhận tiếp.',
                      ),
                    ),
                  if (row != null) ...[
                    Text(
                      row.ingredientName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(row.ingredientSku ?? 'Chưa có SKU'),
                    Text('Kho: ${row.warehouseName} · ${row.warehouseCode}'),
                    const SizedBox(height: 12),
                    Wrap(children: [InventoryAlertBadge(row.status)]),
                    const SizedBox(height: 12),
                    const Text(
                      'Đây là một đợt cảnh báo đã lưu. Xác nhận đã xem không làm thay đổi số dư hoặc chứng từ kho.',
                    ),
                    if (AccessPolicy.canAcknowledgeInventoryAlert(session) &&
                        row.status.code == 'OPEN')
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                            key: const ValueKey('acknowledge-inventory-alert'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(48, 48),
                            ),
                            onPressed: c.canAcknowledge
                                ? () async {
                                    final result = await c.acknowledge();
                                    if (context.mounted &&
                                        c.allowed &&
                                        result is Success) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Đã xác nhận đã xem cảnh báo.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                : null,
                            icon: const Icon(Icons.done_all),
                            label: const Text('Xác nhận đã xem'),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Text(
                      'Tại thời điểm phát cảnh báo',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Phát lúc ${alertMoment(row.triggeredAt)}. Tên, SKU, đơn vị và ngưỡng bên dưới được giữ theo lịch sử.',
                    ),
                    const SizedBox(height: 12),
                    ResponsiveColumns(
                      minColumnWidth: 260,
                      maxColumns: 2,
                      children: [
                        metric(
                          'Tồn vật lý lúc phát',
                          row.quantityAtTrigger,
                          row.unit,
                        ),
                        metric(
                          'Ngưỡng lúc phát',
                          row.thresholdQuantity,
                          row.unit,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Số dư hiện tại',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'Số tồn ở lần tải gần nhất. Cảnh báo dựa trên tồn thực tế; hàng đang giữ cho đơn làm giảm số khả dụng.',
                    ),
                    const SizedBox(height: 12),
                    if (row.currentQuantity == null)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Không còn dữ liệu so sánh'),
                        ),
                      )
                    else
                      ResponsiveColumns(
                        minColumnWidth: 240,
                        maxColumns: 4,
                        children: [
                          metric('Tồn vật lý', row.currentQuantity!, row.unit),
                          metric('Đang giữ', row.reservedQuantity!, row.unit),
                          metric('Khả dụng', row.availableQuantity!, row.unit),
                          metric(
                            'Ngưỡng hiện tại',
                            row.currentMinQuantity!,
                            row.unit,
                          ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    Text(
                      'Lịch sử đợt cảnh báo',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Phát: ${alertMoment(row.triggeredAt)}'),
                    if (row.acknowledgedAt != null) ...[
                      Text('Đã xem: ${alertMoment(row.acknowledgedAt!)}'),
                      SelectableText('Người xác nhận: ${row.acknowledgedBy}'),
                    ],
                    if (row.resolvedAt != null) ...[
                      Text('Kết thúc: ${alertMoment(row.resolvedAt!)}'),
                      Text('Lý do: ${row.resolutionReason!.label}'),
                    ],
                    if (row.acknowledgedAt == null)
                      const Text('Chưa có xác nhận đã xem.'),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => context.go(
                            stockHistoryLocation(
                              warehouseId: row.warehouseId,
                              ingredientId: row.ingredientId,
                            ),
                          ),
                          icon: const Icon(Icons.history),
                          label: const Text('Lịch sử giao dịch'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
