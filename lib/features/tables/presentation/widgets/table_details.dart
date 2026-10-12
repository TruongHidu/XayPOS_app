import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import '../controllers/table_controller.dart';
import 'table_dialogs.dart';
import 'table_actions.dart';
import 'table_area_picker.dart';
import 'table_navigation.dart';
import 'table_session_form.dart';
import 'table_transfer_dialog.dart';

class TableDetails extends ConsumerStatefulWidget {
  const TableDetails({super.key, required this.id});
  final String id;
  @override
  ConsumerState<TableDetails> createState() => _TableDetailsState();
}

class _TableDetailsState extends ConsumerState<TableDetails> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(tableSessionControllerProvider(widget.id)).loadCurrent();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(tableDetailControllerProvider(widget.id)), t = c.value;
    final sessions = ref.watch(tableSessionControllerProvider(widget.id));
    return TableFormLayout(
      title: t == null ? 'Chi tiết bàn' : '${t.code} • ${t.name}',
      busy: false,
      onSubmit: null,
      showSubmit: false,
      children: [
        if (c.loading) const LinearProgressIndicator(),
        TableFailurePanel(failure: c.failure, onReload: c.load),
        if (t != null) ...[
          Row(
            children: [
              Expanded(
                child: Text('Khu vực: ${t.area?.name ?? 'Chưa gán khu vực'}'),
              ),
              TableActionMenu(table: t),
            ],
          ),
          Text('Sức chứa: ${t.capacity} • Thứ tự: ${t.displayOrder}'),
          TableBadges(table: t),
          Text('Tạo: ${tableDate(t.createdAt)}'),
          Text('Cập nhật: ${tableDate(t.updatedAt)}'),
          const Divider(height: 32),
          Text(
            'Phiên hiện tại',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (sessions.currentLoading) const LinearProgressIndicator(),
          TableFailurePanel(
            failure: sessions.currentFailure,
            onReload: sessions.loadCurrent,
          ),
          if (!sessions.currentLoading &&
              sessions.currentFailure == null &&
              sessions.current == null)
            const Text('Bàn chưa có phiên đang mở.'),
          if (sessions.current != null)
            TableSessionCard(session: sessions.current!),
          TextButton(
            onPressed: () => showTableDialog(
              context,
              ref,
              permission: 'TABLE_VIEW',
              child: TableSessionHistory(tableId: widget.id),
            ),
            child: const Text('Xem lịch sử phiên'),
          ),
        ],
      ],
    );
  }
}

class TableBadges extends StatelessWidget {
  const TableBadges({super.key, required this.table});
  final RestaurantTable table;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      Chip(
        avatar: Icon(
          table.status == TableStatus.available
              ? Icons.check_circle_outline
              : Icons.pause_circle_outline,
          size: 18,
        ),
        label: Text(
          table.status == TableStatus.available
              ? 'Hoạt động'
              : 'Ngừng hoạt động',
        ),
      ),
      Chip(
        backgroundColor: table.occupied
            ? Theme.of(context).colorScheme.secondaryContainer
            : null,
        avatar: Icon(
          table.occupied ? Icons.people : Icons.event_seat_outlined,
          size: 18,
        ),
        label: Text(
          table.occupied
              ? 'Có khách${table.currentSession == null ? '' : ' • ${table.currentSession!.guestCount} người'}'
              : 'Trống',
        ),
      ),
    ],
  );
}

class TableSessionCard extends ConsumerStatefulWidget {
  const TableSessionCard({super.key, required this.session});
  final TableSession session;
  @override
  ConsumerState<TableSessionCard> createState() => _TableSessionCardState();
}

