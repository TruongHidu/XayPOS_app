import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../screens/stock_document_detail_screen.dart';
import '../../../../app/providers.dart';
import '../../../../core/ui/widgets/create_speed_dial_fab.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../../../core/ui/widgets/endless_list_footer.dart';
import '../../../../core/ui/widgets/list_states.dart';
import '../../domain/entities/stock_document.dart';
import '../../domain/entities/stock_queries.dart';
import 'inventory_widgets.dart';
import 'stock_widgets.dart';
import 'warehouse_picker.dart';

class StockDocumentList extends ConsumerWidget {
  const StockDocumentList({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(stockDocumentListProvider), q = c.query;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StockFilterLayout(
          listenable: c,
          title: 'Bộ lọc chứng từ',
          onRefresh: c.load,
          activeCount: () => [
            c.query.type,
            c.query.status,
            c.query.warehouseId,
            c.query.dates,
          ].where((value) => value != null).length,
          onClear: () => c.filter(StockDocumentQuery(q: c.query.q)),
          search: TextFormField(
            key: ValueKey(('document-search', c)),
            initialValue: q.q,
            maxLength: 100,
            decoration: inventoryField(
              'Tìm mã hoặc ghi chú',
            ).copyWith(prefixIcon: const Icon(Icons.search), counterText: ''),
            onChanged: c.search,
          ),
          filters: () {
            final q = c.query;
            return [
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final value = await chooseInventoryWarehouse(
                        context,
                        ref,
                      );
                      if (context.mounted && value != null && c.current) {
                        c.filter(q.copyWith(warehouseId: () => value.id));
                      }
                    },
                    icon: const Icon(Icons.warehouse_outlined),
                    label: Text(
                      q.warehouseId == null
                          ? 'Tất cả kho'
                          : 'Kho: ${q.warehouseId}',
                    ),
                  ),
                  if (q.warehouseId != null)
                    IconButton(
                      tooltip: 'Bỏ lọc kho',
                      onPressed: () =>
                          c.filter(q.copyWith(warehouseId: () => null)),
                      icon: const Icon(Icons.close),
                    ),
                  StockDateFilter(
                    range: q.dates,
                    changed: (v) => c.filter(q.copyWith(dates: () => v)),
                  ),
                ],
              ),
            ];
          },
        ),
        const SizedBox(height: 16),
        LoadingStrip(loading: c.loading),
        InventoryFailurePanel(
          failure: c.failure,
          retry: c.loading ? null : c.load,
        ),
        if (c.failure != null && c.hasLoaded)
          const Text('Đang giữ kết quả lần tải trước.'),
        if (c.hasLoaded && c.rows.isEmpty && c.failure == null)
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            message: 'Chưa có chứng từ phù hợp.',
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
        if (c.hasLoaded && c.rows.isNotEmpty)
          EndlessListFooter(
            hasMore: c.hasMore,
            failureMessage: c.endless.failure?.message,
            endLabel: 'Đã hiển thị tất cả ${c.totalElements} chứng từ',
            onLoadMore: c.loadMore,
          ),
      ],
    );
  }
}

/// Floating add button of Chứng từ kho: create a receipt, issue or adjustment,
/// or return to the draft / unverified request kept by the create form.
class StockDocumentCreateFab extends ConsumerWidget {
  const StockDocumentCreateFab({super.key});

  static const _newDocument = '/app/inventory/stock-documents/new';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final create = ref.watch(stockDocumentCreateProvider);
    if (create.busy) return const SizedBox.shrink();
    final List<SpeedDialOption> options;
    if (create.uncertain) {
      // A pending request must be verified before any other document starts.
      options = [
        SpeedDialOption(
          label: 'Khôi phục yêu cầu chưa xác minh',
          icon: Icons.pending_actions,
          onSelected: (context) async {
            await context.push(_newDocument);
          },
        ),
      ];
    } else {
      options = [
        for (final type in create.allowedTypes)
          SpeedDialOption(
            label: 'Tạo phiếu ${type.label.toLowerCase()}',
            icon: switch (type) {
              StockDocumentType.receipt => Icons.move_to_inbox_outlined,
              StockDocumentType.issue => Icons.outbox_outlined,
              _ => Icons.tune,
            },
            onSelected: (context) async {
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
              await context.push(_newDocument);
            },
          ),
        if (create.dirty && create.result == null)
          SpeedDialOption(
            label: 'Tiếp tục phiếu đang soạn',
            icon: Icons.edit_note,
            onSelected: (context) async {
              await context.push(_newDocument);
            },
          ),
      ];
    }
    return CreateSpeedDialFab(
      tooltip: 'Tạo chứng từ',
      directWhenSingle: false,
      options: options,
    );
  }
}
