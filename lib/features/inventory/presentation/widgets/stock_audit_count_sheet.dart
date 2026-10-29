import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/stock_audit.dart';
import '../controllers/stock_audit_detail_controller.dart';
import '../providers/stock_audit_providers.dart';
import 'inventory_widgets.dart';
import 'stock_widgets.dart';

class StockAuditCountSheet extends ConsumerWidget {
  const StockAuditCountSheet({super.key, required this.auditId});
  final String auditId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(stockAuditDetailProvider(auditId)), q = c.query;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Bảng số đếm', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Nhập đúng số lượng đếm được trên kệ, gồm cả hàng đang giữ cho đơn. Tên, đơn vị, tồn hệ thống và giá được lấy tại lúc bắt đầu kiểm kê.',
        ),
        const SizedBox(height: 16),
        StockFilterLayout(
          identity: ('audit-items', c),
          search: TextFormField(
            key: ValueKey(('audit-item-search', c)),
            initialValue: q.q,
            maxLength: 100,
            decoration: inventoryField(
              'Tìm nguyên liệu hoặc SKU trong phiên',
            ).copyWith(prefixIcon: const Icon(Icons.search), counterText: ''),
            onChanged: c.search,
          ),
          children: [
            StockSelect(
              label: 'Số đếm',
              value: q.counted?.toString() ?? 'all',
              items: const {
                'all': 'Tất cả',
                'true': 'Đã đếm',
                'false': 'Chưa đếm',
              },
              changed: (v) => c.filter(
                q.copyWith(counted: () => v == 'all' ? null : v == 'true'),
              ),
            ),
            StockSelect(
              label: 'Chênh lệch',
              value: q.differenceOnly.toString(),
              items: const {
                'false': 'Tất cả dòng',
                'true': 'Chỉ có chênh lệch',
              },
              changed: (v) => c.filter(q.copyWith(differenceOnly: v == 'true')),
            ),
            StockSelect(
              label: 'Sắp xếp',
              value: q.sortBy,
              items: const {
                'name': 'Tên nguyên liệu',
                'sku': 'SKU',
                'systemQuantity': 'Tồn lúc bắt đầu',
                'countedQuantity': 'Số đếm đã lưu',
                'differenceQuantity': 'Chênh lệch đã lưu',
              },
              changed: (v) => c.filter(q.copyWith(sortBy: v)),
            ),
            StockSelect(
              label: 'Thứ tự',
              value: q.direction,
              items: const {'asc': 'Tăng dần', 'desc': 'Giảm dần'},
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
        if (c.hasCountDrafts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InventoryBadge(
                '${c.dirtyCount} dòng chưa lưu · trên mọi trang',
                warning: true,
              ),
            ),
          ),
        if (c.itemsLoading) const LinearProgressIndicator(),
        InventoryFailurePanel(
          failure: c.itemFailure,
          retry: c.itemsLoading ? null : c.loadItems,
        ),
        if (c.itemsLoaded && c.rows.isEmpty && c.itemFailure == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('Không có nguyên liệu nào khớp bộ lọc.'),
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
                    dataRowMinHeight: 190,
                    dataRowMaxHeight: 260,
                    columns: const [
                      DataColumn(label: Text('Nguyên liệu / Đơn vị')),
                      DataColumn(label: Text('Tồn lúc bắt đầu')),
                      DataColumn(label: Text('Số đếm thực tế')),
                      DataColumn(label: Text('Chênh lệch')),
                      DataColumn(label: Text('Giá tham chiếu\nlúc bắt đầu')),
                      DataColumn(label: Text('Ghi chú')),
                    ],
                    rows: [
                      for (final row in c.rows)
                        DataRow(
                          key: ValueKey('audit-row-${row.id}'),
                          cells: [
                            DataCell(
                              SizedBox(
                                width: 220,
                                child: Tooltip(
                                  message: '${row.name}\n${row.sku ?? ''}',
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        row.name,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        '${row.sku ?? 'Chưa có SKU'} · ${row.unit}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                inventoryAmount(row.systemQuantity, row.unit),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 190,
                                child: _QuantityField(controller: c, row: row),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 160,
                                child: _Difference(controller: c, row: row),
                              ),
                            ),
                            DataCell(
                              Text(
                                '${stockDisplay(row.referenceUnitCostSnapshot)} / ${row.unit}',
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 220,
                                child: _NoteField(controller: c, row: row),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            }
            // One column on phones; tablet cards remain wide enough for touch input.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in c.rows)
                  Card(
                    key: ValueKey('audit-row-${row.id}'),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            row.name,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${row.sku ?? 'Chưa có SKU'} · Đơn vị: ${row.unit}',
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tồn lúc bắt đầu: ${inventoryAmount(row.systemQuantity, row.unit)}',
                          ),
                          const SizedBox(height: 12),
                          _QuantityField(controller: c, row: row),
                          const SizedBox(height: 8),
                          _Difference(controller: c, row: row),
                          const SizedBox(height: 12),
                          _NoteField(controller: c, row: row),
                          const SizedBox(height: 8),
                          Text(
                            'Giá tham chiếu lúc bắt đầu: ${stockDisplay(row.referenceUnitCostSnapshot)} / ${row.unit}',
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (c.itemsLoaded)
          InventoryPaging(
            page: q.page,
            totalPages: c.totalPages,
            totalElements: c.totalElements,
            loading: c.itemsLoading || c.busy,
            changed: c.page,
          ),
      ],
    );
  }
}

class _QuantityField extends StatelessWidget {
  const _QuantityField({required this.controller, required this.row});
  final StockAuditDetailController controller;
  final StockAuditItem row;
  @override
  Widget build(BuildContext context) {
    final draft = controller.draft(row.id);
    if (!controller.canManage ||
        controller.audit?.status != StockAuditStatus.counting) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.countedQuantity == null
                ? 'Chưa đếm'
                : inventoryAmount(row.countedQuantity!, row.unit),
          ),
          if (draft != null)
            const Text('Còn bản nhập chưa lưu trong phiên làm việc.'),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          key: ValueKey(('audit-count', row.id, controller.epoch(row.id))),
          initialValue:
              draft?.rawQuantity ??
              row.countedQuantity?.toString().replaceAll('.', ',') ??
              '',
          enabled: controller.editable,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: inventoryField(
            'Số đếm thực tế',
            hint: 'Chưa đếm',
            error: draft?.error,
          ).copyWith(suffixText: row.unit),
          onChanged: (v) => controller.edit(row, rawQuantity: v),
        ),
        const SizedBox(height: 6),
        Text(
          draft != null
              ? 'Đã nhập · chưa lưu'
              : row.countedQuantity == null
              ? 'Chưa đếm'
              : 'Đã lưu',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (draft != null)
          Text(
            'Đã lưu trên máy chủ: ${row.countedQuantity == null ? 'Chưa đếm' : inventoryAmount(row.countedQuantity!, row.unit)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (draft != null)
          TextButton(
            onPressed: controller.busy
                ? null
                : () => controller.restore(row.id),
            child: const Text('Khôi phục số đã lưu'),
          ),
      ],
    );
  }
}

class _NoteField extends StatelessWidget {
  const _NoteField({required this.controller, required this.row});
  final StockAuditDetailController controller;
  final StockAuditItem row;
  @override
  Widget build(BuildContext context) {
    if (!controller.canManage ||
        controller.audit?.status != StockAuditStatus.counting) {
      return Text(row.note ?? 'Không có ghi chú');
    }
    return TextFormField(
      key: ValueKey(('audit-count-note', row.id, controller.epoch(row.id))),
      initialValue: controller.draft(row.id)?.note ?? row.note ?? '',
      enabled: controller.editable,
      minLines: 1,
      maxLines: 3,
      maxLength: 1000,
      decoration: inventoryField('Ghi chú dòng').copyWith(counterText: ''),
      onChanged: (v) => controller.edit(row, note: v),
    );
  }
}

class _Difference extends StatelessWidget {
  const _Difference({required this.controller, required this.row});
  final StockAuditDetailController controller;
  final StockAuditItem row;
  @override
  Widget build(BuildContext context) {
    final draft = controller.draft(row.id);
    final quantity = draft == null ? row.countedQuantity : draft.quantity;
    if (quantity == null) {
      return const Text('Chênh lệch: chưa có số đếm hợp lệ');
    }
    final difference = StockAuditDifference.between(
      quantity,
      row.systemQuantity,
    );
    final text = difference.isZero
        ? 'Khớp hệ thống'
        : difference.negative
        ? 'Thiếu ${difference.toString().substring(1).replaceAll('.', ',')} ${row.unit}'
        : 'Thừa +${difference.toString().replaceAll('.', ',')} ${row.unit}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InventoryBadge(
          text,
          warning: !difference.isZero,
          positive: difference.isZero,
        ),
        if (draft != null)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Chênh lệch dự kiến · chưa lưu'),
          ),
      ],
    );
  }
}
