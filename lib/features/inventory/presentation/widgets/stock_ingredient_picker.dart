import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/values/item_type.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/stock_document.dart';
import 'inventory_widgets.dart';

Future<InventoryBalance?> pickStockIngredient(
  BuildContext context,
  WidgetRef ref, {
  required String warehouseId,
  required StockDocumentType type,
  required Set<String> excluded,
}) => showInventoryDialog<InventoryBalance>(
  context,
  ref,
  permission: type.permission,
  child: StockIngredientPicker(
    warehouseId: warehouseId,
    type: type,
    excluded: excluded,
  ),
);

class StockIngredientPicker extends ConsumerWidget {
  const StockIngredientPicker({
    super.key,
    required this.warehouseId,
    required this.type,
    required this.excluded,
  });
  final String warehouseId;
  final StockDocumentType type;
  final Set<String> excluded;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(
      stockIngredientPickerProvider((warehouseId: warehouseId, type: type)),
    );
    return InventoryDialogFrame(
      title: 'Chọn hàng hóa',
      children: [
        TextField(
          decoration: inventoryField(
            'Tìm tên hoặc SKU',
          ).copyWith(prefixIcon: const Icon(Icons.search)),
          maxLength: 100,
          onChanged: c.search,
        ),
        if (c.loading) const LinearProgressIndicator(),
        InventoryFailurePanel(failure: c.failure, retry: c.load),
        Text(
          'Khả dụng = Tồn kho − Đang giữ cho đơn. Số liệu để tham khảo, '
          'hệ thống kiểm tra lại khi xác nhận phiếu.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (c.hasLoaded && c.rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Không có hàng hóa phù hợp.'),
          ),
        for (final row in c.rows)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _StockItemOption(
              row: row,
              added: excluded.contains(row.stockItemId),
              inactiveForReceipt:
                  type == StockDocumentType.receipt && !row.ingredientActive,
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

class _StockItemOption extends StatelessWidget {
  const _StockItemOption({
    required this.row,
    required this.added,
    required this.inactiveForReceipt,
    required this.onTap,
  });
  final InventoryBalance row;
  final bool added, inactiveForReceipt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final enabled = !added && !inactiveForReceipt;
    final menuItem = row.itemType == ItemType.menuItem;
    final subtitle = [
      row.itemType.label,
      if (row.ingredientSku != null) 'SKU ${row.ingredientSku}',
    ].join(' · ');
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: enabled ? scheme.surface : scheme.surfaceContainerHighest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          key: ValueKey('stock-pick-${row.stockItemId}'),
          onTap: enabled ? onTap : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: menuItem
                              ? scheme.tertiaryContainer
                              : scheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          menuItem
                              ? Icons.local_drink_outlined
                              : Icons.eco_outlined,
                          size: 22,
                          color: menuItem
                              ? scheme.onTertiaryContainer
                              : scheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.ingredientName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        added
                            ? Icons.check_circle
                            : enabled
                            ? Icons.add_circle_outline
                            : Icons.block,
                        color: added ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Figure(
                          'Tồn kho',
                          inventoryAmount(row.quantity, row.baseUnit),
                        ),
                        _Figure(
                          'Đang giữ',
                          inventoryAmount(row.reservedQuantity, row.baseUnit),
                        ),
                        _Figure(
                          'Khả dụng',
                          inventoryAmount(row.availableQuantity, row.baseUnit),
                          emphasis: true,
                        ),
                      ],
                    ),
                  ),
                  if (row.lowStock ||
                      !row.configured ||
                      !row.ingredientActive ||
                      added)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (added)
                            const InventoryBadge(
                              'Đã có trong phiếu',
                              positive: true,
                            ),
                          if (row.lowStock)
                            const InventoryBadge('Sắp hết', warning: true),
                          if (!row.configured)
                            const InventoryBadge('Chưa cấu hình'),
                          if (!row.ingredientActive)
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
          ),
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {this.emphasis = false});
  final String label, value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
                color: emphasis ? scheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
