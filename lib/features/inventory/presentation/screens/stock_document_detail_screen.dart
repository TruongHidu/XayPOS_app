import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../domain/entities/stock_document.dart';
import '../../domain/entities/stock_inputs.dart';
import '../widgets/inventory_widgets.dart';
import '../widgets/stock_widgets.dart';
import '../widgets/stock_document_forms.dart';
import '../widgets/stock_ingredient_picker.dart';

/// Shows the stock document detail as a slide-up overlay covering 80% of the screen.
Future<void> showStockDocumentDetailOverlay(
  BuildContext context,
  WidgetRef ref, {
  required String documentId,
}) {
  final session = ref.read(authControllerProvider).state.session;
  if (!AccessPolicy.canInventory(session, 'INVENTORY_VIEW')) {
    return Future.value();
  }
  final scope = ref.read(inventoryScopeProvider);
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Đóng chi tiết chứng từ',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      final size = MediaQuery.sizeOf(context);
      final isWide = size.width > 1200;
      return Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: isWide ? 1160 : double.infinity,
          height: size.height * 0.8,
          child: _StockDetailOverlay(
            key: ValueKey(('stock-detail-overlay', scope, documentId)),
            id: documentId,
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curvedAnimation),
        child: child,
      );
    },
  );
}

class _StockDetailOverlay extends ConsumerStatefulWidget {
  const _StockDetailOverlay({super.key, required this.id});
  final String id;
  @override
  ConsumerState<_StockDetailOverlay> createState() =>
      _StockDetailOverlayState();
}

class _StockDetailOverlayState extends ConsumerState<_StockDetailOverlay> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(stockDocumentDetailProvider(widget.id)).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailState = ref.watch(stockDocumentDetailProvider(widget.id));
    final doc = detailState.document;

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with drag handle and swipe-down to dismiss
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (details) {
              if ((details.primaryVelocity ?? 0) > 200) {
                Navigator.of(context).pop();
              }
            },
            child: Container(
              color: theme.colorScheme.surface,
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      doc?.documentCode ?? 'Chi tiết chứng từ',
                                      style: theme.textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (doc?.status != null) ...[
                                    const SizedBox(width: 8),
                                    StockStatusBadge(doc!.status),
                                  ],
                                ],
                              ),
                              if (doc != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '${doc.warehouseName} · ${formatLocalDate(doc.createdAt)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Tải lại',
                          onPressed: detailState.loading || detailState.busy
                              ? null
                              : () => ref
                                  .read(stockDocumentDetailProvider(widget.id))
                                  .load(),
                          icon: const Icon(Icons.refresh),
                        ),
                        IconButton(
                          tooltip: 'Đóng',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          // Scrollable body taking the remaining 80% height
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _StockDetailBody(id: widget.id),
            ),
          ),
        ],
      ),
    );
  }
}

class StockDocumentDetailScreen extends ConsumerWidget {
  const StockDocumentDetailScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(inventoryScopeProvider);
    if (!AccessPolicy.canInventory(
      ref.watch(authControllerProvider).state.session,
      'INVENTORY_VIEW',
    )) {
      return const Center(child: Text('Bạn chưa có quyền xem chứng từ.'));
    }
    return _StockDetailWorkspace(key: ValueKey((scope, id)), id: id);
  }
}

