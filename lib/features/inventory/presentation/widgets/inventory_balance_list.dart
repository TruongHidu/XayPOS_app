import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/ui/widgets/endless_list_footer.dart';
import '../../../../app/providers.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/inventory_quantity.dart';
import 'inventory_widgets.dart';
import 'inventory_threshold_dialog.dart';

class InventoryBalanceList extends ConsumerWidget {
  const InventoryBalanceList({
    super.key,
    required this.target,
    this.warehouseActive,
  });
  final BalanceListTarget target;
  final bool? warehouseActive;
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    InventoryBalance row,
    bool edit,
  ) async {
    final result = await showInventoryDialog<bool>(
      context,
      ref,
      permission: edit ? 'INVENTORY_THRESHOLD_UPDATE' : 'INVENTORY_VIEW',
      child: InventoryThresholdDialog(
        warehouseId: row.warehouseId,
        ingredientId: row.ingredientId,
        edit: edit,
      ),
    );
    if (context.mounted && result == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã cập nhật ngưỡng tồn.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(inventoryBalancesProvider(target)), q = c.query;
    Widget badges(InventoryBalance row) => Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (row.lowStock) const InventoryBadge('Tồn thấp', warning: true),
        if (row.minQuantity == InventoryQuantity.zero)
          const InventoryBadge('Đã tắt cảnh báo'),
        if (!row.lowStock && row.minQuantity != InventoryQuantity.zero)
          const InventoryBadge('Trong ngưỡng', positive: true),
        if (!row.configured) const InventoryBadge('Chưa cấu hình'),
        if (!row.ingredientActive)
          const InventoryBadge('Nguyên liệu ngừng hoạt động'),
      ],
    );
    Widget actions(InventoryBalance row) => Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        TextButton(
          onPressed: () => _open(context, ref, row, false),
          child: const Text('Chi tiết'),
        ),
        if (c.can('INVENTORY_THRESHOLD_UPDATE'))
          OutlinedButton(
            onPressed: warehouseActive == false
                ? null
                : () => _open(context, ref, row, true),
            child: const Text('Sửa ngưỡng'),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (warehouseActive == false)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'Kho đã ngừng hoạt động. Bạn vẫn có thể xem số dư tồn.',
            ),
          ),
        InventoryFilters(
          identity: c,
          listenable: c,
          search: q.q,
          onSearch: c.search,
          active: () => c.query.ingredientActive,
          onActive: (v) => c.filter(active: v),
          sortBy: () => c.query.sortBy,
          direction: () => c.query.direction,
          sorts: const {
            'ingredientName': 'Tên nguyên liệu',
            'sku': 'SKU',
            'quantity': 'Số lượng',
            'minQuantity': 'Ngưỡng',
            'updatedAt': 'Cập nhật',
          },
          onSort: (v) => c.filter(active: c.query.ingredientActive, sortBy: v),
          onDirection: (v) =>
              c.filter(active: c.query.ingredientActive, direction: v),
        ),
        const SizedBox(height: 16),
        if (c.loading) const LinearProgressIndicator(),
        InventoryFailurePanel(
          failure: c.failure,
          retry: c.loading ? null : c.load,
        ),
        if (c.failure != null && c.hasLoaded)
          const Text(
            'Đang giữ dữ liệu lần tải trước. Tải lại để kiểm tra số dư mới nhất.',
          ),
        if (c.hasLoaded && c.rows.isEmpty && c.failure == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              target.lowStock
                  ? 'Không có dòng tồn thấp phù hợp.'
                  : 'Chưa có nguyên liệu phù hợp đang theo dõi tồn trong kho này.',
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            if (constraints.maxWidth >= 1100 && scale <= 1.3) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    columnSpacing: 20,
                    dataRowMinHeight: 90,
                    dataRowMaxHeight: 112,
                    headingRowColor: WidgetStatePropertyAll(
                      Theme.of(context).colorScheme.surfaceContainerLow,
                    ),
                    columns: [
                      const DataColumn(label: Text('Nguyên liệu')),
                      if (target.lowStock) const DataColumn(label: Text('Kho')),
                      const DataColumn(label: Text('Trong kho'), numeric: true),
                      const DataColumn(label: Text('Đang giữ'), numeric: true),
                      const DataColumn(
                        label: Text('Có thể dùng'),
                        numeric: true,
                      ),
                      const DataColumn(label: Text('Ngưỡng'), numeric: true),
                      const DataColumn(label: Text('Trạng thái')),
                      const DataColumn(label: Text('Thao tác')),
                    ],
                    rows: [
                      for (final row in c.rows)
                        DataRow(
                          key: ValueKey('balance-${row.key}'),
                          color: row.lowStock
                              ? const WidgetStatePropertyAll(Color(0xFFFFFAF2))
                              : null,
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 210,
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
                                          fontWeight: FontWeight.w600,
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
                            if (target.lowStock)
                              DataCell(Text(row.warehouseCode)),
                            DataCell(
                              Text(inventoryAmount(row.quantity, row.baseUnit)),
                            ),
                            DataCell(
                              Text(
                                inventoryAmount(
                                  row.reservedQuantity,
                                  row.baseUnit,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                inventoryAmount(
                                  row.availableQuantity,
                                  row.baseUnit,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                inventoryAmount(row.minQuantity, row.baseUnit),
                              ),
                            ),
                            DataCell(SizedBox(width: 220, child: badges(row))),
                            DataCell(SizedBox(width: 240, child: actions(row))),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            }
            return ResponsiveColumns(
              minColumnWidth: 330 * scale.clamp(1, 1.5),
              maxColumns: 3,
              spacing: 12,
              children: [
                for (final row in c.rows)
                  _BalanceCard(
                    key: ValueKey('balance-${row.key}'),
                    row: row,
                    showWarehouse: target.lowStock,
                    badges: badges(row),
                    actions: actions(row),
                    onOpen: () => _open(context, ref, row, false),
                  ),
              ],
            );
          },
        ),
        if (c.hasLoaded && c.rows.isNotEmpty)
          EndlessListFooter(
            hasMore: c.hasMore,
            failureMessage: c.endless.failure?.message,
            endLabel: 'Đã hiển thị tất cả ${c.totalElements} nguyên liệu',
            onLoadMore: c.loadMore,
          ),
      ],
    );
  }
}

