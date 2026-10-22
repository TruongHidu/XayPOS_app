import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
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
    if (!AccessPolicy.canViewOrderRecipeSnapshot(
      ref.watch(authControllerProvider).state.session,
    )) {
      return const SizedBox.shrink();
    }
    return TextButton.icon(
      key: ValueKey('order-ingredients-${line.id}'),
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      icon: const Icon(Icons.receipt_long_outlined),
      label: const Text('Xem nguyên liệu'),
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
    if (!AccessPolicy.canViewOrderRecipeSnapshot(session)) {
      return const SizedBox.shrink();
    }
    final target = (orderId: widget.order.id, orderItemId: widget.line.id);
    final snapshot = ref.watch(orderRecipeSnapshotProvider(target));
    final allocationAllowed = AccessPolicy.canViewOrderItemAllocation(session);
    final allocation = allocationAllowed && _allocationRequested
        ? ref.watch(orderItemAllocationProvider(target))
        : null;
    final ScopedReadController<Object>? selected = _allocation
        ? allocation
        : snapshot;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Nguyên liệu của món',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: SingleChildScrollView(
                  key: PageStorageKey((
                    'order-ingredient-detail',
                    target,
                    _allocation,
                  )),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.line.itemName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('Đơn: ${widget.order.summary.orderCode}'),
                      Text(
                        '${widget.line.quantity} ${widget.line.unit} · ${widget.line.status.label}',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Công thức đã chốt'),
                            selected: !_allocation,
                            onSelected: (_) =>
                                setState(() => _allocation = false),
                          ),
                          if (allocationAllowed)
                            ChoiceChip(
                              label: const Text('Giữ & tiêu thụ kho'),
                              selected: _allocation,
                              onSelected: (_) => setState(() {
                                _allocationRequested = true;
                                _allocation = true;
                              }),
                            ),
                        ],
                      ),
                      if (!allocationAllowed)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Cần quyền xem kho và tính năng kho để xem giữ/tiêu thụ nguyên liệu.',
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (selected?.loading == true)
                        const LinearProgressIndicator(),
                      if (selected?.stale == true)
                        const _Info(
                          'Dữ liệu lần tải trước. Đơn hoặc tồn kho đã thay đổi; hãy làm mới để đối chiếu.',
                        ),
                      if (selected?.failure != null)
                        OrderFailurePanel(
                          failure: selected!.failure,
                          retry: selected.loading ? null : selected.load,
                          label: 'Thử lại',
                        ),
                      if (!_allocation && snapshot.value != null)
                        _SnapshotDetails(snapshot.value!),
                      if (_allocation && allocation?.value != null)
                        _AllocationDetails(allocation!.value!),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: selected == null || selected.loading
                      ? null
                      : selected.load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Làm mới'),
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
  const _SnapshotDetails(this.value);
  final OrderRecipeSnapshot value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Info(value.status.label),
      Text(
        'Dòng món đã gọi: ${ingredientNumber(value.orderQuantity)} ${value.orderUnit}',
      ),
      if (value.capturedAt != null)
        Text('Thời điểm chốt: ${formatLocalDate(value.capturedAt!)}'),
      if (value.status == RecipeSnapshotStatus.captured) ...[
        Text(
          'Công thức đã chốt – Phiên bản ${value.recipeVersion}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          'Công thức cho ${ingredientNumber(value.yieldQuantity!)} ${value.yieldUnit}',
        ),
        const _Info(
          'Đây là công thức đã chốt khi gửi/chấp nhận món. Thay đổi công thức hiện tại không làm thay đổi dữ liệu này.',
        ),
        _IngredientRows(
          headers: const [
            'Lượng cả mẻ',
            'Hao hụt',
            'Cần cho dòng món',
            'Theo dõi kho',
          ],
          rows: [
            for (final row in value.ingredients)
              _IngredientRow(row.name, row.sku, [
                '${ingredientNumber(row.recipeQuantity)} ${row.unit}',
                '${_percent(row.wastePercent)}%',
                '${ingredientNumber(row.requiredQuantity)} ${row.unit}',
                row.trackInventory ? 'Có' : 'Không theo dõi tồn',
              ]),
          ],
        ),
      ],
    ],
  );
}