class _StockDetailWorkspace extends ConsumerWidget {
  const _StockDetailWorkspace({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(stockDocumentDetailProvider(id));
    return StockPageFrame(
      title: c.document?.documentCode ?? 'Chi tiết chứng từ',
      onRefresh: c.load,
      actions: [
        OutlinedButton(
          onPressed: () => context.go('/app/inventory/stock-documents'),
          child: const Text('Danh sách chứng từ'),
        ),
        IconButton(
          tooltip: 'Tải lại chi tiết',
          onPressed: c.loading || c.busy ? null : c.load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: _StockDetailBody(id: id),
    );
  }
}

// ── Shared detail body used by both the full screen and overlay ──────────

Future<void> _editNote(BuildContext context, WidgetRef ref, String id) async {
  final c = ref.read(stockDocumentDetailProvider(id));
  await c.load();
  if (!context.mounted || !c.current || !c.editable) return;
  final saved = await showInventoryDialog<bool>(
    context,
    ref,
    permission: c.document!.type.permission,
    child: StockNoteEditor(baseline: c.document!),
  );
  if (context.mounted && saved == true) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã lưu ghi chú.')));
  }
}

Future<void> _editLine(
  BuildContext context,
  WidgetRef ref,
  String id, {
  String? itemId,
}) async {
  final c = ref.read(stockDocumentDetailProvider(id));
  await c.load();
  if (!context.mounted || !c.current || !c.editable) return;
  final baseline = c.document!,
      row = itemId == null
          ? null
          : c.document!.items.where((r) => r.id == itemId).firstOrNull;
  if (itemId != null && row == null) return;
  final ingredient = row != null
      ? null
      : await pickStockIngredient(
          context,
          ref,
          warehouseId: baseline.warehouseId,
          type: baseline.type,
          excluded: baseline.items.map((r) => r.ingredientId).toSet(),
        );
  if (!context.mounted || !c.current || row == null && ingredient == null) {
    return;
  }
  final saved = await showInventoryDialog<bool>(
    context,
    ref,
    permission: baseline.type.permission,
    child: StockLineEditor(
      type: baseline.type,
      ingredientId: row?.ingredientId ?? ingredient!.ingredientId,
      name: row?.ingredientName ?? ingredient!.ingredientName,
      unit: row?.unit ?? ingredient!.baseUnit,
      sku: row?.ingredientSku ?? ingredient?.ingredientSku,
      baseline: baseline,
      itemId: itemId,
      initial: row == null
          ? null
          : StockLineInput(
              ingredientId: row.ingredientId,
              quantity: row.quantity,
              unitCost: row.unitCost,
              direction: row.direction,
              note: row.note,
            ),
    ),
  );
  if (context.mounted && saved == true) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đã lưu dòng nguyên liệu.')));
  }
}

Future<void> _deleteLine(
  BuildContext context,
  WidgetRef ref,
  String id,
  String item,
) async {
  final c = ref.read(stockDocumentDetailProvider(id));
  await c.load();
  if (!context.mounted || !c.current || !c.editable) return;
  final baseline = c.document!,
      row = c.document!.items.where((r) => r.id == item).firstOrNull;
  if (row == null) return;
  if (!await confirmStockAction(
    context,
    ref,
    permission: baseline.type.permission,
    title: 'Xóa dòng nguyên liệu?',
    message:
        'Xóa ${row.ingredientName} khỏi phiếu ${baseline.documentCode}? Phiếu vẫn là nháp và chưa thay đổi tồn.',
    confirm: 'Xóa dòng',
  )) {
    return;
  }
  if (!context.mounted || !c.current) return;
  final response = await c.deleteLine(baseline, item);
  if (context.mounted && response is Success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          c.needsRead
              ? 'Đã xóa dòng. Cần tải lại để kiểm tra version.'
              : 'Đã xóa dòng.',
        ),
      ),
    );
  }
}