class _TableSessionCardState extends ConsumerState<TableSessionCard> {
  bool _opening = false;
  Future<void> _action(String action) async {
    setState(() => _opening = true);
    try {
      final result = await ref
          .read(tableSessionControllerProvider(widget.session.tableId))
          .getDetail(widget.session.id);
      if (!mounted) return;
      if (result case Error(failure: final f)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(f.message)));
        return;
      }
      final b = (result as Success<TableSession>).value;
      if (action == 'transfer') {
        await showTableTransferDialog(context, ref, sessionId: b.id);
        return;
      }
      if (action == 'transferHistory') {
        await showTableDialog(
          context,
          ref,
          permission: 'TABLE_VIEW',
          child: TableTransferHistoryView(sessionId: b.id),
        );
        return;
      }
      await showTableDialog(
        context,
        ref,
        permission: action == 'detail'
            ? 'TABLE_VIEW'
            : action == 'cancel'
            ? 'TABLE_CLOSE'
            : 'TABLE_OPEN',
        child: action == 'detail'
            ? TableFormLayout(
                title: b.sessionCode,
                busy: false,
                onSubmit: null,
                showSubmit: false,
                children: [
                  ...sessionInfo(b),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (b.status == TableSessionStatus.open &&
                          ref
                              .read(tableSessionControllerProvider(b.tableId))
                              .can('TABLE_TRANSFER'))
                        FilledButton.tonalIcon(
                          onPressed: () => showTableTransferDialog(
                            context,
                            ref,
                            sessionId: b.id,
                          ),
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Chuyển bàn'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => showTableDialog(
                          context,
                          ref,
                          permission: 'TABLE_VIEW',
                          child: TableTransferHistoryView(sessionId: b.id),
                        ),
                        icon: const Icon(Icons.history),
                        label: const Text('Lịch sử chuyển bàn'),
                      ),
                    ],
                  ),
                ],
              )
            : TableSessionForm(session: b, cancel: action == 'cancel'),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session,
        c = ref.watch(tableSessionControllerProvider(s.tableId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...sessionInfo(s),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _opening ? null : () => _action('detail'),
                  child: const Text('Chi tiết phiên'),
                ),
                if (s.status == TableSessionStatus.open && c.can('TABLE_OPEN'))
                  TextButton(
                    onPressed: _opening || c.pending('session:${s.id}')
                        ? null
                        : () => _action('edit'),
                    child: const Text('Sửa phiên'),
                  ),
                if (s.status == TableSessionStatus.open &&
                    c.can('TABLE_TRANSFER'))
                  TextButton.icon(
                    onPressed:
                        _opening ||
                            ref
                                .watch(tableEventsProvider)
                                .sessionTransferBlocked(s.id)
                        ? null
                        : () => _action('transfer'),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Chuyển bàn'),
                  ),
                TextButton(
                  onPressed: _opening ? null : () => _action('transferHistory'),
                  child: const Text('Lịch sử chuyển bàn'),
                ),
                if (s.status == TableSessionStatus.open && c.can('TABLE_CLOSE'))
                  TextButton(
                    onPressed: _opening || c.pending('session:${s.id}')
                        ? null
                        : () => _action('cancel'),
                    child: const Text('Hủy mở nhầm'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

List<Widget> sessionInfo(TableSession s) => [
  Text(
    '${s.tableCode} • ${s.tableName}',
    style: const TextStyle(fontWeight: FontWeight.bold),
  ),
  Text(s.sessionCode),
  Text(
    '${switch (s.status) {
      TableSessionStatus.open => 'Đang phục vụ',
      TableSessionStatus.cancelled => 'Đã hủy',
      TableSessionStatus.closed => 'Đã đóng',
    }} • ${s.guestCount} khách',
  ),
  Text('Mở: ${tableDate(s.openedAt)}'),
  if (s.note != null) Text('Ghi chú: ${s.note}'),
  if (s.closedAt != null) Text('Kết thúc: ${tableDate(s.closedAt!)}'),
  if (s.cancelReason != null) Text('Lý do hủy: ${s.cancelReason}'),
];

class TableSessionHistory extends ConsumerStatefulWidget {
  const TableSessionHistory({super.key, required this.tableId});
  final String tableId;
  @override
  ConsumerState<TableSessionHistory> createState() =>
      _TableSessionHistoryState();
}

class _TableSessionHistoryState extends ConsumerState<TableSessionHistory> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(tableSessionControllerProvider(widget.tableId)).load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(tableSessionControllerProvider(widget.tableId));
    return TableFormLayout(
      title: 'Lịch sử phiên phục vụ',
      busy: false,
      onSubmit: null,
      showSubmit: false,
      children: [
        DropdownButtonFormField<TableSessionStatus?>(
          isExpanded: true,
          value: c.query.sessionStatus,
          decoration: tableField('Trạng thái phiên'),
          items: [
            const DropdownMenuItem(value: null, child: Text('Tất cả')),
            for (final s in TableSessionStatus.values)
              DropdownMenuItem(
                value: s,
                child: Text(switch (s) {
                  TableSessionStatus.open => 'Đang phục vụ',
                  TableSessionStatus.cancelled => 'Đã hủy',
                  TableSessionStatus.closed => 'Đã đóng',
                }),
              ),
          ],
          onChanged: (v) =>
              c.setQuery(c.query.copyWith(sessionStatus: () => v)),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: () async {
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 366)),
                );
                if (range != null && mounted) {
                  c.setQuery(
                    c.query.copyWith(
                      openedFrom: () => range.start,
                      openedTo: () => range.end
                          .add(const Duration(days: 1))
                          .subtract(const Duration(microseconds: 1)),
                    ),
                  );
                }
              },
              child: Text(
                c.query.openedFrom == null
                    ? 'Lọc ngày mở'
                    : '${tableDate(c.query.openedFrom!)} – ${tableDate(c.query.openedTo!)}',
              ),
            ),
            if (c.query.openedFrom != null)
              TextButton(
                onPressed: () => c.setQuery(
                  c.query.copyWith(
                    openedFrom: () => null,
                    openedTo: () => null,
                  ),
                ),
                child: const Text('Bỏ lọc ngày'),
              ),
            TextButton(
              onPressed: () => c.setQuery(
                c.query.copyWith(
                  direction: c.query.direction == 'desc' ? 'asc' : 'desc',
                ),
              ),
              child: Text(
                c.query.direction == 'desc'
                    ? 'Mới nhất trước'
                    : 'Cũ nhất trước',
              ),
            ),
            IconButton(
              tooltip: 'Tải lại lịch sử',
              onPressed: c.load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (c.loading) const LinearProgressIndicator(),
        TableFailurePanel(failure: c.failure, onReload: c.load),
        if (c.hasLoaded && c.rows.isEmpty) const Text('Chưa có phiên phù hợp.'),
        for (final s in c.rows)
          TableSessionCard(key: ValueKey(s.id), session: s),
        TablePagination(
          page: c.query.page,
          pages: c.totalPages,
          total: c.totalElements,
          onPage: c.setPage,
        ),
      ],
    );
  }
}

