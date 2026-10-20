import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/stock_document.dart';
import '../widgets/inventory_widgets.dart';
import '../widgets/warehouse_picker.dart';
import '../widgets/stock_widgets.dart';
import '../widgets/stock_document_forms.dart';
import '../widgets/stock_ingredient_picker.dart';

class StockDocumentCreateScreen extends ConsumerWidget {
  const StockDocumentCreateScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(inventoryScopeProvider);
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canInventory(session, 'INVENTORY_VIEW')) {
      return const Center(child: Text('Bạn chưa có quyền xem kho.'));
    }
    return _StockCreateWorkspace(key: ValueKey(scope));
  }
}

class _StockCreateWorkspace extends ConsumerWidget {
  const _StockCreateWorkspace({super.key});
  Future<void> _line(BuildContext context, WidgetRef ref, {int? index}) async {
    final c = ref.read(stockDocumentCreateProvider), warehouse = c.warehouse;
    if (!c.editable || warehouse == null) return;
    final existing = index == null ? null : c.lines[index];
    final ingredient =
        existing?.ingredient ??
        await pickStockIngredient(
          context,
          ref,
          warehouseId: warehouse.id,
          type: c.type,
          excluded: c.lines.map((r) => r.input.ingredientId).toSet(),
        );
    if (!context.mounted || ingredient == null || !c.current || !c.editable) {
      return;
    }
    await showInventoryDialog<bool>(
      context,
      ref,
      permission: c.type.permission,
      child: StockLineEditor(
        type: c.type,
        ingredientId: ingredient.ingredientId,
        name: ingredient.ingredientName,
        unit: ingredient.baseUnit,
        sku: ingredient.ingredientSku,
        initial: existing?.input,
        onSave: (input) async => c.put(ingredient, input, index: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(stockDocumentCreateProvider);
    if (c.result != null) {
      return StockPageFrame(
        title: 'Phiếu đã được lưu',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.result!.documentCode),
            StockStatusBadge(c.result!.status),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go(stockDetailLocation(c.result!.id)),
              child: const Text('Mở chi tiết chứng từ'),
            ),
          ],
        ),
      );
    }
    if (c.allowedTypes.isEmpty) {
      return const StockPageFrame(
        title: 'Tạo chứng từ',
        child: Text(
          'Bạn cần quyền nhập, xuất hoặc điều chỉnh kho để tạo phiếu.',
        ),
      );
    }
    return StockPageFrame(
      title: 'Tạo chứng từ',
      actions: [
        FilledButton.icon(
          onPressed: c.busy
              ? null
              : () async {
                  final response = await c.save();
                  if (!context.mounted || !c.current) return;
                  if (response case Success(value: final value)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã lưu chứng từ.')),
                    );
                    context.go(stockDetailLocation(value.id));
                  }
                },
          icon: const Icon(Icons.save_outlined),
          label: Text(c.uncertain ? 'Thử lại yêu cầu ban đầu' : 'Lưu nháp'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.busy) const LinearProgressIndicator(),
          InventoryFailurePanel(failure: c.failure),
          if (c.uncertain)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Yêu cầu đang chờ xác minh. Nội dung được khóa; thử lại sẽ dùng đúng mã đối chiếu và nội dung ban đầu. Không tự tạo phiếu khác.',
                  ),
                  TextButton(
                    onPressed: () => context.go('/app/inventory?tab=documents'),
                    child: const Text('Đối chiếu danh sách chứng từ'),
                  ),
                  if (c.failure?.code == 'IDEMPOTENCY_KEY_REUSED')
                    OutlinedButton(
                      onPressed: c.busy
                          ? null
                          : () async {
                              if (await confirmStockAction(
                                context,
                                ref,
                                permission: c.type.permission,
                                title: 'Đã đối chiếu phiếu?',
                                message:
                                    'Chỉ bắt đầu yêu cầu khác sau khi đã kiểm tra danh sách và xác định đúng chứng từ. Không dùng thao tác này để thử lại một yêu cầu timeout.',
                                confirm: 'Đã đối chiếu dữ liệu',
                              )) {
                                c.acknowledgeKeyConflict();
                              }
                            },
                      child: const Text('Đã kiểm tra dữ liệu máy chủ'),
                    ),
                ],
              ),
            ),
          ResponsiveColumns(
            minColumnWidth: 300,
            maxColumns: 2,
            spacing: 12,
            children: [
              StockSelect(
                label: 'Loại chứng từ',
                value: c.type.code,
                items: {for (final t in c.allowedTypes) t.code: t.label},
                enabled: c.editable,
                changed: (v) async {
                  final type = StockDocumentType.values.firstWhere(
                    (t) => t.code == v,
                  );
                  if (c.lines.isNotEmpty &&
                      !await confirmStockAction(
                        context,
                        ref,
                        permission: c.type.permission,
                        title: 'Đổi loại chứng từ?',
                        message:
                            'Các dòng đang nhập sẽ được bỏ để chọn lại đúng loại phiếu.',
                        confirm: 'Đổi loại',
                      )) {
                    return;
                  }
                  if (context.mounted && c.current) c.setType(type);
                },
              ),
              OutlinedButton.icon(
                onPressed: !c.editable
                    ? null
                    : () async {
                        final value = await chooseInventoryWarehouse(
                          context,
                          ref,
                        );
                        if (!context.mounted || value == null || !c.current) {
                          return;
                        }
                        if (!value.active) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Kho ngừng hoạt động, không thể tạo phiếu mới.',
                              ),
                            ),
                          );
                          return;
                        }
                        if (c.lines.isNotEmpty &&
                            value.id != c.warehouse?.id &&
                            !await confirmStockAction(
                              context,
                              ref,
                              permission: c.type.permission,
                              title: 'Đổi kho của phiếu?',
                              message:
                                  'Các dòng đang nhập sẽ được bỏ. Hãy chọn lại nguyên liệu và số dư của kho mới.',
                              confirm: 'Đổi kho',
                            )) {
                          return;
                        }
                        if (context.mounted && c.current) {
                          c.selectWarehouse(value);
                        }
                      },
                icon: const Icon(Icons.warehouse_outlined),
                label: Text(
                  c.warehouse == null
                      ? 'Chọn kho'
                      : '${c.warehouse!.name} · ${c.warehouse!.code}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: ValueKey(('stock-create-note', c)),
            initialValue: c.note,
            enabled: c.editable,
            maxLength: 2000,
            minLines: 2,
            maxLines: 6,
            decoration: inventoryField(
              'Ghi chú chứng từ',
              error: c.failure?.fieldErrors['note'],
            ),
            onChanged: c.setNote,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${c.lines.length} dòng nguyên liệu',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              OutlinedButton.icon(
                onPressed:
                    !c.editable || c.warehouse == null || c.lines.length >= 100
                    ? null
                    : () => _line(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Thêm nguyên liệu'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Lưu nháp chưa làm thay đổi tồn kho. Bạn sẽ kiểm tra và xác nhận riêng ở chi tiết phiếu.',
          ),
          if (c.lines.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Chưa có dòng nguyên liệu. Có thể lưu nháp rỗng và bổ sung sau.',
              ),
            ),
          for (final row in c.lines.indexed)
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.$2.ingredient.ingredientName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${row.$2.ingredient.ingredientSku ?? 'Chưa có SKU'} · ${row.$2.ingredient.baseUnit}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Số lượng: ${inventoryAmount(row.$2.input.quantity, row.$2.ingredient.baseUnit)}',
                    ),
                    Text('Đơn giá: ${stockDisplay(row.$2.input.unitCost)}'),
                    if (row.$2.input.direction != null)
                      InventoryBadge(
                        row.$2.input.direction!.label,
                        warning:
                            row.$2.input.direction ==
                            AdjustmentDirection.decrease,
                      ),
                    if (row.$2.input.note?.isNotEmpty == true)
                      Text(row.$2.input.note!),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: !c.editable
                              ? null
                              : () => _line(context, ref, index: row.$1),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Sửa dòng'),
                        ),
                        TextButton.icon(
                          onPressed: !c.editable
                              ? null
                              : () => c.remove(row.$1),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Bỏ dòng'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
