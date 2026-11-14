import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../domain/entities/stock_audit.dart';
import '../../domain/entities/inventory_instant_range.dart';
import 'inventory_widgets.dart';
import 'stock_widgets.dart';
import 'warehouse_picker.dart';
import '../../domain/entities/inventory_entities.dart';

String stockAuditLocation(String id) =>
    '/app/inventory/audits/${Uri.encodeComponent(id)}';

Future<Warehouse?> chooseStockAuditWarehouse(
  BuildContext context,
  WidgetRef ref, {
  bool manage = false,
}) => showStockAuditDialog<Warehouse>(
  context,
  ref,
  permission: manage ? 'STOCK_AUDIT_MANAGE' : 'INVENTORY_VIEW',
  child: const WarehousePickerDialog(),
);

class StockAuditStatusBadge extends StatelessWidget {
  const StockAuditStatusBadge(this.status, {super.key});
  final StockAuditStatus status;
  @override
  Widget build(BuildContext context) => InventoryBadge(
    status.label,
    warning: status == StockAuditStatus.counting,
    positive: status == StockAuditStatus.confirmed,
  );
}

class StockAuditPageFrame extends StatelessWidget {
  const StockAuditPageFrame({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.onRefresh,
    this.showTitle = true,
  });
  final String title;

  /// False when the app bar already shows [title].
  final bool showTitle;
  final Widget child;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) {
    final scroll = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (showTitle)
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    Wrap(spacing: 8, runSpacing: 8, children: actions),
                  ],
                ),
                const SizedBox(height: 20),
                child,
              ],
            ),
          ),
        ),
      ],
    );
    return onRefresh == null
        ? scroll
        : RefreshIndicator(onRefresh: onRefresh!, child: scroll);
  }
}

/// Includes STOCK_AUDIT even for read-only dialogs whose permission is VIEW.
class StockAuditScopeGuard extends ConsumerWidget {
  const StockAuditScopeGuard({
    super.key,
    required this.scope,
    this.permission = 'INVENTORY_VIEW',
    required this.child,
  });
  final Object? scope;
  final String permission;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (scope != AccessPolicy.inventoryScope(session) ||
        !AccessPolicy.canViewStockAudits(session) ||
        !AccessPolicy.canInventory(session, permission)) {
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && route?.isActive == true) {
          Navigator.of(context).removeRoute(route!);
        }
      });
      return const SizedBox.shrink();
    }
    return child;
  }
}

Future<T?> showStockAuditDialog<T>(
  BuildContext context,
  WidgetRef ref, {
  String permission = 'INVENTORY_VIEW',
  required Widget child,
}) {
  final session = ref.read(authControllerProvider).state.session;
  if (!AccessPolicy.canViewStockAudits(session) ||
      !AccessPolicy.canInventory(session, permission)) {
    return Future.value();
  }
  final scope = AccessPolicy.inventoryScope(session);
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (_) => StockAuditScopeGuard(
      scope: scope,
      permission: permission,
      child: child,
    ),
  );
}

Future<bool> confirmAuditAction(
  BuildContext context,
  WidgetRef ref, {
  required String permission,
  required String title,
  required String message,
  required String confirm,
}) async =>
    await showStockAuditDialog<bool>(
      context,
      ref,
      permission: permission,
      child: Builder(
        builder: (context) => InventoryDialogFrame(
          title: title,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Quay lại'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirm),
            ),
          ],
          children: [Text(message)],
        ),
      ),
    ) ??
    false;

class InventoryInstantDateFilter extends ConsumerWidget {
  const InventoryInstantDateFilter({
    super.key,
    required this.range,
    required this.changed,
  });
  final InventoryInstantRange? range;
  final ValueChanged<InventoryInstantRange?> changed;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      OutlinedButton.icon(
        icon: const Icon(Icons.date_range_outlined),
        label: Text(
          range?.from == null && range?.to == null
              ? 'Khoảng ngày tạo'
              : '${range?.from == null ? '…' : stockDay(range!.from!)} – ${range?.to == null ? '…' : stockDay(range!.to!.toLocal().subtract(const Duration(days: 1)))}',
        ),
        onPressed: () async {
          final scope = ref.read(inventoryScopeProvider);
          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(1),
            lastDate: DateTime(9999, 12, 30),
            initialDateRange: range?.from == null || range?.to == null
                ? null
                : DateTimeRange(
                    start: range!.from!.toLocal(),
                    end: range!.to!.toLocal().subtract(const Duration(days: 1)),
                  ),
            helpText: 'Chọn khoảng ngày tạo',
            saveText: 'Áp dụng',
            builder: (_, child) =>
                StockAuditScopeGuard(scope: scope, child: child!),
          );
          if (context.mounted &&
              picked != null &&
              scope == ref.read(inventoryScopeProvider)) {
            changed(InventoryInstantRange.days(picked.start, picked.end));
          }
        },
      ),
      if (range != null)
        IconButton(
          tooltip: 'Bỏ lọc ngày',
          onPressed: () => changed(null),
          icon: const Icon(Icons.close),
        ),
    ],
  );
}

/// Explains why the server refused to confirm a counting session whose stock
/// moved after it started. Pops `true` when staff choose to recount.
class StockAuditStaleDialog extends StatelessWidget {
  const StockAuditStaleDialog({super.key, required this.canCancel});

  /// Staff may cancel the session here; otherwise a manager has to.
  final bool canCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget fact(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
    return AlertDialog(
      key: const ValueKey('stock-audit-stale-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      scrollable: true,
      icon: Icon(Icons.sync_problem_outlined, color: scheme.tertiary),
      title: const Text('Chưa chốt được kiểm kê'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Trong lúc đếm, kho đã có nhập, xuất hoặc bếp đã dùng nguyên '
              'liệu. Số đã đếm không còn khớp với tồn lúc bắt đầu nên hệ '
              'thống không chốt, tránh làm lệch kho.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  fact(Icons.inventory_2_outlined, 'Tồn kho chưa bị thay đổi.'),
                  fact(
                    Icons.fact_check_outlined,
                    'Số đã đếm vẫn được giữ để xem lại.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              canCancel
                  ? 'Hãy hủy phiên này và đếm lại ở phiên mới, nên làm lúc '
                        'ít đơn.'
                  : 'Người quản lý kiểm kê cần hủy phiên này để đếm lại ở '
                        'phiên mới.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      actions: canCancel
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Để sau'),
              ),
              FilledButton(
                key: const ValueKey('stock-audit-stale-recount'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Hủy phiên, đếm lại'),
              ),
            ]
          : [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Đã hiểu'),
              ),
            ],
    );
  }
}

/// Stays on the page after the dialog is closed, so the disabled confirm
/// button never goes unexplained.
class StockAuditStaleNotice extends StatelessWidget {
  const StockAuditStaleNotice({super.key, required this.onOpen});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const ValueKey('stock-audit-stale-notice'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_problem_outlined, size: 20, color: scheme.tertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Phiên này không chốt được vì tồn kho đã thay đổi trong lúc đếm.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton(onPressed: onOpen, child: const Text('Xử lý')),
        ],
      ),
    );
  }
}
