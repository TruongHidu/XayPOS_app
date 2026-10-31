import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../domain/entities/stock_audit.dart';
import '../controllers/stock_audit_detail_controller.dart';
import '../widgets/inventory_widgets.dart';
import '../widgets/stock_audit_count_sheet.dart';
import '../widgets/stock_audit_widgets.dart';
import '../widgets/stock_widgets.dart';

class StockAuditDetailScreen extends ConsumerWidget {
  const StockAuditDetailScreen({super.key, required this.id});
  final String id;
  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final c = ref.read(stockAuditDetailProvider(id));
    if (!c.headerEditable || c.audit?.status != StockAuditStatus.draft) return;
    if (await confirmAuditAction(
      context,
      ref,
      permission: 'STOCK_AUDIT_MANAGE',
      title: 'Bắt đầu kiểm kê?',
      message:
          '${c.audit!.auditCode} · ${c.audit!.warehouseName}\n\nHệ thống chốt toàn bộ nguyên liệu được theo dõi, gồm cả nguyên liệu ngừng hoạt động. Kho vẫn có thể phát sinh giao dịch; nhập, xuất hoặc chế biến có thể khiến bạn phải hủy phiên và đếm lại. Nên kiểm kê lúc ít giao dịch.',
      confirm: 'Bắt đầu kiểm kê',
    )) {
      await c.startCounting();
    }
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    final c = ref.read(stockAuditDetailProvider(id));
    if (!c.canPost) return;
    final a = c.audit!;
    if (await confirmAuditAction(
      context,
      ref,
      permission: 'STOCK_AUDIT_CONFIRM',
      title: 'Chốt kiểm kê?',
      message:
          '${a.auditCode}\n${a.warehouseName} · ${a.warehouseCode}\nĐã đếm ${a.countedItemCount}/${a.itemCount} · ${a.changedItemCount} dòng chênh lệch\n\nThao tác có thể điều chỉnh tồn vật lý bằng chứng từ tự động. Máy chủ sẽ kiểm tra tồn đang giữ và biến động kể từ lúc bắt đầu. Phiên đã chốt chỉ đọc.',
      confirm: 'Chốt kiểm kê',
    )) {
      await c.post();
    }
  }

  Future<void> _note(
    BuildContext context,
    WidgetRef ref, {
    bool cancel = false,
  }) async {
    final c = ref.read(stockAuditDetailProvider(id));
    if (!c.headerEditable) return;
    await showStockAuditDialog<bool>(
      context,
      ref,
      permission: 'STOCK_AUDIT_MANAGE',
      child: _AuditNoteEditor(
        auditId: id,
        cancel: cancel,
        initial: cancel ? '' : c.headerNoteDraft ?? c.audit!.note ?? '',
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canViewStockAudits(session)) {
      return const Center(
        child: Text('Bạn chưa có quyền hoặc tính năng xem kiểm kê kho.'),
      );
    }
    final c = ref.watch(stockAuditDetailProvider(id)), a = c.audit;
    final page = StockAuditPageFrame(
      title: a?.auditCode ?? 'Chi tiết kiểm kê',
      onRefresh: c.load,
      actions: [
        IconButton(
          tooltip: 'Tải lại kiểm kê, giữ bản nhập',
          onPressed: c.busy || c.loading ? null : c.load,
          icon: const Icon(Icons.refresh),
        ),
        if (c.headerEditable)
          OutlinedButton.icon(
            onPressed: () => _note(context, ref),
            icon: const Icon(Icons.edit_note),
            label: const Text('Sửa ghi chú'),
          ),
        if (c.headerEditable && a?.status == StockAuditStatus.draft)
          FilledButton.icon(
            onPressed: () => _start(context, ref),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Bắt đầu kiểm kê'),
          ),
        if (c.canConfirm && a?.status == StockAuditStatus.counting)
          FilledButton.icon(
            onPressed: c.canPost ? () => _confirm(context, ref) : null,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Chốt kiểm kê'),
          ),
        if (c.headerEditable)
          TextButton.icon(
            onPressed: () => _note(context, ref, cancel: true),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Hủy phiên'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.loading || c.busy) const LinearProgressIndicator(),
          InventoryFailurePanel(
            failure: c.failure,
            retry: c.busy
                ? null
                : c.requiresReview
                ? c.verify
                : c.load,
          ),
          if (c.notice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                c.notice!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          if (c.requiresReview) _AuditReview(controller: c),
          if (c.snapshotStale)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Tồn kho đã thay đổi kể từ lúc bắt đầu nên phiên này không thể chốt. Số đếm được giữ để tham khảo; hãy hủy phiên và tạo phiên kiểm kê mới để đếm lại.',
                ),
              ),
            ),
          if (a != null) ...[
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StockAuditStatusBadge(a.status),
                        InventoryBadge(
                          'Đã đếm ${a.countedItemCount}/${a.itemCount}',
                        ),
                        InventoryBadge(
                          '${a.changedItemCount} dòng chênh lệch',
                          warning: a.changedItemCount > 0,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${a.warehouseName} · ${a.warehouseCode}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (a.itemCount > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: LinearProgressIndicator(
                          value: a.countedItemCount / a.itemCount,
                          minHeight: 8,
                        ),
                      ),
                    if (a.note != null) Text(a.note!),
                    Text(
                      'Tạo: ${formatLocalDate(a.createdAt)} · ${a.createdBy}',
                    ),
                    if (a.startedAt != null)
                      Text(
                        'Bắt đầu: ${formatLocalDate(a.startedAt!)} · ${a.startedBy ?? '—'}',
                      ),
                    if (a.confirmedAt != null)
                      Text(
                        'Chốt: ${formatLocalDate(a.confirmedAt!)} · ${a.confirmedBy ?? '—'}',
                      ),
                    if (a.cancelledAt != null)
                      Text(
                        'Hủy: ${formatLocalDate(a.cancelledAt!)} · ${a.cancelledBy ?? '—'}',
                      ),
                    if (a.status == StockAuditStatus.confirmed) ...[
                      const SizedBox(height: 12),
                      if (a.adjustmentDocumentId != null)
                        OutlinedButton.icon(
                          onPressed: () => context.push(
                            stockDetailLocation(a.adjustmentDocumentId!),
                          ),
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: Text(
                            'Xem chứng từ điều chỉnh ${a.adjustmentDocumentCode ?? ''}',
                          ),
                        )
                      else
                        const Text(
                          'Số đếm khớp hệ thống, không phát sinh điều chỉnh.',
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (a.status == StockAuditStatus.draft)
              const Text(
                'Phiên nháp chưa có bảng số đếm. Nhấn “Bắt đầu kiểm kê” để chốt phạm vi và dữ liệu hệ thống.',
              )
            else ...[
              if (a.status == StockAuditStatus.counting &&
                  c.stockMayHaveChanged)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Trong lúc đếm có đơn hàng hoặc phiếu kho mới. Bạn cứ đếm tiếp; hệ thống sẽ tự kiểm tra lại khi chốt.',
                  ),
                ),
              if (a.status == StockAuditStatus.counting &&
                  c.canConfirm &&
                  !c.canPost)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    c.dirty
                        ? 'Lưu hết bản nhập trước khi chốt kiểm kê.'
                        : a.countedItemCount != a.itemCount
                        ? 'Còn dòng chưa đếm trên toàn phiên. Dùng bộ lọc “Chưa đếm” để tìm.'
                        : 'Chưa thể chốt khi đang tải, xử lý hoặc cần đối chiếu dữ liệu.',
                  ),
                ),
              StockAuditCountSheet(auditId: id),
            ],
          ],
        ],
      ),
    );
    return Column(
      children: [
        Expanded(child: page),
        if (c.dirty)
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${c.dirtyCount} dòng chưa lưu${c.headerNoteDraft != null ? ' · Có ghi chú chưa lưu' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('audit-save-drafts'),
                      onPressed: c.canSaveDrafts ? c.saveDrafts : null,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Lưu bản nhập'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AuditReview extends ConsumerWidget {
  const _AuditReview({required this.controller});
  final StockAuditDetailController controller;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = controller;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Cần đối chiếu dữ liệu',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Số bạn đã nhập vẫn được giữ. Hãy tải lại để xem dữ liệu mới nhất trước khi tiếp tục.',
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: c.busy ? null : c.verify,
                  icon: const Icon(Icons.sync),
                  label: const Text('Tải và đối chiếu'),
                ),
                if (c.hasCompared && c.pendingCommand == null)
                  FilledButton(
                    onPressed: c.busy ? null : c.acknowledgeReview,
                    child: const Text('Đã đối chiếu, tiếp tục'),
                  ),
                if (c.hasCompared &&
                    c.pendingCommand != null &&
                    {
                      StockAuditCommand.start,
                      StockAuditCommand.confirm,
                      StockAuditCommand.cancel,
                    }.contains(c.pendingCommand!.kind))
                  FilledButton(
                    onPressed: c.busy ? null : c.retryPendingTransition,
                    child: const Text('Thử lại đúng yêu cầu ban đầu'),
                  ),
                if (c.hasCompared &&
                    c.pendingCommand != null &&
                    {
                      StockAuditCommand.counts,
                      StockAuditCommand.note,
                    }.contains(c.pendingCommand!.kind))
                  OutlinedButton(
                    onPressed: c.busy
                        ? null
                        : () async {
                            if (await confirmAuditAction(
                              context,
                              ref,
                              permission: 'STOCK_AUDIT_MANAGE',
                              title: 'Đã đối chiếu bản nhập?',
                              message:
                                  'Chưa xác nhận được lần lưu vừa rồi đã áp dụng hay chưa. Chỉ tiếp tục sau khi đã đối chiếu các dòng và ghi chú với dữ liệu máy chủ. Thao tác này giữ bản nhập và không tự gửi lại.',
                              confirm: 'Đã đối chiếu, giữ bản nhập',
                            )) {
                              c.acknowledgeUnappliedPatch();
                            }
                          },
                    child: const Text('Tiếp tục sửa sau đối chiếu'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditNoteEditor extends ConsumerStatefulWidget {
  const _AuditNoteEditor({
    required this.auditId,
    required this.initial,
    required this.cancel,
  });
  final String auditId, initial;
  final bool cancel;
  @override
  ConsumerState<_AuditNoteEditor> createState() => _AuditNoteEditorState();
}

class _AuditNoteEditorState extends ConsumerState<_AuditNoteEditor> {
  late final TextEditingController _note = TextEditingController(
    text: widget.initial,
  );
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(stockAuditDetailProvider(widget.auditId));
    return InventoryDialogFrame(
      title: widget.cancel ? 'Hủy phiên kiểm kê?' : 'Sửa ghi chú kiểm kê',
      busy: c.busy,
      actions: [
        FilledButton(
          onPressed: !c.headerEditable
              ? null
              : () async {
                  final response = widget.cancel
                      ? await c.cancelAudit(_note.text)
                      : await c.saveNote(_note.text);
                  if (context.mounted && response is Success) {
                    Navigator.of(context).pop(true);
                  }
                },
          child: Text(widget.cancel ? 'Xác nhận hủy phiên' : 'Lưu ghi chú'),
        ),
      ],
      children: [
        if (widget.cancel)
          Text(
            'Hủy phiên không thay đổi tồn và vẫn giữ bảng số đếm đã lưu.${c.dirty ? ' ${c.dirtyCount} dòng đang nhập chưa lưu sẽ được bỏ sau khi hủy thành công.' : ''} Để trống ghi chú sẽ giữ ghi chú cũ.',
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          enabled: !c.busy,
          minLines: 2,
          maxLines: 6,
          maxLength: 2000,
          onChanged: widget.cancel ? null : c.setHeaderNoteDraft,
          decoration: inventoryField(
            widget.cancel
                ? 'Lý do / ghi chú (tùy chọn)'
                : 'Ghi chú (để trống để xóa)',
          ),
        ),
        InventoryFailurePanel(failure: c.failure),
        if (c.requiresReview)
          const Text(
            'Đóng cửa sổ để đối chiếu dữ liệu. Ghi chú đang soạn được giữ để bạn mở lại và tiếp tục.',
          ),
      ],
    );
  }
}
