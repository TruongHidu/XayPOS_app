import 'package:flutter/material.dart';

import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/ingredient_query.dart';
import '../controllers/ingredient_controller.dart';
import 'menu_dialogs.dart';

class IngredientList extends StatefulWidget {
  const IngredientList({
    super.key,
    required this.controller,
    required this.canCreate,
    required this.canUpdate,
    required this.canDelete,
    required this.opening,
    required this.onAction,
  });

  final IngredientController controller;
  final bool canCreate, canUpdate, canDelete;
  final Set<String> opening;
  final Future<void> Function(Ingredient, String) onAction;

  @override
  State<IngredientList> createState() => _IngredientListState();
}

class _IngredientListState extends State<IngredientList> {
  int _searchReset = 0;
  IngredientController get controller => widget.controller;

  Widget _select(
    String label,
    String value,
    Map<String, String> choices,
    ValueChanged<String> changed,
  ) => DropdownButtonFormField<String>(
    key: ValueKey((label, value, _searchReset)),
    value: value,
    isExpanded: true,
    itemHeight: null,
    decoration: menuField(label),
    items: [
      for (final entry in choices.entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value)),
    ],
    onChanged: (value) {
      if (value != null) changed(value);
    },
  );

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final query = state.query;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: ValueKey(('ingredient-search', controller, _searchReset)),
            initialValue: query.q,
            maxLength: 100,
            decoration: menuField(
              'Tìm tên nguyên liệu hoặc SKU',
            ).copyWith(prefixIcon: const Icon(Icons.search)),
            onChanged: controller.search,
          ),
          const SizedBox(height: 12),
          ResponsiveColumns(
            minColumnWidth: 220 * textScale.clamp(1.0, double.infinity),
            maxColumns: 4,
            spacing: 12,
            children: [
              _select(
                'Trạng thái',
                query.active?.toString() ?? 'all',
                const {
                  'all': 'Tất cả trạng thái',
                  'true': 'Đang sử dụng',
                  'false': 'Ngừng sử dụng',
                },
                (v) => controller.setActiveFilter(_bool(v)),
              ),
              _select(
                'Theo dõi tồn kho',
                query.trackInventory?.toString() ?? 'all',
                const {
                  'all': 'Tất cả',
                  'true': 'Có theo dõi',
                  'false': 'Không theo dõi',
                },
                (v) => controller.setTrackInventoryFilter(_bool(v)),
              ),
              _select('Sắp xếp theo', query.sortBy, const {
                'createdAt': 'Ngày tạo',
                'updatedAt': 'Ngày cập nhật',
                'name': 'Tên nguyên liệu',
                'sku': 'SKU',
                'costPrice': 'Giá vốn',
              }, controller.setSort),
              _select(
                'Chiều sắp xếp',
                query.direction,
                const {'asc': 'Tăng dần', 'desc': 'Giảm dần'},
                (v) => controller.setSort(query.sortBy, direction: v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (query.hasFilters)
                TextButton.icon(
                  onPressed: () {
                    controller.setQuery(const IngredientQuery());
                    setState(() => _searchReset++);
                  },
                  icon: const Icon(Icons.filter_alt_off),
                  label: const Text('Xóa bộ lọc'),
                ),
              TextButton.icon(
                onPressed: state.loading ? null : controller.load,
                icon: const Icon(Icons.refresh),
                label: const Text('Làm mới'),
              ),
            ],
          ),
          if (state.loading) const LinearProgressIndicator(),
          MenuFailurePanel(
            failure: state.failure,
            onReload: controller.load,
            reloadLabel: 'Thử lại',
          ),
          if (state.hasLoaded &&
              !state.loading &&
              state.failure == null &&
              state.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  const Icon(Icons.kitchen_outlined, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    query.hasFilters
                        ? 'Không có kết quả phù hợp với bộ lọc.'
                        : 'Chưa có nguyên liệu.',
                  ),
                  if (widget.canCreate && !query.hasFilters) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Dùng nút "Thêm nguyên liệu" phía trên để bắt đầu.',
                    ),
                  ],
                ],
              ),
            ),
          if (state.rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            if (constraints.maxWidth >= 900 * textScale)
              _table(constraints.maxWidth, textScale)
            else
              ResponsiveColumns(
                minColumnWidth: 300 * textScale.clamp(1.0, double.infinity),
                maxColumns: 4,
                spacing: 12,
                children: [for (final item in state.rows) _card(item)],
              ),
          ],
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Text(
                '${state.totalElements} nguyên liệu · Trang ${query.page + 1}/${state.totalPages == 0 ? 1 : state.totalPages}',
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 110 * textScale.clamp(1.0, double.infinity),
                    child: _select(
                      'Mỗi trang',
                      query.size.toString(),
                      const {'10': '10', '20': '20', '50': '50', '100': '100'},
                      (v) => controller.setPageSize(int.parse(v)),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Trang trước',
                    onPressed: state.loading || query.page == 0
                        ? null
                        : () => controller.setPage(query.page - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Trang sau',
                    onPressed:
                        state.loading || query.page >= state.totalPages - 1
                        ? null
                        : () => controller.setPage(query.page + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool? _bool(String value) => value == 'all' ? null : value == 'true';
  bool _busy(Ingredient item) =>
      controller.isPending(item.id) || widget.opening.contains(item.id);

  Widget _actions(Ingredient item) => PopupMenuButton<String>(
    tooltip: 'Thao tác nguyên liệu',
    enabled: !_busy(item),
    onSelected: (action) => widget.onAction(item, action),
    itemBuilder: (_) => [
      const PopupMenuItem(value: 'view', child: Text('Chi tiết')),
      if (widget.canUpdate) ...[
        const PopupMenuItem(value: 'edit', child: Text('Sửa thông tin')),
        PopupMenuItem(
          value: 'status',
          child: Text(item.active ? 'Ngừng sử dụng' : 'Bật sử dụng'),
        ),
      ],
      if (widget.canDelete)
        const PopupMenuItem(value: 'delete', child: Text('Xóa nguyên liệu')),
    ],
    icon: _busy(item)
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.more_vert),
  );

  Widget _card(Ingredient item) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: _busy(item) ? null : () => widget.onAction(item, 'view'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _actions(item),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Giá vốn: ${item.costPrice} / ${item.baseUnit}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Text('SKU: ${item.sku ?? 'Chưa có'}'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(item.active ? 'Đang sử dụng' : 'Ngừng sử dụng'),
                  ),
                  Chip(
                    label: Text(
                      item.trackInventory
                          ? 'Theo dõi tồn kho'
                          : 'Không theo dõi tồn kho',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _table(double width, double textScale) => Card(
    margin: EdgeInsets.zero,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: width),
        child: DataTable(
          showCheckboxColumn: false,
          headingRowHeight: 56 * textScale,
          dataRowMinHeight: 64,
          dataRowMaxHeight: double.infinity,
          columns: const [
            DataColumn(label: Text('Tên nguyên liệu')),
            DataColumn(label: Text('SKU')),
            DataColumn(label: Text('Đơn vị cơ sở')),
            DataColumn(label: Text('Giá vốn / đơn vị'), numeric: true),
            DataColumn(label: Text('Theo dõi tồn kho')),
            DataColumn(label: Text('Trạng thái')),
            DataColumn(label: Text('Thao tác')),
          ],
          rows: [
            for (final item in controller.state.rows)
              DataRow(
                key: ValueKey(item.id),
                onSelectChanged: _busy(item)
                    ? null
                    : (_) => widget.onAction(item, 'view'),
                cells: [
                  DataCell(Text(item.name)),
                  DataCell(Text(item.sku ?? '—')),
                  DataCell(Text(item.baseUnit)),
                  DataCell(Text('${item.costPrice}')),
                  DataCell(Text(item.trackInventory ? 'Có' : 'Không')),
                  DataCell(
                    Text(item.active ? 'Đang sử dụng' : 'Ngừng sử dụng'),
                  ),
                  DataCell(_actions(item)),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}
