import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/stock_document.dart';
import '../../domain/entities/stock_queries.dart';
import '../../domain/entities/stock_numbers.dart';
import 'inventory_widgets.dart';

String stockDisplay(Object value) {
  if (value is! StockMoney) return value.toString().replaceAll('.', ',');
  final parts = value.toString().split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  return '$whole${parts.length == 1 ? '' : ',${parts[1]}'}';
}

String stockDay(DateTime value) {
  final d = value.toLocal();
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String stockDetailLocation(String id) =>
    '/app/inventory/stock-documents/${Uri.encodeComponent(id)}';
String stockHistoryLocation({
  String? warehouseId,
  String? ingredientId,
  String? documentId,
}) => Uri(
  path: '/app/inventory/transactions',
  queryParameters: {
    if (warehouseId != null) 'warehouseId': warehouseId,
    if (ingredientId != null) 'ingredientId': ingredientId,
    if (documentId != null) 'documentId': documentId,
  },
).toString();

class StockStatusBadge extends StatelessWidget {
  const StockStatusBadge(this.status, {super.key});
  final StockDocumentStatus status;
  @override
  Widget build(BuildContext context) => InventoryBadge(
    status.label,
    warning: status == StockDocumentStatus.draft,
    positive: status == StockDocumentStatus.confirmed,
  );
}

class StockSelect extends StatelessWidget {
  const StockSelect({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.changed,
    this.enabled = true,
  });
  final String label, value;
  final Map<String, String> items;
  final ValueChanged<String> changed;
  final bool enabled;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    key: ValueKey((label, value)),
    value: value,
    isExpanded: true,
    itemHeight: null,
    decoration: inventoryField(label),
    items: [
      for (final e in items.entries)
        DropdownMenuItem(value: e.key, child: Text(e.value)),
    ],
    onChanged: !enabled
        ? null
        : (v) {
            if (v != null) changed(v);
          },
  );
}

class StockFilterLayout extends StatelessWidget {
  const StockFilterLayout({
    super.key,
    required this.identity,
    required this.children,
    this.search,
  });
  final Object identity;
  final List<Widget> children;
  final Widget? search;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final filters = ResponsiveColumns(
        minColumnWidth: 240 * scale.clamp(1, 1.5),
        maxColumns: 4,
        spacing: 12,
        children: children,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (search != null) ...[search!, const SizedBox(height: 12)],
          if (box.maxWidth < 700 || box.maxWidth < 1000 && scale > 1.3)
            ExpansionTile(
              // Keep the expanded bool separate from the parent's scroll offset
              // and from filters in other inventory tabs.
              key: PageStorageKey(('stock-filters', identity)),
              title: const Text('Lọc và sắp xếp'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.symmetric(vertical: 12),
              children: [filters],
            )
          else
            filters,
        ],
      );
    },
  );
}

class StockDateFilter extends ConsumerWidget {
  const StockDateFilter({
    super.key,
    required this.range,
    required this.changed,
  });
  final StockDateRange? range;
  final ValueChanged<StockDateRange?> changed;
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
              : range?.from == null
              ? 'Đến ${stockDay(range!.to!)}'
              : range?.to == null
              ? 'Từ ${stockDay(range!.from!)}'
              : '${stockDay(range!.from!)} – ${stockDay(range!.to!)}',
        ),
        onPressed: () async {
          final scope = ref.read(inventoryScopeProvider);
          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(1),
            lastDate: DateTime(9999, 12, 31),
            initialDateRange: range?.from == null || range?.to == null
                ? null
                : DateTimeRange(
                    start: range!.from!.toLocal(),
                    end: range!.to!.toLocal(),
                  ),
            helpText: 'Chọn khoảng ngày tạo',
            saveText: 'Áp dụng',
            builder: (context, child) => InventoryScopeGuard(
              scope: scope,
              permission: 'INVENTORY_VIEW',
              child: child!,
            ),
          );
          if (context.mounted &&
              picked != null &&
              scope == ref.read(inventoryScopeProvider)) {
            changed(StockDateRange.days(picked.start, picked.end));
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

class StockPageFrame extends ConsumerWidget {
  const StockPageFrame({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.permission = 'INVENTORY_VIEW',
    this.onRefresh,
  });
  final String title, permission;
  final Widget child;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canInventory(session, 'INVENTORY_VIEW') ||
        !AccessPolicy.canInventory(session, permission)) {
      return const Center(child: Text('Bạn chưa có quyền mở chức năng này.'));
    }
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
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => context.go('/app/inventory'),
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('Về kho'),
                        ),
                        ...actions,
                      ],
                    ),
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

Future<bool> confirmStockAction(
  BuildContext context,
  WidgetRef ref, {
  required String permission,
  required String title,
  required String message,
  required String confirm,
}) async =>
    await showInventoryDialog<bool>(
      context,
      ref,
      permission: permission,
      child: Builder(
        builder: (dialogContext) => InventoryDialogFrame(
          title: title,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Quay lại'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirm),
            ),
          ],
          children: [Text(message)],
        ),
      ),
    ) ??
    false;
