import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/result/result.dart';
import '../../domain/entities/table_entities.dart';
import '../providers/tables_providers.dart';
import 'table_area_picker.dart';
import 'table_dialogs.dart';

Future<TableSessionTransferResult?> showTableTransferDialog(
  BuildContext context,
  WidgetRef ref, {
  required String sessionId,
}) async {
  final value = await showTableDialog<TableSessionTransferResult>(
    context,
    ref,
    permission: 'TABLE_TRANSFER',
    child: TableTransferDialog(sessionId: sessionId),
  );
  if (value != null && context.mounted) {
    final session = value.session;
    final message = value.replayed == true
        ? 'Đã đối chiếu yêu cầu. Phiên hiện ở ${session.tableCode} • ${session.tableName}.'
        : 'Đã chuyển phiên đến ${session.tableCode} • ${session.tableName}.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
  return value;
}

class TableTransferDialog extends ConsumerStatefulWidget {
  const TableTransferDialog({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<TableTransferDialog> createState() =>
      _TableTransferDialogState();
}

class _TableTransferDialogState extends ConsumerState<TableTransferDialog> {
  late final TextEditingController _reason;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(
      tableTransferControllerProvider(widget.sessionId),
    );
    _reason = TextEditingController(text: controller.reason);
    if (!controller.uncertain) Future.microtask(controller.loadContext);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = ref.read(
      tableTransferControllerProvider(widget.sessionId),
    );
    final response = controller.uncertain
        ? await controller.retry()
        : await controller.submit();
    if (!mounted) return;
    if (response case Success(value: final value)) {
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(
      tableTransferControllerProvider(widget.sessionId),
    );
    final session = controller.currentSession;
    final selected = controller.selected;
    final uncertain = controller.uncertain;
    return TableFormLayout(
      title: 'Chuyển bàn',
      busy: controller.busy,
      onSubmit: uncertain
          ? (controller.canRetry ? _submit : null)
          : (controller.canSubmit ? _submit : null),
      submitLabel: uncertain ? 'Thử lại yêu cầu cũ' : 'Xác nhận chuyển bàn',
      children: [
        if (controller.sessionLoading || controller.targetsLoading)
          const LinearProgressIndicator(),
        TableFailurePanel(
          failure: controller.sessionFailure,
          onReload: uncertain ? null : controller.loadSession,
        ),
        TableFailurePanel(
          failure: controller.targetsFailure,
          onReload: uncertain ? null : controller.loadTargets,
        ),
        TableFailurePanel(
          failure: controller.failure,
          onReload: uncertain ? null : controller.loadContext,
        ),
        if (uncertain)
          _Notice(
            text:
                'Chưa xác định lần chuyển trước đã thành công hay chưa. Bàn đích, version và lý do đã được khóa. Hãy thử lại đúng yêu cầu cũ.',
          ),
        if (controller.conflictingMutation && !uncertain)
          const _Notice(
            text:
                'Phiên đang có thao tác tạo, sửa hoặc gọi thêm món. Hãy hoàn tất thao tác đó trước khi chuyển bàn.',
          ),
        if (session != null) ...[
          Text(
            'Bàn hiện tại: ${session.tableCode} • ${session.tableName}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('${session.sessionCode} • ${session.guestCount} khách'),
          if (session.status != TableSessionStatus.open && !uncertain)
            const _Notice(
              text: 'Chỉ phiên đang phục vụ mới có thể chuyển bàn.',
            ),
          const SizedBox(height: 16),
          AbsorbPointer(
            absorbing: controller.frozen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  onChanged: controller.search,
                  decoration: tableField(
                    'Tìm bàn trống',
                    helper: 'Tìm theo mã hoặc tên bàn.',
                  ).copyWith(prefixIcon: const Icon(Icons.search)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final value = await pickTableArea(
                          context,
                          ref,
                          activeOnly: true,
                        );
                        if (mounted && value != null) {
                          controller.filterArea(value.area);
                        }
                      },
                      icon: const Icon(Icons.filter_alt_outlined),
                      label: Text(
                        controller.query.areaId == null
                            ? 'Tất cả khu vực'
                            : 'Đổi khu vực',
                      ),
                    ),
                    if (controller.query.areaId != null)
                      TextButton(
                        onPressed: () => controller.filterArea(null),
                        child: const Text('Bỏ lọc'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!controller.targetsLoading &&
              controller.targetsFailure == null &&
              controller.targets.isEmpty)
            Text(
              controller.query.q.trim().isEmpty &&
                      controller.query.areaId == null
                  ? 'Hiện không có bàn trống phù hợp.'
                  : 'Không có kết quả phù hợp với bộ lọc.',
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 600
                  ? 3
                  : constraints.maxWidth >= 360
                  ? 2
                  : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: controller.targets.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: columns == 1 ? 2.5 : 1.7,
                ),
                itemBuilder: (_, index) {
                  final table = controller.targets[index];
                  final active = selected?.id == table.id;
                  return InkWell(
                    onTap: controller.frozen
                        ? null
                        : () => controller.select(table),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: active
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerLow,
                        border: Border.all(
                          color: active
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${table.code} • ${table.name}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(table.area?.name ?? 'Không thuộc khu vực'),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
          TablePagination(
            page: controller.query.page,
            pages: controller.totalPages,
            total: controller.totalElements,
            onPage: controller.setPage,
          ),
          if (selected != null) ...[
            const SizedBox(height: 12),
            Text(
              'Đã chọn: ${selected.code} • ${selected.name}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            enabled: !controller.frozen,
            onChanged: controller.setReason,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: tableField(
              'Lý do chuyển (không bắt buộc)',
              error: controller.failure?.fieldErrors['reason'],
            ),
          ),
        ],
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text),
  );
}

class TableTransferHistoryView extends ConsumerStatefulWidget {
  const TableTransferHistoryView({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<TableTransferHistoryView> createState() =>
      _TableTransferHistoryViewState();
}

class _TableTransferHistoryViewState
    extends ConsumerState<TableTransferHistoryView> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(tableTransferHistoryControllerProvider(widget.sessionId))
          .load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(
      tableTransferHistoryControllerProvider(widget.sessionId),
    );
    return TableFormLayout(
      title: 'Lịch sử chuyển bàn',
      busy: false,
      onSubmit: null,
      showSubmit: false,
      children: [
        if (controller.loading) const LinearProgressIndicator(),
        TableFailurePanel(
          failure: controller.failure,
          onReload: controller.load,
        ),
        if (controller.hasLoaded && controller.rows.isEmpty)
          const Text('Phiên này chưa có lịch sử chuyển bàn.'),
        for (final entry in controller.rows)
          Card(
            child: ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(
                '${entry.fromTable.code} • ${entry.fromTable.name}  →  '
                '${entry.toTable.code} • ${entry.toTable.name}',
              ),
              subtitle: Text(
                '${tableDate(entry.transferredAt)}\n'
                'Người chuyển: ${entry.actorUserId}'
                '${entry.reason == null ? '' : '\nLý do: ${entry.reason}'}',
              ),
              isThreeLine: true,
            ),
          ),
        TablePagination(
          page: controller.page,
          pages: controller.totalPages,
          total: controller.totalElements,
          onPage: controller.setPage,
        ),
      ],
    );
  }
}
