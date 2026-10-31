import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/inventory_inputs.dart';
import '../../domain/entities/inventory_quantity.dart';
import '../controllers/inventory_controller.dart';
import 'inventory_widgets.dart';
import 'stock_widgets.dart';

class InventoryThresholdDialog extends ConsumerStatefulWidget {
  const InventoryThresholdDialog({
    super.key,
    required this.warehouseId,
    required this.ingredientId,
    this.edit = false,
  });
  final String warehouseId, ingredientId;
  final bool edit;
  @override
  ConsumerState<InventoryThresholdDialog> createState() =>
      _InventoryThresholdDialogState();
}

class _InventoryThresholdDialogState
    extends ConsumerState<InventoryThresholdDialog> {
  final _value = TextEditingController();
  InventoryBalance? _baseline;
  String? _error;
  Failure? _failure;
  @override
  Widget build(BuildContext context) {
    final identity = (
      warehouseId: widget.warehouseId,
      ingredientId: widget.ingredientId,
    );
    final c = ref.watch(inventoryBalanceDetailProvider(identity));
    final row = c.balance;
    if (_baseline == null && row != null) {
      _baseline = row;
      _value.text = row.minQuantity.toString();
    }
    final verification = c.events.verification(c.key);
    return InventoryDialogFrame(
      title: widget.edit ? 'Cập nhật ngưỡng tồn' : 'Chi tiết tồn kho',
      busy: c.loading || c.busy,
      canClose: !InventoryController.unknown(verification),
      actions: [
        TextButton.icon(
          onPressed: c.busy || c.loading || c.requiresReview
              ? null
              : () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  router.go(
                    stockHistoryLocation(
                      warehouseId: widget.warehouseId,
                      ingredientId: widget.ingredientId,
                    ),
                  );
                },
          icon: const Icon(Icons.history),
          label: const Text('Xem biến động'),
        ),
        if (widget.edit)
          FilledButton(
            onPressed: !c.canSave || _baseline == null
                ? null
                : () async {
                    InventoryQuantity quantity;
                    try {
                      quantity = InventoryQuantity.parse(_value.text);
                    } on FormatException catch (e) {
                      setState(() => _error = e.message);
                      return;
                    }
                    setState(() => _error = null);
                    final result = await c.save(
                      _baseline!,
                      UpdateInventoryThresholdInput(
                        _baseline!.version,
                        quantity,
                      ),
                    );
                    if (!context.mounted || !c.current) return;
                    if (result is Success<InventoryBalance>) {
                      Navigator.of(context).pop(true);
                    } else if (result case Error(failure: final error)) {
                      setState(() {
                        _failure = error;
                        _error = error.fieldErrors['minQuantity'];
                      });
                    }
                  },
            child: const Text('Lưu ngưỡng'),
          ),
      ],
      children: [
        if (row != null) ...[
          Text(
            row.ingredientName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('SKU: ${row.ingredientSku ?? '—'}'),
          Text(
            'Kho: ${c.warehouse?.name ?? row.warehouseCode} · ${row.warehouseCode}',
          ),
          const SizedBox(height: 12),
          Text('Trong kho: ${inventoryAmount(row.quantity, row.baseUnit)}'),
          Text(
            'Đang giữ: ${inventoryAmount(row.reservedQuantity, row.baseUnit)}',
          ),
          Text(
            'Có thể dùng: ${inventoryAmount(row.availableQuantity, row.baseUnit)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            'Ngưỡng hiện tại: ${inventoryAmount(row.minQuantity, row.baseUnit)}',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (!row.configured) const InventoryBadge('Chưa cấu hình'),
              if (row.lowStock) const InventoryBadge('Tồn thấp', warning: true),
              if (row.minQuantity == InventoryQuantity.zero)
                const InventoryBadge('Đã tắt cảnh báo'),
              if (!row.ingredientActive)
                const InventoryBadge('Nguyên liệu ngừng hoạt động'),
            ],
          ),
          if (c.warehouse?.active == false)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Kho ngừng hoạt động, chỉ có thể xem số dư.'),
            ),
          if (widget.edit) ...[
            const SizedBox(height: 20),
            TextField(
              controller: _value,
              enabled: c.canSave,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: inventoryField(
                'Ngưỡng tối thiểu',
                hint: 'Ví dụ: 10.5',
                error: _error,
              ).copyWith(suffixText: row.baseUnit),
            ),
            const SizedBox(height: 8),
            const Text(
              'Nhập 0 để tắt cảnh báo. Cảnh báo xuất hiện khi tồn nhỏ hơn hoặc bằng ngưỡng. Dùng dấu chấm cho phần thập phân, tối đa 3 chữ số.',
            ),
          ],
        ],
        InventoryFailurePanel(failure: _failure ?? c.failure ?? verification),
        if (verification != null)
          const Text(
            'Giữ nguyên bản đang nhập. Hãy tải lại và đối chiếu dữ liệu trước khi lưu tiếp.',
          ),
        if (c.failure != null || verification != null)
          OutlinedButton(
            onPressed: c.loading || c.busy
                ? null
                : () async {
                    if (widget.edit &&
                        !await confirmInventoryDraftReload(context, ref)) {
                      return;
                    }
                    if (!context.mounted) return;
                    await c.load();
                    if (!context.mounted || !c.current || c.failure != null) {
                      return;
                    }
                    setState(() {
                      _baseline = c.balance;
                      _value.text = c.balance?.minQuantity.toString() ?? '';
                      _error = null;
                      _failure = null;
                    });
                  },
            child: const Text('Tải lại để đối chiếu'),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }
}
