import 'package:flutter/material.dart';

import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/ingredient.dart';
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
  IngredientController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final query = state.query;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                    const Text('Dùng nút + ở góc dưới bên phải để bắt đầu.'),
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
        ],
      ),
    );
  }

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
                item.costConfigured
                    ? 'Giá vốn tham chiếu: ${menuMoney(item.costPrice)} / ${item.baseUnit}'
                    : 'Chưa cấu hình giá vốn',
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
                  DataCell(
                    Text(
                      item.costConfigured
                          ? menuMoney(item.costPrice)
                          : 'Chưa cấu hình giá vốn',
                    ),
                  ),
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
