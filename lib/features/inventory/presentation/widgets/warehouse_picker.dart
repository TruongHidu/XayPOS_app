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

Future<Warehouse?> chooseInventoryWarehouse(
  BuildContext context,
  WidgetRef ref,
) => showInventoryDialog<Warehouse>(
  context,
  ref,
  child: const WarehousePickerDialog(),
);

class WarehousePickerDialog extends ConsumerWidget {
  const WarehousePickerDialog({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(warehouseSelectorProvider);
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
            child: OutlinedButton(
              key: ValueKey('select-warehouse-${row.id}'),
              onPressed: () => Navigator.of(context).pop(row),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(12),
                alignment: Alignment.centerLeft,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(row.code),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (row.isDefault)
                        const InventoryBadge('Mặc định', positive: true),
                      InventoryBadge(
                        row.active ? 'Đang hoạt động' : 'Ngừng hoạt động',
                      ),
                      if (c.selected?.id == row.id)
                        const InventoryBadge('Đang chọn', positive: true),
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