/// What a kitchen needs at a glance: how much can still be used, and how close
/// that is to the alert threshold. Details stay in the threshold dialog.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    super.key,
    required this.row,
    required this.showWarehouse,
    required this.badges,
    required this.actions,
    required this.onOpen,
  });

  final InventoryBalance row;
  final bool showWarehouse;
  final Widget badges, actions;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final tracked = row.minQuantity != InventoryQuantity.zero;
    final level = row.lowStock
        ? const Color(0xFFB45309)
        : const Color(0xFF0F766E);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: row.lowStock ? const Color(0xFFFFFAF2) : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: row.lowStock
              ? const Color(0xFFFDE68A)
              : colors.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                row.ingredientName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showWarehouse)
                Text('Kho: ${row.warehouseCode}', style: muted),
              const SizedBox(height: 10),
              Text('Có thể dùng', style: muted),
              Text(
                inventoryAmount(row.availableQuantity, row.baseUnit),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tracked ? level : null,
                ),
              ),
              if (tracked) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    // Full at twice the threshold, half-way at the threshold.
                    value:
                        (row.availableQuantity.scaled /
                                (row.minQuantity.scaled * 2))
                            .clamp(0.0, 1.0),
                    minHeight: 6,
                    color: level,
                    backgroundColor: level.withValues(alpha: 0.15),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Cảnh báo khi dưới ${inventoryAmount(row.minQuantity, row.baseUnit)}',
                  style: muted,
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Trong kho ${inventoryAmount(row.quantity, row.baseUnit)} · Đang giữ ${inventoryAmount(row.reservedQuantity, row.baseUnit)}',
                style: muted,
              ),
              const SizedBox(height: 10),
              badges,
              const SizedBox(height: 4),
              actions,
            ],
          ),
        ),
      ),
    );
  }
}