Future<void> _transition(
  BuildContext context,
  WidgetRef ref,
  String id,
  bool posting,
) async {
  final c = ref.read(stockDocumentDetailProvider(id));
  await c.load();
  if (!context.mounted || !c.current || !c.editable) return;
  final d = c.document!;
  if (!await confirmStockAction(
    context,
    ref,
    permission: d.type.permission,
    title: posting ? 'Xác nhận chứng từ?' : 'Hủy phiếu nháp?',
    message: posting
        ? '${d.documentCode}\n${d.type.label} · ${d.warehouseName} (${d.warehouseCode})\n${d.lineCount} dòng · Giá trị: ${stockDisplay(d.totalCost)}\n\nXác nhận sẽ ghi nhận ${d.type == StockDocumentType.adjustment
              ? 'tăng/giảm theo từng dòng'
              : d.type == StockDocumentType.receipt
              ? 'tăng tồn'
              : 'giảm tồn'}. Một dòng không hợp lệ sẽ hủy toàn bộ lần ghi nhận. Phiếu đã xác nhận không còn sửa hoặc hủy được.'
        : 'Hủy phiếu ${d.documentCode} tại ${d.warehouseName}? Phiếu nháp bị hủy không làm thay đổi tồn kho.',
    confirm: posting ? 'Xác nhận ghi nhận tồn' : 'Hủy phiếu',
  )) {
    return;
  }
  if (!context.mounted || !c.current) return;
  final response = await c.transition(d, posting: posting);
  if (context.mounted && response is Success) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(posting ? 'Đã xác nhận chứng từ.' : 'Đã hủy phiếu nháp.'),
      ),
    );
  }
}

