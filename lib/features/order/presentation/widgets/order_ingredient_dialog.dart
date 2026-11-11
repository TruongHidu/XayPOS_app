import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/ui/controllers/scoped_read_controller.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../../inventory/domain/entities/order_item_allocation.dart';
import '../../../inventory/domain/entities/stock_document.dart';
import '../../../inventory/presentation/providers/order_item_allocation_providers.dart';
import '../../../inventory/presentation/widgets/stock_widgets.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_recipe_snapshot.dart';
import '../providers/order_recipe_snapshot_providers.dart';
import 'order_widgets.dart';

class OrderIngredientsButton extends ConsumerWidget {
  const OrderIngredientsButton({
    super.key,
    required this.order,
    required this.line,
  });
  final OrderDetail order;
  final OrderLine line;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    final recipeAllowed = AccessPolicy.canViewOrderRecipeSnapshot(session);
    if (!recipeAllowed && !AccessPolicy.canViewOrderItemAllocation(session)) {
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      key: ValueKey('order-ingredients-${line.id}'),
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      icon: const Icon(Icons.receipt_long_outlined),
      label: Text(recipeAllowed ? 'Xem nguyên liệu' : 'Xem kho của món'),
      onPressed: () => showOrderDialog<void>(
        context,
        ref,
        permission: 'ORDER_VIEW',
        child: OrderIngredientDialog(order: order, line: line),
      ),
    );
  }
}

class OrderIngredientDialog extends ConsumerStatefulWidget {
  const OrderIngredientDialog({
    super.key,
    required this.order,
    required this.line,
  });
  final OrderDetail order;
  final OrderLine line;
  @override
  ConsumerState<OrderIngredientDialog> createState() =>
      _OrderIngredientDialogState();
}

