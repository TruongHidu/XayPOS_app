import 'package:flutter/material.dart';
import '../controllers/order_draft_controller.dart';
import '../controllers/order_append_controller.dart';
import '../../../tables/presentation/controllers/table_transfer_controller.dart';
import '../../../tables/presentation/widgets/table_dialogs.dart';
import 'order_widgets.dart';

class OrderExitGuard {
  OrderDraftController? draft;
  final Set<OrderAppendController> _appends = {};
  final Set<TableTransferController> _transfers = {};
  void registerAppend(OrderAppendController controller) =>
      _appends.add(controller);
  void unregisterAppend(OrderAppendController controller) =>
      _appends.remove(controller);
  void registerTransfer(TableTransferController controller) =>
      _transfers.add(controller);
  void unregisterTransfer(TableTransferController controller) =>
      _transfers.remove(controller);
  Future<bool> allow(BuildContext context) async {
    for (final transfer in _transfers) {
      if (transfer.isCurrent && (transfer.busy || transfer.uncertain)) {
        await showDialog<void>(
          context: context,
          builder: (_) => TableScopeGuard(
            scope: transferScope(transfer),
            permission: 'TABLE_TRANSFER',
            child: const AlertDialog(
              title: Text('Chưa xác định kết quả chuyển bàn'),
              content: Text(
                'Hãy mở lại chuyển bàn và thử lại đúng yêu cầu ban đầu trước khi rời màn hình.',
              ),
            ),
          ),
        );
        return false;
      }
    }
    for (final append in _appends) {
      if (append.current && (append.busy || append.uncertain)) {
        await showDialog<void>(
          context: context,
          builder: (_) => OrderScopeGuard(
            scope: append.scope,
            permission: 'ORDER_UPDATE',
            child: const AlertDialog(
              title: Text('Chưa xác định kết quả gọi thêm'),
              content: Text(
                'Hãy kiểm tra lại bằng yêu cầu gọi thêm ban đầu trước khi rời luồng. GET hiện trạng không xác nhận lần gửi này.',
              ),
            ),
          ),
        );
        return false;
      }
    }
    final d = draft;
    if (d == null || !d.current || d.result != null) return true;
    if (d.busy || d.uncertain) {
      await showDialog<void>(
        context: context,
        builder: (_) => OrderScopeGuard(
          scope: d.scope,
          permission: 'ORDER_CREATE',
          child: const AlertDialog(
            title: Text('Chưa xác định kết quả tạo'),
            content: Text(
              'Hãy chờ hoặc kiểm tra lại bằng yêu cầu ban đầu trước khi rời luồng.',
            ),
          ),
        ),
      );
      return false;
    }
    if (!d.dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (_) => OrderScopeGuard(
            scope: d.scope,
            permission: 'ORDER_CREATE',
            child: AlertDialog(
              title: const Text('Bỏ giỏ đang nhập?'),
              content: const Text('Giỏ món chưa lưu sẽ bị bỏ.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Giữ giỏ'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Bỏ giỏ'),
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  Object? transferScope(TableTransferController controller) => controller.scope;
}
