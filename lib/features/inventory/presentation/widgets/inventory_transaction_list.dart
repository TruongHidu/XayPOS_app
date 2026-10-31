import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../../../core/ui/widgets/endless_list_footer.dart';
import '../../../../core/ui/widgets/filter_panel_button.dart';
import '../../domain/entities/stock_document.dart';
import '../../domain/entities/stock_queries.dart';
import 'inventory_widgets.dart';
import 'stock_widgets.dart';
import 'stock_ingredient_picker.dart';
import 'warehouse_picker.dart';

class InventoryTransactionList extends ConsumerWidget {
  const InventoryTransactionList({
    super.key,
    this.target = const StockHistoryTarget(),
  });
  final StockHistoryTarget target;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(inventoryTransactionsProvider(target)), q = c.query;
    final canOpenOrder = AccessPolicy.canOrders(
      ref.watch(authControllerProvider).state.session,
      'ORDER_VIEW',
    );
    String price(InventoryTransaction row) =>
        row.unitCost == null ? 'Chưa định giá' : stockDisplay(row.unitCost!);
    String shortId(String id) => id.length > 16
        ? '${id.substring(0, 8)}…${id.substring(id.length - 6)}'
        : id;
    Widget origin(InventoryTransaction row) =>
        row.source == InventoryTransactionSource.stockDocument
        ? TextButton(
            onPressed: () => context.push(stockDetailLocation(row.documentId!)),
            child: Text(row.documentCode!),
          )
        : SizedBox(
            width: 240,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: 'Đơn: ${row.orderId}\nDòng món: ${row.orderItemId}',
                  child: Text(
                    'Đơn: ${shortId(row.orderId!)}\nDòng món: ${shortId(row.orderItemId!)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (canOpenOrder)
                  TextButton(
                    onPressed: () => context.push(
                      '/app/orders/${Uri.encodeComponent(row.orderId!)}',
                    ),
                    child: const Text('Xem đơn'),
                  ),
              ],
            ),
          );
    Widget change(InventoryTransaction row) => InventoryBadge(
      '${row.change.negative ? '' : '+'}${stockDisplay(row.change)} ${row.unit}',
      warning: row.change.negative,
      positive: !row.change.negative,
    );
    String name(String id, String fallback) => c.names[id] ?? fallback;
    int activeFilters() {
      final q = c.query;
      return [
        q.warehouseId != null,
        q.ingredientId != null,
        q.dates != null,
        q.source != null,
        q.type != null,
        q.direction != 'desc',
      ].where((active) => active).length;
    }

    final filtered =
        activeFilters() > 0 ||
        q.documentId != null ||
        q.orderId != null ||
        q.orderItemId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterPanelButton(
              listenable: c,
              title: 'Bộ lọc biến động',
              onRefresh: c.load,
              activeCount: activeFilters,
              onClear: () => c.filter(const InventoryTransactionQuery()),
              filters: () {
                final q = c.query;
                return [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final row = await chooseInventoryWarehouse(context, ref);
                      if (context.mounted && row != null && c.current) {
                        c.names[row.id] = '${row.name} · ${row.code}';
                        c.filter(
                          c.query.copyWith(
                            warehouseId: () => row.id,
                            ingredientId: () => null,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.warehouse_outlined),
                    label: Text(
                      q.warehouseId == null
                          ? 'Tất cả kho'
                          : 'Kho: ${name(q.warehouseId!, 'đã chọn')}',
                    ),
                  ),
                  Tooltip(
                    message: q.warehouseId == null
                        ? 'Chọn kho trước để lọc theo nguyên liệu'
                        : '',
                    child: OutlinedButton.icon(
                      onPressed: q.warehouseId == null
                          ? null
                          : () async {
                              // Viewing the ledger must not require a mutation or ingredient permission.
                              final row = await showInventoryDialog(
                                context,
                                ref,
                                child: StockIngredientPicker(
                                  warehouseId: q.warehouseId!,
                                  type: StockDocumentType.issue,
                                  excluded: const {},
                                ),
                              );
                              if (context.mounted && row != null && c.current) {
                                c.names[row.ingredientId] = row.ingredientName;
                                c.filter(
                                  c.query.copyWith(
                                    ingredientId: () => row.ingredientId,
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.grass_outlined),
                      label: Text(
                        q.ingredientId == null
                            ? 'Tất cả nguyên liệu'
                            : 'Nguyên liệu: ${name(q.ingredientId!, 'đã chọn')}',
                      ),
                    ),
                  ),
                  StockDateFilter(
                    range: q.dates,
                    changed: (v) => c.filter(c.query.copyWith(dates: () => v)),
                  ),
                  StockSelect(
                    label: 'Nguồn giao dịch',
                    value: q.source?.code ?? 'all',
                    items: {
                      'all': 'Tất cả nguồn',
                      for (final source in InventoryTransactionSource.values)
                        source.code: source.label,
                    },
                    changed: (value) => c.filter(
                      q.copyWith(
                        source: () => InventoryTransactionSource.values
                            .where((e) => e.code == value)
                            .firstOrNull,
                      ),
                    ),
                  ),
                  StockSelect(
                    label: 'Loại biến động',
                    value: q.type?.code ?? 'all',
                    items: {
                      'all': 'Tất cả biến động',
                      for (final v in InventoryTransactionType.values)
                        v.code: v.label,
                    },
                    changed: (v) => c.filter(
                      q.copyWith(
                        type: () => InventoryTransactionType.values
                            .where((t) => t.code == v)
                            .firstOrNull,
                      ),
                    ),
                  ),
                  StockSelect(
                    label: 'Thứ tự',
                    value: q.direction,
                    items: const {'desc': 'Mới trước', 'asc': 'Cũ trước'},
                    changed: (v) => c.filter(q.copyWith(direction: v)),
                  ),
                ];
              },
            ),
            IconButton(
              tooltip: 'Tải lại biến động',
              onPressed: c.loading ? null : c.load,
              icon: const Icon(Icons.refresh),
            ),
            if (q.warehouseId != null)
              InputChip(
                avatar: const Icon(Icons.warehouse_outlined, size: 18),
                label: Text('Kho: ${name(q.warehouseId!, 'đã chọn')}'),
                onDeleted: () => c.filter(
                  q.copyWith(warehouseId: () => null, ingredientId: () => null),
                ),
              ),
            if (q.ingredientId != null)
              InputChip(
                avatar: const Icon(Icons.grass_outlined, size: 18),
                label: Text('Nguyên liệu: ${name(q.ingredientId!, 'đã chọn')}'),
                onDeleted: () => c.filter(q.copyWith(ingredientId: () => null)),
              ),
            if (q.documentId != null)
              InputChip(
                avatar: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text('Phiếu: ${name(q.documentId!, 'đã chọn')}'),
                onDeleted: () => c.filter(q.copyWith(documentId: () => null)),
              ),
            if (q.orderId != null)
              Tooltip(
                message: q.orderId!,
                child: InputChip(
                  avatar: const Icon(Icons.receipt_outlined, size: 18),
                  label: Text('Đơn: ${shortId(q.orderId!)}'),
                  onDeleted: () => c.filter(
                    q.copyWith(orderId: () => null, orderItemId: () => null),
                  ),
                ),
              ),
            if (q.orderItemId != null)
              Tooltip(
                message: q.orderItemId!,
                child: InputChip(
                  label: Text('Dòng món: ${shortId(q.orderItemId!)}'),
                  onDeleted: () =>
                      c.filter(q.copyWith(orderItemId: () => null)),
                ),
              ),
            if (filtered)
              TextButton(
                onPressed: () => c.filter(const InventoryTransactionQuery()),
                child: const Text('Xóa bộ lọc'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (c.loading) const LinearProgressIndicator(),
        InventoryFailurePanel(
          failure: c.failure,
          retry: c.loading ? null : c.load,
        ),
        if (c.failure != null && c.hasLoaded)
          const Text('Đang hiển thị kết quả lần tải trước.'),
        if (c.hasLoaded && c.rows.isEmpty && c.failure == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              filtered
                  ? 'Không có biến động nào khớp bộ lọc. Thử bỏ bớt bộ lọc hoặc đổi khoảng ngày.'
                  : 'Chưa có biến động kho. Lịch sử sẽ xuất hiện sau khi xác nhận phiếu nhập/xuất hoặc khi món được chế biến.',
            ),
          ),
        LayoutBuilder(
          builder: (context, box) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            if (box.maxWidth >= 1100 && scale <= 1.3) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: box.maxWidth),
                  child: DataTable(
                    headingRowColor: WidgetStatePropertyAll(
                      Theme.of(context).colorScheme.surfaceContainerLow,
                    ),
                    dataRowMinHeight: 80,
                    dataRowMaxHeight: 112,
                    columns: const [
                      DataColumn(label: Text('Thời gian / Kho')),
                      DataColumn(label: Text('Nguyên liệu')),
                      DataColumn(label: Text('Loại')),
                      DataColumn(label: Text('Chênh lệch')),
                      DataColumn(label: Text('Tồn trước → sau')),
                      DataColumn(label: Text('Đơn giá')),
                      DataColumn(label: Text('Nguồn giao dịch')),
                    ],
                    rows: [
                      for (final row in c.rows)
                        DataRow(
                          key: ValueKey('stock-transaction-${row.id}'),
                          cells: [
                            DataCell(
                              Text(
                                '${formatLocalDate(row.createdAt)}\n${row.warehouseCode}',
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 220,
                                child: Text(
                                  '${row.ingredientName}\n${row.ingredientSku ?? 'Chưa có SKU'}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            DataCell(Text(row.type.label)),
                            DataCell(change(row)),
                            DataCell(
                              Text(
                                '${inventoryAmount(row.before, row.unit)} → ${inventoryAmount(row.after, row.unit)}',
                              ),
                            ),
                            DataCell(Text(price(row))),
                            DataCell(origin(row)),
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
                    key: ValueKey('stock-transaction-${row.id}'),
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.ingredientName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(row.ingredientSku ?? 'Chưa có SKU'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              InventoryBadge(row.type.label),
                              change(row),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text('Kho: ${row.warehouseCode}'),
                          Text(
                            'Trước: ${inventoryAmount(row.before, row.unit)}',
                          ),
                          Text('Sau: ${inventoryAmount(row.after, row.unit)}'),
                          Text('Đơn giá: ${price(row)}'),
                          Text('Nguồn: ${row.source.label}'),
                          Text(formatLocalDate(row.createdAt)),
                          Text('Người ghi nhận: ${row.createdBy}'),
                          const SizedBox(height: 8),
                          origin(row),
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
            endLabel: 'Đã hiển thị tất cả ${c.totalElements} biến động',
            onLoadMore: c.loadMore,
          ),
      ],
    );
  }
}