class _OrderIngredientDialogState extends ConsumerState<OrderIngredientDialog> {
  bool _allocation = false, _allocationRequested = false;
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).state.session;
    final recipeAllowed = AccessPolicy.canViewOrderRecipeSnapshot(session);
    final allocationAllowed = AccessPolicy.canViewOrderItemAllocation(session);
    if (!recipeAllowed && !allocationAllowed) {
      return const SizedBox.shrink();
    }
    final target = (orderId: widget.order.id, orderItemId: widget.line.id);
    final snapshot = recipeAllowed
        ? ref.watch(orderRecipeSnapshotProvider(target))
        : null;
    final showAllocation = _allocation || !recipeAllowed;
    final allocation =
        allocationAllowed && (_allocationRequested || !recipeAllowed)
        ? ref.watch(orderItemAllocationProvider(target))
        : null;
    final ScopedReadController<Object>? selected = showAllocation
        ? allocation
        : snapshot;
    final failure = selected?.failure;
    // Without recipe rights the server only opens direct stock lines, so a
    // refused line is an expected outcome of a mode the app can't know upfront.
    final recipeOnlyLine =
        !recipeAllowed &&
        const {
          FailureType.forbidden,
          FailureType.featureNotEntitled,
        }.contains(failure?.type);
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.line.itemName,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${widget.line.quantity} ${widget.line.unit} · ${widget.line.status.label}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Làm mới',
                    onPressed: selected == null || selected.loading
                        ? null
                        : selected.load,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  key: PageStorageKey((
                    'order-ingredient-detail',
                    target,
                    showAllocation,
                  )),
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (recipeAllowed && allocationAllowed) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Công thức'),
                              selected: !_allocation,
                              onSelected: (_) =>
                                  setState(() => _allocation = false),
                            ),
                            ChoiceChip(
                              label: const Text('Kho'),
                              selected: _allocation,
                              onSelected: (_) => setState(() {
                                _allocationRequested = true;
                                _allocation = true;
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (selected?.loading == true)
                        const LinearProgressIndicator(),
                      if (selected?.stale == true)
                        const _Info(
                          'Dữ liệu lần tải trước. Đơn hoặc tồn kho đã thay đổi; hãy làm mới để đối chiếu.',
                        ),
                      if (recipeOnlyLine)
                        const _Info(
                          'Chỉ món trừ tồn trực tiếp mới xem được khi không có quyền công thức.',
                        )
                      else if (failure != null)
                        OrderFailurePanel(
                          failure: failure,
                          retry: selected!.loading ? null : selected.load,
                          label: 'Thử lại',
                        ),
                      if (!showAllocation && snapshot?.value != null)
                        _SnapshotDetails(
                          snapshot!.value!,
                          allocationAllowed: allocationAllowed,
                        ),
                      if (showAllocation && allocation?.value != null)
                        _AllocationDetails(allocation!.value!),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String ingredientNumber(Object number) {
  final parts = number.toString().split('.');
  return '${parts.first.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')}${parts.length > 1 ? ',${parts[1]}' : ''}';
}

String _percent(int hundredths) => ingredientNumber(
  '${hundredths ~/ 100}.${(hundredths % 100).toString().padLeft(2, '0').replaceFirst(RegExp(r'0+$'), '')}'
      .replaceFirst(RegExp(r'\.$'), ''),
);

class _SnapshotDetails extends StatelessWidget {
  const _SnapshotDetails(this.value, {required this.allocationAllowed});
  final OrderRecipeSnapshot value;
  final bool allocationAllowed;
  @override
  Widget build(BuildContext context) {
    final captured = value.status == RecipeSnapshotStatus.captured;
    final yieldText = captured
        ? '${ingredientNumber(value.yieldQuantity!)} ${value.yieldUnit}'
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusCard(
          done: captured,
          title: value.status.label,
          badge: captured ? 'Phiên bản ${value.recipeVersion}' : null,
          lines: [
            if (value.capturedAt != null)
              'Lúc ${formatLocalDate(value.capturedAt!)}',
            if (captured) 'Sửa công thức sau đó không làm đổi dữ liệu này.',
            if (allocationAllowed &&
                value.status == RecipeSnapshotStatus.recipeDisabled)
              'Nếu món trừ kho trực tiếp, xem ở mục Kho.',
            if (value.costSourceSnapshot != null)
              'Nguồn giá vốn: ${value.costSourceSnapshot!.label}',
          ],
        ),
        if (captured) ...[
          const SizedBox(height: 16),
          _IngredientList(
            title:
                'Cần cho ${ingredientNumber(value.orderQuantity)} ${value.orderUnit}',
            rows: [
              for (final row in value.ingredients)
                _IngredientRow(
                  name: row.name,
                  sku: row.sku,
                  amount:
                      '${ingredientNumber(row.requiredQuantity)} ${row.unit}',
                  detail: [
                    'Định mức ${ingredientNumber(row.recipeQuantity)} ${row.unit}'
                        ' / $yieldText',
                    if (row.wastePercent > 0)
                      'hao hụt ${_percent(row.wastePercent)}%',
                  ].join(' · '),
                  untracked: !row.trackInventory,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _AllocationDetails extends StatelessWidget {
  const _AllocationDetails(this.value);
  final OrderItemAllocation value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _StatusCard(
        done:
            value.status == AllocationStatus.reserved ||
            value.status == AllocationStatus.consumed,
        title: value.status.label,
        lines: [
          if (value.directStock) 'Món trừ tồn trực tiếp, không dùng công thức.',
          switch (value.status) {
            AllocationStatus.reserved => 'Đã giữ chỗ, chưa trừ tồn kho.',
            AllocationStatus.consumed => 'Đã trừ tồn kho.',
            AllocationStatus.released => 'Đã trả lại phần giữ chỗ.',
            AllocationStatus.skipped => value.skipReason!.label,
            AllocationStatus.notSubmitted => 'Món chưa gửi bếp.',
          },
          if (value.reservedAt != null)
            'Giữ lúc ${formatLocalDate(value.reservedAt!)}',
          if (value.consumedAt != null)
            'Trừ kho lúc ${formatLocalDate(value.consumedAt!)}',
          if (value.releasedAt != null)
            'Trả lại lúc ${formatLocalDate(value.releasedAt!)}',
          if (value.warehouseId != null) 'Kho: ${value.warehouseId}',
        ],
      ),
      if (value.ingredients.isNotEmpty) ...[
        const SizedBox(height: 16),
        _IngredientList(
          title: 'Số lượng đã chốt',
          rows: [
            for (final row in value.ingredients)
              _IngredientRow(
                name: row.name,
                sku: row.sku,
                amount: '${ingredientNumber(row.quantity)} ${row.unit}',
              ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: () {
          final router = GoRouter.maybeOf(context);
          final location = stockHistoryLocation(
            orderId: value.orderId,
            orderItemId: value.orderItemId,
            source: InventoryTransactionSource.orderItem,
            type: value.directStock
                ? InventoryTransactionType.directUse
                : InventoryTransactionType.recipeUse,
          );
          Navigator.of(context).pop();
          router?.go(location);
        },
        icon: const Icon(Icons.history),
        label: const Text('Xem giao dịch tiêu thụ'),
      ),
    ],
  );
}

/// One summary block: what state the data is in, plus a few short facts.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.done,
    required this.title,
    this.badge,
    this.lines = const [],
  });
  final bool done;
  final String title;
  final String? badge;
  final List<String> lines;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: done
            ? scheme.primary.withValues(alpha: 0.08)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? Icons.check_circle : Icons.info_outline,
            size: 22,
            color: done ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge!,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                for (final line in lines) ...[
                  const SizedBox(height: 4),
                  Text(line, style: muted),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _IngredientRow {
  const _IngredientRow({
    required this.name,
    required this.sku,
    required this.amount,
    this.detail,
    this.untracked = false,
  });
  final String name, amount;
  final String? sku, detail;
  final bool untracked;
}

/// Name on the left, the amount that matters on the right.
class _IngredientList extends StatelessWidget {
  const _IngredientList({required this.title, required this.rows});
  final String title;
  final List<_IngredientRow> rows;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rows[i].name,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (rows[i].sku != null)
                              Text('SKU ${rows[i].sku}', style: muted),
                            if (rows[i].detail != null)
                              Text(rows[i].detail!, style: muted),
                            if (rows[i].untracked)
                              Text(
                                'Không theo dõi tồn',
                                style: muted?.copyWith(
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        flex: 2,
                        child: Text(
                          rows[i].amount,
                          textAlign: TextAlign.end,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
