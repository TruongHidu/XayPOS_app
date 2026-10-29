import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/inventory_alert.dart';
import '../../domain/entities/inventory_entities.dart';
import 'inventory_alert_widgets.dart';
import 'inventory_widgets.dart';
import 'stock_widgets.dart';
import 'warehouse_picker.dart';
import 'inventory_alert_sync_status.dart';

/// Embedded in the inventory workspace. Its provider is created only while the
/// tab is mounted; alert rows already contain all metadata, without detail GETs.
class InventoryAlertList extends ConsumerStatefulWidget {
  const InventoryAlertList({super.key});
  @override
  ConsumerState<InventoryAlertList> createState() => _InventoryAlertListState();
}

class _InventoryAlertListState extends ConsumerState<InventoryAlertList> {
  Warehouse? _warehouse;
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canViewInventoryAlerts(session)) {
      return const Text(
        'Bạn cần quyền xem kho và tính năng cảnh báo tồn thấp.',
      );
    }
    final c = ref.watch(inventoryAlertListProvider), q = c.query;
    Widget open(InventoryAlert row) => OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: () => context.go(inventoryAlertLocation(row.id)),
      icon: const Icon(Icons.visibility_outlined),
      label: const Text('Chi tiết'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InventoryAlertSyncStatus(),
        const Text(
          'Danh sách các lần nguyên liệu chạm ngưỡng tồn thấp, kể cả đã xử lý. Đánh dấu “Đã xem” không bổ sung hàng; mở “Tồn thấp hiện tại” để xem hàng đang thiếu.',
        ),
        const SizedBox(height: 16),
        StockFilterLayout(
          identity: ('alerts', c),
          search: TextFormField(
            key: ValueKey(('alert-search', c)),
            initialValue: q.q,
            maxLength: 100,
            onChanged: c.search,
            decoration: inventoryField(
              'Tìm cảnh báo',
              hint: 'Tên hoặc SKU tại thời điểm cảnh báo',
            ).copyWith(prefixIcon: const Icon(Icons.search), counterText: ''),
          ),
          children: [
            StockSelect(
              label: 'Trạng thái cảnh báo',
              value: q.status?.code ?? 'all',
              items: {
                'all': 'Tất cả',
                for (final s in InventoryAlertStatus.values) s.code: s.label,
              },
              changed: (v) => c.filter(
                q.copyWith(
                  status: () => InventoryAlertStatus.values
                      .where((s) => s.code == v)
                      .firstOrNull,
                ),
              ),
            ),
            StockSelect(
              label: 'Sắp xếp',
              value: q.sortBy,
              items: const {
                'triggeredAt': 'Thời điểm phát',
                'updatedAt': 'Cập nhật gần nhất',
              },
              changed: (v) => c.filter(q.copyWith(sortBy: v)),
            ),
            StockSelect(
              label: 'Thứ tự',
              value: q.direction,
              items: const {'desc': 'Mới nhất trước', 'asc': 'Cũ nhất trước'},
              changed: (v) => c.filter(q.copyWith(direction: v)),
            ),
            StockSelect(
              label: 'Mỗi trang',
              value: '${q.size}',
              items: const {
                '20': '20 dòng',
                '50': '50 dòng',
                '100': '100 dòng',
              },
              changed: (v) => c.filter(q.copyWith(size: int.parse(v))),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.warehouse_outlined),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              label: Text(
                q.warehouseId == null
                    ? 'Tất cả kho'
                    : _warehouse?.name ?? q.warehouseId!,
              ),
              onPressed: () async {
                final scope = ref.read(inventoryScopeProvider);
                final result = await showDialog<Warehouse>(
                  context: context,
                  builder: (_) => InventoryAlertScopeGuard(
                    scope: scope,
                    child: const WarehousePickerDialog(),
                  ),
                );
                if (mounted && c.allowed && result != null) {
                  setState(() => _warehouse = result);
                  c.filter(c.query.copyWith(warehouseId: () => result.id));
                }
              },
            ),
            if (q.warehouseId != null)
              IconButton(
                tooltip: 'Bỏ lọc kho',
                onPressed: () {
                  setState(() => _warehouse = null);
                  c.filter(q.copyWith(warehouseId: () => null));
                },
                icon: const Icon(Icons.close),
              ),
            InventoryAlertDateFilter(
              range: q.dates,
              changed: (v) => c.filter(q.copyWith(dates: () => v)),
            ),
            OutlinedButton.icon(
              onPressed: c.loading ? null : c.load,
              icon: const Icon(Icons.refresh),
              label: const Text('Tải lại cảnh báo'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Đang lọc: ${q.status?.label ?? 'Tất cả trạng thái'}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (c.loading)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        InventoryFailurePanel(
          failure: c.failure,
          retry: c.loading ? null : c.load,
        ),
        if (c.failure != null && c.hasLoaded)
          const Text('Đang hiển thị kết quả lần tải trước.'),
        if (c.hasLoaded && c.rows.isEmpty && c.failure == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text('Không có đợt cảnh báo phù hợp với bộ lọc.'),
          ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            if (box.maxWidth >= 1100 && scale <= 1.3) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: box.maxWidth),
                  child: DataTable(
                    columnSpacing: 20,
                    dataRowMinHeight: 100,
                    dataRowMaxHeight: 120,
                    columns: const [
                      DataColumn(label: Text('Nguyên liệu / SKU')),
                      DataColumn(label: Text('Kho')),
                      DataColumn(label: Text('Trạng thái')),
                      DataColumn(label: Text('Lúc phát / Ngưỡng')),
                      DataColumn(label: Text('Thời điểm phát')),
                      DataColumn(label: Text('Thao tác')),
                    ],
                    rows: [
                      for (final row in c.rows)
                        DataRow(
                          key: ValueKey('alert-${row.id}'),
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 200,
                                child: Tooltip(
                                  message: row.ingredientName,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row.ingredientName,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        row.ingredientSku ?? 'Chưa có SKU',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 160,
                                child: Tooltip(
                                  message: row.warehouseName,
                                  child: Text(
                                    '${row.warehouseName}\n${row.warehouseCode}',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(InventoryAlertBadge(row.status)),
                            DataCell(
                              Text(
                                '${inventoryAmount(row.quantityAtTrigger, row.unit)}\nNgưỡng ${inventoryAmount(row.thresholdQuantity, row.unit)}',
                              ),
                            ),
                            DataCell(Text(alertMoment(row.triggeredAt))),
                            DataCell(open(row)),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            }
            return ResponsiveColumns(
              minColumnWidth: 340 * scale.clamp(1, 1.5),
              maxColumns: 3,
              spacing: 12,
              children: [
                for (final row in c.rows)
                  Card(
                    key: ValueKey('alert-${row.id}'),
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            row.ingredientName,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(row.ingredientSku ?? 'Chưa có SKU'),
                          const SizedBox(height: 8),
                          Wrap(children: [InventoryAlertBadge(row.status)]),
                          const SizedBox(height: 12),
                          Text(
                            'Kho: ${row.warehouseName} · ${row.warehouseCode}',
                          ),
                          Text(
                            'Tồn lúc phát: ${inventoryAmount(row.quantityAtTrigger, row.unit)}',
                          ),
                          Text(
                            'Ngưỡng lúc phát: ${inventoryAmount(row.thresholdQuantity, row.unit)}',
                          ),
                          Text('Phát: ${alertMoment(row.triggeredAt)}'),
                          if (row.resolutionReason != null)
                            Text(row.resolutionReason!.label),
                          const SizedBox(height: 12),
                          open(row),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (c.hasLoaded)
          InventoryPaging(
            page: q.page,
            totalPages: c.totalPages,
            totalElements: c.totalElements,
            loading: c.loading,
            changed: c.page,
          ),
      ],
    );
  }
}
