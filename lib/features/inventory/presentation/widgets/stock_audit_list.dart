import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/stock_audit.dart';
import 'inventory_widgets.dart';
import 'stock_audit_widgets.dart';
import 'stock_widgets.dart';

class StockAuditList extends ConsumerWidget {
  const StockAuditList({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canViewStockAudits(session)) {
      return const Text('Bạn chưa có quyền hoặc tính năng kiểm kê kho.');
    }
    final c = ref.watch(stockAuditListProvider), q = c.query;
    final create = c.canManage ? ref.watch(stockAuditCreateProvider) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (create != null)
              FilledButton.icon(
                onPressed: create.busy
                    ? null
                    : () {
                        if (create.result != null) create.begin();
                        context.go('/app/inventory/audits/new');
                      },
                icon: const Icon(Icons.add),
                label: Text(
                  create.uncertain
                      ? 'Đối chiếu yêu cầu tạo'
                      : create.dirty && create.result == null
                      ? 'Tiếp tục phiên đang soạn'
                      : 'Tạo kiểm kê',
                ),
              ),
            IconButton(
              tooltip: 'Tải lại kiểm kê',
              onPressed: c.loading ? null : c.load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Kiểm kê toàn bộ nguyên liệu được theo dõi tại thời điểm bắt đầu. Nên thực hiện cuối ca hoặc lúc ít giao dịch.',
        ),
        const SizedBox(height: 16),
        StockFilterLayout(
          identity: ('audits', c),
          search: TextFormField(
            key: ValueKey(('audit-search', c)),
            initialValue: q.q,
            maxLength: 100,
            decoration: inventoryField(
              'Tìm mã hoặc ghi chú kiểm kê',
            ).copyWith(prefixIcon: const Icon(Icons.search), counterText: ''),
            onChanged: c.search,
          ),
          children: [
            StockSelect(
              label: 'Trạng thái kiểm kê',
              value: q.status?.code ?? 'all',
              items: {
                'all': 'Tất cả trạng thái',
                for (final s in StockAuditStatus.values) s.code: s.label,
              },
              changed: (v) => c.filter(
                q.copyWith(
                  status: () => StockAuditStatus.values
                      .where((s) => s.code == v)
                      .firstOrNull,
                ),
              ),
            ),
            StockSelect(
              label: 'Sắp xếp',
              value: q.sortBy,
              items: const {
                'createdAt': 'Ngày tạo',
                'startedAt': 'Bắt đầu',
                'updatedAt': 'Cập nhật',
                'auditCode': 'Mã kiểm kê',
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
                final value = await chooseStockAuditWarehouse(context, ref);
                if (context.mounted && value != null && c.canView) {
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
            InventoryInstantDateFilter(
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
            padding: EdgeInsets.all(24),
            child: Text('Chưa có phiên kiểm kê phù hợp.'),
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
                    dataRowMinHeight: 88,
                    dataRowMaxHeight: 120,
                    columns: const [
                      DataColumn(label: Text('Phiên kiểm kê')),
                      DataColumn(label: Text('Kho')),
                      DataColumn(label: Text('Trạng thái')),
                      DataColumn(label: Text('Tiến độ')),
                      DataColumn(label: Text('Ngày tạo')),
                      DataColumn(label: Text('Thao tác')),
                    ],
                    rows: [
                      for (final row in c.rows)
                        DataRow(
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 230,
                                child: Tooltip(
                                  message:
                                      '${row.auditCode}\n${row.note ?? ''}',
                                  child: Text(
                                    '${row.auditCode}\n${row.note ?? ''}',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
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
                            DataCell(StockAuditStatusBadge(row.status)),
                            DataCell(
                              Text(
                                '${row.countedItemCount}/${row.itemCount} đã đếm\n${row.changedItemCount} dòng chênh lệch',
                              ),
                            ),
                            DataCell(Text(formatLocalDate(row.createdAt))),
                            DataCell(
                              TextButton(
                                onPressed: () =>
                                    context.go(stockAuditLocation(row.id)),
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
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.auditCode,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          StockAuditStatusBadge(row.status),
                          const SizedBox(height: 12),
                          Text('${row.warehouseName} · ${row.warehouseCode}'),
                          Text(
                            'Đã đếm ${row.countedItemCount}/${row.itemCount} · ${row.changedItemCount} dòng chênh lệch',
                          ),
                          Text('Tạo: ${formatLocalDate(row.createdAt)}'),
                          if (row.note != null)
                            Text(
                              row.note!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          TextButton(
                            onPressed: () =>
                                context.go(stockAuditLocation(row.id)),
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
