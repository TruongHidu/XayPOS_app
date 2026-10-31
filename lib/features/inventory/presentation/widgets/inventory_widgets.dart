import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/ui/widgets/filter_panel_button.dart';
import '../../domain/entities/inventory_quantity.dart';

Future<T?> showInventoryDialog<T>(
  BuildContext context,
  WidgetRef ref, {
  String permission = 'INVENTORY_VIEW',
  required Widget child,
}) {
  final session = ref.read(authControllerProvider).state.session;
  if (!AccessPolicy.canInventory(session, 'INVENTORY_VIEW') ||
      !AccessPolicy.canInventory(session, permission)) {
    return Future.value();
  }
  final scope = AccessPolicy.inventoryScope(session);
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        InventoryScopeGuard(scope: scope, permission: permission, child: child),
  );
}

class InventoryScopeGuard extends ConsumerWidget {
  const InventoryScopeGuard({
    super.key,
    required this.scope,
    required this.permission,
    required this.child,
  });
  final Object? scope;
  final String permission;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (scope != AccessPolicy.inventoryScope(session) ||
        !AccessPolicy.canInventory(session, 'INVENTORY_VIEW') ||
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

class InventoryDialogFrame extends StatelessWidget {
  const InventoryDialogFrame({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.busy = false,
    this.canClose = true,
  });
  final String title;
  final List<Widget> children, actions;
  final bool busy, canClose;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && canClose,
    child: Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Đóng',
                      onPressed: busy || !canClose
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (busy) const LinearProgressIndicator(),
                const SizedBox(height: 16),
                ...children,
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class InventoryFailurePanel extends StatelessWidget {
  const InventoryFailurePanel({
    super.key,
    this.failure,
    this.retry,
    this.label = 'Tải lại',
  });
  final Failure? failure;
  final VoidCallback? retry;
  final String label;
  @override
  Widget build(BuildContext context) => failure == null
      ? const SizedBox.shrink()
      : Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(failure!.message),
              if (failure!.fieldErrors.isNotEmpty)
                Text(failure!.fieldErrors.values.join('\n')),
              if (retry != null)
                TextButton.icon(
                  onPressed: retry,
                  icon: const Icon(Icons.refresh),
                  label: Text(label),
                ),
            ],
          ),
        );
}

class InventoryBadge extends StatelessWidget {
  const InventoryBadge(
    this.label, {
    super.key,
    this.warning = false,
    this.positive = false,
  });
  final String label;
  final bool warning, positive;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: warning
          ? const Color(0xFFFFF3E0)
          : positive
          ? const Color(0xFFE8F5E9)
          : const Color(0xFFF0F2F5),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: warning
            ? const Color(0xFF8A4B00)
            : positive
            ? const Color(0xFF256029)
            : const Color(0xFF455A64),
      ),
    ),
  );
}

class InventoryPaging extends StatelessWidget {
  const InventoryPaging({
    super.key,
    required this.page,
    required this.totalPages,
    required this.totalElements,
    required this.loading,
    required this.changed,
  });
  final int page, totalPages, totalElements;
  final bool loading;
  final ValueChanged<int> changed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text('$totalElements kết quả'),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: 'Trang trước',
              onPressed: loading || page == 0 ? null : () => changed(page - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text('Trang ${totalPages == 0 ? 0 : page + 1}/$totalPages'),
            IconButton(
              tooltip: 'Trang sau',
              onPressed: loading || page + 1 >= totalPages
                  ? null
                  : () => changed(page + 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    ),
  );
}

InputDecoration inventoryField(String label, {String? hint, String? error}) =>
    InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      errorMaxLines: 3,
      border: const OutlineInputBorder(),
    );
String inventoryAmount(InventoryQuantity value, String unit) =>
    '${value.toString().replaceAll('.', ',')} $unit';

class InventoryFilters extends StatelessWidget {
  const InventoryFilters({
    super.key,
    required this.identity,
    required this.listenable,
    required this.search,
    required this.onSearch,
    required this.active,
    required this.onActive,
    required this.sortBy,
    required this.direction,
    required this.sorts,
    required this.onSort,
    required this.onDirection,
    this.warehouses = false,
  });
  final Object identity;
  final Listenable listenable;
  final String search;

  /// Read again while the filter panel is open, so these stay current.
  final bool? Function() active;
  final String Function() sortBy, direction;
  final Map<String, String> sorts;
  final bool warehouses;
  final ValueChanged<String> onSearch, onSort, onDirection;
  final ValueChanged<bool?> onActive;
  @override
  Widget build(BuildContext context) {
    Widget select(
      String label,
      String value,
      Map<String, String> items,
      ValueChanged<String> changed,
    ) => DropdownButtonFormField<String>(
      key: ValueKey((identity, label, value)),
      value: value,
      isExpanded: true,
      itemHeight: null,
      decoration: inventoryField(label),
      items: [
        for (final entry in items.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: (v) {
        if (v != null) changed(v);
      },
    );
    return SearchFilterRow(
      search: TextFormField(
        key: ValueKey(('inventory-search', identity)),
        initialValue: search,
        maxLength: 100,
        decoration: inventoryField(
          warehouses ? 'Tìm kho' : 'Tìm nguyên liệu',
          hint: warehouses ? 'Mã hoặc tên kho' : 'Tên hoặc SKU',
        ).copyWith(prefixIcon: const Icon(Icons.search), counterText: ''),
        onChanged: onSearch,
      ),
      filter: FilterPanelButton(
        listenable: listenable,
        title: warehouses ? 'Bộ lọc kho' : 'Bộ lọc tồn kho',
        activeCount: () => active() == null ? 0 : 1,
        onClear: () => onActive(null),
        filters: () => [
          select(
            'Trạng thái',
            active()?.toString() ?? 'all',
            const {'all': 'Tất cả', 'true': 'Đang bật', 'false': 'Đã tắt'},
            (v) => onActive(v == 'all' ? null : v == 'true'),
          ),
          select('Sắp xếp', sortBy(), sorts, onSort),
          select('Thứ tự', direction(), const {
            'asc': 'Tăng dần',
            'desc': 'Giảm dần',
          }, onDirection),
        ],
      ),
    );
  }
}

Future<bool> confirmInventoryDraftReload(
  BuildContext context,
  WidgetRef ref,
) => showInventoryDialog<bool>(
  context,
  ref,
  child: Builder(
    builder: (dialogContext) => AlertDialog(
      title: const Text('Thay thế bản đang sửa?'),
      content: const Text(
        'Nội dung đang nhập sẽ được thay bằng dữ liệu mới nhất. Hãy kiểm tra lại trước khi lưu.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Giữ bản nháp'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Tải dữ liệu mới'),
        ),
      ],
    ),
  ),
).then((value) => value ?? false);