class TableQrDialog extends ConsumerWidget {
  const TableQrDialog({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(tableQrControllerProvider(id)), q = c.value;
    return TableFormLayout(
      title: 'Quản lý QR bàn',
      busy: false,
      onSubmit: null,
      showSubmit: false,
      children: [
        if (c.loading) const LinearProgressIndicator(),
        TableFailurePanel(failure: c.failure, onReload: c.load),
        const Text(
          'Chưa cấu hình website menu công khai. Đường dẫn bên dưới là payload quản trị; chưa có chức năng mở menu công khai.',
        ),
        if (q != null) ...[
          const SizedBox(height: 16),
          const Text('QR token'),
          SelectableText(q.qrToken),
          const SizedBox(height: 12),
          const Text('Đường dẫn QR'),
          SelectableText(q.qrPath),
          Text('Version: ${q.version}'),
          FilledButton.tonal(
            onPressed: c.loading || c.pending('table:$id')
                ? null
                : () => showTableDialog(
                    context,
                    ref,
                    permission: 'TABLE_UPDATE',
                    child: TableConfirmation<TableQrPayload>(
                      title: 'Xoay mã QR?',
                      permission: 'TABLE_UPDATE',
                      initial: q,
                      describe: (_) =>
                          'Token cũ sẽ bị thay. Các bản QR đã phát hành cần được cập nhật.',
                      reload: () async {
                        await c.load();
                        return c.value != null
                            ? Success(c.value!)
                            : Error(c.failure ?? TableController.expired);
                      },
                      submit: c.rotateCurrent,
                    ),
                  ),
            child: const Text('Xoay mã QR'),
          ),
        ],
      ],
    );
  }
}
