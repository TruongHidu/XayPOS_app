import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
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
      title: 'Chọn nguyên liệu',
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
        const Text(
          'Tồn là số dư tham khảo. Hệ thống kiểm tra lại khi xác nhận phiếu.',
        ),
        if (c.hasLoaded && c.rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Không có nguyên liệu phù hợp.'),
          ),
        for (final row in c.rows)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton(
              key: ValueKey('stock-pick-${row.ingredientId}'),
              onPressed:
                  excluded.contains(row.ingredientId) ||
                      type == StockDocumentType.receipt && !row.ingredientActive
                  ? null
                  : () => Navigator.of(context).pop(row),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(12),
                alignment: Alignment.centerLeft,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.ingredientName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${row.ingredientSku ?? 'Chưa có SKU'} · ${row.baseUnit}',
                  ),
                  Text('Tồn: ${inventoryAmount(row.quantity, row.baseUnit)}'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (!row.configured)
                        const InventoryBadge('Chưa cấu hình'),
                      if (!row.ingredientActive)
                        const InventoryBadge('Ngừng hoạt động'),
                      if (excluded.contains(row.ingredientId))
                        const InventoryBadge('Đã có trong phiếu'),
                    ],
                  ),
                ],
              ),
            ),
          ),
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
