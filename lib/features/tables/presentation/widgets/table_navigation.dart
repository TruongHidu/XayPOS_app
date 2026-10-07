import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import 'table_dialogs.dart';
import 'table_actions.dart';
import 'table_area_form.dart';
import 'restaurant_table_form.dart';
import 'table_session_form.dart';
import 'table_details.dart';

Future<void> tableAction(
  BuildContext context,
  WidgetRef ref,
  String action,
  RestaurantTable row,
) async {
  if (action == 'history') {
    await showTableDialog(
      context,
      ref,
      permission: 'TABLE_VIEW',
      child: TableSessionHistory(tableId: row.id),
    );
    return;
  }
  if (action == 'detail') {
    await showTableDialog(
      context,
      ref,
      permission: 'TABLE_VIEW',
      child: TableDetails(id: row.id),
    );
    return;
  }
  if (action == 'qr') {
    await showTableDialog(
      context,
      ref,
      permission: 'TABLE_UPDATE',
      child: TableQrDialog(id: row.id),
    );
    return;
  }
  final c = ref.read(restaurantTableControllerProvider);
  final result = await c.getDetail(row.id);
  if (!context.mounted) return;
  if (result case Error(failure: final f)) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(f.message)));
    return;
  }
  final b = (result as Success<RestaurantTable>).value;
  final permission = action == 'open' ? 'TABLE_OPEN' : 'TABLE_UPDATE';
  final Widget child = switch (action) {
    'edit' => RestaurantTableForm(initial: b),
    'area' => TableAreaAssignment(initial: b),
    'open' => TableSessionForm(table: b),
    'delete' => TableConfirmation<RestaurantTable>(
      title: 'Xóa bàn?',
      permission: permission,
      initial: b,
      describe: (v) =>
          'Xóa ${v.code} • ${v.name}? Mã bàn vẫn được giữ sau khi xóa. Lịch sử phiên vẫn có thể xem.',
      reload: () => c.getDetail(b.id),
      submit: (v) async {
        final r = await c.delete(v);
        return switch (r) {
          Success() => const Success(null),
          Error(failure: final f) => Error(f),
        };
      },
    ),
    _ => TableConfirmation<RestaurantTable>(
      title: b.status == TableStatus.available ? 'Tắt bàn?' : 'Bật bàn?',
      permission: permission,
      initial: b,
      describe: (v) =>
          'Đổi ${v.code} sang ${b.status == TableStatus.available ? 'ngừng hoạt động' : 'hoạt động'}?',
      reload: () => c.getDetail(b.id),
      submit: (v) => c.setStatus(
        v,
        b.status == TableStatus.available
            ? TableStatus.inactive
            : TableStatus.available,
      ),
    ),
  };
  await showTableDialog(context, ref, permission: permission, child: child);
}

Future<void> areaAction(
  BuildContext context,
  WidgetRef ref,
  String action,
  TableArea row,
) async {
  final c = ref.read(tableAreaControllerProvider);
  final result = await c.getDetail(row.id);
  if (!context.mounted) return;
  if (result case Error(failure: final f)) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(f.message)));
    return;
  }
  final b = (result as Success<TableArea>).value;
  final permission = action == 'detail' ? 'TABLE_VIEW' : 'TABLE_UPDATE';
  final Widget child = switch (action) {
    'detail' => TableFormLayout(
      title: b.name,
      busy: false,
      onSubmit: null,
      showSubmit: false,
      children: [
        Text(b.description ?? 'Chưa có mô tả'),
        Text(
          'Thứ tự: ${b.displayOrder} • ${b.active ? 'Hoạt động' : 'Ngừng hoạt động'}',
        ),
        Text('Tạo: ${tableDate(b.createdAt)}'),
        Text('Cập nhật: ${tableDate(b.updatedAt)}'),
      ],
    ),
    'edit' => TableAreaForm(initial: b),
    'delete' => TableConfirmation<TableArea>(
      title: 'Xóa khu vực?',
      permission: permission,
      initial: b,
      describe: (v) =>
          'Xóa ${v.name}? Khu vực phải không còn bàn, kể cả bàn ngừng hoạt động.',
      reload: () => c.getDetail(b.id),
      submit: (v) async {
        final r = await c.delete(v);
        return switch (r) {
          Success() => const Success(null),
          Error(failure: final f) => Error(f),
        };
      },
    ),
    _ => TableConfirmation<TableArea>(
      title: b.active ? 'Tắt khu vực?' : 'Bật khu vực?',
      permission: permission,
      initial: b,
      describe: (v) =>
          '${b.active ? 'Tắt' : 'Bật'} ${v.name}? Không thể tắt khi khu vực có phiên đang phục vụ.',
      reload: () => c.getDetail(b.id),
      submit: (v) => c.setStatus(v, !b.active),
    ),
  };
  await showTableDialog(context, ref, permission: permission, child: child);
}

class TableActionMenu extends ConsumerStatefulWidget {
  const TableActionMenu({super.key, required this.table});
  final RestaurantTable table;
  @override
  ConsumerState<TableActionMenu> createState() => _TableActionMenuState();
}

class _TableActionMenuState extends ConsumerState<TableActionMenu> {
  bool _opening = false;
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(restaurantTableControllerProvider), t = widget.table;
    return PopupMenuButton<String>(
      tooltip: 'Thao tác bàn',
      enabled: !_opening && !c.pending('table:${t.id}'),
      onSelected: (a) async {
        setState(() => _opening = true);
        try {
          await tableAction(context, ref, a, t);
        } finally {
          if (mounted) setState(() => _opening = false);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'detail', child: Text('Chi tiết bàn')),
        const PopupMenuItem(value: 'history', child: Text('Lịch sử phiên')),
        if (c.can('TABLE_OPEN') && t.canOpen)
          const PopupMenuItem(value: 'open', child: Text('Mở phiên phục vụ')),
        if (c.can('TABLE_UPDATE')) ...[
          const PopupMenuItem(value: 'edit', child: Text('Sửa thông tin')),
          PopupMenuItem(
            value: 'area',
            enabled: !t.occupied,
            child: const Text('Gán / bỏ khu vực'),
          ),
          PopupMenuItem(
            value: 'status',
            enabled: !t.occupied,
            child: Text(
              t.status == TableStatus.available ? 'Tắt bàn' : 'Bật bàn',
            ),
          ),
          const PopupMenuItem(value: 'qr', child: Text('Quản lý QR')),
          PopupMenuItem(
            value: 'delete',
            enabled: !t.occupied,
            child: const Text('Xóa bàn'),
          ),
        ],
      ],
    );
  }
}
