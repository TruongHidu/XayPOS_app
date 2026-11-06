import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../domain/entities/inventory_entities.dart';
import 'inventory_widgets.dart';

Future<void> pickInventoryWarehouse(BuildContext context, WidgetRef ref) async {
  final selector = ref.read(warehouseSelectorProvider);
  final result = await showInventoryDialog<Warehouse>(
    context,
    ref,
    child: const WarehousePickerDialog(),
  );
  if (context.mounted && selector.current && result != null) {
    selector.select(result);
  }
}

/// Pass [selectedId] with [followSelector] false when the caller owns its own
/// choice (a form's warehouse) rather than the shared inventory selection.
Future<Warehouse?> chooseInventoryWarehouse(
  BuildContext context,
  WidgetRef ref, {
  String? selectedId,
  bool followSelector = true,
}) => showInventoryDialog<Warehouse>(
  context,
  ref,
  child: WarehousePickerDialog(
    selectedId: selectedId,
    followSelector: followSelector,
  ),
);

class WarehousePickerDialog extends ConsumerWidget {
  const WarehousePickerDialog({
    super.key,
    this.selectedId,
    this.followSelector = true,
  });
  final String? selectedId;
  final bool followSelector;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(warehouseSelectorProvider);
    final highlighted = followSelector ? c.selected?.id : selectedId;
    return InventoryDialogFrame(
      title: 'Chọn kho',
      children: [
        TextFormField(
          key: ValueKey(c),
          initialValue: c.query.q,
          maxLength: 100,
          decoration: inventoryField(
            'Tìm kho',
            hint: 'Mã hoặc tên kho',
          ).copyWith(counterText: '', prefixIcon: const Icon(Icons.search)),
          onChanged: c.search,
        ),
        if (c.loading)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        InventoryFailurePanel(
          failure: c.failure,
          retry: c.loading ? null : c.load,
        ),
        if (!c.loading && c.rows.isEmpty && c.failure == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Không tìm thấy kho phù hợp.'),
          ),
        for (final row in c.rows)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _WarehouseOption(
              row: row,
              selected: highlighted == row.id,
              onTap: () => Navigator.of(context).pop(row),
            ),
          ),
        const SizedBox(height: 4),
        InventoryPaging(
          page: c.query.page,
          totalPages: c.totalPages,
          totalElements: c.totalElements,
          loading: c.loading,
          changed: c.page,
        ),
      ],
    );
  }
}

class _WarehouseOption extends StatelessWidget {
  const _WarehouseOption({
    required this.row,
    required this.selected,
    required this.onTap,
  });
  final Warehouse row;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final muted = !row.active;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.45)
            : scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          key: ValueKey('select-warehouse-${row.id}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: muted
                        ? scheme.surfaceContainerHighest
                        : scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.warehouse_outlined,
                    size: 22,
                    color: muted
                        ? scheme.onSurfaceVariant
                        : scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: muted ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Mã ${row.code}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (row.isDefault || muted)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (row.isDefault)
                                const InventoryBadge(
                                  'Mặc định',
                                  positive: true,
                                ),
                              if (muted)
                                const InventoryBadge(
                                  'Ngừng hoạt động',
                                  warning: true,
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle : Icons.chevron_right,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
