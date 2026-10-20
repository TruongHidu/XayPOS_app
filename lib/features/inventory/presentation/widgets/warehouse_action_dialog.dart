import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../domain/entities/inventory_entities.dart';
import '../controllers/warehouse_list_controller.dart';
import '../controllers/inventory_controller.dart';
import '../controllers/inventory_events.dart';
import 'inventory_widgets.dart';

String warehouseActionLabel(WarehouseAction action) => switch (action) {
  WarehouseAction.enable => 'Bật kho',
  WarehouseAction.disable => 'Tắt kho',
  WarehouseAction.makeDefault => 'Đặt mặc định',
  WarehouseAction.delete => 'Xóa kho',
};

class WarehouseActionDialog extends ConsumerStatefulWidget {
  const WarehouseActionDialog({super.key, required this.id, this.action});
  final String id;
  final WarehouseAction? action;
  @override
  ConsumerState<WarehouseActionDialog> createState() =>
      _WarehouseActionDialogState();
}

class _WarehouseActionDialogState extends ConsumerState<WarehouseActionDialog> {
  Warehouse? _baseline;
  Failure? _failure;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  String get _key => InventoryEvents.warehouseKey(widget.id);
  Future<void> _load() async {
    if (!mounted) return;
    final c = ref.read(warehouseListProvider);
    setState(() => _loading = true);
    final result = await c.detail(widget.id, verify: true);
    if (!mounted || !c.current) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Success(value: final value):
          _baseline = value;
          _failure = null;
        case Error(failure: final error):
          _failure = error;
          if (error.type == FailureType.notFound) {
            _baseline = null;
            c.events.resolve(_key);
          }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(warehouseListProvider),
        events = ref.watch(inventoryEventsProvider);
    final pending = events.pending(_key),
        verification = events.verification(_key),
        row = _baseline,
        action = widget.action;
    final valid =
        row != null &&
        !(action == WarehouseAction.delete || action == WarehouseAction.disable
            ? row.isDefault
            : action == WarehouseAction.makeDefault
            ? !row.active
            : false);
    return InventoryDialogFrame(
      title: action == null ? 'Chi tiết kho' : warehouseActionLabel(action),
      busy: pending || _loading,
      canClose: !InventoryController.unknown(verification),
      actions: [
        if (action != null)
          FilledButton(
            onPressed:
                !valid ||
                    pending ||
                    _loading ||
                    verification != null ||
                    !c.can(
                      action == WarehouseAction.delete
                          ? 'WAREHOUSE_DELETE'
                          : 'WAREHOUSE_UPDATE',
                    )
                ? null
                : () async {
                    final result = await c.act(row, action);
                    if (!context.mounted || !c.current) return;
                    if (result is Success<Warehouse?>) {
                      Navigator.of(context).pop(true);
                    } else if (result case Error(failure: final error)) {
                      setState(() => _failure = error);
                    }
                  },
            child: Text(
              'Xác nhận ${warehouseActionLabel(action).toLowerCase()}',
            ),
          ),
      ],
      children: [
        if (row != null) ...[
          Text(row.name, style: Theme.of(context).textTheme.titleMedium),
          Text('Mã kho: ${row.code}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InventoryBadge(
                row.active ? 'Đang hoạt động' : 'Ngừng hoạt động',
                positive: row.active,
              ),
              if (row.isDefault)
                const InventoryBadge('Mặc định', positive: true),
            ],
          ),
          const SizedBox(height: 12),
          Text('Ngày tạo: ${formatLocalDate(row.createdAt)}'),
          Text('Cập nhật: ${formatLocalDate(row.updatedAt)}'),
          if (action != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(switch (action) {
                WarehouseAction.delete =>
                  'Xóa mềm kho này? Mã kho vẫn được giữ và không thể dùng để tạo kho khác.',
                WarehouseAction.disable =>
                  'Ngừng sử dụng kho này? Kho chỉ được tắt khi không còn số lượng tồn khác 0.',
                WarehouseAction.enable => 'Cho phép kho này hoạt động trở lại?',
                WarehouseAction.makeDefault =>
                  'Đặt kho này làm mặc định? Kho mặc định hiện tại sẽ được thay thế.',
              }),
            ),
          if (!valid)
            const Text('Thao tác không khả dụng với trạng thái kho hiện tại.'),
        ],
        InventoryFailurePanel(
          failure: _failure ?? verification,
          retry: pending || _loading ? null : _load,
          label: 'Tải lại để đối chiếu',
        ),
        if (InventoryController.unknown(verification))
          const Text(
            'Cần tải lại để xác định kết quả trước khi đóng hoặc gửi tiếp.',
          ),
      ],
    );
  }
}