class _AllocationDetails extends StatelessWidget {
  const _AllocationDetails(this.value);
  final OrderItemAllocation value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _Info(value.status.label),
      Text(switch (value.status) {
        AllocationStatus.reserved => 'Đã giữ chỗ, chưa giảm tồn vật lý.',
        AllocationStatus.consumed =>
          'Đã giảm tồn vật lý và ghi giao dịch tiêu thụ.',
        AllocationStatus.released =>
          'Đã trả phần giữ chỗ; không phải nhập tăng tồn vật lý.',
        AllocationStatus.skipped => value.skipReason!.label,
        AllocationStatus.notSubmitted =>
          'Món chưa gửi, chưa có dữ liệu giữ nguyên liệu.',
      }),
      if (value.warehouseId != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SelectableText('Kho đã chốt: ${value.warehouseId}'),
        ),
      if (value.reservedAt != null)
        Text('Giữ lúc: ${formatLocalDate(value.reservedAt!)}'),
      if (value.consumedAt != null)
        Text('Tiêu thụ lúc: ${formatLocalDate(value.consumedAt!)}'),
      if (value.releasedAt != null)
        Text('Giải phóng lúc: ${formatLocalDate(value.releasedAt!)}'),
      if (value.ingredients.isNotEmpty) ...[
        const SizedBox(height: 16),
        _IngredientRows(
          headers: const ['Lượng đã chốt'],
          rows: [
            for (final row in value.ingredients)
              _IngredientRow(row.name, row.sku, [
                '${ingredientNumber(row.quantity)} ${row.unit}',
              ]),
          ],
        ),
      ],
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: () {
          final router = GoRouter.maybeOf(context);
          final location = stockHistoryLocation(
            orderId: value.orderId,
            orderItemId: value.orderItemId,
            source: InventoryTransactionSource.orderItem,
            type: InventoryTransactionType.recipeUse,
          );
          Navigator.of(context).pop();
          router?.go(location);
        },
        icon: const Icon(Icons.history),
        label: const Text('Xem giao dịch tiêu thụ'),
      ),
      const Text(
        'Món đang giữ chỗ hoặc đã giải phóng có thể chưa có giao dịch tiêu thụ.',
      ),
    ],
  );
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
  const _IngredientRow(this.name, this.sku, this.values);
  final String name;
  final String? sku;
  final List<String> values;
}

class _IngredientRows extends StatelessWidget {
  const _IngredientRows({required this.headers, required this.rows});
  final List<String> headers;
  final List<_IngredientRow> rows;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (box.maxWidth >= 850 && scale <= 1.3) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            dataRowMinHeight: 72,
            dataRowMaxHeight: 112,
            columns: [
              const DataColumn(label: Text('Nguyên liệu / SKU')),
              for (final h in headers) DataColumn(label: Text(h)),
            ],
            rows: [
              for (final row in rows)
                DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 220,
                        child: Tooltip(
                          message: row.name,
                          child: Text(
                            '${row.name}${row.sku == null ? '' : '\n${row.sku}'}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    for (var i = 0; i < headers.length; i++)
                      DataCell(
                        Text(
                          row.values[i],
                          style:
                              headers[i].contains('Cần') ||
                                  headers[i].contains('Lượng đã')
                              ? const TextStyle(fontWeight: FontWeight.w700)
                              : null,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in rows)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      row.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (row.sku != null) Text('SKU: ${row.sku}'),
                    const SizedBox(height: 8),
                    for (var i = 0; i < headers.length; i++)
                      Text(
                        '${headers[i]}: ${row.values[i]}',
                        style:
                            headers[i].contains('Cần') ||
                                headers[i].contains('Lượng đã')
                            ? const TextStyle(fontWeight: FontWeight.w700)
                            : null,
                      ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
