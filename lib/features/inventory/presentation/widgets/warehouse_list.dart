import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/ui/widgets/endless_list_footer.dart';
import '../../../../app/providers.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/inventory_entities.dart';
import '../controllers/inventory_events.dart';
import '../controllers/warehouse_list_controller.dart';
import 'inventory_widgets.dart';
import 'warehouse_form.dart';
import 'warehouse_action_dialog.dart';

class WarehouseList extends ConsumerWidget {
  const WarehouseList({super.key});
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    Warehouse row,
    String action,
  ) async {
    final permission = action == 'edit'
        ? 'WAREHOUSE_UPDATE'
        : action == 'delete'
        ? 'WAREHOUSE_DELETE'
        : const {'enable', 'disable', 'default'}.contains(action)
        ? 'WAREHOUSE_UPDATE'
        : 'INVENTORY_VIEW';
    final result = await showInventoryDialog<Object?>(
      context,
      ref,
      permission: permission,
      child: action == 'edit'
          ? WarehouseForm(id: row.id)
          : WarehouseActionDialog(
              id: row.id,
              action: switch (action) {
                'enable' => WarehouseAction.enable,
                'disable' => WarehouseAction.disable,
                'default' => WarehouseAction.makeDefault,
                'delete' => WarehouseAction.delete,
                _ => null,
              },
            ),
    );
    if (context.mounted && result != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã cập nhật kho.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(warehouseListProvider), q = c.query;
    Widget actions(Warehouse row) => PopupMenuButton<String>(
      tooltip: 'Thao tác kho ${row.name}',
      enabled: !c.events.pending(InventoryEvents.warehouseKey(row.id)),
      onSelected: (action) => _open(context, ref, row, action),
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'view', child: Text('Xem chi tiết')),
        if (c.can('WAREHOUSE_UPDATE')) ...[
          const PopupMenuItem(value: 'edit', child: Text('Sửa thông tin')),
          PopupMenuItem(
            value: row.active ? 'disable' : 'enable',
            enabled: !row.isDefault,
            child: Text(row.active ? 'Tắt kho' : 'Bật kho'),
          ),
          PopupMenuItem(
            value: 'default',
            enabled: row.active && !row.isDefault,
            child: const Text('Đặt mặc định'),
          ),
        ],
        if (c.can('WAREHOUSE_DELETE'))
          PopupMenuItem(
            value: 'delete',
            enabled: !row.isDefault,
            child: const Text('Xóa kho'),
          ),
      ],
    );
    Widget badges(Warehouse row) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        InventoryBadge(
          row.active ? 'Đang hoạt động' : 'Ngừng hoạt động',
          positive: row.active,
        ),
        if (row.isDefault) const InventoryBadge('Mặc định', positive: true),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InventoryFilters(
          identity: c,
          listenable: c,
          search: q.q,
          onSearch: c.search,
          active: () => c.query.active,
          warehouses: true,
          onActive: (v) => c.filter(active: v),
          sortBy: () => c.query.sortBy,
          direction: () => c.query.direction,
          sorts: const {
            'createdAt': 'Ngày tạo',
            'name': 'Tên kho',
            'code': 'Mã kho',
            'updatedAt': 'Cập nhật',
          },
          onSort: (v) => c.filter(active: c.query.active, sortBy: v),
          onDirection: (v) => c.filter(active: c.query.active, direction: v),
        ),
        const SizedBox(height: 16),
        if (c.loading) const LinearProgressIndicator(),
        InventoryFailurePanel(
          failure: c.failure,
          retry: c.loading ? null : c.load,
        ),
        if (c.failure != null && c.hasLoaded)
          const Text('Đang giữ dữ liệu lần tải trước. Tải lại để đối chiếu.'),
        if (c.hasLoaded && c.rows.isEmpty && c.failure == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'Chưa có kho phù hợp. Bạn có thể đổi bộ lọc hoặc thêm kho mới nếu được cấp quyền.',
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            if (constraints.maxWidth >= 1000 && scale <= 1.3) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    headingRowColor: WidgetStatePropertyAll(
                      Theme.of(context).colorScheme.surfaceContainerLow,
                    ),
                    columns: const [
                      DataColumn(label: Text('Mã kho')),
                      DataColumn(label: Text('Tên kho')),
                      DataColumn(label: Text('Trạng thái')),
                      DataColumn(label: Text('Thao tác')),
                    ],
                    dataRowMinHeight: 76,
                    dataRowMaxHeight: 110,
                    rows: [
                      for (final row in c.rows)
                        DataRow(
                          key: ValueKey('warehouse-${row.id}'),
                          cells: [
                            DataCell(Text(row.code)),
                            DataCell(
                              SizedBox(
                                width: 280,
                                child: Tooltip(
                                  message: row.name,
                                  child: Text(
                                    row.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(badges(row)),
                            DataCell(actions(row)),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            }
            return ResponsiveColumns(
              minColumnWidth: 300 * scale.clamp(1, 1.5),
              maxColumns: 3,
              spacing: 12,
              children: [
                for (final row in c.rows)
                  Card(
                    key: ValueKey('warehouse-${row.id}'),
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(row.code),
                                  ],
                                ),
                              ),
                              actions(row),
                            ],
                          ),
                          const SizedBox(height: 12),
                          badges(row),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: () => _open(context, ref, row, 'view'),
                            icon: const Icon(Icons.info_outline),
                            label: const Text('Xem chi tiết'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (c.hasLoaded && c.rows.isNotEmpty)
          EndlessListFooter(
            hasMore: c.hasMore,
            failureMessage: c.endless.failure?.message,
            endLabel: 'Đã hiển thị tất cả ${c.totalElements} kho',
            onLoadMore: c.loadMore,
          ),
      ],
    );
  }
}
