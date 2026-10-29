import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../screens/stock_document_detail_screen.dart';
import '../../../../app/providers.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../domain/entities/stock_document.dart';
import 'inventory_widgets.dart';
import 'stock_widgets.dart';
import 'warehouse_picker.dart';

class StockDocumentList extends ConsumerWidget {
  const StockDocumentList({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(stockDocumentListProvider),
        q = c.query,
        create = ref.watch(stockDocumentCreateProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in create.allowedTypes)
              FilledButton.icon(
                onPressed: create.busy || create.uncertain
                    ? null
                    : () async {
                        if (create.dirty &&
                            create.result == null &&
                            !await confirmStockAction(
                              context,
                              ref,
                              permission: type.permission,
                              title: 'Bắt đầu phiếu khác?',
                              message:
                                  'Bản đang soạn chưa lưu sẽ được bỏ. Có thể quay lại để tiếp tục phiếu hiện tại.',
                              confirm: 'Tạo phiếu khác',
                            )) {
                          return;
                        }
                        if (!context.mounted || !create.current) return;
                        create.begin(type);
                        context.go('/app/inventory/stock-documents/new');
                      },
                icon: const Icon(Icons.add),
                label: Text('Tạo phiếu ${type.label.toLowerCase()}'),
              ),
            if (create.dirty && !create.uncertain && create.result == null)
              OutlinedButton.icon(
                onPressed: () =>
                    context.go('/app/inventory/stock-documents/new'),
                icon: const Icon(Icons.edit_note),
                label: const Text('Tiếp tục phiếu đang soạn'),
              ),
            if (create.uncertain)
              OutlinedButton.icon(
                onPressed: () =>
                    context.go('/app/inventory/stock-documents/new'),
                icon: const Icon(Icons.pending_actions),
                label: const Text('Khôi phục yêu cầu chưa xác minh'),
              ),
            IconButton(
              tooltip: 'Tải lại chứng từ',
              onPressed: c.loading ? null : c.load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 16),
        StockFilterLayout(
          identity: c,
          search: TextFormField(
            key: ValueKey(('document-search', c)),
            initialValue: q.q,
            maxLength: 100,
            decoration: inventoryField(
              'Tìm mã hoặc ghi chú',
            ).copyWith(prefixIcon: const Icon(Icons.search), counterText: ''),
            onChanged: c.search,
          ),
          children: [
            StockSelect(
              label: 'Loại phiếu',
              value: q.type?.code ?? 'all',
              items: {
                'all': 'Tất cả loại',
                for (final v in StockDocumentType.values) v.code: v.label,
              },
              changed: (v) => c.filter(
                q.copyWith(
                  type: () => StockDocumentType.values
                      .where((t) => t.code == v)
                      .firstOrNull,
                ),
              ),
            ),
            StockSelect(
              label: 'Trạng thái phiếu',
              value: q.status?.code ?? 'all',
              items: {
                'all': 'Tất cả trạng thái',
                for (final v in StockDocumentStatus.values) v.code: v.label,
              },
              changed: (v) => c.filter(
                q.copyWith(
                  status: () => StockDocumentStatus.values
                      .where((t) => t.code == v)
                      .firstOrNull,
                ),
              ),
            ),
            StockSelect(
              label: 'Sắp xếp',
              value: q.sortBy,
              items: const {
                'createdAt': 'Ngày tạo',
                'updatedAt': 'Cập nhật',
                'documentCode': 'Mã phiếu',
                'documentType': 'Loại phiếu',
                'status': 'Trạng thái',
                'totalCost': 'Tổng giá trị',
              },
              changed: (v) => c.filter(q.copyWith(sortBy: v)),
            ),
            StockSelect(
              label: 'Thứ tự',
              value: q.direction,
              items: const {'desc': 'Mới/lớn trước', 'asc': 'Cũ/nhỏ trước'},
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
              onPressed: () async {
                final value = await chooseInventoryWarehouse(context, ref);
                if (context.mounted && value != null && c.current) {
                  c.filter(q.copyWith(warehouseId: () => value.id));
                }
              },
              icon: const Icon(Icons.warehouse_outlined),
              label: Text(
                q.warehouseId == null ? 'Tất cả kho' : 'Kho: ${q.warehouseId}',
              ),
            ),
            if (q.warehouseId != null)
              IconButton(
                tooltip: 'Bỏ lọc kho',
                onPressed: () => c.filter(q.copyWith(warehouseId: () => null)),
                icon: const Icon(Icons.close),
              ),
            StockDateFilter(
              range: q.dates,
              changed: (v) => c.filter(q.copyWith(dates: () => v)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (c.loading) const LinearProgressIndicator(),
        InventoryFailurePanel(
          failure: c.failure,
          retry: c.loading ? null : c.load,
        ),
        if (c.failure != null && c.hasLoaded)
          const Text('Đang giữ kết quả lần tải trước.'),
        if (c.hasLoaded && c.rows.isEmpty && c.failure == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Chưa có chứng từ phù hợp.'),
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
                      DataColumn(label: Text('Chứng từ')),
                      DataColumn(label: Text('Kho')),
                      DataColumn(label: Text('Trạng thái')),
                      DataColumn(label: Text('Số dòng')),
                      DataColumn(label: Text('Tổng giá trị')),
                      DataColumn(label: Text('Ngày tạo')),
                      DataColumn(label: Text('Thao tác')),
                    ],
                    rows: [
                      for (final row in c.rows)
                        DataRow(
                          key: ValueKey('stock-document-${row.id}'),
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 220,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      row.documentCode,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(row.type.label),
                                  ],
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 180,
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
                            DataCell(StockStatusBadge(row.status)),
                            DataCell(Text('${row.lineCount}')),
                            DataCell(Text(stockDisplay(row.totalCost))),
                            DataCell(Text(stockDay(row.createdAt))),
                            DataCell(
                              TextButton(
                                onPressed: () => showStockDocumentDetailOverlay(
                                  context,
                                  ref,
                                  documentId: row.id,
                                ),
                                child: const Text('Chi tiết'),
                              ),
                            ),
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
                    key: ValueKey('stock-document-${row.id}'),
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.documentCode,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              InventoryBadge(row.type.label),
                              StockStatusBadge(row.status),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text('${row.warehouseName} · ${row.warehouseCode}'),
                          Text(
                            '${row.lineCount} dòng · Giá trị: ${stockDisplay(row.totalCost)}',
                          ),
                          Text('Tạo: ${formatLocalDate(row.createdAt)}'),
                          if (row.note != null)
                            Text(
                              row.note!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => showStockDocumentDetailOverlay(
                              context,
                              ref,
                              documentId: row.id,
                            ),
                            child: const Text('Chi tiết'),
                          ),
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