class _StockDetailBody extends ConsumerWidget {
  const _StockDetailBody({required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(stockDocumentDetailProvider(id)), d = c.document;
    Widget actions(StockDocumentItem row) => Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        TextButton.icon(
          onPressed: c.editable
              ? () => _editLine(context, ref, id, itemId: row.id)
              : null,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Sửa dòng'),
        ),
        TextButton.icon(
          onPressed: c.editable
              ? () => _deleteLine(context, ref, id, row.id)
              : null,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Xóa dòng'),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.loading || c.busy) const LinearProgressIndicator(),
        InventoryFailurePanel(
          failure: c.failure,
          retry: c.loading || c.busy ? null : c.load,
          label: 'Tải lại để đối chiếu',
        ),
        if (c.requiresReview)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Chưa xác minh dữ liệu mới nhất. Các thao tác lưu bị khóa cho đến khi tải lại đúng phiếu.',
            ),
          ),
        if (d != null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InventoryBadge(d.type.label),
              StockStatusBadge(d.status),
            ],
          ),
          const SizedBox(height: 16),
          ResponsiveColumns(
            minColumnWidth: 260,
            maxColumns: 3,
            spacing: 12,
            children: [
              Text('Kho: ${d.warehouseName}\n${d.warehouseCode}'),
              Text(
                'Số dòng: ${d.lineCount}\nTổng giá trị: ${stockDisplay(d.totalCost)}',
              ),
              Text(
                'Tạo: ${formatLocalDate(d.createdAt)}\nCập nhật: ${formatLocalDate(d.updatedAt)}',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Người tạo: ${d.createdBy}'),
          if (d.confirmedAt != null)
            Text(
              'Xác nhận: ${formatLocalDate(d.confirmedAt!)} · ${d.confirmedBy}',
            ),
          if (d.cancelledAt != null)
            Text('Hủy: ${formatLocalDate(d.cancelledAt!)} · ${d.cancelledBy}'),
          const SizedBox(height: 12),
          Text('Ghi chú: ${d.note ?? '—'}'),
          if (d.stockAuditId != null) ...[
            const SizedBox(height: 12),
            const InventoryBadge('Sinh từ kiểm kê — chỉ đọc'),
            if (AccessPolicy.canViewStockAudits(
              ref.watch(authControllerProvider).state.session,
            ))
              TextButton.icon(
                onPressed: () => context.go(
                  '/app/inventory/audits/${Uri.encodeComponent(d.stockAuditId!)}',
                ),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Xem phiên kiểm kê'),
              ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (d.stockAuditId == null &&
                  d.status == StockDocumentStatus.draft &&
                  c.can(d.type.permission)) ...[
                OutlinedButton(
                  onPressed: c.editable
                      ? () => _editNote(context, ref, id)
                      : null,
                  child: const Text('Sửa ghi chú'),
                ),
                OutlinedButton.icon(
                  onPressed: c.editable
                      ? () => _editLine(context, ref, id)
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm nguyên liệu'),
                ),
                FilledButton.icon(
                  onPressed: c.editable && d.items.isNotEmpty
                      ? () => _transition(context, ref, id, true)
                      : null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Xác nhận chứng từ'),
                ),
                TextButton(
                  onPressed: c.editable
                      ? () => _transition(context, ref, id, false)
                      : null,
                  child: const Text('Hủy phiếu nháp'),
                ),
              ],
              if (d.status == StockDocumentStatus.confirmed)
                OutlinedButton.icon(
                  onPressed: () => context.go(
                    stockHistoryLocation(
                      documentId: d.id,
                      warehouseId: d.warehouseId,
                    ),
                  ),
                  icon: const Icon(Icons.history),
                  label: const Text('Xem biến động'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (d.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Phiếu chưa có nguyên liệu. Bổ sung ít nhất một dòng trước khi xác nhận.',
              ),
            ),
          LayoutBuilder(
            builder: (context, box) {
              final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
              if (box.maxWidth >= 1100 && scale <= 1.3) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: box.maxWidth),
                    child: DataTable(
                      dataRowMinHeight: 80,
                      dataRowMaxHeight: 120,
                      headingRowColor: WidgetStatePropertyAll(
                        Theme.of(context).colorScheme.surfaceContainerLow,
                      ),
                      columns: [
                        const DataColumn(label: Text('Nguyên liệu')),
                        const DataColumn(label: Text('Số lượng / Đơn vị')),
                        if (d.type == StockDocumentType.adjustment)
                          const DataColumn(label: Text('Hướng')),
                        const DataColumn(label: Text('Đơn giá')),
                        const DataColumn(label: Text('Thành tiền')),
                        const DataColumn(label: Text('Ghi chú')),
                        if (d.stockAuditId == null &&
                            d.status == StockDocumentStatus.draft &&
                            c.can(d.type.permission))
                          const DataColumn(label: Text('Thao tác')),
                      ],
                      rows: [
                        for (final row in d.items)
                          DataRow(
                            key: ValueKey('stock-line-${row.id}'),
                            cells: [
                              DataCell(
                                SizedBox(
                                  width: 220,
                                  child: Text(
                                    '${row.ingredientName}\n${row.ingredientSku ?? 'Chưa có SKU'}',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(inventoryAmount(row.quantity, row.unit)),
                              ),
                              if (d.type == StockDocumentType.adjustment)
                                DataCell(
                                  InventoryBadge(
                                    row.direction!.label,
                                    warning:
                                        row.direction ==
                                        AdjustmentDirection.decrease,
                                  ),
                                ),
                              DataCell(Text(stockDisplay(row.unitCost))),
                              DataCell(Text(stockDisplay(row.totalCost))),
                              DataCell(
                                SizedBox(
                                  width: 180,
                                  child: Tooltip(
                                    message: row.note ?? '',
                                    child: Text(
                                      row.note ?? '—',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
                              if (d.stockAuditId == null &&
                                  d.status == StockDocumentStatus.draft &&
                                  c.can(d.type.permission))
                                DataCell(actions(row)),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              }
              return ResponsiveColumns(
                minColumnWidth: 330 * scale.clamp(1, 1.5),
                maxColumns: 3,
                spacing: 12,
                children: [
                  for (final row in d.items)
                    Card(
                      key: ValueKey('stock-line-${row.id}'),
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.ingredientName,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(row.ingredientSku ?? 'Chưa có SKU'),
                            const SizedBox(height: 12),
                            Text(
                              'Số lượng: ${inventoryAmount(row.quantity, row.unit)}',
                            ),
                            Text('Đơn giá: ${stockDisplay(row.unitCost)}'),
                            Text('Thành tiền: ${stockDisplay(row.totalCost)}'),
                            if (row.direction != null)
                              InventoryBadge(
                                row.direction!.label,
                                warning:
                                    row.direction ==
                                    AdjustmentDirection.decrease,
                              ),
                            if (row.note != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(row.note!),
                              ),
                            if (d.stockAuditId == null &&
                                d.status == StockDocumentStatus.draft &&
                                c.can(d.type.permission))
                              actions(row),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}
